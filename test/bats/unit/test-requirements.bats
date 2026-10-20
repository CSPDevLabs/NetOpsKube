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
