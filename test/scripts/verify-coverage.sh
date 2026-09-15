#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCOPE_FILE="${ROOT}/test/coverage/unit-scope.txt"
UNIT_DIR="${ROOT}/test/bats/unit"

if [[ ! -f "$SCOPE_FILE" ]]; then
  echo "Error: missing $SCOPE_FILE" >&2
  exit 1
fi

mapfile -t REQUIRED < <(grep -v '^[[:space:]]*$' "$SCOPE_FILE" | grep -v '^#')
mapfile -t TEST_NAMES < <(grep -h '^@test ' "$UNIT_DIR"/*.bats | sed 's/^@test "//;s/"[[:space:]]*{[[:space:]]*$//')

MISSING=0
COVERED=0

echo "--> COVERAGE: Unit scope (${#REQUIRED[@]} items)"
for item in "${REQUIRED[@]}"; do
  found=0
  for name in "${TEST_NAMES[@]}"; do
    if [[ "$name" == "$item" ]]; then
      found=1
      break
    fi
  done
  if [[ "$found" -eq 1 ]]; then
    echo "    [PASS] $item"
    COVERED=$((COVERED + 1))
  else
    echo "    [FAIL] missing test: $item"
    MISSING=$((MISSING + 1))
  fi
done

echo ""
if [[ "$MISSING" -ne 0 ]]; then
  echo "--> COVERAGE: ${COVERED}/${#REQUIRED[@]} unit scope items covered — FAILED"
  exit 1
fi

echo "--> COVERAGE: ${COVERED}/${#REQUIRED[@]} unit scope items covered — 100%"
