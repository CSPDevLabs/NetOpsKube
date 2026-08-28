# Epic 9 — Recipe Health & Integration Testing

Per-recipe automated health/integration tests on deploy. Baseline recipes: **BNG** and **DIA**. Broken recipes surface in testing before manifest publish.

## Three-repo test model

| Repo | Layer | Command | Cluster? |
|------|-------|---------|------------|
| **kpt** | Package validation (manifests, setters) | `make test` | No |
| **netopskube** | Orchestration unit + recipe verify | `make test-epic9` / `make test-recipes` | Unit: no; recipes: yes |
| **nok-controller** | Component unit tests | `pytest` | No |

## Quick start (no cluster)

```bash
# kpt — validate BNG/DIA packages
cd kpt && make test

# netopskube — unit tests + kpt validation (eac workspace layout)
cd netopskube && make test-epic9

# nok-controller — Python unit tests
cd nok-controller && pip install -r requirements.txt pytest pytest-flask pytest-mock && pytest
```

## Recipe verification (cluster required)

```bash
cd netopskube

make verify-recipe-bng
make verify-recipe-dia
make test-recipes

# Full stack (containerlab + gitops + metrics)
NOK_RECIPE_VERIFY_LEVEL=full make verify-recipe-bng
```

### Install-level checks

- `nok-controller` ready in `nok-base` (endpoints + optional `/targets`)
- Recipe namespace pods Running/Completed
- Portal `/healthz`
- Prometheus Ready

### Full-level checks (adds)

- gNMIc subscriptions `running`
- gNMIc metrics present in Prometheus

## Pre-publish gate

`push-bng-manifests` and `push-dia-manifests` run install-level `verify-recipe-*` when `NOK_VERIFY_BEFORE_PUBLISH=yes` (default).

Skip when no cluster: `NOK_VERIFY_BEFORE_PUBLISH=no make push-dia-manifests`

## Flux DIA naming

DIA GitOps kustomizations use prefix `dia-` (e.g. `dia-prometheus`) to avoid collisions with BNG (`prometheus`). Set `FLUX_DIA_KUST_PREFIX` to override.

## CI

`.github/workflows/epic9-test.yml` runs:

1. NetOpsKube `make test` (BATS unit + coverage)
2. kpt `make test` (package validation)
3. nok-controller `pytest`

## See also

- `test/README.md` — BATS layout and integration tests
- `make help-recipe-verify` — all verify targets
- `workspace/epic-9-testing-slides.md` — Monday presentation deck
