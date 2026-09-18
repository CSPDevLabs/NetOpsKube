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

**Note:** Switching from enabled to disabled on an existing cluster **can prune** SDCIO resources. `configure-sdcio-kpt` writes `*` into `.krmignore` under each SDCIO kpt subpackage; the next `kpt live apply` (with `--inventory-policy=adopt`) removes resources that drop out of the package — including config-server PVCs. To keep data, leave SDCIO enabled, back up PVCs, or redeploy on a fresh cluster.

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
| `PROM_RETENTION_SIZE` | _(unset)_ | BBM Prometheus CR + recipe Prometheus |
| `PROM_STORAGE_SIZE` | _(unset)_ | Recipe Prometheus PVC (adds PVC when set) |
| `GNMIC_REPLICAS` | `1` | All gNMIc Cluster CRs in recipe manifests |
| `GNMIC_CPU_REQUEST` | _(unset)_ | gNMIc Cluster CRs |
| `GNMIC_MEMORY_REQUEST` | _(unset)_ | gNMIc Cluster CRs |
| `GNMIC_CPU_LIMIT` | _(unset)_ | gNMIc Cluster CRs |
| `GNMIC_MEMORY_LIMIT` | _(unset)_ | gNMIc Cluster CRs |

BBM retention is patched on `nok-bbm/prometheus/prometheus-cr.yaml` via `make update-kpt-tuning-setters` (runs before `install-bbm-pkg`).
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
