#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "help-troubleshoot lists troubleshooting targets" {
  run make -C "$NETOPSKUBE_ROOT" help-troubleshoot
  [ "$status" -eq 0 ]
  [[ "$output" == *"verify-lb-ips"* ]]
  [[ "$output" == *"verify-gnmic-subscriptions"* ]]
  [[ "$output" == *"restart-gnmic-collector"* ]]
}

@test "verify-gnmic-subscriptions warns when no targets exist" {
  mock_kubectl_no_gnmic_targets
  run make -C "$NETOPSKUBE_ROOT" verify-gnmic-subscriptions \
    KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No gNMIc Targets found"* ]]
}
