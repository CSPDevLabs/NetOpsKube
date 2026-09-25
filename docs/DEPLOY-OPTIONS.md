# Deploy-time options

Makefile / environment flags for optional components and observability tuning.

## SDCIO optional deployment

```bash
# Default: SDCIO platform + recipe exporters enabled
make try-nok-bng

# Observability-only (no SDCIO config-server, no recipe SDCIO exporters/GitOps dirs)
make SDCIO_ENABLED=NO try-nok-bng
```

| `SDCIO_ENABLED` | Effect |
|-----------------|--------|
| `YES` / `yes` / `Yes` (default) | Deploy SDCIO config-server (nok-base), ndt-sdcio-visual (recipe kpt), Flux dirs `sdcio` + `schemas` |
| Anything else | Skip above; gNMIc + Prometheus + Grafana unchanged |

Per-device opt-out remains available: `spec.sdcio.enabled: false` on NetworkDeviceTarget CRs.

**Note:** `configure-sdcio-kpt` adds package-root `.krmignore` patterns (`sdcio/**`, `ndt-sdcio-visual/**`) so kpt stops applying those paths. kpt only reads `.krmignore` at a package root (directory with a `Kptfile`) or nested subpackages — not under arbitrary subfolders.

Switching from enabled to disabled on an existing cluster **will prune** SDCIO resources on the next `kpt live apply` (`--inventory-policy=adopt`), including config-server PVCs (4×10Gi per [SIZING-GUIDE.md](SIZING-GUIDE.md)). To keep data, leave SDCIO enabled, back up PVCs, or redeploy on a fresh cluster.

## Prometheus / gNMIc tuning

See [PROMETHEUS-GNMIC-TUNING.md](PROMETHEUS-GNMIC-TUNING.md) for sizing guidance.

```bash
make PROM_RETENTION=7d PROM_RETENTION_SIZE=8GB PROM_STORAGE_SIZE=20Gi \
     GNMIC_REPLICAS=2 GNMIC_CPU_REQUEST=500m GNMIC_MEMORY_LIMIT=2Gi \
     try-nok-bng
```

| Variable | Default | Applies to |
|----------|---------|------------|
| `PROM_RETENTION` | `24h` | BBM Prometheus CR + recipe Prometheus |
| `PROM_RETENTION_SIZE` | _(empty)_ | BBM Prometheus CR + recipe Prometheus |
| `PROM_STORAGE_SIZE` | _(unset)_ | Recipe Prometheus PVC (adds PVC when set) |
| `GNMIC_REPLICAS` | `1` | All gNMIc Cluster CRs in recipe manifests |
| `GNMIC_CPU_REQUEST` | _(unset)_ | gNMIc Cluster CRs |
| `GNMIC_MEMORY_REQUEST` | _(unset)_ | gNMIc Cluster CRs |
| `GNMIC_CPU_LIMIT` | _(unset)_ | gNMIc Cluster CRs |
| `GNMIC_MEMORY_LIMIT` | _(unset)_ | gNMIc Cluster CRs |

BBM: `make update-kpt-tuning-setters` patches `nok-bbm/prometheus/prometheus-cr.yaml` before `install-bbm-pkg` (direct `yq` until kpt package exposes retention setters).

Recipe values are applied at manifest push time (`push-bng-manifests` / `push-dia-manifests`).

## Grafana dashboards (proxy-restricted environments)

BNG and DIA dashboards are delivered from in-cluster Gitea repo `grafana-dashboards`:

- BNG JSON: `bng/` prefix (`bng/bng-core-aggregation.json`, …)
- DIA JSON: `dia/` prefix (`dia/routing-and-fdb.json`, …)

```bash
# Default: in-cluster Gitea URLs in GrafanaDashboard CRs
make gitops-bng-kustomization

# Fallback when Gitea is not used (requires cluster egress to GitHub)
make GRAFANA_DASHBOARD_SOURCE=upstream gitops-bng-kustomization
```

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_DASHBOARD_SOURCE` | `gitea` | `gitea` or `upstream` |
| `GRAFANA_DASHBOARD_GITEA_BASE` | `http://gitea-http.nok-git.svc.cluster.local:3000/<GITEA_ADMIN_USER>/grafana-dashboards/raw/branch/main` | Base URL for dashboard JSON |
| `FLUX_GRAFANA_REPO` | `grafana-dashboards` | Gitea repo name |

Push dashboards per recipe: `make push-bng-grafana-dashboards` or `make push-dia-grafana-dashboards` (included in the matching `gitops-*-kustomization` target).

Interim without Gitea: set `GRAFANA_DASHBOARD_SOURCE=upstream` or embed JSON in manifests manually (GrafanaDashboard `spec.json`).

## Gitea image (KinD, corporate networks)

`install-git-pkg` runs `patch-gitea-kpt-manifest` and `preload-gitea-image` so the cluster uses a pullable image (default Docker Hub, not `docker.gitea.com`).

```bash
make preload-gitea-image    # optional if install-git-pkg will run anyway
make install-git-pkg
```

| Variable | Default | Description |
|----------|---------|-------------|
| `GITEA_IMAGE` | `docker.io/gitea/gitea:1.25.4-rootless` | Image written into kpt `nok-git` and loaded into KinD |
| `GITEA_IMAGE_PLATFORM` | `linux/$(ARCH)` from host `uname -m` (`linux/amd64` on x86_64, `linux/arm64` on aarch64) | Platform for `docker pull` / `docker save` when loading into KinD |

Preload pulls one platform (e.g. `linux/amd64`), then `docker save` piped to `ctr images import` on the KinD node **without** `--all-platforms`. `kind load docker-image` fails here because the Gitea tag’s index lists amd64, arm64, and riscv64 while the host only has amd64 layers ([kind known issue](https://kind.sigs.k8s.io/docs/user/known-issues/)).

If preload still fails after a manual `docker pull --platform linux/amd64`, ensure KinD exists (`make cluster-up`) and Docker is usable (`docker info`). On hosts with a broken system Docker wrapper, use `export PATH=$PWD/tools:$PATH` as in the main README.
