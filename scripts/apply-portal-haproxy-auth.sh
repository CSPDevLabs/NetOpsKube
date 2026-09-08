#!/usr/bin/env bash
# Portal static + menu from kpt (Keycloak login at /login).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

export KEYCLOAK_ENABLED="${KEYCLOAK_ENABLED:-YES}"

echo "==> Portal static + menu from kpt (Keycloak auth gate enabled)"
bash "$ROOT/scripts/apply-portal-static.sh"
