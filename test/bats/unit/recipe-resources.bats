#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_mock_bin
  cat > "${MOCK_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *api-resources*gnmic*)
    echo "targets"
    exit 0
    ;;
  "get targets.operator.gnmic.dev -n nok-bng --no-headers")
    exit 0
    ;;
  "get crd networkdevicetargets.nok.dev")
    exit 0
    ;;
  "get networkdevicetargets.nok.dev -n nok-bng --no-headers")
    exit 0
    ;;
esac
echo "unexpected kubectl command: $*" >&2
exit 90
EOF
  chmod +x "${MOCK_BIN}/kubectl"
}

# bats test_tags=req:RCP-02
@test "recipe resource verification fails when gNMIc targets are missing" {
  run make -C "$NETOPSKUBE_ROOT" verify-recipe-resources \
    NOK_RECIPE=bng KUBECTL="${MOCK_BIN}/kubectl" \
    RECIPE_MANIFESTS_DIR=/nonexistent-recipe-manifests
  [ "$status" -ne 0 ]
  [[ "$output" == *"No gNMIc Target resources"* ]]
}