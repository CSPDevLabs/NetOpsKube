#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-${ROOT}/test/unit-tests-requirements.md}"
UNIT_DIR="${UNIT_DIR:-${ROOT}/test/bats/unit}"

if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
  echo "Error: missing requirements file: $REQUIREMENTS_FILE" >&2
  exit 1
fi

REQUIREMENT_IDS=""
KNOWN_IDS=" "
USED_IDS=" "
requirement_count=0
failures=0

contains_id() {
  case "$1" in
    *" $2 "*) return 0 ;;
    *) return 1 ;;
  esac
}

while IFS= read -r requirement_id; do
  if contains_id "$KNOWN_IDS" "$requirement_id"; then
    echo "[FAIL] duplicate requirement ID: $requirement_id" >&2
    failures=$((failures + 1))
  else
    KNOWN_IDS="${KNOWN_IDS}${requirement_id} "
  fi
  REQUIREMENT_IDS="${REQUIREMENT_IDS}${requirement_id} "
  requirement_count=$((requirement_count + 1))
done < <(sed -nE 's/^- `([A-Z]+-[0-9]+)`: .+$/\1/p' "$REQUIREMENTS_FILE")

if [[ "$requirement_count" -eq 0 ]]; then
  echo "Error: no requirements found in $REQUIREMENTS_FILE" >&2
  exit 1
fi

for test_file in "$UNIT_DIR"/*.bats; do
  [[ -f "$test_file" ]] || continue
  pending_id=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^#\ bats\ test_tags=req:([A-Z]+-[0-9]+)$ ]]; then
      pending_id="${BASH_REMATCH[1]}"
    elif [[ "$line" == @test\ * ]]; then
      test_name="$(sed -E 's/^@test "([^"]*)".*/\1/' <<< "$line")"
      if [[ -z "$pending_id" ]]; then
        echo "[FAIL] $test_file: untagged unit test: $test_name" >&2
        failures=$((failures + 1))
      elif ! contains_id "$KNOWN_IDS" "$pending_id"; then
        echo "[FAIL] $test_file: unknown requirement ID $pending_id for: $test_name" >&2
        failures=$((failures + 1))
      else
        if ! contains_id "$USED_IDS" "$pending_id"; then
          USED_IDS="${USED_IDS}${pending_id} "
        fi
      fi
      pending_id=""
    else
      pending_id=""
    fi
  done < "$test_file"
done

for requirement_id in $REQUIREMENT_IDS; do
  if contains_id "$USED_IDS" "$requirement_id"; then
    echo "[PASS] $requirement_id"
  else
    echo "[FAIL] no tagged unit test for requirement $requirement_id" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo "--> REQUIREMENTS: $requirement_count documented requirements; $failures failures" >&2
  exit 1
fi

echo "--> REQUIREMENTS: all $requirement_count documented requirements have tagged unit tests"
