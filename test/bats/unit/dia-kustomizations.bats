#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_mock_bin
  export FLUX_LOG="${BATS_TEST_TMPDIR}/flux.log"
  cat > "${MOCK_BIN}/flux" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" ]]; then
  echo "kustomization not found"
  exit 1
fi
if [[ "$1" == "create" ]]; then
  printf '%s\n' "$*" >> "$FLUX_LOG"
  exit 0
fi
echo "unexpected flux command: $*" >&2
exit 90
EOF
  chmod +x "${MOCK_BIN}/flux"
}

# bats test_tags=req:DIA-01
@test "create-dia-kustomizations uses the configured prefix" {
  local manifests="${BATS_TEST_TMPDIR}/manifests"
  mkdir -p "${manifests}/nok-prometheus"

  run make -C "$NETOPSKUBE_ROOT" create-dia-kustomizations \
    DIA_MANIFESTS_DIR="$manifests" \
    FLUX="${MOCK_BIN}/flux" \
    FLUX_DIA_REPO=dia-resources \
    FLUX_DIA_KUST_PREFIX=custom-

  [ "$status" -eq 0 ]
  [[ "$output" == *"Checking Kustomization for custom-nok-prometheus"* ]]
  grep -q 'create kustomization custom-nok-prometheus' "$FLUX_LOG"
  grep -q -- '--path=./nok-prometheus' "$FLUX_LOG"
}
