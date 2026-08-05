# Shared helpers for NetOpsKube BATS tests.

# Repo root (netopskube/), three levels up from test/bats/unit/*.bats
NETOPSKUBE_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
export NETOPSKUBE_ROOT

# Copy fixture nok-kpt tree into an isolated temp directory for each test.
setup_nok_kpt_fixture() {
  FIXTURE_NOK_KPT="${BATS_TEST_TMPDIR}/nok-kpt"
  rm -rf "$FIXTURE_NOK_KPT"
  cp -a "${NETOPSKUBE_ROOT}/test/fixtures/nok-kpt/." "$FIXTURE_NOK_KPT"
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
