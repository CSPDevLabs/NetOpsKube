# NetOpsKube Quick Start (local simulation)

## What you have running now

**Full stack** (`make try-nok-bng` + `make deploy-clab-bng`) is deployed on KinD cluster `nok-demo`.

| Component | Namespace | Access |
|-----------|-----------|--------|
| KinD cluster | `nok-demo` | `export KUBECONFIG=~/.kube/config` |
| **BNG Portal** | `nok-bng` | http://bng.nok.local:8080 |
| **Gitea (GitOps)** | `nok-git` | http://bng.nok.local:8080/gitea (user: `nok` / `N0kP4ssw0rd`) |
| Ingress | `nok-base` | port-forward on `0.0.0.0:8080` |
| BNG clab (4x srsim + radius + bngblaster) | Docker | `docker ps \| grep clab` |

Add to `/etc/hosts`: `127.0.0.1 bng.nok.local`

KinD MetalLB/LB IPs are auto-patched at `make cluster-up` to match the KinD Docker network — no manual `ip route` workaround needed.

Installed operators: cert-manager, Grafana Operator, Prometheus Operator, gnmic Operator, SDCIO config-server, MetalLB, ingress-nginx.

## Commands

```bash
cd /root/eac

# Check cluster
export KUBECONFIG=~/.kube/config
./tools/kubectl --context kind-nok-demo get pods -A

# Re-run base install (idempotent)
make try-nok

# Tear down
make delete-cluster
```

## Full BNG demo (next step)

The complete EAC demo (`make try-nok-bng`) adds:
- Nokia BNG containerlab topology (srsim)
- BNG observability (gnmic → Prometheus → Grafana)
- Gitea + FluxCD GitOps
- Portal at http://bng.nok.local:8080

**Prerequisites:**
1. Pull Nokia srsim image:
   ```bash
   docker pull registry.srlinux.dev/pub/nokia_srsim:25.10.R1
   ```
2. Place SROS license at:
   ```
   nok-clabs/nok-bng/srsim-lic-25.txt
   ```
   (Request from Nokia — required for srsim)

3. Free port 8080 (or edit Makefile port-forward) — currently used by another container on this host.

Then run:
```bash
make try-nok-bng
# or step by step:
make install-bng-pkg
sudo make deploy-clab-bng
```

## Simulate subscriber traffic (after BNG clab is up)

```bash
sudo docker exec -it clab-sros-bngt-bngblaster bash -c 'bngblaster -C pppoe.json -I -l dhcp'
```

## Repo layout

| Path | Purpose |
|------|---------|
| `Makefile` | Orchestration — start here |
| `nok-kpt/` | KPT packages (nok-base, nok-bbm, nok-bng, nok-git, nok-lb) |
| `nok-clabs/` | Containerlab topologies |
| `tools/` | kind, kubectl, kpt, flux, containerlab binaries |
| `build/kind-cluster.yaml` | KinD cluster config |

## Learning path (matches EAC Delivery Consultant skills)

1. **Today:** Explore `kubectl get pods -A`, Grafana dashboards at :3000, Prometheus targets at :9090
2. **Next:** Read `nok-kpt/nok-bbm/` — self-monitoring package (blackbox probes, dashboards-as-code)
3. **Then:** Deploy BNG once you have license + srsim image
4. **Deep dive:** `nok-kpt/nok-bng/` — gnmic subscriptions, Grafana dashboards, alert rules
