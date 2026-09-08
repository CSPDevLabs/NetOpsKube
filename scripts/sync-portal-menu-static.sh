#!/usr/bin/env bash
# Apply menu-config changes and refresh portal static bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORTAL="${PORTAL_DIR:-$ROOT/../kpt/nok-base/portal}"
[[ -d "$PORTAL" ]] || PORTAL="$ROOT/nok-kpt/nok-base/portal"
[[ -d "$PORTAL" ]] || { echo "ERROR: portal dir not found"; exit 1; }

echo "==> Applying menu config from $PORTAL/portal-menu-config.yaml"
bash "$ROOT/scripts/apply-portal-static.sh"
