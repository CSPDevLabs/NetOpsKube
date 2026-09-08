#!/usr/bin/env bash
# Deploy HAProxy gateway (Keycloak login at /login and /auth).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECTL="$ROOT/tools/kubectl"
[[ -x "$KUBECTL" ]] || KUBECTL=kubectl
H="$ROOT/manifests/auth/haproxy"
A="$ROOT/manifests/auth"

echo "==> [1/5] Keycloak (same-host /auth)"
$KUBECTL apply -f "$A/keycloak/keycloak-proxy-headers.yaml"
$KUBECTL apply -f "$A/keycloak/keycloak-deploy.yaml"
$KUBECTL rollout status deployment/keycloak -n nok-base --timeout=180s

echo "==> [2/5] HAProxy gateway (portal static + apps via ingress-nginx)"
$KUBECTL apply -f "$H/haproxy-configmap.yaml"
$KUBECTL apply -f "$H/haproxy-svc.yaml"
$KUBECTL apply -f "$H/haproxy-deploy.yaml"
$KUBECTL rollout status deployment/nok-haproxy -n nok-base --timeout=120s

echo "==> [3/5] Ingress → HAProxy"
$KUBECTL delete ingress keycloak-ingress nok-apps-portal-ingress \
  -n nok-base --ignore-not-found --wait=true
for ns in nok-bng nok-dia; do
  $KUBECTL delete ingress nok-apps-portal-ingress -n "$ns" --ignore-not-found --wait=true
done
$KUBECTL apply -f "$H/gateway-ingress.yaml"

echo "==> [4/5] Portal static + menu (Keycloak /login)"
bash "$ROOT/scripts/apply-portal-haproxy-auth.sh"

echo "==> [5/5] Strip oauth2-proxy auth-url from app ingresses (fixes 500)"
bash "$ROOT/scripts/strip-oauth2-ingress-auth.sh"

echo "==> [6/6] BNG ingress paths (/nok-bng/*)"
KPT_BNG="${KPT_BNG_INGRESS:-$ROOT/../kpt/nok-bng/ingress/ingress.yaml}"
[[ -f "$KPT_BNG" ]] || KPT_BNG="$ROOT/nok-kpt/nok-bng/ingress/ingress.yaml"
if [[ -f "$KPT_BNG" ]]; then
  $KUBECTL apply -f "$KPT_BNG"
fi

echo ""
echo "==> Verify"
bash "$ROOT/scripts/test-portal-apps.sh" || bash "$ROOT/scripts/test-auth-haproxy.sh"
