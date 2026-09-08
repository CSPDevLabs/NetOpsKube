#!/usr/bin/env bash
# Build portal static ConfigMap from kpt files (no KinD docker cp required).
# Safe on KinD: scale to 0 before replacing ConfigMaps (avoids CrashLoop + stuck rollouts).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECTL="$ROOT/tools/kubectl"
[[ -x "$KUBECTL" ]] || KUBECTL=kubectl
KUBECTL_TIMEOUT="${KUBECTL_TIMEOUT:-60}"

PORTAL="${PORTAL_DIR:-}"
if [[ -z "$PORTAL" ]]; then
  for candidate in \
    "$ROOT/../kpt/nok-base/portal" \
    "$ROOT/../../kpt/nok-base/portal" \
    "$ROOT/nok-kpt/nok-base/portal"; do
    if [[ -d "$candidate" && -f "$candidate/index.html" ]]; then
      PORTAL="$candidate"
      break
    fi
  done
fi
[[ -n "$PORTAL" && -f "$PORTAL/index.html" ]] || {
  echo "ERROR: portal dir not found. Set PORTAL_DIR=../kpt/nok-base/portal" >&2
  exit 1
}

SOURCE_VERSION="$(grep -o 'class="version">[^<]*' "$PORTAL/index.html" | head -1 | sed 's/.*>//')"
echo "==> Portal source: $PORTAL ($SOURCE_VERSION)"
if [[ "$SOURCE_VERSION" != "v2.0" ]]; then
  echo "WARN: expected portal v2.0 in source; found '${SOURCE_VERSION:-unknown}'." >&2
  echo "      Use PORTAL_DIR pointing at your updated kpt/nok-base/portal checkout." >&2
fi

NS=nok-base
DEPLOY=nok-apps-portal-app
LABEL='app=nok-apps-portal'

MENU_TMP="$(mktemp)"
trap 'rm -f "$MENU_TMP"' EXIT

kubectl() {
  if ! timeout "$KUBECTL_TIMEOUT" "$KUBECTL" "$@"; then
    echo "ERROR: kubectl failed (timeout ${KUBECTL_TIMEOUT}s): $*" >&2
    return 1
  fi
}

check_cluster() {
  echo "==> Checking cluster access"
  if ! timeout 15 "$KUBECTL" cluster-info &>/dev/null; then
    echo "ERROR: cannot reach Kubernetes API. Start KinD and check KUBECONFIG." >&2
    exit 1
  fi
}

stop_portal() {
  echo "==> Stopping portal (scale to 0, clear stuck pods/ReplicaSets)"
  kubectl scale "deployment/$DEPLOY" -n "$NS" --replicas=0 || true
  kubectl wait --for=delete pod -l "$LABEL" -n "$NS" --timeout=120s 2>/dev/null || true
  kubectl delete pods -n "$NS" -l "$LABEL" --force --grace-period=0 2>/dev/null || true
  # Remove ALL old ReplicaSets (not only scale=0) — fixes dual-RS / CrashLoop state
  kubectl delete rs -n "$NS" -l "$LABEL" 2>/dev/null || true
}

ready_pod() {
  kubectl get pods -n "$NS" -l "$LABEL" \
    -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==true)].metadata.name}' 2>/dev/null \
    | awk '{print $1}'
}

dump_portal_diagnostics() {
  echo "==> Portal diagnostics" >&2
  kubectl get pods,rs -n "$NS" -l "$LABEL" 2>/dev/null || true
  local pod
  pod="$(kubectl get pods -n "$NS" -l "$LABEL" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "$pod" ]]; then
    kubectl describe pod "$pod" -n "$NS" 2>/dev/null | tail -25 >&2 || true
    kubectl logs "$pod" -n "$NS" --tail=40 2>/dev/null >&2 || true
  fi
}

create_portal_static_configmap() {
  local menu_file="$1"
  # icons.js is large (~230KB); kubectl apply adds a last-applied-configuration
  # annotation that exceeds the 256KB annotation limit — use create instead.
  # Only run while portal is scaled to 0 (no pod mounts during delete/create).
  kubectl delete configmap nok-apps-portal-static -n "$NS" --ignore-not-found
  kubectl create configmap nok-apps-portal-static -n "$NS" \
    --from-file=index.html="$PORTAL/index.html" \
    --from-file=styles.css="$PORTAL/styles.css" \
    --from-file=icons.js="$PORTAL/icons.js" \
    --from-file=menu-config.json="$menu_file"
}

verify_menu_config() {
  local pod code body
  pod="$(ready_pod)"
  if [[ -z "$pod" ]]; then
    dump_portal_diagnostics
    echo "ERROR: no Ready portal pod after rollout" >&2
    return 1
  fi
  if ! kubectl exec -n "$NS" "$pod" -- test -s /usr/share/nginx/html/menu-config.json 2>/dev/null; then
    kubectl exec -n "$NS" "$pod" -- ls -la /usr/share/nginx/html/ 2>/dev/null || true
    echo "ERROR: menu-config.json missing in pod $pod" >&2
    return 1
  fi
  code="$(kubectl exec -n "$NS" "$pod" -- wget -qO- -S http://127.0.0.1/menu-config.json 2>&1 \
    | awk '/HTTP\// {print $2; exit}')"
  if [[ "$code" != "200" ]]; then
    echo "ERROR: /menu-config.json returned HTTP ${code:-unknown} in pod $pod" >&2
    return 1
  fi
  body="$(kubectl exec -n "$NS" "$pod" -- wget -qO- http://127.0.0.1/menu-config.json 2>/dev/null || true)"
  if ! grep -q '"solutions"' <<<"$body"; then
    echo "ERROR: menu-config.json is not valid portal menu JSON" >&2
    echo "$body" | head -5 >&2
    return 1
  fi
  echo "==> Verified menu-config.json in pod $pod"
}

patch_menu_auth_required() {
  local menu_file="$1"
  local required="false"

  if [[ "${KEYCLOAK_ENABLED:-}" == "YES" ]]; then
    required="true"
  elif timeout 10 "$KUBECTL" get deploy keycloak -n nok-base &>/dev/null; then
    required="true"
    echo "==> Keycloak detected; enabling portal auth gate"
  fi

  python3 - "$menu_file" "$required" <<'PY'
import json, sys
path, required = sys.argv[1], sys.argv[2] == "true"
with open(path, encoding="utf-8") as f:
    menu = json.load(f)
menu.setdefault("auth", {})["required"] = required
menu["auth"]["loginUrl"] = "/login"
with open(path, "w", encoding="utf-8") as f:
    json.dump(menu, f, indent=2)
    f.write("\n")
PY
}

verify_portal_version() {
  local pod version
  pod="$(ready_pod)"
  [[ -n "$pod" ]] || return 1
  version="$(kubectl exec -n "$NS" "$pod" -- grep -o 'class="version">[^<]*' /usr/share/nginx/html/index.html 2>/dev/null | head -1 | sed 's/.*>//' || true)"
  if [[ "$version" == "v2.0" ]]; then
    echo "==> Verified portal UI $version in pod $pod"
    return 0
  fi
  echo "ERROR: cluster portal is '${version:-unknown}' (expected v2.0). Wrong PORTAL_DIR or stale ConfigMap." >&2
  echo "       Re-run: PORTAL_DIR=$PORTAL make fix-portal" >&2
  return 1
}

start_portal() {
  echo "==> Starting portal (scale to 1)"
  kubectl apply -f "$PORTAL/deploy.yaml"
  kubectl scale "deployment/$DEPLOY" -n "$NS" --replicas=1
  if ! kubectl rollout status "deployment/$DEPLOY" -n "$NS" --timeout=180s; then
    dump_portal_diagnostics
    return 1
  fi
}

check_cluster
echo "==> Deploying portal static files"

stop_portal

kubectl apply -f "$PORTAL/portal-menu-config.yaml"
kubectl get configmap nok-apps-menu-config -n "$NS" \
  -o jsonpath='{.data.menu-config\.json}' > "$MENU_TMP"
if [[ ! -s "$MENU_TMP" ]]; then
  echo "ERROR: nok-apps-menu-config has no menu-config.json data" >&2
  exit 1
fi
patch_menu_auth_required "$MENU_TMP"

kubectl apply -f "$PORTAL/portal-nok-apps-nginx-config.yaml"
kubectl apply -f "$PORTAL/deploy.yaml"
create_portal_static_configmap "$MENU_TMP"

start_portal
verify_menu_config
verify_portal_version

echo "==> Portal updated successfully ($SOURCE_VERSION)"
echo "    Open: http://bng.nok.local:8080/  (hard-refresh: Ctrl+Shift+R)"
