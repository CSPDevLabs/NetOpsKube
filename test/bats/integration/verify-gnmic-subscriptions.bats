#!/usr/bin/env bats

# Integration tests require a deployed KinD cluster (make try-nok or similar).
# They are skipped unless NOK_RUN_INTEGRATION_TESTS=yes.

setup() {
  if [[ "${NOK_RUN_INTEGRATION_TESTS:-}" != "yes" ]]; then
    skip "Set NOK_RUN_INTEGRATION_TESTS=yes to run integration tests"
  fi
  NETOPSKUBE_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "verify-gnmic-subscriptions passes on a healthy deployment" {
  run make -C "$NETOPSKUBE_ROOT" verify-gnmic-subscriptions
  [ "$status" -eq 0 ]
  [[ "$output" == *"All subscriptions are running"* ]]
}
