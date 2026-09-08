#!/usr/bin/env bash
# Remove common NetOpsKube lab cruft (safe defaults; use flags for recipes).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECTL="$ROOT/tools/kubectl"
[[ -x "$KUBECTL" ]] || KUBECTL=kubectl

PRUNE_AURA=YES
PRUNE_DIA_PORTAL=YES
PRUNE_DIA_NS=NO
PRUNE_ALERT_WEBHOOK=YES

usage() {
  cat <<'EOF'
Usage: cluster-prune.sh [options]

  --all-dia          Delete entire nok-dia namespace (Flux may recreate)
  --no-aura          Skip aura-kind namespace
  --help             Show this help

Removes by default:
  - aura-kind namespace (unrelated crash-looping stack)
  - duplicate portal deployment in nok-dia
  - alert-webhook-test in nok-bng
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all-dia) PRUNE_DIA_NS=YES ;;
    --no-aura) PRUNE_AURA=NO ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ "$PRUNE_AURA" == YES ]]; then
  echo "==> Deleting aura-kind (not NetOpsKube)"
  $KUBECTL delete namespace aura-kind --ignore-not-found --wait=false
fi

if [[ "$PRUNE_DIA_PORTAL" == YES ]]; then
  echo "==> Removing duplicate portal in nok-dia (unified portal is in nok-base)"
  $KUBECTL delete deployment nok-apps-portal-app -n nok-dia --ignore-not-found --wait=true
  $KUBECTL delete ingress nok-apps-portal-ingress -n nok-dia --ignore-not-found
  $KUBECTL delete configmap nok-apps-portal-html-config nok-apps-portal-nginx-config \
    -n nok-dia --ignore-not-found 2>/dev/null || true
fi

if [[ "$PRUNE_DIA_NS" == YES ]]; then
  echo "==> Deleting nok-dia namespace"
  $KUBECTL delete namespace nok-dia --ignore-not-found --wait=false
fi

if [[ "$PRUNE_ALERT_WEBHOOK" == YES ]]; then
  echo "==> Removing alert-webhook-test (lab only)"
  $KUBECTL delete deployment alert-webhook-test -n nok-bng --ignore-not-found --wait=true
fi

echo "==> Done. Pod count:"
$KUBECTL get pods -A --no-headers 2>/dev/null | wc -l || true
