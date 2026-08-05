# NetOpsKube tests (BATS)

[BATS](https://github.com/bats-core/bats-core) drives the test suite. Unit tests are fast and need no KinD cluster.

## Install

```bash
# Ubuntu / Debian
sudo apt install bats

# macOS
brew install bats-core
```

Ensure `yq` is available (downloaded automatically by `make check-tools`).

## Run

```bash
# Default: unit tests only
make test

# Explicit targets
make test-unit          # BATS unit tests (no cluster)
make test-integration   # BATS integration tests (skipped unless enabled)
make test-smoke         # existing make verify-lb-ips (cluster required)
```

### Console output

BATS prints a per-test PASS/FAIL line and ends with a summary:

```text
update-kpt-lb-setters.bats
 ✓ update-kpt-lb-setters writes LB IPs for a non-default KinD prefix
 ...
6 tests, 0 failures

--> TEST: Unit tests completed successfully.
```

### Integration tests

Integration tests are **skipped by default**. Enable when a cluster is up:

```bash
NOK_RUN_INTEGRATION_TESTS=yes make test-integration
```

## Layout

```text
test/
  bats/
    unit/           # KinD setter wiring, Makefile smoke
    integration/    # verify-lb-ips against live cluster
  fixtures/
    nok-kpt/        # minimal apply-setters.yaml trees for unit tests
  helpers/
    common.bash
```

## Adding tests

1. Add a `*.bats` file under `test/bats/unit/` for logic that does not need a cluster.
2. Use `KIND_NET_PREFIX=172.30.0` on the `make` command line to avoid Docker/KinD detection.
3. Point `NOK_KPT_DIR` at a fixture copy via `setup_nok_kpt_fixture` in `helpers/common.bash`.
