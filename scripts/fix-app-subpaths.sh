#!/usr/bin/env bash
# Fix Grafana/Prometheus subpath URLs so apps load in the portal iframe.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECTL="$ROOT/tools/kubectl"
[[ -x "$KUBECTL" ]] || KUBECTL=kubectl

patch_if_exists() {
  local kind="$1" name="$2" ns="$3" patch="$4"
  if $KUBECTL get "$kind" "$name" -n "$ns" &>/dev/null; then
    echo "==> Patch $kind/$name ($ns)"
    $KUBECTL patch "$kind" "$name" -n "$ns" --type merge -p "$patch"
  fi
}

echo "==> Grafana + Prometheus subpath URLs"

patch_if_exists grafana grafana nok-bng \
  '{"spec":{"config":{"server":{"root_url":"http://bng.nok.local:8080/nok-bng/grafana/","serve_from_sub_path":"false"}}}}'

patch_if_exists grafana bbm-grafana nok-bbm \
  '{"spec":{"config":{"server":{"root_url":"http://bng.nok.local:8080/bbm/","serve_from_sub_path":"false"},"security":{"allow_embedding":"true"}},"deployment":{"spec":{"template":{"spec":{"containers":[{"name":"grafana","env":[{"name":"GF_SECURITY_ALLOW_EMBEDDING","value":"true"}]}]}}}}}}'

patch_if_exists prometheus nok-bng nok-bng \
  '{"spec":{"externalUrl":"/nok-bng/prometheus","routePrefix":"/"}}'

if $KUBECTL get kustomization prometheus -n flux-system &>/dev/null; then
  gitea_external=$(
    curl -fsS --resolve bng.nok.local:8080:127.0.0.1 \
      "http://bng.nok.local:8080/gitea/nok/nok-bng-resources/raw/branch/main/prometheus/prometheus.yaml" 2>/dev/null \
      | awk '/externalUrl:/ {print $2; exit}'
  )
  if [[ "$gitea_external" == "/prometheus" ]]; then
    echo "==> Suspend Flux prometheus kustomization (Gitea has stale externalUrl: /prometheus)"
    $KUBECTL patch kustomization prometheus -n flux-system --type merge -p '{"spec":{"suspend":true}}' || true
    echo "    Permanent fix: cd netopskube && make push-bng-manifests"
    echo "    Then: kubectl patch kustomization prometheus -n flux-system --type merge -p '{\"spec\":{\"suspend\":false}}'"
  fi
fi

echo "==> Wait for Grafana rollouts"
for ns in nok-bng nok-bbm; do
  for deploy in grafana-deployment bbm-grafana-deployment; do
    if $KUBECTL get deploy "$deploy" -n "$ns" &>/dev/null; then
      $KUBECTL rollout status "deployment/$deploy" -n "$ns" --timeout=180s || true
    fi
  done
done

echo "==> Verify subpath redirects"
check_location() {
  local path="$1" expect="$2"
  local loc
  loc=$(curl -sSI --resolve bng.nok.local:8080:127.0.0.1 "http://bng.nok.local:8080${path}" \
    | tr -d '\r' | awk -F': ' '/^Location:/ {print $2; exit}')
  if [[ -n "$loc" && "$loc" == *"$expect"* ]]; then
    echo "PASS: $path → $loc"
  elif [[ -z "$loc" ]]; then
    echo "PASS: $path → 200 (no redirect)"
  else
    echo "WARN: $path → $loc (expected *${expect}*)" >&2
  fi
}

check_location "/nok-bng/prometheus/graph" "/nok-bng/prometheus"
check_location "/nok-bng/grafana/dashboards" "/nok-bng/grafana"
check_location "/bbm/dashboards" "/bbm"

echo "==> Subpath fixes applied"
