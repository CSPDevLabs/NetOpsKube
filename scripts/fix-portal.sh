#!/usr/bin/env bash
# Recover a broken portal (stuck rollout, CrashLoopBackOff, missing menu-config).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/scripts/apply-portal-static.sh" "$@"
