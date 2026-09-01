# NetOpsKube sizing guide (compute & storage)

Customer-facing reference for planning CPU, memory, and disk for NetOpsKube deployments. Values below reflect **current defaults** in kpt / nok-clabs manifests unless noted.

## Deployment profiles

| Profile | Use case | Recipes | SDCIO | Typical devices |
|---------|----------|---------|-------|-----------------|
| **Lab / KinD** | Dev, demo, CI | BNG or DIA | On (default) | 1–5 (containerlab) |
| **Single recipe** | One production recipe | BNG **or** DIA | Optional | 10–50 |
| **Dual recipe** | BNG + DIA on one cluster | Both | Optional | 10–50 per recipe |
| **Platform only** | BBM + portal, no recipe | None | Off | N/A |

---

## Control plane (always on with `make try-nok`)

| Component | Namespace | Replicas | CPU (req) | Memory (req) | Storage | Notes |
|-----------|-----------|----------|-----------|--------------|---------|-------|
| ingress-nginx | nok-base | 1 | — | — | — | KinD LB via MetalLB |
| cert-manager | nok-base | 3 pods | — | — | — | |
| prometheus-operator | nok-base | 1 | — | — | — | CRD controller |
| gnmic-operator | nok-base | 1 | 500m limit | 128Mi limit | — | Manages gNMIc clusters |
| grafana-operator | nok-base | 1 | — | — | — | |
| nok-controller | nok-base | 1 | — | — | — | NDT → gNMIc/SDCIO glue |
| **SDCIO config-server** | nok-base | 1 | — | — | **4× 10Gi PVC** | Skip when `SDCIO_ENABLED=NO` |
| Portal | nok-base / recipe | 1 | 50m | 64Mi | 1Gi PVC (base) | Unified portal on `nok-restructure` |

**Lab minimum (KinD node):** 4 vCPU, 8 GiB RAM, 50 GiB disk (Docker host). Tight but workable for one recipe + clab.

**Recommended lab:** 8 vCPU, 16 GiB RAM, 100 GiB disk.

---

## BBM (platform observability — `make install-bbm-pkg`)

| Component | CPU | Memory | Storage | Retention |
|-----------|-----|--------|---------|-----------|
| BBM Prometheus | — | 400Mi req | **10Gi PVC** | **24h** (operator default; not set in CR) |
| BBM Grafana | 250m req | — | 1Gi PVC | — |
| blackbox-exporter | — | — | — | — |
| kube-state-metrics | — | — | — | — |

BBM scrapes platform health (ingress, gNMIc reachability, node ping). Scale storage if keeping >24h or high-cardinality probes.

---

## Per recipe (BNG or DIA — `make try-nok-bng` / `try-nok-dia`)

### Observability core

| Component | Replicas | CPU | Memory | Storage | Retention |
|-----------|----------|-----|--------|---------|-----------|
| Recipe Prometheus | 1 | — | 400Mi req | **none (ephemeral)** | **24h** default |
| Alertmanager | 1 | — | — | — | 120h default |
| Grafana | 1 | — | — | 10Gi PVC (nok-clabs) | — |
| Loki | 1 | — | — | — | — |
| fluent-bit / promtail | 1 each | — | — | — | — |

**Production recommendation:** add PVC to recipe Prometheus (start **20–50Gi**) and set `retention` / `retentionSize` explicitly (see tuning doc).

### gNMIc collectors (nok-clabs `gnmic/clusters/`)

| Cluster (BNG) | Replicas | Image | Purpose |
|---------------|----------|-------|---------|
| `bng-metrics` | **1** | gnmic:latest | Telemetry → Prometheus |
| `bng-state` | **1** | gnmic:latest | State subscriptions |

| Cluster (DIA) | Replicas | Image | Purpose |
|---------------|----------|-------|---------|
| `dia-metrics` | **1** | 0.46.0 | Telemetry |
| `dia-state` | **1** | 0.46.0 | State |
| `dia-core-metrics` | **1** | 0.46.0 | Core metrics |

**No CPU/memory limits** are set on collector pods today — plan headroom on the node.

| Device count (per recipe) | gNMIc replicas (per cluster) | Notes |
|---------------------------|------------------------------|-------|
| 1–10 | 1 | Default |
| 10–30 | 1–2 | Monitor CPU on collector; split metrics vs state if needed |
| 30–100 | 2+ | Add replicas or additional clusters; size Prometheus PVC |
| 100+ | Scale out | Dedicated collectors per region/role; see tuning guidelines |

Rule of thumb: **~50–100 streaming subscriptions per gNMIc replica** before latency rises (validate in your environment).

### SDCIO (when enabled)

| Component | Namespace | Storage | Notes |
|-----------|-----------|---------|-------|
| config-server + data-server | nok-base | 4× 10Gi PVC | Platform config/schema |
| sdcio-metrics-exporter | recipe | — | Per-recipe metrics |
| GitOps: schemas, profiles, configs | via Flux | — | In `nok-clabs` manifests |

Disable at deploy time with `SDCIO_ENABLED=NO` (planned Makefile flag) to drop platform SDCIO + recipe exporters.

### Telemetry stack (per recipe)

| Component | Notes |
|-----------|-------|
| syslog-ng | LoadBalancer (syslog ingest) |
| lightweight-linux | Lab traffic / tools |
| ndt-metrics-exporter | NDT CR metrics |

---

## Dual recipe (BNG + DIA)

Approximate **multipliers** vs single recipe:

| Resource | Single recipe | BNG + DIA |
|----------|---------------|-----------|
| Recipe namespaces | 1 | 2 |
| Prometheus instances | 1 | 2 |
| gNMIc clusters | 2 (BNG) or 3 (DIA) | 5 total |
| Grafana instances | 1 | 2 |
| GitOps repos | 1–2 | 3–4 (+ `grafana-dashboards` for DIA) |

**Recommended dual-recipe node:** 16 vCPU, 32 GiB RAM, 200 GiB disk (lab); production sizes depend on device count and retention.

---

## KinD / MetalLB networking

| Resource | Default | Setter |
|----------|---------|--------|
| Ingress LB IP | `172.18.0.100` (template) | `ingress-lb-ip` — patched to KinD prefix at `cluster-up` |
| MetalLB pool | `.100–.120` | `metallb-pool-range` |
| Pod CIDR | `10.244.0.0/16` | `build/kind-cluster.yaml` |
| Service CIDR | `10.96.0.0/12` | `build/kind-cluster.yaml` |

---

## Tuning knobs

See [DEPLOY-OPTIONS.md](DEPLOY-OPTIONS.md) and [PROMETHEUS-GNMIC-TUNING.md](PROMETHEUS-GNMIC-TUNING.md).

| Knob | Default | Makefile variable |
|------|---------|-------------------|
| `SDCIO_ENABLED` | `YES` | `SDCIO_ENABLED=NO` |
| Prometheus `retention` | `24h` | `PROM_RETENTION` |
| Prometheus PVC (BBM) | `10Gi` | `PROM_STORAGE_SIZE_BBM` |
| Prometheus PVC (recipe) | ephemeral | `PROM_STORAGE_SIZE` |
| gNMIc `replicas` | `1` | `GNMIC_REPLICAS` |
| gNMIc resources | unset | `GNMIC_CPU_REQUEST`, `GNMIC_MEMORY_LIMIT`, … |

---

## Quick customer answers

**Q: Minimum VM for a demo with BNG + containerlab?**  
A: 8 vCPU, 16 GiB RAM, 100 GiB disk on the Docker/KinD host.

**Q: Do we need SDCIO?**  
A: Only if you use SDCIO config management and deviation metrics. Observability (gNMIc + Prometheus + Grafana) works without SDCIO platform pods; set `spec.sdcio.enabled: false` on NDTs or deploy with `SDCIO_ENABLED=NO`.

**Q: How long is metrics history kept?**  
A: **24 hours** by default (Prometheus operator default). BBM has 10Gi disk; recipe Prometheus is ephemeral unless you add storage.

**Q: How do we scale for more routers?**  
A: Increase gNMIc collector replicas, add Prometheus PVC + retention caps, and scale the KinD/production node per tables above.

---

## Related docs

- [Installation guide](NetOpsKube_Installation_Guide.md)
- [Corporate proxy / Grafana](Ubuntu-Deployment-In-Corporate-Environments.md)
- [Network Device Targets](NETWORK-DEVICE-TARGET.md)
- [Troubleshooting](TROUBLESHOOTING.md)
