# Shared helpers for NetOpsKube BATS tests.

# Repo root (netopskube/), three levels up from test/bats/unit/*.bats
NETOPSKUBE_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
export NETOPSKUBE_ROOT

# kpt checkout for recipe package assertions (local ../kpt, CI kpt/, or KPT_ROOT).
kpt_root_for_tests() {
  if [[ -n "${KPT_ROOT:-}" && -d "$KPT_ROOT" ]]; then
    echo "$KPT_ROOT"
  elif [[ -d "${NETOPSKUBE_ROOT}/kpt" ]]; then
    echo "${NETOPSKUBE_ROOT}/kpt"
  elif [[ -d "${NETOPSKUBE_ROOT}/../kpt" ]]; then
    echo "${NETOPSKUBE_ROOT}/../kpt"
  else
    echo "Error: kpt checkout not found (clone kpt or set KPT_ROOT)" >&2
    return 1
  fi
}

# Copy kpt packages from the sibling kpt repo into an isolated temp tree per test.
setup_nok_kpt_fixture() {
  local kpt_root
  kpt_root="$(kpt_root_for_tests)" || return 1

  FIXTURE_NOK_KPT="${BATS_TEST_TMPDIR}/nok-kpt"
  rm -rf "$FIXTURE_NOK_KPT"
  mkdir -p "$FIXTURE_NOK_KPT"

  local pkg
  for pkg in nok-base nok-bng nok-dia nok-git nok-lb nok-bbm; do
    if [[ -d "${kpt_root}/${pkg}" ]]; then
      cp -a "${kpt_root}/${pkg}" "$FIXTURE_NOK_KPT/"
    fi
  done

  if [[ ! -f "$FIXTURE_NOK_KPT/nok-base/apply-setters.yaml" ]]; then
    echo "Error: kpt packages missing under ${kpt_root}" >&2
    return 1
  fi

  export FIXTURE_NOK_KPT
}

# Return an expanded Makefile variable value with optional overrides.
make_var() {
  local var_name="$1"
  shift
  make -C "$NETOPSKUBE_ROOT" --eval "all:;@echo \$(${var_name})" "$@" -s
}

# Run a Makefile target against the fixture nok-kpt checkout.
run_make() {
  # shellcheck disable=SC2068
  run make -C "$NETOPSKUBE_ROOT" "$@" NOK_KPT_DIR="$FIXTURE_NOK_KPT"
}

yq_get() {
  local file="$1"
  local key="$2"
  "${NETOPSKUBE_ROOT}/tools/yq" eval ".data.\"${key}\"" "$file"
}

setup_mock_bin() {
  MOCK_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$MOCK_BIN"
  export MOCK_BIN
  export PATH="${MOCK_BIN}:${PATH}"
}

mock_docker_with_image() {
  setup_mock_bin
  cat > "${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "images" && "$2" == "-q" ]]; then
  echo "fake-srsim-image-id"
  exit 0
fi
exec command docker "$@"
EOF
  chmod +x "${MOCK_BIN}/docker"
}

mock_docker_without_image() {
  setup_mock_bin
  cat > "${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "images" && "$2" == "-q" ]]; then
  exit 0
fi
exec command docker "$@"
EOF
  chmod +x "${MOCK_BIN}/docker"
}

mock_kubectl_no_gnmic_targets() {
  setup_mock_bin
  cat > "${MOCK_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"targets.operator.gnmic.dev"* && "$*" == *"jsonpath"* ]]; then
  exit 0
fi
exec command kubectl "$@"
EOF
  chmod +x "${MOCK_BIN}/kubectl"
}
