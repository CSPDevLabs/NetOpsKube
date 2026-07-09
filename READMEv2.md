# NetOpsKube — README v2

## Overview

NetOpsKube stands up a self-contained **NetOps platform on Kubernetes**: a place where network devices (real or emulated) are modeled as Kubernetes objects, continuously polled for telemetry, and exposed through a single observability + config-management portal. It's built for network engineers who want a Kubernetes-native, GitOps-managed alternative to a pile of standalone NMS tools.

Everything is driven from one `Makefile`. Running `make try-nok` gets you, in order:

1. A local **Kind** (Kubernetes-in-Docker) cluster.
2. A **base platform layer** — ingress, MetalLB load balancer, cert-manager, a custom `nok-controller` with CRDs for modeling network devices, SDCIO (schema-driven config I/O for network devices), the Prometheus and gNMIc Kubernetes operators, and a Grafana operator.
3. A **self-monitoring layer** ("BBM" — blackbox monitoring) that watches the platform itself.

From there, optional layers add:

- A **BNG (Broadband Network Gateway) use case** — a full observability + logging stack (Prometheus, Loki, Promtail, Fluent Bit, syslog, gNMIc collectors) plus a web portal, wired up against a **Containerlab** topology of emulated Nokia routers.
- **GitOps** — a Gitea instance and Flux, so that once bootstrapped, the BNG manifests are pulled from a Git repo and reconciled continuously instead of being applied by hand.
- **Keycloak + OAuth2-Proxy** — SSO/OIDC authentication in front of the portal and its ingresses.

The whole thing is reproducible on a laptop: `make delete-cluster` tears it all down, `make try-nok-bng` builds it back up.

## Repository layout

```
NetOpsKube/
├── Makefile                 # orchestration: tools, cluster, packages, GitOps, auth, proxy
├── make/troubleshoot.mk     # day-2 operational targets (included by the root Makefile)
├── build/kind-cluster.yaml  # generated Kind cluster config
├── tools/                   # downloaded CLI binaries (kind, kubectl, helm, kpt, clab, flux, ...)
├── docs/                    # installation guide, GitOps setup, troubleshooting runbook, CRD reference
├── nok-kpt/                 # ← cloned at runtime from CSPDevLabs/kpt   (KPT packages = "what to deploy")
├── nok-clabs/                # ← cloned at runtime from CSPDevLabs/nok-clabs (Containerlab topologies)
└── nok-portal-auth/         # ← cloned at runtime, only if Keycloak is enabled
```

The three arrowed directories are **separate git repositories** pulled down by `make git-clone-kpt` / `git-clone-clab` / `configure-auth`. They're `.gitignore`d here — this repo only holds the orchestration logic that assembles them, not the manifests themselves. Think of `NetOpsKube` as the "control script" repo, and `nok-kpt` / `nok-clabs` as the "content" repos it pulls in.

## How it's all linked together

### 1. The cluster is the substrate

`make cluster-up` renders `build/kind-cluster.yaml` into a live Kind config (patching in your API-server address and port mappings via `yq`) and creates a single-node Kind cluster named `nok-demo`. Every subsequent layer is just Kubernetes manifests applied to this one cluster.

### 2. KPT packages are the unit of deployment

Rather than raw `kubectl apply -f`, most components ship as **KPT packages** under `nok-kpt/`. Each package (`nok-base`, `nok-lb`, `nok-bng`, `nok-bbm`, `nok-git`) has its own `Kptfile` and is applied with `kpt live init` (adopt/track resources as a "package") followed by `kpt live apply` (apply + reconcile-wait). The Makefile wraps this in two macros:

- `INSTALL_KPT_PACKAGE` — plain apply.
- `INSTALL_KPT_PACKAGE_WITH_SETTERS` — runs `kpt fn render` first, to substitute KRM function "setters" (used by `nok-bbm`, which needs per-environment values baked into its manifests before applying).

Packages depend on each other in a specific order, encoded directly in `make` target prerequisites:

```
nok-base  →  nok-lb  →  nok-bng
   │                       │
   └── nok-controller      └── depends on base (namespaces, CRDs, ingress) + lb (external IPs)
       + SDCIO + operators
```

- **`nok-base`**: namespaces, nginx ingress controller, MetalLB (the load-balancer *controller*, not its IP pool), cert-manager, the Grafana operator, the `nok-controller` (a custom controller + two CRDs — `NetworkDeviceTarget` and `NetworkHostTarget` — that represent network elements as Kubernetes objects), and SDCIO (schema-driven config management for those devices), plus `nok-crd-metrics`.
- **`nok-lb`**: the MetalLB `IPAddressPool`/`L2Advertisement` config — split out from `nok-base` because it has to wait for MetalLB's controller deployment to be `Ready` first (`wait-for-metallb-ready`).
- **`nok-bng`**: the BNG use case — Prometheus, Loki, Promtail, Fluent Bit, syslog receiver, a `nettool-instance` (test/troubleshooting pod), `ndt-sdcio-visual` (network digital-twin / SDCIO visualization), a web portal, and its own ingress.
- **`nok-bbm`** ("Base/Blackbox Monitoring"): self-monitoring for the platform — Prometheus, Grafana dashboards, `blackbox_exporter`, `kube-state-metrics` (`ksm`), and a `core-dns-updater` that keeps CoreDNS aware of dynamically-added targets (e.g. Containerlab nodes, via `clab-scripts`).
- **`nok-git`**: Gitea, the in-cluster Git server used as the GitOps source of truth (see below).

Two operators are applied as raw manifests rather than KPT packages (`install-prom-oper`, `install-gnmic-oper`): the **Prometheus Operator** and the **gNMIc Operator**. The gNMIc Operator is what actually turns `NetworkDeviceTarget` objects into live gNMI subscriptions — this is the connective tissue between "a device is declared in Kubernetes" and "telemetry is flowing."

### 3. Network devices are modeled as Kubernetes CRDs

The `nok-controller` package installs `NetworkDeviceTarget` and `NetworkHostTarget` CRDs (see `docs/NETWORK-DEVICE-TARGET.md`). A `NetworkDeviceTarget` declares a device's address, vendor labels, and two independent integrations:

- `sdcio:` — config management via SDCIO (schema provider/version, connection/sync profiles).
- `gnmic:` — telemetry via the gNMIc Operator (credentials, target profile, port).

This is the core abstraction of the platform: instead of hand-editing gNMIc/SDCIO configuration, you create one CRD per device and the operators reconcile the rest. `make verify-gnmic-subscriptions` (in `make/troubleshoot.mk`) walks all `NetworkDeviceTarget`s and reports per-cluster gNMI subscription state, so this is the first place to look when telemetry stops flowing.

### 4. Containerlab supplies the (emulated) network

`nok-clabs/nok-bng/topo.yaml` defines the actual lab: four emulated Nokia routers (`agg`, `bng1`, `bng2`, `core`, running `nokia_srsim`), a FreeRADIUS server, and a BNG Blaster traffic generator, wired together and attached to the `172.21.20.0/24` management network. `make deploy-clab-bng` brings this topology up (after checking the SROS image and license file are present); `NetworkDeviceTarget` objects in the `nok-bng` KPT package then point at these same container IPs, so the Kubernetes-side device models and the Containerlab-side emulated devices are two views of the same lab. `core-dns-updater` (in `nok-bbm`) keeps in-cluster DNS resolving Containerlab container names as they come and go.

A second, standalone topology (`nok-clabs/nok-dia`) simulates a larger telco network (SR-2SE/IXR routers) independent of the BNG use case — useful for topology/CLI experimentation without the full BNG stack.

### 5. GitOps: Gitea + Flux take over from the Makefile

Once the base platform and BNG are up, `make gitops-init` and `make gitops-bng-kustomization` shift BNG manifest management from "the Makefile applies things once" to "Flux continuously reconciles from Git":

1. `nok-git` (Gitea) is already running from step 2.
2. An admin user, an SSH deploy key (`~/.ssh/flux_ed25519` by default), and two repos are created in Gitea: `flux-bootstrap` (Flux's own config) and `nok-bng-resources` (BNG manifests).
3. `flux bootstrap git` points Flux at `flux-bootstrap`, path `clusters/NetOpsKube`.
4. The *current contents* of `nok-clabs/nok-bng/nok-manifests` are force-pushed as a fresh, single-commit snapshot into `nok-bng-resources` (`push-bng-manifests` — this deliberately discards prior history in that repo each time it runs).
5. A Flux `Kustomization` is created per top-level subdirectory of that manifests tree, so each subsystem reconciles independently.

After this point, changes to BNG manifests should go through the Gitea repo (Flux will pull and apply them), not through repeated `kpt live apply` — the Makefile's own KPT-based `install-bng-pkg` and Flux's reconciliation are two different delivery paths for the same namespace, and running both against the same live resources is redundant once GitOps is bootstrapped. `docs/GITEA-AND-FLUX-GITOPS-SETUP.md` documents the equivalent manual steps if you want to understand or replicate the flow without the Makefile.

### 6. Access and authentication

Everything is reached through the single nginx ingress controller from `nok-base`, port-forwarded to the host on `:8080` by `make start-ingress-port-forward`:

| Service | URL | Notes |
|---|---|---|
| BNG portal | `http://bng.nok.local:8080/` | add `bng.nok.local` to `/etc/hosts`, or `curl --resolve` |
| Gitea | `http://gitea.nok.local` | → `172.19.0.100` |
| Keycloak admin | `http://keycloak.nok.local:8080/admin/master/console` | only if `KEYCLOAK_ENABLED=YES` |

Authentication is **optional and additive**: with `KEYCLOAK_ENABLED=NO` (default) everything above is open. Setting `KEYCLOAK_ENABLED=YES` before `make try-nok-bng` (or running `make configure-auth` after the fact) deploys Keycloak (realm `netopskube`) and OAuth2-Proxy, then annotates the portal's ingresses (`nok-apps-ingress`, `nok-apps-portal-ingress`) to route through OAuth2-Proxy's `/oauth2/auth` endpoint before the app is reached. Users are provisioned manually in the Keycloak admin console — there's no self-service signup.

### 7. Proxy handling for restricted environments

A handful of deployments need outbound internet access (e.g. `coredns-updater`, `blackbox-exporter`, the Grafana operator, `config-server`, and — if Keycloak is on — `oauth2-proxy`). These are listed once in `PROXY_DEPLOYMENTS` in the Makefile; `make set-proxy-env` / `make unset-proxy-env` push or strip `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` env vars into exactly that list and roll the deployments. If you add a component that needs proxy access, add it to `PROXY_DEPLOYMENTS` rather than handling it ad hoc.

## Typical workflows

**Spin up the base platform only** (no BNG, no Containerlab):
```bash
make try-nok
```

**Full BNG demo with GitOps** (Containerlab + Flux, no auth):
```bash
make try-nok-bng
```

**Everything, including the emulated router lab** (requires SROS image + license):
```bash
sudo make deploy-bng   # per README.md: cluster + base + BNG apps + Containerlab
```

**Generate subscriber traffic** once the BNG lab is up:
```bash
sudo docker exec -it clab-sros-bngt-bngblaster bash -c 'bngblaster -C pppoe.json -I -l dhcp'
```

**Tear everything down**:
```bash
make destroy-clab-bng   # if Containerlab was deployed
make delete-cluster
```

## Where to go next

- `docs/NetOpsKube_Installation_Guide.md` — detailed, step-by-step install instructions.
- `docs/GITEA-AND-FLUX-GITOPS-SETUP.md` — manual walkthrough of the GitOps bootstrap.
- `docs/TROUBLESHOOTING.md` and `make help-troubleshoot` — day-2 operational commands.
- `docs/NETWORK-DEVICE-TARGET.md` — full `NetworkDeviceTarget` CRD reference.
- `CLAUDE.md` — orientation for AI coding agents working in this repo (Makefile target map, dependency graph, GitOps flow internals).
