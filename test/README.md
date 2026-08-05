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
# Default: unit tests + 100% unit-scope coverage report
make test

# Explicit targets
make test-unit          # BATS unit tests only (32 tests)
make test-coverage      # verify test/coverage/unit-scope.txt is fully covered
make test-integration   # BATS integration tests (skipped unless enabled)
make test-smoke         # existing make verify-lb-ips (cluster required)
```

### Console output

```text
32 tests, 0 failures

--> TEST: Unit tests completed successfully.
--> COVERAGE: 32/32 unit scope items covered — 100%
```

### What “100% coverage” means

Unit coverage is **100% of the Makefile logic listed in** `test/coverage/unit-scope.txt` — all testable shell/Makefile behavior that does not require a live KinD cluster, clab deploy, or Gitea API.

Cluster-only flows (`try-nok`, `install-*-pkg`, GitOps, clab deploy) are covered separately via integration/smoke targets when a cluster is up.

### Integration tests

Integration tests are **skipped by default**. Enable when a cluster is up:

```bash
NOK_RUN_INTEGRATION_TESTS=yes make test-integration
```

## Layout

```text
test/
  bats/
    unit/              # 32 tests — overlays, setters, vars, clab checks, …
    integration/       # verify-lb-ips, verify-gnmic (cluster required)
  coverage/
    unit-scope.txt    # canonical list of unit-testable behaviors
  scripts/
    verify-coverage.sh
  fixtures/
    nok-kpt/          # minimal apply-setters + Gitea manifests
  helpers/
    common.bash
```

## Adding tests

1. Add a `*.bats` file under `test/bats/unit/` for logic that does not need a cluster.
2. Add a matching line to `test/coverage/unit-scope.txt` (required for `make test` to pass).
3. Use `KIND_NET_PREFIX=172.30.0` on the `make` command line to avoid Docker/KinD detection.
4. Point `NOK_KPT_DIR` at a fixture copy via `setup_nok_kpt_fixture` in `helpers/common.bash`.
