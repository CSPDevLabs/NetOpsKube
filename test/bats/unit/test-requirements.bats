#!/usr/bin/env bats

load '../../helpers/common.bash'

# bats test_tags=req:TEST-01
@test "test-kpt fails when the validator is missing" {
  run make -C "$NETOPSKUBE_ROOT" test-kpt \
    KPT_VALIDATE_DIR="${BATS_TEST_TMPDIR}/missing-kpt" \
    YQ=/bin/true

  [ "$status" -ne 0 ]
  [[ "$output" == *"kpt validate-recipes.sh not found"* ]]
}

# bats test_tags=req:TEST-01
@test "requirement check fails when its requirements file is missing" {
  run env REQUIREMENTS_FILE="${BATS_TEST_TMPDIR}/missing-requirements.md" \
    bash "${NETOPSKUBE_ROOT}/test/scripts/verify-requirements.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing requirements file"* ]]
}

# bats test_tags=req:TEST-01
@test "requirement check fails when a unit test has no requirement tag" {
  local fixture="${BATS_TEST_TMPDIR}/untagged"
  mkdir -p "$fixture/unit"
  printf '%s\n' '- `RCP-99`: A recipe requirement.' >"$fixture/requirements.md"
  printf '%s\n' '@test "untagged test" {' '}' >"$fixture/unit/fixture.bats"

  run env REQUIREMENTS_FILE="$fixture/requirements.md" UNIT_DIR="$fixture/unit" \
    bash "${NETOPSKUBE_ROOT}/test/scripts/verify-requirements.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"untagged unit test"* ]]
}

# bats test_tags=req:TEST-01
@test "requirement check fails when a test tag is unknown" {
  local fixture="${BATS_TEST_TMPDIR}/unknown-tag"
  mkdir -p "$fixture/unit"
  printf '%s\n' '- `RCP-99`: A recipe requirement.' >"$fixture/requirements.md"
  printf '%s\n' '# bats test_tags=req:UNKNOWN-01' '@test "unknown tag" {' '}' \
    >"$fixture/unit/fixture.bats"

  run env REQUIREMENTS_FILE="$fixture/requirements.md" UNIT_DIR="$fixture/unit" \
    bash "${NETOPSKUBE_ROOT}/test/scripts/verify-requirements.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown requirement ID UNKNOWN-01"* ]]
}

# bats test_tags=req:TEST-01
@test "requirement check fails when a requirement has no tagged test" {
  local fixture="${BATS_TEST_TMPDIR}/unused-requirement"
  mkdir -p "$fixture/unit"
  printf '%s\n' '- `RCP-99`: A recipe requirement.' >"$fixture/requirements.md"

  run env REQUIREMENTS_FILE="$fixture/requirements.md" UNIT_DIR="$fixture/unit" \
    bash "${NETOPSKUBE_ROOT}/test/scripts/verify-requirements.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no tagged unit test for requirement RCP-99"* ]]
}
