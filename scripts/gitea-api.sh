#!/usr/bin/env bash
# Call Gitea REST API via the running Gitea pod (avoids ingress subpath / 405 issues).
# Usage: gitea-api.sh /user/keys
#        GITEA_API_METHOD=POST GITEA_API_DATA='{"title":"x","key":"y"}' gitea-api.sh /user/keys
set -euo pipefail

ENDPOINT="${1:?usage: gitea-api.sh /user/keys}"
METHOD="${GITEA_API_METHOD:-GET}"
DATA="${GITEA_API_DATA:-}"

: "${GITOPS_NAMESPACE:?GITOPS_NAMESPACE required}"
: "${GITEA_ADMIN_USER:?GITEA_ADMIN_USER required}"
: "${GITEA_ADMIN_PASS:?GITEA_ADMIN_PASS required}"
KUBECTL="${KUBECTL:-kubectl}"

POD="$("$KUBECTL" get pods -n "$GITOPS_NAMESPACE" -l app.kubernetes.io/name=gitea \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')"
if [ -z "$POD" ]; then
  echo "ERROR: no running Gitea pod in namespace $GITOPS_NAMESPACE" >&2
  exit 1
fi

CURL_ARGS=(curl -sf -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" -X "$METHOD")
if [ -n "$DATA" ]; then
  CURL_ARGS+=(-H "Content-Type: application/json" -d "$DATA")
fi
CURL_ARGS+=("http://localhost:3000/api/v1${ENDPOINT}")

exec "$KUBECTL" exec -n "$GITOPS_NAMESPACE" "$POD" -c gitea -- "${CURL_ARGS[@]}"
