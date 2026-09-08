#!/usr/bin/env bash
# Smoke-test portal app paths via HAProxy → ingress-nginx.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECTL="$ROOT/tools/kubectl"
[[ -x "$KUBECTL" ]] || KUBECTL=kubectl
CURL="curl -sS --resolve bng.nok.local:8080:127.0.0.1"
BASE="http://bng.nok.local:8080"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
check() {
  local path="$1" min="$2"
  local code
  code=$($CURL -o /dev/null -w '%{http_code}' "${BASE}${path}" || echo "000")
  if [[ "$code" -ge "$min" && "$code" -lt 400 ]]; then
    pass "GET ${path} → ${code}"
  else
    fail "GET ${path} → ${code} (expected 2xx/3xx)"
  fi
}

echo "==> Menu config"
$CURL "${BASE}/menu-config.json" | grep -q '"solutions"' || fail "menu-config.json invalid"
pass "menu-config.json"

echo "==> App paths (via HAProxy → ingress-nginx)"
check "/gitea/nok" 200
check "/bbm/dashboards" 200
check "/nok-bng/prometheus/graph" 200
check "/nok-bng/grafana/dashboards" 200
check "/nok-bng/alertmanager" 200

echo "==> All portal app checks passed"
