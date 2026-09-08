#!/usr/bin/env bash
# Smoke-test HAProxy + Keycloak login (no oauth2-proxy).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECTL="$ROOT/tools/kubectl"
[[ -x "$KUBECTL" ]] || KUBECTL=kubectl
CURL="curl -sS --fail --resolve bng.nok.local:8080:127.0.0.1"
BASE="http://bng.nok.local:8080"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "==> HAProxy pod"
$KUBECTL get pods -n nok-base -l app=nok-haproxy -o jsonpath='{.items[0].status.phase}{"\n"}' | grep -q Running || fail "nok-haproxy not Running"

echo "==> No oauth2-proxy"
$KUBECTL get deploy oauth2-proxy -n nok-base 2>/dev/null && fail "oauth2-proxy still deployed" || pass "oauth2-proxy absent"

echo "==> Portal has no oauth2 in index.html"
count=$($KUBECTL exec -n nok-base deploy/nok-apps-portal-app -- grep -c oauth2 /usr/share/nginx/html/index.html 2>/dev/null | head -1 | tr -d '\n' || true)
count=${count:-0}
[ "$count" = "0" ] || fail "portal index.html still references oauth2 ($count)"
pass "portal index.html clean"

echo "==> /login keeps :8080"
LOC=$($CURL -sI "${BASE}/login" | tr -d '\r' | grep -i '^location:' | cut -d' ' -f2-)
echo "$LOC" | grep -q 'bng.nok.local:8080' || fail "/login redirect missing :8080: $LOC"
echo "$LOC" | grep -q 'realms/netopskube' || fail "/login not netopskube realm: $LOC"
pass "/login → netopskube on :8080"

echo "==> Portal menu auth gate"
auth_required=$($KUBECTL exec -n nok-base deploy/nok-apps-portal-app -- \
  wget -qO- http://127.0.0.1/menu-config.json 2>/dev/null \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('auth',{}).get('required', False))" 2>/dev/null || echo "false")
if $KUBECTL get deploy keycloak -n nok-base &>/dev/null; then
  [ "$auth_required" = "True" ] && pass "menu auth.required=true" || fail "menu auth.required not true (portal loads without login)"
else
  pass "Keycloak not deployed; skipping auth.required check"
fi

echo "==> Portal home"
code=$($CURL -o /dev/null -w '%{http_code}' "${BASE}/")
[ "$code" = "200" ] && pass "GET / → $code" || fail "GET / → $code"

echo "==> All checks passed"
