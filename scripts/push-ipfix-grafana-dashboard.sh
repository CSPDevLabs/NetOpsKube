#!/usr/bin/env bash
# Publish only the BNG-specific IPFIX dashboard into the shared Gitea Grafana repository.
set -euo pipefail

: "${GRAFANA_DASHBOARDS_STAGING:?GRAFANA_DASHBOARDS_STAGING required}"
: "${FLUX_GRAFANA_REPO:?FLUX_GRAFANA_REPO required}"
: "${FLUX_GIT_BRANCH:?FLUX_GIT_BRANCH required}"
: "${GITEA_SSH_HOST:?GITEA_SSH_HOST required}"
: "${GITEA_ADMIN_USER:?GITEA_ADMIN_USER required}"
: "${FLUX_SSH_KEY:?FLUX_SSH_KEY required}"
: "${BNG_IPFIX_GRAFANA_SOURCE_DIR:?BNG_IPFIX_GRAFANA_SOURCE_DIR required}"
: "${BNG_IPFIX_GRAFANA_DASHBOARD:?BNG_IPFIX_GRAFANA_DASHBOARD required}"

PREFIX="${BNG_IPFIX_GRAFANA_REPO_PREFIX:-bng}"
SRC_FILE="${BNG_IPFIX_GRAFANA_SOURCE_DIR}/${BNG_IPFIX_GRAFANA_DASHBOARD}"

if [[ ! -f "$SRC_FILE" ]]; then
  echo "ERROR: IPFIX dashboard not found: $SRC_FILE" >&2
  exit 1
fi

REPO_URL="ssh://git@${GITEA_SSH_HOST}/${GITEA_ADMIN_USER}/${FLUX_GRAFANA_REPO}.git"
export GIT_SSH_COMMAND="ssh -o IdentitiesOnly=yes -i ${FLUX_SSH_KEY} -o StrictHostKeyChecking=no"

echo "--> IPFIX: Publishing ${BNG_IPFIX_GRAFANA_DASHBOARD} to ${FLUX_GRAFANA_REPO}/${PREFIX}/"

rm -rf "$GRAFANA_DASHBOARDS_STAGING"
mkdir -p "$(dirname "$GRAFANA_DASHBOARDS_STAGING")"

if ! git clone --depth 1 -b "$FLUX_GIT_BRANCH" \
    "$REPO_URL" "$GRAFANA_DASHBOARDS_STAGING"; then
  echo "ERROR: Could not clone the existing Grafana repository and branch." >&2
  exit 1
fi

mkdir -p "${GRAFANA_DASHBOARDS_STAGING}/${PREFIX}"
cp "$SRC_FILE" "${GRAFANA_DASHBOARDS_STAGING}/${PREFIX}/${BNG_IPFIX_GRAFANA_DASHBOARD}"

cd "$GRAFANA_DASHBOARDS_STAGING"
git add "${PREFIX}/${BNG_IPFIX_GRAFANA_DASHBOARD}"

if git diff --cached --quiet; then
  echo "--> IPFIX: Dashboard is unchanged; nothing to push"
  exit 0
fi

git config user.name "$GITEA_ADMIN_USER"
git config user.email "${GITEA_ADMIN_USER}@localhost"
git commit -m "Grafana: publish IPFIX flow analytics dashboard"
git push origin "$FLUX_GIT_BRANCH"

echo "--> IPFIX: Dashboard push completed"
