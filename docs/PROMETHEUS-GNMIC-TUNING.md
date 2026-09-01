# Prometheus & gNMIc tuning guidelines

Operator guidance for adjusting retention, storage, and collector scale. Knobs are exposed via Makefile variables (see [DEPLOY-OPTIONS.md](DEPLOY-OPTIONS.md)).

## Prometheus

### Current defaults

| Instance | Location | `retention` | `retentionSize` | PVC |
|----------|----------|-------------|-----------------|-----|
| BBM | `kpt/nok-bbm/prometheus/prometheus-cr.yaml` | unset → **24h** | unset | **10Gi** |
| BNG recipe | `nok-clabs/.../prometheus/prometheus.yaml` | unset → **24h** | unset | **none** |
| DIA recipe | `nok-clabs/.../prometheus/prometheus.yaml` | unset → **24h** | unset | **none** |

### Recommendations

| Scenario | `retention` | `retentionSize` | PVC |
|----------|-------------|-----------------|-----|
| Lab / demo | `24h` or default | — | optional |
| Ops troubleshooting | `7d` | `8GB` | 20Gi |
| Longer trending | `15d` | `20GB` | 50Gi |
| High cardinality (many targets) | `24h`–`72h` | set byte cap | 50Gi+ |

Example patch on recipe Prometheus CR:

```yaml
spec:
  retention: 7d
  retentionSize: 8GB
  storage:
    volumeClaimTemplate:
      spec:
        resources:
          requests:
            storage: 20Gi
```

**Sizing guide:** allocate ~1–2 GiB per 100k active series per day of retention (rough order of magnitude; validate with `prometheus_tsdb_storage_blocks_bytes`).

---

## gNMIc collectors

### Current defaults

All clusters in `nok-clabs/nok-bng|dia/nok-manifests/gnmic/clusters/` use **`replicas: 1`** and **no `resources`** block.

| Recipe | Clusters | Typical subscriptions |
|--------|----------|------------------------|
| BNG | `bng-metrics`, `bng-state` | Per device × pipeline |
| DIA | `dia-metrics`, `dia-state`, `dia-core-metrics` | Per device × pipeline |

### When to increase replicas

| Signal | Action |
|--------|--------|
| Collector pod CPU >70% sustained | Increase `spec.replicas` or split subscriptions |
| Scrape lag / stale metrics | Add replica or reduce subs per cluster |
| >~50 devices on one cluster | Plan 2 replicas minimum |
| Mixed metrics + state load | Keep separate clusters (already split on BNG/DIA) |

Example:

```yaml
apiVersion: operator.gnmic.dev/v1alpha1
kind: Cluster
metadata:
  name: bng-metrics
  namespace: nok-bng
spec:
  replicas: 2
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: "2"
      memory: 2Gi
```

### Image pinning

- BNG uses `ghcr.io/openconfig/gnmic:latest` — **pin a version** in production (DIA uses `0.46.0`).
- Align BNG/DIA on the same gnmic version when tuning.

---

## Makefile variables

| Variable | Applies to | Example |
|----------|------------|---------|
| `PROM_RETENTION` | BBM + recipe Prometheus | `7d` |
| `PROM_RETENTION_SIZE` | BBM + recipe Prometheus | `8GB` |
| `PROM_STORAGE_SIZE_BBM` | BBM PVC | `10Gi` |
| `PROM_STORAGE_SIZE` | Recipe PVC (when set) | `20Gi` |
| `GNMIC_REPLICAS` | all clusters in recipe | `2` |
| `GNMIC_CPU_REQUEST` | Cluster CR | `500m` |
| `GNMIC_MEMORY_LIMIT` | Cluster CR | `2Gi` |

BBM: `make update-kpt-tuning-setters` writes kpt setters in `nok-bbm/apply-setters.yaml`.

Recipe: applied automatically when running `push-bng-manifests` / `push-dia-manifests` (staging copy + `yq` patch).

---

## Verification after changes

```bash
make verify-recipe-prometheus-ready RECIPE=bng
make verify-recipe-gnmic-subscriptions RECIPE=bng
NOK_RECIPE_VERIFY_LEVEL=full make verify-recipe-metrics RECIPE=bng
```

See [SIZING-GUIDE.md](SIZING-GUIDE.md) for node-level compute planning.
