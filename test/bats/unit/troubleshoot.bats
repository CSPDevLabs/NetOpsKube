#!/usr/bin/env bats

load '../../helpers/common.bash'

# bats test_tags=req:HELP-01
@test "help-troubleshoot lists troubleshooting targets" {
  run make -C "$NETOPSKUBE_ROOT" help-troubleshoot
  [ "$status" -eq 0 ]
  [[ "$output" == *"verify-lb-ips"* ]]
  [[ "$output" == *"verify-gnmic-subscriptions"* ]]
  [[ "$output" == *"restart-gnmic-collector"* ]]
}

# bats test_tags=req:GNMIC-01
@test "verify-gnmic-subscriptions warns when no targets exist" {
  mock_kubectl_no_gnmic_targets
  run make -C "$NETOPSKUBE_ROOT" verify-gnmic-subscriptions \
    KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No gNMIc Targets found"* ]]
}

# bats test_tags=req:GNMIC-01
@test "verify-gnmic-subscriptions fails when any subscription is stopped" {
  setup_mock_bin
  cat > "${MOCK_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "get targets.operator.gnmic.dev -n nok-bng -o jsonpath="*)
    echo test-target ;;
  "get targets.operator.gnmic.dev -n nok-bng test-target -o json")
    printf '{"status":{"clusterStates":{"test-cluster":{"connectionState":"READY","subscriptions":{"test-subscription":"%s","healthy-subscription":"running"}}}}}\n' "$MOCK_SUBSCRIPTION_STATE" ;;
  *) echo "unexpected kubectl call: $*" >&2; exit 99 ;;
esac
EOF
  chmod +x "${MOCK_BIN}/kubectl"
  export MOCK_SUBSCRIPTION_STATE=stopped
  run make -C "$NETOPSKUBE_ROOT" verify-gnmic-subscriptions KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"One or more subscriptions are not in 'running' state"* ]]
  [[ "$output" != *"All subscriptions are running"* ]]

  export MOCK_SUBSCRIPTION_STATE=running
  run make -C "$NETOPSKUBE_ROOT" verify-gnmic-subscriptions KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All subscriptions are running"* ]]
}
