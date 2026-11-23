#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_mock_bin
  export MOCK_POD_PHASE=Pending
  export MOCK_POD_READY=False
  export MOCK_POD_DELETING=no
  export MOCK_POD_RESPONSE=normal
  export MOCK_DEPLOYMENT_FAILURE=no
  cat > "${MOCK_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "get namespace nok-bng") exit 0 ;;
  "get deploy -n nok-bng -o name")
    if [[ "$MOCK_DEPLOYMENT_FAILURE" == yes ]]; then
      echo "Forbidden: deployments access denied" >&2
      exit 1
    fi
    exit 0 ;;
  "get pods -n nok-bng -o json")
    case "$MOCK_POD_RESPONSE" in
      error) echo "Forbidden: pods access denied" >&2; exit 1 ;;
      empty) echo '{"items":[]}'; exit 0 ;;
      invalid) echo 'not JSON'; exit 0 ;;
    esac
    jq -n --arg phase "$MOCK_POD_PHASE" --arg ready "$MOCK_POD_READY" \
      --arg deleting "$MOCK_POD_DELETING" \
      '{items: [{metadata: {name: "test-pod", deletionTimestamp:
        (if $deleting == "yes" then "2026-11-17T00:00:00Z" else null end)},
        status: {phase: $phase, conditions: [{type: "Ready", status: $ready}]}}]}'
    exit $? ;;
esac
echo "unexpected kubectl command: $*" >&2
exit 90
EOF
  chmod +x "${MOCK_BIN}/kubectl"
}

# bats test_tags=req:RCP-02
@test "recipe pod verification fails when a pod is unhealthy" {
  run make -C "$NETOPSKUBE_ROOT" verify-recipe-pods KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test-pod"* ]]
  [[ "$output" == *"Pending"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe pod verification fails when a pod is Running but not Ready" {
  export MOCK_POD_PHASE=Running

  run make -C "$NETOPSKUBE_ROOT" verify-recipe-pods KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test-pod"* ]]
  [[ "$output" == *"Ready=False"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe pod verification rejects a terminating pod even if Ready is True" {
  export MOCK_POD_PHASE=Running MOCK_POD_READY=True MOCK_POD_DELETING=yes

  run make -C "$NETOPSKUBE_ROOT" verify-recipe-pods KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test-pod"* ]]
  [[ "$output" == *"deleting=true"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe pod verification rejects non-running pods even if Ready is True" {
  export MOCK_POD_READY=True
  for phase in Pending Failed Unknown; do
    export MOCK_POD_PHASE="$phase"
    run make -C "$NETOPSKUBE_ROOT" verify-recipe-pods KUBECTL="${MOCK_BIN}/kubectl"
    [ "$status" -ne 0 ]
    [[ "$output" == *"phase=$phase"* ]]
  done
}

# bats test_tags=req:RCP-02
@test "recipe pod verification accepts Ready running pods and succeeded jobs" {
  for state in Running:True Succeeded:False; do
    export MOCK_POD_PHASE="${state%:*}" MOCK_POD_READY="${state#*:}"
    run make -C "$NETOPSKUBE_ROOT" verify-recipe-pods KUBECTL="${MOCK_BIN}/kubectl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[PASS] 1 pod(s) Ready or completed"* ]]
  done
}

# bats test_tags=req:RCP-02
@test "recipe pod verification fails on pod API errors without reporting success" {
  export MOCK_POD_RESPONSE=error

  run make -C "$NETOPSKUBE_ROOT" verify-recipe-pods KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Forbidden: pods access denied"* ]]
  [[ "$output" == *"Unable to list pods"* ]]
  [[ "$output" != *"[PASS]"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe pod verification rejects empty and malformed pod lists" {
  for response in empty invalid; do
    export MOCK_POD_RESPONSE="$response"
    run make -C "$NETOPSKUBE_ROOT" verify-recipe-pods KUBECTL="${MOCK_BIN}/kubectl"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No pods or invalid pod list"* ]]
    [[ "$output" != *"[PASS]"* ]]
  done
}

# bats test_tags=req:RCP-02
@test "recipe pod verification reports deployment API errors" {
  export MOCK_DEPLOYMENT_FAILURE=yes

  run make -C "$NETOPSKUBE_ROOT" verify-recipe-pods KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Forbidden: deployments access denied"* ]]
  [[ "$output" == *"Unable to list deployments"* ]]
}
