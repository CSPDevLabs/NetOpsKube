# Unit tests — recipe health and integration testing

Per-recipe automated health/integration tests on deploy. Baseline recipes: **BNG** and **DIA**. Operators run verification after deploy; publish to Gitea is unchanged.

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

# netopskube — unit tests + kpt validation (sibling kpt checkout or KPT_ROOT)
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

## Optional pre-publish check

`verify-before-publish-bng` and `verify-before-publish-dia` run install-level `verify-recipe-*` only when **`NOK_VERIFY_BEFORE_PUBLISH=yes`** (default: **no**).

They are **not** attached to `push-bng-manifests` / `push-dia-manifests`. Publish behavior is unchanged from pre–Epic 9 installs.

```bash
# Optional, explicit gate before you push manifests yourself:
NOK_VERIFY_BEFORE_PUBLISH=yes make verify-before-publish-bng
```

## Flux DIA naming

DIA GitOps kustomizations use prefix `dia-` (e.g. `dia-prometheus`) to avoid collisions with BNG (`prometheus`). Set `FLUX_DIA_KUST_PREFIX` to override.

## CI

`.github/workflows/epic9-test.yml` runs on push to `main` and on pull requests:

1. NetOpsKube `make test` (BATS unit + coverage)
2. kpt `make test` (package validation)
3. nok-controller `pytest`

**kpt pin:** workflow checks out `feat/portal-embedding` until the portal kpt PR merges; follow-up to pin a SHA or use `main` / `feat/ip-setters`.

## See also

- `test/README.md` — operator test guide (BATS, recipes, CI)
- `make help-recipe-verify` — all verify targets
