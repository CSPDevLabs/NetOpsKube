# Test contribution guide

This guide helps contributors decide **what** to test and **where**, whether
you are changing recipe packages (kpt), install orchestration (NetOpsKube), or
application logic (nok-controller). Operators who only want run commands should
read [TESTING.md](TESTING.md).

## What is BATS?

[BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System)
runs shell tests: each case is an `@test "description" { ... }` block that
typically invokes `make` or a script and asserts exit status and output.

NetOpsKube uses BATS for **orchestration** tests under `test/bats/`:

| Directory | Cluster required? | Part of default `make test`? |
|-----------|-------------------|------------------------------|
| `test/bats/unit/` | No | Yes |
| `test/bats/integration/` | Yes | No (opt-in via env vars) |

BATS does not replace recipe package validation in the **kpt** repo (see below).

## Three layers of testing

| Layer | Repository | Tooling | What it protects |
|-------|------------|---------|------------------|
| **Package / manifest** | kpt | `make test`, `test/validate-recipes.sh` | Recipe packages build and publish: Kptfile, setters, required paths, portal/ingress rules, YAML parse |
| **Orchestration (unit)** | NetOpsKube | BATS unit + `test/unit-tests-requirements.md` | Makefile targets, defaults, scripts that patch or clone repos, recipe-verify wiring — without a live cluster |
| **Deployed health (integration)** | NetOpsKube | `make verify-recipe-*`, optional BATS in `test/bats/integration/` | End-to-end checks after install: pods, portal health, Prometheus, optional gNMI/metrics with lab topology |

**nok-controller** uses **pytest** for Python unit tests (`pytest -q` from that
repo’s root). That is separate from BATS.

## Choosing a test type

Use this when planning a change. You may need more than one layer.

| You changed… | Add or update… | Repository |
|--------------|----------------|------------|
| Recipe YAML, apply-setters, ingress, portal files under a `nok-*` package | Package checks in `test/validate-recipes.sh` (and `test/README.md` if the checklist changes) | **kpt** |
| A new or changed **Makefile target**, default variable, or install script | BATS **unit** test; extend `test/unit-tests-requirements.md` and requirement tag if behavior is new | **NetOpsKube** |
| Recipe-specific **Flux/GitOps** naming or kustomization logic in Make | BATS unit test in a focused `test/bats/unit/<topic>.bats` (see existing files for patterns) | **NetOpsKube** |
| **Post-deploy** health (pods, metrics, portal) for a recipe | `make/recipe-verify.mk` targets and, optionally, `test/bats/integration/recipe-*.bats` | **NetOpsKube** |
| Controller or API behavior | pytest cases | **nok-controller** |

**Rule of thumb:** manifest and setter correctness belong in **kpt** validation;
how the lab installs and verifies belongs in **NetOpsKube** BATS or recipe
verify. Do not assert large YAML trees in BATS when the kpt validator can do it
without a cluster.

## What merge to `main` expects

CI (`.github/workflows/unit-tests.yml`) runs on **push to `main`** only:

1. NetOpsKube `make test` — all BATS unit tests and the requirement-tag gate
2. kpt `make test`
3. nok-controller `pytest`

No KinD cluster is provisioned in that workflow. Integration BATS and
`NOK_RECIPE_VERIFY_LEVEL=full` checks are for **local or lab** use before you
rely on a new recipe in production.

Before you open a PR, from the relevant repo roots:

```bash
# NetOpsKube
make test
make test-kpt    # or KPT_VALIDATE_DIR=/path/to/kpt make test-kpt

# kpt (when you touched packages)
make test

# nok-controller (when you touched Python)
pytest -q
```

## Adding a NetOpsKube BATS unit test

Detailed file layout and helpers: [test/README.md](../test/README.md).

Short checklist:

1. Put the `@test` in the most relevant `test/bats/unit/*.bats` file, or add a
   new file named after the Make concern (kebab-case).
2. If you document new behavior, add a line to
   `test/unit-tests-requirements.md` and tag the test:
   `# bats test_tags=req:XX-NN` (same ID as in that file).
3. Use `test/helpers/common.bash` — `make_var`, `run_make`, `setup_nok_kpt_fixture`,
   mocks for `kubectl`/`docker` when needed.
4. Never modify the real kpt checkout in a unit test; copy fixtures into
   `BATS_TEST_TMPDIR`.
5. Prefer `KIND_NET_PREFIX=172.30.0` (or similar) on `make` lines so tests do not
   depend on host Docker defaults.
6. Run `make test` until BATS and the requirement check both pass.

Every unit `@test` must have a requirement tag. The gate fails if a tag is
missing, unknown, or a requirement has no tagged test.

## Adding kpt package validation

See the **kpt** repo `test/README.md` and `test/validate-recipes.sh`. When you
add or extend a recipe package, register it in the validator (package list,
required setters, required files) and mirror the structural checks already used
for existing recipes (Kptfile pipeline, shared portal rules, YAML parse).

Run `make test` in kpt before you merge package changes.

## Adding integration / recipe verification

Integration is optional in CI but valuable for recipe owners.

1. Implement or extend checks in `make/recipe-verify.mk` (`verify-recipe-*`,
   namespace and health steps).
2. Optionally add `test/bats/integration/<topic>.bats` that calls those Make
   targets.
3. In `setup()`, **skip** unless `NOK_RUN_INTEGRATION_TESTS=yes` (and use a
   separate flag for expensive full-level checks if needed — see existing
   `recipe-*.bats` files).

Recipe verify targets must remain safe to document in `help-recipe-verify`;
update unit tests that list help output when you add new verify targets.

## What not to commit in tests

Follow public repo hygiene: no secrets, kubeconfigs, or license files in
fixtures; no references to monorepo-only `workspace/` paths or internal planning
docs.

## See also

- [TESTING.md](TESTING.md) — run commands for operators
- [test/README.md](../test/README.md) — NetOpsKube BATS file map and unit-test conventions
- [test/unit-tests-requirements.md](../test/unit-tests-requirements.md) — requirement IDs for unit tests
- **kpt** `test/README.md` — recipe package validation (sibling repository)
