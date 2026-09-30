#!/usr/bin/env bats

# BNG recipe integration tests (Epic 9).
# Require a deployed KinD cluster with install-bng-pkg (or try-nok-bng).
# Skipped unless NOK_RUN_INTEGRATION_TESTS=yes.

setup() {
  if [[ "${NOK_RUN_INTEGRATION_TESTS:-}" != "yes" ]]; then
    skip "Set NOK_RUN_INTEGRATION_TESTS=yes to run integration tests"
  fi
  NETOPSKUBE_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "verify-recipe-bng install-level checks pass" {
  run make -C "$NETOPSKUBE_ROOT" verify-recipe-bng NOK_RECIPE_VERIFY_LEVEL=install
  [ "$status" -eq 0 ]
  [[ "$output" == *"All install-level checks passed"* ]]
}

@test "verify-recipe-bng full-level checks pass when clab is deployed" {
  if [[ "${NOK_RUN_FULL_RECIPE_TESTS:-}" != "yes" ]]; then
    skip "Set NOK_RUN_FULL_RECIPE_TESTS=yes when containerlab + gitops are up"
  fi
  run make -C "$NETOPSKUBE_ROOT" verify-recipe-bng NOK_RECIPE_VERIFY_LEVEL=full
  [ "$status" -eq 0 ]
  [[ "$output" == *"gNMIc metric series"* ]]
}
