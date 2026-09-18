#!/usr/bin/env bash
# Push recipe Grafana dashboard JSON to in-cluster Gitea (preserves other recipe prefixes).
# Usage: push-grafana-dashboards.sh bng|dia|cgnat
set -euo pipefail

RECIPE="${1:?usage: push-grafana-dashboards.sh bng|dia|cgnat}"

: "${GRAFANA_DASHBOARDS_STAGING:?GRAFANA_DASHBOARDS_STAGING required}"
: "${FLUX_GRAFANA_REPO:?FLUX_GRAFANA_REPO required}"
: "${FLUX_GIT_BRANCH:?FLUX_GIT_BRANCH required}"
: "${GITEA_SSH_HOST:?GITEA_SSH_HOST required}"
: "${GITEA_ADMIN_USER:?GITEA_ADMIN_USER required}"
: "${FLUX_SSH_KEY:?FLUX_SSH_KEY required}"
: "${NOK_CLABS_DIR:?NOK_CLABS_DIR required}"

BNG_GRAFANA_REPO_PREFIX="${BNG_GRAFANA_REPO_PREFIX:-bng}"
DIA_GRAFANA_REPO_PREFIX="${DIA_GRAFANA_REPO_PREFIX:-dia}"
CGNAT_GRAFANA_REPO_PREFIX="${CGNAT_GRAFANA_REPO_PREFIX:-cgnat}"

case "$RECIPE" in
  bng)
    SRC_DIR="${NOK_CLABS_DIR}/nok-bng/grafana-dashboards"
    PREFIX="$BNG_GRAFANA_REPO_PREFIX"
    ;;
  dia)
    SRC_DIR="${NOK_CLABS_DIR}/nok-dia/grafana-dashboards"
    PREFIX="$DIA_GRAFANA_REPO_PREFIX"
    ;;
  cgnat)
    SRC_DIR="${NOK_CLABS_DIR}/nok-cgnat/grafana-dashboards"
    PREFIX="$CGNAT_GRAFANA_REPO_PREFIX"
    ;;
  *)
    echo "ERROR: RECIPE must be bng, dia, or cgnat (got '$RECIPE')" >&2
    exit 1
    ;;
esac

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: $SRC_DIR not found — run 'make git-clone-clab' first" >&2
  exit 1
fi

shopt -s nullglob
json_files=("$SRC_DIR"/*.json)
if [[ ${#json_files[@]} -eq 0 ]]; then
  echo "ERROR: no dashboard JSON files in $SRC_DIR" >&2
  exit 1
fi

REPO_URL="ssh://git@${GITEA_SSH_HOST}/${GITEA_ADMIN_USER}/${FLUX_GRAFANA_REPO}.git"
export GIT_SSH_COMMAND="ssh -o IdentitiesOnly=yes -i ${FLUX_SSH_KEY} -o StrictHostKeyChecking=no"

echo "--> GIT: Pushing ${RECIPE} Grafana dashboards to ${FLUX_GRAFANA_REPO}/${PREFIX}/"
rm -rf "${GRAFANA_DASHBOARDS_STAGING}"
mkdir -p "${GRAFANA_DASHBOARDS_STAGING}"

if git clone --depth 1 -b "${FLUX_GIT_BRANCH}" "$REPO_URL" "${GRAFANA_DASHBOARDS_STAGING}" 2>/dev/null; then
  echo "    Cloned existing ${FLUX_GRAFANA_REPO} repo"
else
  mkdir -p "${GRAFANA_DASHBOARDS_STAGING}"
  git -C "${GRAFANA_DASHBOARDS_STAGING}" init -b "${FLUX_GIT_BRANCH}"
  git -C "${GRAFANA_DASHBOARDS_STAGING}" remote add origin "$REPO_URL"
fi

mkdir -p "${GRAFANA_DASHBOARDS_STAGING}/${PREFIX}"
cp "${json_files[@]}" "${GRAFANA_DASHBOARDS_STAGING}/${PREFIX}/"

cd "${GRAFANA_DASHBOARDS_STAGING}"
git add -A
git commit -m "Grafana dashboards (${RECIPE})" --allow-empty
git push --force origin "${FLUX_GIT_BRANCH}"

echo "--> GIT: ${RECIPE} Grafana dashboards push completed"
