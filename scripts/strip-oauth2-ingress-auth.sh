#!/usr/bin/env bash
# Remove legacy nginx auth-url annotations that pointed at oauth2-proxy (causes 500).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECTL="$ROOT/tools/kubectl"
[[ -x "$KUBECTL" ]] || KUBECTL=kubectl

echo "==> Strip oauth2-proxy auth-url from app ingresses"
for ns in nok-bng nok-dia nok-bbm nok-git nok-base; do
  while IFS= read -r ing; do
    [ -n "$ing" ] || continue
    echo "    $ns/$ing"
    $KUBECTL annotate ingress "$ing" -n "$ns" \
      nginx.ingress.kubernetes.io/auth-url- \
      nginx.ingress.kubernetes.io/auth-signin- \
      nginx.ingress.kubernetes.io/auth-response-headers- \
      --overwrite 2>/dev/null || true
  done < <($KUBECTL get ingress -n "$ns" -o json 2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
for i in d.get('items',[]):
  a=i.get('metadata',{}).get('annotations') or {}
  if 'nginx.ingress.kubernetes.io/auth-url' in a or 'nginx.ingress.kubernetes.io/auth-signin' in a:
    print(i['metadata']['name'])
" 2>/dev/null || true)
done

echo "==> Done"
