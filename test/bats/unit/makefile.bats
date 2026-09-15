#!/usr/bin/env bats

@test "make help exits successfully" {
  NETOPSKUBE_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  run make -C "$NETOPSKUBE_ROOT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"try-nok"* ]]
  [[ "$output" == *"test-unit"* ]]
}

@test "make test target is documented in help" {
  NETOPSKUBE_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  run make -C "$NETOPSKUBE_ROOT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"test"* ]]
}
