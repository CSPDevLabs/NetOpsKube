# NetOpsKube testing

This is the operator guide to the NetOpsKube, kpt recipe, and nok-controller
test commands. Contributors choosing what to test and where to add it should
read [TEST-CONTRIBUTION.md](TEST-CONTRIBUTION.md). For BATS file layout and unit-test
conventions, see [test/README.md](../test/README.md).

## Unit tests and package validation

From the NetOpsKube repository root:

```bash
# Runs BATS unit tests and checks that all documented requirements have tests.
make test

# Run only the BATS tests, without the requirement check.
make test-unit

# Validate the kpt recipe packages selected by NOK_KPT_DIR (default: ./nok-kpt).
# Run `make git-clone-kpt` first if that checkout does not exist.
make test-kpt

# Use another kpt checkout, such as a sibling checkout.
make test-kpt KPT_VALIDATE_DIR=../kpt
```

`make test` provisions the pinned Bats 1.11.1 and yq version from
`make/settings.mk` when needed. Tests are isolated from a live cluster; tests
that inspect kpt files use `KPT_ROOT`, `./nok-kpt`, `./kpt`, or `../kpt`, in
that order. To select a checkout explicitly, export `KPT_ROOT=/path/to/kpt`.

The CI workflow `.github/workflows/unit-tests.yml` runs on pushes to `main`:

1. NetOpsKube BATS unit tests and requirement checks, using a separate kpt checkout at `./kpt`.
2. kpt package validation.
3. nok-controller Python tests.

The workflow currently uses kpt branch `feat/portal-embedding` until its
portal changes land. Follow up by pinning the kpt checkout to a commit SHA or
switching to the appropriate maintained branch.

## Recipe verification

Recipe verification checks a deployed environment and requires the cluster
and recipe to be installed:

```bash
make verify-recipe-bng
make verify-recipe-dia
make test-recipes
```

For direct verification, select a recipe with `NOK_RECIPE=bng` or
`NOK_RECIPE=dia`; unrelated Make targets do not read this selector.

`NOK_RECIPE_VERIFY_LEVEL` must be `install` or `full`; any other value is
rejected.

The default `NOK_RECIPE_VERIFY_LEVEL=install` checks nok-controller readiness;
recipe pods; gNMIc Targets, NetworkDeviceTargets, recipe Flux Kustomizations
(for example `bng-sdcio` when SDCIO is enabled), and Grafana operator CRs in the
recipe namespace; Portal `/healthz`; and Prometheus readiness.

Pod checks require a non-empty pod list. Each pod must be `Running` with its
`Ready` condition set to `True`, or have completed successfully (`Succeeded`).
Pods being deleted are rejected even if they still report Ready. Failed pod
or deployment queries fail verification rather than being treated as an empty
list.

Resource checks require gNMIc Targets (`targets.operator.gnmic.dev`),
NetworkDeviceTargets, Grafanas, GrafanaDatasources, and GrafanaDashboards.
Missing APIs, denied queries, and empty resource lists fail verification.
The recipe manifests directory must exist and contain enabled manifest
subdirectories; each corresponding Flux Kustomization must be readable and
Ready. Only the `sdcio` and `schemas` Flux checks are omitted when
`SDCIO_ENABLED=NO`, matching deployment behavior.

Set
`NOK_RECIPE_VERIFY_LEVEL=full` to add gNMIc subscription and Prometheus metric
checks. A non-running subscription fails verification immediately; successful
metric checks cannot override that failure:

```bash
NOK_RECIPE_VERIFY_LEVEL=full make verify-recipe-bng
```

The optional `verify-before-publish-*` targets are not prerequisites of
`push-bng-manifests` or `push-dia-manifests`. Publishing remains independent
of verification. To run an optional explicit check:

```bash
NOK_VERIFY_BEFORE_PUBLISH=yes make verify-before-publish-bng
```

## Other repositories

From each repository's root:

```bash
# kpt recipe packages
make test

# nok-controller
pytest -q
```

Recipe verification and integration tests that require a running cluster are
separate from the default unit-test workflow.
