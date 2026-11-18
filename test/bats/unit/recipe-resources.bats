#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_mock_bin
  export MOCK_MISSING_RESOURCE=""
  export MOCK_FAILED_RESOURCE=""
  export MOCK_FLUX_NOT_READY=""
  export MOCK_NAMESPACE=nok-bng
  export MOCK_KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  RESOURCE_TYPES=(
    targets.operator.gnmic.dev networkdevicetargets.nok.dev
    grafanas.grafana.integreatly.org grafanadatasources.grafana.integreatly.org
    grafanadashboards.grafana.integreatly.org
  )
  MANIFESTS_DIR="${BATS_TEST_TMPDIR}/manifests"
  mkdir -p "${MANIFESTS_DIR}/sdcio" "${MANIFESTS_DIR}/grafana"
  cat > "${MOCK_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_KUBECTL_LOG"
case "$*" in
  "get targets.operator.gnmic.dev -n $MOCK_NAMESPACE -o name" | \
  "get networkdevicetargets.nok.dev -n $MOCK_NAMESPACE -o name" | \
  "get grafanas.grafana.integreatly.org -n $MOCK_NAMESPACE -o name" | \
  "get grafanadatasources.grafana.integreatly.org -n $MOCK_NAMESPACE -o name" | \
  "get grafanadashboards.grafana.integreatly.org -n $MOCK_NAMESPACE -o name")
    if [[ "$2" == "$MOCK_FAILED_RESOURCE" ]]; then
      echo "API unavailable or access denied: $2" >&2
      exit 1
    fi
    if [[ "$2" != "$MOCK_MISSING_RESOURCE" ]]; then
      echo "$2/test-resource"
    fi
    exit 0 ;;
  "get kustomizations.kustomize.toolkit.fluxcd.io "*)
    if [[ "$3" == "$MOCK_FAILED_RESOURCE" ]]; then
      echo "NotFound or access denied: $3" >&2
      exit 1
    fi
    if [[ "$3" == "$MOCK_FLUX_NOT_READY" ]]; then
      echo False
    else
      echo True
    fi
    exit 0 ;;
esac
echo "unexpected kubectl command: $*" >&2
exit 90
EOF
  chmod +x "${MOCK_BIN}/kubectl"
}

verify_resources() {
  run make -C "$NETOPSKUBE_ROOT" verify-recipe-resources \
    KUBECTL="${MOCK_BIN}/kubectl" RECIPE_MANIFESTS_DIR="$MANIFESTS_DIR" "$@"
}

# bats test_tags=req:RCP-02
@test "recipe resource verification fails when gNMIc targets are missing" {
  export MOCK_MISSING_RESOURCE=targets.operator.gnmic.dev
  verify_resources
  [ "$status" -ne 0 ]
  [[ "$output" == *"No required targets.operator.gnmic.dev resources"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe resource verification queries all required types and BNG Flux names" {
  verify_resources
  [ "$status" -eq 0 ]
  for resource in "${RESOURCE_TYPES[@]}"; do
    grep -Fxq "get $resource -n nok-bng -o name" "$MOCK_KUBECTL_LOG"
  done
  [[ "$output" == *"Flux Kustomization 'bng-sdcio' Ready"* ]]
  [[ "$output" == *"Flux Kustomization 'bng-grafana' Ready"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe resource verification uses the DIA namespace and configured Flux prefix" {
  export MOCK_NAMESPACE=nok-dia
  verify_resources NOK_RECIPE=dia FLUX_DIA_KUST_PREFIX=custom-
  [ "$status" -eq 0 ]
  for resource in "${RESOURCE_TYPES[@]}"; do
    grep -Fxq "get $resource -n nok-dia -o name" "$MOCK_KUBECTL_LOG"
  done
  [[ "$output" == *"Flux Kustomization 'custom-sdcio' Ready"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe resource verification rejects missing NDT and Grafana resources" {
  for resource in "${RESOURCE_TYPES[@]:1}"; do
    export MOCK_MISSING_RESOURCE="$resource"
    verify_resources
    [ "$status" -ne 0 ]
    [[ "$output" == *"No required $resource resources"* ]]
  done
}

# bats test_tags=req:RCP-02
@test "recipe resource verification fails on API errors for every required resource type" {
  for resource in "${RESOURCE_TYPES[@]}"; do
    export MOCK_FAILED_RESOURCE="$resource"
    verify_resources
    [ "$status" -ne 0 ]
    [[ "$output" == *"API unavailable or access denied: $resource"* ]]
    [[ "$output" == *"Unable to list $resource"* ]]
  done
}

# bats test_tags=req:RCP-02
@test "recipe resource verification fails on missing or inaccessible Flux Kustomizations" {
  export MOCK_FAILED_RESOURCE=bng-sdcio
  verify_resources
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to read Flux Kustomization 'bng-sdcio'"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe resource verification fails on unready Flux Kustomizations" {
  export MOCK_FLUX_NOT_READY=bng-grafana
  verify_resources
  [ "$status" -ne 0 ]
  [[ "$output" == *"Flux Kustomization 'bng-grafana' not Ready"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe resource verification fails when its manifests directory is missing or empty" {
  MANIFESTS_DIR="${BATS_TEST_TMPDIR}/missing"
  verify_resources
  [ "$status" -ne 0 ]
  [[ "$output" == *"Recipe manifests dir"*"missing"* ]]

  mkdir -p "$MANIFESTS_DIR"
  verify_resources
  [ "$status" -ne 0 ]
  [[ "$output" == *"No enabled recipe manifests to verify"* ]]
}

# bats test_tags=req:RCP-02
@test "recipe resource verification skips only explicitly disabled SDCIO Flux resources" {
  mkdir -p "${MANIFESTS_DIR}/schemas"
  verify_resources SDCIO_ENABLED=NO
  [ "$status" -eq 0 ]
  [[ "$output" == *"Flux Kustomization 'bng-grafana' Ready"* ]]
  ! grep -Eq 'kustomizations.*bng-(sdcio|schemas)' "$MOCK_KUBECTL_LOG"
}