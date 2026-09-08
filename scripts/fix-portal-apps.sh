#!/usr/bin/env bash
# Fix HAProxy routing + recipe ingress paths so portal apps open (Gitea, Grafana, …).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECTL="$ROOT/tools/kubectl"
[[ -x "$KUBECTL" ]] || KUBECTL=kubectl
H="$ROOT/manifests/auth/haproxy"
KPT_BNG="${KPT_BNG_INGRESS:-$ROOT/../kpt/nok-bng/ingress/ingress.yaml}"
[[ -f "$KPT_BNG" ]] || KPT_BNG="$ROOT/nok-kpt/nok-bng/ingress/ingress.yaml"

echo "==> [1/4] HAProxy: portal static only; apps → ingress-nginx"
$KUBECTL apply -f "$H/haproxy-configmap.yaml"
$KUBECTL rollout restart deployment/nok-haproxy -n nok-base
$KUBECTL rollout status deployment/nok-haproxy -n nok-base --timeout=120s

echo "==> [2/5] BNG ingress paths (/nok-bng/prometheus, …)"
$KUBECTL apply -f "$KPT_BNG"
$KUBECTL apply -f "${KPT_BNG%/ingress/ingress.yaml}/portal/portal-gitea-proxy-svc.yaml" 2>/dev/null || true
$KUBECTL apply -f "${KPT_BNG%/ingress/ingress.yaml}/portal/portal-bbm-grafana-proxy-svc.yaml" 2>/dev/null || true

echo "==> [3/5] Grafana/Prometheus subpath URLs (iframe-safe)"
bash "$ROOT/scripts/fix-app-subpaths.sh"

echo "==> [4/5] Strip oauth2-proxy auth-url from ingresses"
bash "$ROOT/scripts/strip-oauth2-ingress-auth.sh"

echo "==> [5/5] Verify app paths"
bash "$ROOT/scripts/test-portal-apps.sh"

echo ""
echo "==> Apps should open from portal. Hard-refresh: http://bng.nok.local:8080/"
