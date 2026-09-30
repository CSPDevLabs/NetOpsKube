# NetOpsKube tests (BATS)

Operator-facing guide for the NetOpsKube test suite. [BATS](https://github.com/bats-core/bats-core) drives unit and integration tests; `make/test.mk` defines the targets below.

## Install

```bash
# Ubuntu / Debian
sudo apt install bats

# macOS
brew install bats-core
```

`make test-unit` downloads `yq` automatically when needed.

### kpt checkout (`KPT_ROOT`)

Unit tests copy kpt packages from a **[CSPDevLabs/kpt](https://github.com/CSPDevLabs/kpt)** checkout — not from NetOpsKube.

```bash
# Sibling checkout (recommended for local dev)
git clone -b feat/portal-embedding https://github.com/CSPDevLabs/kpt ../kpt

# Or point at any checkout
export KPT_ROOT=/path/to/kpt
make test
```

**Follow-up:** CI currently pins `feat/portal-embedding`. After the portal kpt PR lands, pin a release SHA or switch to `main` / `feat/ip-setters` so CI does not depend on a throwaway branch.

## Run

```bash
make test                 # unit tests + 100% unit-scope coverage gate
make test-unit            # BATS unit tests only
make test-coverage        # verify test/coverage/unit-scope.txt
make test-integration     # BATS integration (skipped unless enabled)
make test-smoke           # verify-lb-ips (cluster required)

# Per-recipe health (cluster required) — run when you want to validate a deploy
make verify-recipe-bng
make verify-recipe-dia
make test-recipes         # both recipes, install-level
NOK_RECIPE_VERIFY_LEVEL=full make verify-recipe-bng   # + gNMIc + metrics (needs clab)

# Unit-test bundle (no cluster) — see docs/unit-tests.md
make test-epic9           # unit tests + kpt package validation
make test-kpt             # kpt BNG/DIA validate only
```

### Install-level vs full-level

| Check | install (`NOK_RECIPE_VERIFY_LEVEL=install`, default) | full |
|-------|------------------------------------------------------|------|
| `nok-controller` ready | yes | yes |
| Recipe namespace pods Running/Completed | yes | yes |
| Portal `/healthz` | yes | yes |
| Prometheus Ready | yes | yes |
| gNMIc subscriptions running | — | yes |
| gNMIc metrics in Prometheus | — | yes |

**Publish vs verify:** `push-bng-manifests` and `push-dia-manifests` do **not** run recipe verification. GitOps publish assumes the recipe was already tested. Operators and CI run `make verify-recipe-*` or `make test-recipes` when they want a health check.

Optional pre-publish gate (opt-in only):

```bash
NOK_VERIFY_BEFORE_PUBLISH=yes make verify-before-publish-bng
NOK_VERIFY_BEFORE_PUBLISH=yes make verify-before-publish-dia
```

Default: `NOK_VERIFY_BEFORE_PUBLISH=no`.

### Integration tests

Skipped by default. Enable when a cluster is up:

```bash
NOK_RUN_INTEGRATION_TESTS=yes make test-integration

# Full recipe checks (containerlab + gitops deployed):
NOK_RUN_INTEGRATION_TESTS=yes NOK_RUN_FULL_RECIPE_TESTS=yes make test-integration
```

### Console output

```text
36 tests, 0 failures

--> TEST: Unit tests completed successfully.
--> COVERAGE: 36/36 unit scope items covered — 100%
```

Unit coverage is **100% of behaviors listed in** `test/coverage/unit-scope.txt` — Makefile/shell logic that does not need KinD, clab, or Gitea.

## Layout

```text
test/
  bats/
    unit/              # Makefile/setter logic — no cluster
    integration/       # verify-lb-ips, verify-gnmic, recipe-bng, recipe-dia
  coverage/
    unit-scope.txt     # canonical list of unit-testable behaviors
  scripts/
    verify-coverage.sh
  helpers/
    common.bash        # copies kpt packages into a temp dir per test
make/
  recipe-verify.mk     # per-recipe health + metrics checks
  test.mk            # test, test-unit, test-recipes, …
```

## Adding a `@test`

1. Add `test/bats/unit/<name>.bats` for logic that does not need a cluster.
2. Add a matching line to `test/coverage/unit-scope.txt` (required for `make test` to pass).
3. Use `KIND_NET_PREFIX=172.30.0` on the `make` command line to avoid Docker/KinD side effects in unit tests.
4. Ensure a kpt checkout exists (`../kpt`, `./kpt`, or `KPT_ROOT`); `setup_nok_kpt_fixture` copies packages per test.

## CI

GitHub Actions workflow `.github/workflows/epic9-test.yml` runs on **push to `main`** and on **pull requests** (see [docs/unit-tests.md](../docs/unit-tests.md)):

1. NetOpsKube `make test` (BATS unit + coverage)
2. kpt recipe validation (`make test` or `test/validate-recipes.sh`)
3. nok-controller `pytest`

Feature branches without an open PR are not built on push (avoids duplicate runs with `pull_request`). Open a PR to get CI on a feature branch.
