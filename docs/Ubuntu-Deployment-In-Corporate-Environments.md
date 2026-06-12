# Ubuntu Deployment Behind a Corporate Proxy

This guide covers the host-level configuration required to run NetOpsKube
(`kind` + Docker + Containerlab + operator-managed workloads) on an Ubuntu
machine that has **no direct internet access** and must egress through a
corporate HTTP proxy that performs TLS interception.

The standard installation guide assumes direct internet. If you skip the
steps below on a proxied network, you will see symptoms like:

- `docker pull` failing with `tls: failed to verify certificate: x509: certificate signed by unknown authority`
- CoreDNS logs full of `i/o timeout` to `172.18.0.1:53`
- Grafana / Prometheus pods in `CrashLoopBackOff` with
  `dial tcp: lookup grafana.com on 10.96.0.10:53: server misbehaving`
  or `context deadline exceeded while awaiting headers`
- Image pulls inside the kind cluster timing out
- TLS handshake errors like `certificate is not yet valid` / `certificate has expired`
  after a VM is cloned, suspended, or sits on an isolated network — the host
  clock has drifted because the default `pool.ntp.org` upstreams are not
  reachable through the proxy

These are all manifestations of the same underlying issue: the proxy/CA/DNS
configuration that works on the host has not been propagated into Docker,
into the kind nodes, or into the pods.

## Tested versions

This guide has been validated on the following stack. Newer point releases
of any of these components are expected to work; significant version
differences (e.g. Docker < 24, kind < 0.20) may require adjustments.

| Component       | Version             |
|-----------------|---------------------|
| Ubuntu          | 24.04.4 LTS (Noble) |
| Linux kernel    | 6.8.0-100-generic   |
| Docker Engine   | 29.1.3 (client + server) |
| kind            | v0.29.0             |
| Kubernetes node image | `kindest/node:v1.33.1` |
| kubectl         | v1.33.1             |
| Kustomize       | v5.6.0              |

---

> Throughout this guide the example IPs are RFC 5737 documentation
> addresses. Replace them with values for your environment:
> - Proxy URL: `http://192.0.2.10:8000` (TEST-NET-1, RFC 5737)
> - Internal DNS servers: `198.51.100.1`, `198.51.100.2`, `198.51.100.3` (TEST-NET-2, RFC 5737)
> - Corporate root CA bundle: `/path/to/corp-ca.pem`

---

## Conceptual model — four orthogonal layers

Behind a proxy there are **four independent things** to configure. Mixing
them up is the most common source of bugs.

| # | Layer                          | What it controls                                     | Where it is set                                                |
|---|--------------------------------|------------------------------------------------------|----------------------------------------------------------------|
| 1 | Docker daemon proxy            | `docker pull` egress (image registry traffic)        | `/etc/systemd/system/docker.service.d/http-proxy.conf`         |
| 2 | Container DNS                  | `/etc/resolv.conf` written into every new container  | `/etc/docker/daemon.json` `dns:`                               |
| 3 | Host CA trust                  | TLS verification by the daemon and host tools        | `/usr/local/share/ca-certificates/*.crt` + `update-ca-certificates` |
| 4 | Container proxy env defaults   | Apps inside containers reaching the internet         | `~/.docker/config.json` `proxies.default`                      |

In addition, two cluster-level concerns must be addressed:

- **kind nodes** — they are themselves docker containers; they inherit
  layers 1–4, but containerd inside them needs the same CA trust to pull
  images.
- **Pods managed by operators** (Grafana, Prometheus, …) — proxy env vars
  must be declared **in the CR**, not on the rendered Deployment. Otherwise
  the operator reconciles them away.

---

## 1. Host prerequisites

### 1.1 Raise inotify limits

Before doing anything proxy-specific, raise inotify limits — `kind` plus
`k9s` plus `containerlab` will exhaust the defaults and you will see
`Failed to allocate directory watch: Too many open files` from
`systemctl restart` and friends.

```bash
sudo tee /etc/sysctl.d/99-inotify.conf > /dev/null <<'EOF'
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches   = 1048576
EOF
sudo sysctl --system
```

### 1.2 Host time sync (chrony) against internal NTP servers

Behind a corporate proxy, the default Ubuntu time source (`systemd-timesyncd`
talking to `ntp.ubuntu.com` / `pool.ntp.org`) cannot reach the internet, so
the clock silently drifts. Symptoms range from TLS handshake failures
(`certificate is not yet valid`) on freshly cloned VMs, to Prometheus
target pages showing every scrape as “8 minutes ago” even though scraping
is healthy — Prometheus stamps scrapes with the lagging node clock while
the browser compares against real wall‑time.

Install `chrony` and point it at the **internal** NTP servers that your
network provides (use the actual server names for your environment;
`ntp1.corp.example.net` etc. are placeholders):

```bash
sudo apt-get install -y chrony
sudo systemctl disable --now systemd-timesyncd   # avoid two NTP clients fighting
```

Use a drop-in under `/etc/chrony/sources.d/` so the package‑shipped
`/etc/chrony/chrony.conf` stays untouched and survives `apt upgrade`:

```bash
sudo tee /etc/chrony/sources.d/corp-ntp.sources > /dev/null <<'EOF'
# Internal NTP servers reachable without going through the proxy.
# 'iburst'      = fast initial sync (a few seconds instead of minutes)
# 'prefer'      = mark the closest/most authoritative source
# 'minpoll 4'   = poll at least every 16s while we converge
server ntp1.corp.example.net iburst prefer minpoll 4 maxpoll 6
server ntp2.corp.example.net iburst         minpoll 4 maxpoll 6
server ntp3.corp.example.net iburst         minpoll 4 maxpoll 6
EOF
```

> The filename must end in `.sources`. `chronyc reload sources` will
> ignore anything else.

Make sure `/etc/chrony/chrony.conf` keeps the line `sourcedir
/etc/chrony/sources.d` (it does by default on Ubuntu 24.04); without it
the drop-in is not loaded.

Apply and verify:

```bash
sudo systemctl restart chronyd
sudo chronyc reload sources

chronyc sources -v        # expect at least one '^*' (current synced source)
chronyc tracking          # 'System time' offset should be < a few ms
chronyc activity          # '3 sources online' (or however many you configured)
timedatectl status        # 'System clock synchronized: yes', 'NTP service: active'
```

If the host was very far off (e.g. after a long suspend), step the clock
immediately rather than waiting for slewing:

```bash
sudo chronyc -a makestep
```

> The kind nodes and every pod inherit the host kernel clock — fixing
> time on the host fixes it everywhere. There is no chrony to install
> inside the kind containers.

---

## 2. Configure host DNS

If `resolvectl status` shows only `127.0.0.53` (the systemd-resolved stub),
your real upstream resolvers are hidden behind the stub and Docker will
end up giving containers an unreachable nameserver.

Set real servers per-link, and tell DHCP not to overwrite them:

`/etc/netplan/*.yaml` (filename varies):

```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: true
      nameservers:
        addresses: [198.51.100.1, 198.51.100.2, 198.51.100.3]
        search: []
      dhcp4-overrides:
        use-dns: false
```

Apply:

```bash
sudo netplan apply
resolvectl status enp1s0 | grep -E 'DNS Servers|Current DNS'
resolvectl query grafana.com
```

You should now see your three servers and a successful resolution.

---

## 3. Layer 1 — Docker daemon proxy (image pulls)

Already commonly required if you’ve installed Docker on the VM:

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://192.0.2.10:8000"
Environment="HTTPS_PROXY=http://192.0.2.10:8000"
Environment="NO_PROXY=127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.nok.local,.svc,.svc.cluster.local,bbm-grafana-svc,bbm-grafana-svc.nok-bbm,bbm-prometheus-svc,bbm-prometheus-svc.nok-bbm"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

systemctl show docker --property=Environment | tr ' ' '\n' | grep -i proxy
```

> This file controls **only** the docker daemon process. It does **not**
> inject env vars into containers. That is layer 4.

---

## 4. Layer 2 — Container DNS

Without this, every container Docker creates copies the host’s broken
`/etc/resolv.conf` (`127.0.0.53`) and falls back to the unreachable bridge
gateway. Inside the kind cluster this manifests as CoreDNS forwarding to
`172.18.0.1:53` and timing out.

```bash
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "dns": ["198.51.100.1", "198.51.100.2", "198.51.100.3"],
  "dns-search": []
}
EOF
sudo systemctl restart docker
```

> If `daemon.json` already exists with other keys (e.g. `data-root`,
> `log-driver`), do **not** overwrite it. Merge the `dns` key in instead.

Verify a fresh container picks up the new resolvers:

```bash
docker run --rm --network bridge alpine cat /etc/resolv.conf
# expect:
# nameserver 198.51.100.1
# nameserver 198.51.100.2
# nameserver 198.51.100.3
```

---

## 5. Layer 3 — Corporate CA trust

The proxy intercepts TLS using a corporate CA. Browsers and `curl` already
trust it, but Docker / containerd / Go programs read the CA bundle from
the system trust store, so the cert must be installed there.

```bash
sudo cp /path/to/corp-ca.pem /usr/local/share/ca-certificates/corp-proxy.crt
sudo chmod 644 /usr/local/share/ca-certificates/corp-proxy.crt
sudo update-ca-certificates
sudo systemctl restart docker
```

> The file must end in `.crt` and be PEM-encoded — `update-ca-certificates`
> ignores everything else. A bundle with multiple certs is fine.

Verify:

```bash
docker pull alpine
```

This will fail with the cert error before this step and succeed after.

---

## 6. Layer 4 — Default proxy env for `docker run`

Optional but convenient. Without this, `docker run alpine curl https://...`
will still time out unless you pass `-e HTTP_PROXY=...` flags every time.

```bash
mkdir -p ~/.docker
cat > ~/.docker/config.json <<'EOF'
{
  "proxies": {
    "default": {
      "httpProxy":  "http://192.0.2.10:8000",
      "httpsProxy": "http://192.0.2.10:8000",
      "noProxy":    "127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.nok.local,.svc,.svc.cluster.local,bbm-grafana-svc,bbm-grafana-svc.nok-bbm,bbm-prometheus-svc,bbm-prometheus-svc.nok-bbm"
    }
  }
}
EOF
```

> If `~/.docker/config.json` already contains `auths` or `credsStore`
> entries from `docker login`, **merge** the `proxies` block in with `jq`
> rather than overwriting the file.

Verify the six env vars are auto-injected into new containers:

```bash
docker run --rm alpine env | grep -i proxy
```

End-to-end host check:

```bash
docker run --rm alpine sh -c \
  'apk add --no-cache ca-certificates curl >/dev/null 2>&1 && \
   curl -sS -o /dev/null -w "%{http_code}\n" https://grafana.com'
# expect: 200
```

---

## 7. Trust the corporate CA inside kind nodes

`kind` nodes are themselves Docker containers running their own
`containerd`. They need the corporate CA in their trust store so image
pulls and any in-cluster TLS through the proxy succeed.

The simplest way is to mount the host CA into each node via the kind
cluster config:

```yaml
# kind-config.yaml (excerpt)
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: /usr/local/share/ca-certificates/corp-proxy.crt
        containerPath: /usr/local/share/ca-certificates/corp-proxy.crt
        readOnly: true
```

After the cluster is created:

```bash
for n in $(kind get nodes --name nok-demo); do
  docker exec "$n" update-ca-certificates
  docker exec "$n" systemctl restart containerd
done
```

---

## 8. Inject proxy env into operator-managed workloads

`kubectl set env` on a Deployment owned by an operator is overwritten on
the next reconcile. The proxy must be declared in the **CR**, so the
operator renders it into the Deployment every time.

### Grafana (`grafana.integreatly.org/v1beta1`)

`nok-clabs/nok-bng/nok-manifests/grafana/deployment/deployment.yaml`:

```yaml
spec:
  deployment:
    spec:
      template:
        spec:
          containers:
            - name: grafana
              env:
                - name: GF_INSTALL_PLUGINS
                  value: "andrewbmchugh-flow-panel"
                - name: HTTP_PROXY
                  value: "http://192.0.2.10:8000"
                - name: HTTPS_PROXY
                  value: "http://192.0.2.10:8000"
                - name: NO_PROXY
                  value: "127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16,.nok.local,.svc,.svc.cluster.local"
```

### Prometheus Operator CRs (`Prometheus`, `Alertmanager`, `ThanosRuler`)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: bbm-prometheus
  namespace: nok-bbm
spec:
  containers:
    - name: prometheus
      env:
        - name: HTTP_PROXY
          value: "http://192.0.2.10:8000"
        - name: HTTPS_PROXY
          value: "http://192.0.2.10:8000"
        - name: NO_PROXY
          value: "127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16,.nok.local,.svc,.svc.cluster.local"
```

> For Prometheus specifically, prefer per-target `proxyUrl` in
> `ServiceMonitor`/`Probe`/`remoteWrite`/`scrapeConfig` when only some
> targets need to go through the proxy. In-cluster scrapes don’t need the
> proxy and are already covered by `NO_PROXY`.

### Plain Deployments (no operator)

For workloads NOT managed by an operator and temporary patching for deployments under operator management, the Makefile target
`make set-proxy-env` will inject env vars and roll them out:

```bash
cd ~/nok/NetOpsKube
make set-proxy-env
```

Operator-managed deployments must NOT be in `PROXY_DEPLOYMENTS`, since the
operator will undo the patch.

---

## 9. End-to-end verification

After all the steps above, recreate the cluster and validate each layer:

```bash
kind delete cluster --name nok-demo
make deploy-clab-bng

# Layer 2 — DNS in kind node
docker exec nok-demo-control-plane cat /etc/resolv.conf

# Cluster DNS resolves external names
kubectl run -n default dnstest --rm -i --image=busybox:1.36 --restart=Never -- \
  nslookup grafana.com

# Layer 4 — pod can reach external hosts via proxy
kubectl run -n default nettest --rm -i \
  --image=curlimages/curl:8.10.1 --restart=Never \
  --env=HTTP_PROXY=http://192.0.2.10:8000 \
  --env=HTTPS_PROXY=http://192.0.2.10:8000 \
  -- curl -sS -o /dev/null -w "%{http_code}\n" https://grafana.com

# Operator-managed workload
kubectl -n nok-bng rollout status deploy/grafana-deployment --timeout=300s
kubectl -n nok-bng logs deploy/grafana-deployment | grep -E 'plugin|HTTP server'
```

Expected:

- `/etc/resolv.conf` shows `198.51.100.1`, `198.51.100.2`, `198.51.100.3`
- `nslookup grafana.com` returns a real public IP
- `curl` returns `200`
- Grafana logs show `Plugin registered ... andrewbmchugh-flow-panel`
  and `HTTP Server Listen ... :3000`, no plugin install errors

---

## Troubleshooting cheatsheet

| Symptom                                              | Layer  | Fix                                                                 |
|------------------------------------------------------|--------|---------------------------------------------------------------------|
| `docker pull` → `x509: certificate signed by unknown authority` | 3      | Install corp CA, restart docker                                     |
| `docker run alpine curl ...` times out               | 4      | `~/.docker/config.json` `proxies.default`, or pass `-e` flags       |
| Container `/etc/resolv.conf` shows `127.0.0.11` only | normal | User-defined network; Docker’s embedded resolver forwards upstream  |
| Container `/etc/resolv.conf` shows `172.18.0.1`      | 2      | Add `dns` to `daemon.json` and restart docker, then recreate kind   |
| CoreDNS logs `i/o timeout to 172.18.0.1:53`          | 2      | Same as above                                                       |
| Pod: `lookup x.com on 10.96.0.10:53: server misbehaving` | 2      | Same                                                                |
| Pod: `context deadline exceeded while awaiting headers` | pod CR | Inject `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` into the CR            |
| Operator keeps reverting your `kubectl set env`       | pod CR | Move proxy env into the CR, remove from `PROXY_DEPLOYMENTS`         |
| `Failed to allocate directory watch: Too many open files` | host   | Raise `fs.inotify.max_user_instances` and `max_user_watches`        |
| TLS errors `certificate is not yet valid` / `has expired`, or Prometheus targets all show "Nm ago" but health=up | host time | Configure `chrony` against internal NTP, `sudo chronyc -a makestep` |

---

## File-by-file summary

| File                                                                       | Purpose                                               |
|----------------------------------------------------------------------------|-------------------------------------------------------|
| `/etc/sysctl.d/99-inotify.conf`                                            | Raise inotify limits for kind/k9s/clab                |
| `/etc/chrony/sources.d/corp-ntp.sources`                                   | Internal NTP servers for host time sync (chrony)      |
| `/etc/netplan/*.yaml`                                                      | Real DNS servers per-link, ignore DHCP DNS            |
| `/etc/systemd/system/docker.service.d/http-proxy.conf`                     | Docker daemon proxy (image pulls)                     |
| `/etc/docker/daemon.json`                                                  | Container DNS                                         |
| `/usr/local/share/ca-certificates/corp-proxy.crt`                          | Corporate CA in host trust                            |
| `~/.docker/config.json`                                                    | Default proxy env for `docker run`                    |
| kind cluster config `extraMounts`                                          | CA mount into kind nodes                              |
| Grafana / Prometheus CR `containers[].env`                                 | Proxy env propagated by operators                     |
| `Makefile` `PROXY_DEPLOYMENTS` + `set-proxy-env`                           | Proxy env for plain (non-operator) Deployments        |
