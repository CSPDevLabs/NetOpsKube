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

# Full local gate (no cluster): `make test` then `make test-kpt` — see docs/unit-tests.md
make test-kpt             # kpt BNG/DIA package validation (sibling kpt or NOK_KPT_DIR)
```

### Run one file or one test

From the **netopskube** repo root (with `bats` on `PATH` and a kpt checkout when the file needs it):

```bash
# Entire unit file
bats test/bats/unit/makefile-vars.bats

# Single @test by name (BATS filter)
bats test/bats/unit/update-kpt-lb-setters.bats --filter 'writes LB IPs for a non-default KinD prefix'

# Same as CI (unit + coverage gate)
KPT_ROOT=/path/to/kpt make test

# Unit tests only, no coverage check (faster while iterating)
make test-unit
```

Integration files under `test/bats/integration/` are skipped unless you opt in:

```bash
NOK_RUN_INTEGRATION_TESTS=yes bats test/bats/integration/verify-lb-ips.bats
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

## Contributing new BATS tests

Use this checklist when you add Makefile or shell behavior that should stay covered without a live cluster.

### Prerequisites

| Tool | Purpose |
|------|---------|
| [bats](https://github.com/bats-core/bats-core) | Test runner (`make test-unit` checks it is installed) |
| GNU `make` | Targets under test |
| kpt checkout | Package copy tests (`KPT_ROOT`, `../kpt`, or `netopskube/kpt` as in CI) |
| `yq` | Pulled via `make test-unit` into `tools/yq` when missing |

No KinD cluster, containerlab, or Gitea is required for **unit** tests.

### Where to put files

| Path | Use when |
|------|----------|
| `test/bats/unit/<topic>.bats` | Makefile variables, setter scripts, help output, mocked `kubectl`/`docker` — **default for new tests** |
| `test/bats/integration/<topic>.bats` | Needs a deployed cluster (`verify-lb-ips`, recipe health, live gNMIc) |
| `test/helpers/common.bash` | Shared helpers (`make_var`, `run_make`, kpt fixture, mocks) — extend here only when reused |
| `test/coverage/unit-scope.txt` | **Required** for every new unit `@test` name (see below) |

Name files after the Makefile target or script under test (kebab-case), e.g. `update-kpt-lb-setters.bats`, `recipe-verify.bats`. Group related `@test` blocks in one file rather than one file per assertion.

### Coverage gate (unit only)

`make test` runs `test/scripts/verify-coverage.sh`, which requires **every non-comment line** in `test/coverage/unit-scope.txt` to match a `@test "…"` name in `test/bats/unit/*.bats` exactly.

When you add a unit test:

1. Add the `@test` in the appropriate `test/bats/unit/*.bats` file.
2. Add a **single line** to `test/coverage/unit-scope.txt` with the same string as the `@test` title (no quotes).
3. Run `make test` locally before opening a PR.

Integration tests are **not** listed in `unit-scope.txt`.

### Conventions

- **Isolate KinD networking** in unit tests: pass `KIND_NET_PREFIX=172.30.0` (or another non-default prefix) on `make` invocations so tests do not depend on the host Docker network or `172.18.0` defaults.
- **Use helpers** from `test/helpers/common.bash`: `load '../../helpers/common.bash'` from unit files; integration files may set `NETOPSKUBE_ROOT` in `setup` when they do not load helpers.
- **Assert via `run`**: prefer `run make …` and check `$status` / `$output` rather than executing make in the foreground unless you need side effects in a temp dir.
- **kpt fixtures**: call `setup_nok_kpt_fixture` in `setup()` and use `run_make` / `FIXTURE_NOK_KPT` so the real sibling kpt tree is never mutated.
- **Mocks**: use `setup_mock_bin`, `mock_docker_*`, `mock_kubectl_*` for external commands; pass overridden binaries via Makefile vars (e.g. `KUBECTL="${MOCK_BIN}/kubectl"`).
- **No secrets**: do not commit licenses, tokens, kubeconfigs, or `.env` files; use temp dirs under `BATS_TEST_TMPDIR`.
- **No workspace-only paths**: do not reference monorepo `workspace/`, slide decks, or local decision notes in tests or fixtures (public repo hygiene).
- **Integration skips**: integration `setup()` must `skip` unless `NOK_RUN_INTEGRATION_TESTS=yes` so `make test-unit` stays fast and cluster-free.

### Minimal examples

**Makefile variable (no kpt fixture):**

```bash
#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "MY_VAR defaults to expected value" {
  [ "$(make_var MY_VAR)" = "expected" ]
}
```

**Makefile target against kpt fixture:**

```bash
#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_nok_kpt_fixture
}

@test "my-target updates apply-setters for a test prefix" {
  run_make my-target KIND_NET_PREFIX=172.30.0
  [ "$status" -eq 0 ]
  [ "$(yq_get "$FIXTURE_NOK_KPT/nok-base/apply-setters.yaml" some-key)" = "172.30.0.100" ]
}
```

(Add `my-target updates apply-setters for a test prefix` to `test/coverage/unit-scope.txt`.)

**Integration (cluster required, skipped by default):**

```bash
#!/usr/bin/env bats

setup() {
  if [[ "${NOK_RUN_INTEGRATION_TESTS:-}" != "yes" ]]; then
    skip "Set NOK_RUN_INTEGRATION_TESTS=yes to run integration tests"
  fi
  NETOPSKUBE_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "my-target passes on a healthy deployment" {
  run make -C "$NETOPSKUBE_ROOT" my-target
  [ "$status" -eq 0 ]
}
```

### Helper reference (`test/helpers/common.bash`)

| Function | Role |
|----------|------|
| `kpt_root_for_tests` | Resolves `KPT_ROOT`, `kpt/`, or `../kpt` |
| `setup_nok_kpt_fixture` | Copies kpt packages into a per-test temp tree; sets `FIXTURE_NOK_KPT` |
| `make_var NAME [make args…]` | Echoes expanded Makefile variable with optional overrides |
| `run_make [targets…]` | `make` in repo root with `NOK_KPT_DIR="$FIXTURE_NOK_KPT"` |
| `yq_get file key` | Reads `.data."key"` from apply-setters YAML via `tools/yq` |
| `setup_mock_bin` / `mock_*` | Prepends fake `docker`/`kubectl` to `PATH` |

## CI

CI unit tests (workflow `.github/workflows/unit-tests.yml`) run on **push to `main`** and on **pull requests** (see [docs/unit-tests.md](../docs/unit-tests.md)):

1. NetOpsKube `make test` (BATS unit + coverage)
2. kpt recipe validation (`make test` or `test/validate-recipes.sh`)
3. nok-controller `pytest`

Feature branches without an open PR are not built on push (avoids duplicate runs with `pull_request`). Open a PR to get CI on a feature branch.
