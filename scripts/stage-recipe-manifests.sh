#!/usr/bin/env bash
# Stage nok-clabs recipe manifests for GitOps push (copy, tune, patch Grafana URLs).
# Called from make/deploy-tuning.mk — env: STAGING_DIR, SRC_DIR, RECIPE_LABEL, GRAFANA_PREFIX, YQ, tuning vars.
set -euo pipefail

: "${STAGING_DIR:?STAGING_DIR required}"
: "${SRC_DIR:?SRC_DIR required}"
: "${RECIPE_LABEL:?RECIPE_LABEL required}"
: "${GRAFANA_PREFIX:=}"
: "${YQ:?YQ required}"

command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync not found — install rsync or add to PATH" >&2; exit 1; }

PROM_RETENTION="${PROM_RETENTION:-24h}"
PROM_RETENTION_SIZE="${PROM_RETENTION_SIZE:-}"
PROM_STORAGE_SIZE="${PROM_STORAGE_SIZE:-}"
GNMIC_REPLICAS="${GNMIC_REPLICAS:-1}"
GNMIC_CPU_REQUEST="${GNMIC_CPU_REQUEST:-}"
GNMIC_MEMORY_REQUEST="${GNMIC_MEMORY_REQUEST:-}"
GNMIC_CPU_LIMIT="${GNMIC_CPU_LIMIT:-}"
GNMIC_MEMORY_LIMIT="${GNMIC_MEMORY_LIMIT:-}"
GRAFANA_DASHBOARD_SOURCE="${GRAFANA_DASHBOARD_SOURCE:-gitea}"
GRAFANA_DASHBOARD_GITEA_BASE="${GRAFANA_DASHBOARD_GITEA_BASE:-}"
GRAFANA_DASHBOARD_UPSTREAM_BASE="${GRAFANA_DASHBOARD_UPSTREAM_BASE:-}"

echo "--> STAGE [${RECIPE_LABEL}]: ${SRC_DIR} → ${STAGING_DIR}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
rsync -a --exclude '.git' "${SRC_DIR}/" "${STAGING_DIR}/"

PROM_FILE="${STAGING_DIR}/prometheus/prometheus.yaml"
if [[ -f "$PROM_FILE" ]]; then
  echo "--> TUNING: Prometheus settings in ${PROM_FILE}"
  "$YQ" eval ".spec.retention = \"${PROM_RETENTION}\"" -i "$PROM_FILE"
  if [[ -n "$PROM_RETENTION_SIZE" ]]; then
    "$YQ" eval ".spec.retentionSize = \"${PROM_RETENTION_SIZE}\"" -i "$PROM_FILE"
  else
    "$YQ" eval 'del(.spec.retentionSize)' -i "$PROM_FILE"
  fi
  if [[ -n "$PROM_STORAGE_SIZE" ]]; then
    "$YQ" eval ".spec.storage.volumeClaimTemplate.spec.resources.requests.storage = \"${PROM_STORAGE_SIZE}\"" -i "$PROM_FILE"
  fi
fi

for cluster in "${STAGING_DIR}"/gnmic/clusters/*.yaml; do
  [[ -f "$cluster" ]] || continue
  "$YQ" eval ".spec.replicas = ${GNMIC_REPLICAS}" -i "$cluster"
  [[ -n "$GNMIC_CPU_REQUEST" ]] && "$YQ" eval ".spec.resources.requests.cpu = \"${GNMIC_CPU_REQUEST}\"" -i "$cluster"
  [[ -n "$GNMIC_MEMORY_REQUEST" ]] && "$YQ" eval ".spec.resources.requests.memory = \"${GNMIC_MEMORY_REQUEST}\"" -i "$cluster"
  [[ -n "$GNMIC_CPU_LIMIT" ]] && "$YQ" eval ".spec.resources.limits.cpu = \"${GNMIC_CPU_LIMIT}\"" -i "$cluster"
  [[ -n "$GNMIC_MEMORY_LIMIT" ]] && "$YQ" eval ".spec.resources.limits.memory = \"${GNMIC_MEMORY_LIMIT}\"" -i "$cluster"
done

DASH_DIR="${STAGING_DIR}/grafana/dashboards"
if [[ -d "$DASH_DIR" ]]; then
  echo "--> STAGE [${RECIPE_LABEL}]: patching GrafanaDashboard URLs"
  shopt -s nullglob
  for cr in "$DASH_DIR"/*.yaml; do
    name="$("$YQ" eval '.metadata.name' "$cr")"
    if [[ "$GRAFANA_DASHBOARD_SOURCE" == "upstream" ]]; then
      url="${GRAFANA_DASHBOARD_UPSTREAM_BASE}/${RECIPE_LABEL}/grafana-dashboards/${name}.json"
    else
      if [[ -n "$GRAFANA_PREFIX" ]]; then
        path="${GRAFANA_PREFIX}/${name}.json"
      else
        path="${name}.json"
      fi
      url="${GRAFANA_DASHBOARD_GITEA_BASE}/${path}"
    fi
    "$YQ" eval ".spec.url = \"${url}\"" -i "$cr"
  done
fi

echo "--> STAGE [${RECIPE_LABEL}]: done"
