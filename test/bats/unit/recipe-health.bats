#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_mock_bin
  cat > "${MOCK_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "namespace" ]]; then
  exit 0
fi
if [[ "$1" == "get" && "$2" == "deploy" ]]; then
  exit 0
fi
if [[ "$1" == "get" && "$2" == "pods" ]]; then
  echo "unhealthy-pod 0/1 Pending 0 10s"
  exit 0
fi
echo "unexpected kubectl command: $*" >&2
exit 90
EOF
  chmod +x "${MOCK_BIN}/kubectl"
}

# bats test_tags=req:RCP-02
@test "recipe pod verification fails when a pod is unhealthy" {
  run make -C "$NETOPSKUBE_ROOT" verify-recipe-pods KUBECTL="${MOCK_BIN}/kubectl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unhealthy-pod (Pending)"* ]]
}
