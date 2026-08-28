# NetOpsKube tests (BATS)

[BATS](https://github.com/bats-core/bats-core) drives the test suite. Unit tests are fast and need no KinD cluster.

## Install

```bash
# Ubuntu / Debian
sudo apt install bats

# macOS
brew install bats-core
```

Ensure `yq` is available (downloaded automatically by `make test-unit`).

**kpt repo:** Unit tests copy packages from the [CSPDevLabs/kpt](https://github.com/CSPDevLabs/kpt) checkout — not from NetOpsKube. Clone it as a sibling or set `KPT_ROOT`:

```bash
git clone -b feat/portal-embedding https://github.com/CSPDevLabs/kpt ../kpt
# or: export KPT_ROOT=/path/to/kpt
make test
```

## Run

```bash
# Default: unit tests + 100% unit-scope coverage report
make test

# Explicit targets
make test-unit          # BATS unit tests only
make test-coverage      # verify test/coverage/unit-scope.txt is fully covered
make test-integration   # BATS integration tests (skipped unless enabled)
make test-smoke         # verify-lb-ips (cluster required)

# Epic 9 — per-recipe health checks (cluster required)
make test-recipe-bng                              # install-level (pods, portal, prometheus)
make test-recipe-dia
make test-recipes                                 # both recipes, install-level
NOK_RECIPE_VERIFY_LEVEL=full make test-recipe-bng # + gNMIc subs + metrics (needs clab)
```

### Console output

```text
36 tests, 0 failures

--> TEST: Unit tests completed successfully.
--> COVERAGE: 36/36 unit scope items covered — 100%
```

### What “100% coverage” means

Unit coverage is **100% of the Makefile logic listed in** `test/coverage/unit-scope.txt` — all testable shell/Makefile behavior that does not require a live KinD cluster, clab deploy, or Gitea API.

Cluster-only flows (`try-nok`, `install-*-pkg`, GitOps, clab deploy, recipe verification) are covered via integration/smoke targets when a cluster is up.

## Epic 9 — per-recipe integration verification

Epic 9 spans **kpt**, **netopskube**, and **nok-controller**. See `docs/EPIC9.md` for the full model.

```bash
make test-epic9          # unit tests + kpt package validation (no cluster)
make test-kpt            # kpt BNG/DIA validate only
```

After deploying a recipe (`make install-bng-pkg` or full `make try-nok-bng`):

| Check | install level | full level |
|-------|---------------|------------|
| Pods Running/Completed | yes | yes |
| Portal `/healthz` | yes | yes |
| Prometheus Ready | yes | yes |
| gNMIc subscriptions running | — | yes |
| gNMIc metrics in Prometheus | — | yes |

```bash
make verify-recipe-bng
make verify-recipe-dia
NOK_RECIPE_VERIFY_LEVEL=full make verify-recipe-bng   # after clab + gitops
```

**Pre-publish gate:** `push-bng-manifests` and `push-dia-manifests` run full-level verification by default (`NOK_VERIFY_BEFORE_PUBLISH=yes`). A broken recipe blocks manifest publish to Gitea. Skip with `NOK_VERIFY_BEFORE_PUBLISH=no` when no cluster is available.

### Integration tests

Integration tests are **skipped by default**. Enable when a cluster is up:

```bash
NOK_RUN_INTEGRATION_TESTS=yes make test-integration

# Full recipe checks (containerlab + gitops deployed):
NOK_RUN_INTEGRATION_TESTS=yes NOK_RUN_FULL_RECIPE_TESTS=yes make test-integration
```

## Layout

```text
test/
  bats/
    unit/              # Makefile/setter logic — no cluster
    integration/       # verify-lb-ips, verify-gnmic, recipe-bng, recipe-dia
  coverage/
    unit-scope.txt    # canonical list of unit-testable behaviors
  scripts/
    verify-coverage.sh
  helpers/
    common.bash       # copies kpt packages into a temp dir per test
make/
  recipe-verify.mk    # Epic 9 per-recipe health + metrics checks
```

## Adding tests

1. Add a `*.bats` file under `test/bats/unit/` for logic that does not need a cluster.
2. Add a matching line to `test/coverage/unit-scope.txt` (required for `make test` to pass).
3. Use `KIND_NET_PREFIX=172.30.0` on the `make` command line to avoid Docker/KinD detection.
4. Ensure a kpt checkout exists (`../kpt`, `./kpt`, or `KPT_ROOT`); `setup_nok_kpt_fixture` copies packages into a temp dir.
