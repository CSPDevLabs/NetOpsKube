# Branch layout

NetOpsKube work is split so **Epic 9** (tests / recipe verify / CI) stays a separate PR from **deploy options** (items 1·2·3).

## Branch layout

NetOpsKube work is split across focused branches; merge to `main` in this order:

| Order | Branch | Repo | What |
|-------|--------|------|------|
| 1 | `feat/deploy-options` | netopskube | SDCIO, Prom/gNMIc tuning, Grafana via Gitea |
| 2 | `nok-restructure` | kpt | Unified portal in nok-base, recipe `.krmignore` for legacy portal |
| 3 | `feat/bats-unit-tests` | netopskube | Epic 9 tests + `EPIC9_ENABLED` gate |
| 4 | auth (on main or `feat/keycloak`) | netopskube + kpt | HAProxy + Keycloak (`KEYCLOAK_ENABLED=YES`) |

## Branches (detail)

## netopskube: `EPIC9_ENABLED`

| Value | Includes |
|-------|----------|
| `NO` (default on deploy branch) | `deploy-tuning.mk` — no `test.mk` / `recipe-verify.mk` |
| `YES` (`feat/bats-unit-tests`) | Epic 9 verify gate on `push-*-manifests`, `make test` |

```bash
# Deploy options only (no Epic 9)
make SDCIO_ENABLED=YES try-nok-bng

# Epic 9 CI locally
EPIC9_ENABLED=YES make test
```

## One-time repo sync

```bash
make sync-nok-restructure
```

Pulls `kpt@nok-restructure`, `nok-clabs@nok-restructure`.

## Creating the deploy branch

```bash
cd netopskube
git checkout -b feat/deploy-options main
git add make/deploy-tuning.mk docs/ Makefile README.md
git commit -m "feat(deploy): SDCIO optional, Prom/gNMIc tuning, Grafana via Gitea"
```

Epic 9 files (`test/`, `make/test.mk`, `make/recipe-verify.mk`, `docs/EPIC9.md`, `.github/workflows/epic9-test.yml`) remain on `feat/bats-unit-tests` only.

## Merging later

1. Merge `feat/deploy-options` → `main` (items 1·2·3)
2. Rebase `feat/bats-unit-tests` on `main`, set `EPIC9_ENABLED ?= YES` in Makefile
