# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

NetOpsKube is not an application codebase — it's a **Makefile-driven orchestration layer** that provisions a local Kubernetes environment (via Kind) and deploys a NetOps observability/config-management platform onto it (Grafana, Prometheus, gnmic, rsyslog, SDCIO/Kubenet, Gitea+Flux GitOps, Keycloak, and a Nokia BNG Containerlab topology). There is no application source to build/lint/test in the traditional sense — "development" here means editing Makefile targets, KPT packages, and Kubernetes manifests, then exercising them against a real (or Kind) cluster.

Three directories are git repos on their own and are **not** tracked by this repo (they're in `.gitignore` and cloned at runtime by `make` targets):
- `nok-kpt/` — cloned from `CSPDevLabs/kpt`, contains the KPT packages actually applied to the cluster (`nok-base`, `nok-lb`, `nok-bng`, `nok-bbm`, `nok-git`, plus raw-manifest operators `nok-base-prometheus-oper`, `nok-base-gnmic-oper`).
- `nok-clabs/` — cloned from `CSPDevLabs/nok-clabs`, contains Containerlab topologies (`nok-bng`, `nok-dia`) and the BNG's GitOps-managed manifests (`nok-clabs/nok-bng/nok-manifests`).
- `nok-portal-auth/` — cloned (branch `keycloak`) from `CSPDevLabs/nok-portal-auth` only when Keycloak auth is enabled; contains Keycloak/OAuth2-Proxy manifests.

When making changes, be clear about which layer you're editing: the **orchestration Makefile** in this repo, vs. **manifests/packages** that actually live in one of the cloned sibling repos (edits there won't be visible via `git status` here, and won't persist across `rm -rf` of that directory).

## Key commands

Tool binaries (`kind`, `kubectl`, `helm`, `kpt`, `yq`, `k9s`, `gh`, `clab`, `flux`) are downloaded into `./tools/` by the Makefile itself — don't assume they're on `$PATH`; use `make <target>` or the `tools/<name>` binaries directly, or run `make check-tools` first and export `PATH=$PATH:$(pwd)/tools`.

```bash
make help                       # list all top-level targets with descriptions
make help-troubleshoot          # list targets in make/troubleshoot.mk only

make try-nok                    # bring up Kind cluster + base packages (LB, ingress, Prometheus/gnmic operators, BBM)
make try-nok-bng                # try-nok + BNG app + GitOps (Gitea/Flux) + optional Keycloak auth
make deploy-clab-bng            # deploy the Nokia BNG Containerlab topology (needs SROS image + license, see below)
make destroy-clab-bng           # tear down the Containerlab BNG topology
make delete-cluster             # delete the Kind cluster entirely

make install-base-pkg           # apply ./nok-kpt/nok-base via kpt live apply
make install-bng-pkg            # apply ./nok-kpt/nok-bng (depends on base + lb)
make install-bbm-pkg            # apply ./nok-kpt/nok-bbm (uses kpt fn render for setters first)
make install-git-pkg            # apply ./nok-kpt/nok-git (Gitea)

make verify-gnmic-subscriptions # check gNMIc Target subscription health (non-zero exit if any not "running")
make restart-gnmic-collector    # force gnmic collector pod restart to re-subscribe (COLLECTOR=<pod> to target one)

make set-proxy-env              # push HTTP_PROXY/HTTPS_PROXY/NO_PROXY into PROXY_DEPLOYMENTS and roll them
make unset-proxy-env            # remove proxy env vars and roll again

make os-shell                   # print detected OS/ARCH/SHELL/DISTRO_ID as JSON, for sanity-checking the Makefile's platform logic
```

There's no `make all`; `try-nok` and `try-nok-bng`/`deploy-bng`(`sudo`) are the composite entry points. Prerequisites: Docker running, git, internet access; for BNG Containerlab specifically, the `registry.srlinux.dev/pub/nokia_srsim:25.10.R1` image pulled locally and a Nokia SROS license file at `nok-clabs/nok-bng/srsim-lic-25.txt`. Network ranges: `172.19.0.0/24` for Kind/Services, `172.21.20.0/24` for Containerlab.

## Architecture of the Makefile itself

- `Makefile` (root) — tool management, cluster lifecycle, KPT package install targets, Gitea/Flux GitOps bootstrap, Keycloak auth wiring, proxy env management.
- `make/troubleshoot.mk` — included from the root Makefile; day-2 diagnostic/remediation targets (currently gNMIc subscription health). Keep new operational/debugging targets here rather than in the root file, per the file's own header comment.
- `build/kind-cluster.yaml` — generated default Kind cluster config (single control-plane node, `ingress-ready=true` label, `AlwaysAllow` authorization mode, extra port mapping for `EXT_HTTPS_PORT`). The root Makefile has a rule that regenerates this file if missing; `KIND_LAUNCH_CONFIG` (a `/tmp` copy) is the actual file passed to `kind create cluster`, patched at runtime with `yq` for `KIND_API_SERVER_ADDRESS` / `NO_HOST_PORT_MAPPINGS`.

### KPT package installation pattern

Two macros wrap `kpt live init` + `kpt live apply`:
- `INSTALL_KPT_PACKAGE` — plain apply. Skips `kpt live init` if `resourcegroup.yaml` already exists in the package dir (unless `KPT_LIVE_INIT_FORCE=1`), to avoid re-adopting an already-live package.
- `INSTALL_KPT_PACKAGE_WITH_SETTERS` — same, but runs `kpt fn render` first to apply KRM function setters (used for `nok-bbm`, which needs per-cluster/per-target setter values).

Dependency chain for install targets mirrors real runtime dependencies: `install-lb-pkg` waits on MetalLB CRDs from `install-base-pkg` then waits for the MetalLB controller deployment before applying; `install-bng-pkg`/`install-git-pkg` both depend on base + lb.

### GitOps bootstrap flow (`try-nok-bng` → `gitops-init` → `gitops-bng-kustomization`)

1. `gitea-create-admin` / `gitea-create-flux-repo` / `gitea-add-ssh-key` — provision a Gitea admin user and an ed25519 deploy key (generated at `FLUX_SSH_KEY`, default `~/.ssh/flux_ed25519`, if not already present), register it with Gitea, and seed `~/.ssh/known_hosts` for the Gitea SSH host.
2. `flux-bootstrap` — `flux bootstrap git` against the Gitea-hosted `flux-bootstrap` repo, path `clusters/NetOpsKube`.
3. `gitea-create-bng-repo` / `flux-create-bng-secret` / `flux-create-bng-source` — separate repo (`nok-bng-resources`) + Flux `GitRepository` source specifically for BNG manifests.
4. `push-bng-manifests` — **force-pushes** a fresh git history (`rm -rf .git && git init && ... && git push --force`) of `nok-clabs/nok-bng/nok-manifests` to the BNG repo as an "authoritative snapshot." This is destructive to that repo's history by design — be aware before invoking this target against a shared/important Gitea repo.
5. `create-bng-kustomizations` — one Flux `Kustomization` per subdirectory under the manifests dir, source-tracking the GitRepository from step 3.

### Auth (Keycloak) is conditional at Makefile level

`configure-auth` is defined twice inside an `ifeq ($(KEYCLOAK_ENABLED),YES) ... else ... endif` block — when disabled it's a no-op. When enabled, it clones `nok-portal-auth` (branch `keycloak`), applies Postgres + Keycloak + OAuth2-Proxy manifests, and patches `nok-apps-ingress` / `nok-apps-portal-ingress` in namespace `nok-bng` with `nginx.ingress.kubernetes.io/auth-url` / `auth-signin` annotations pointing at oauth2-proxy. Realm is `netopskube`; Keycloak admin console at `http://keycloak.nok.local:8080/admin/master/console` (default admin/admin — change for anything beyond local demo use).

### Proxy env propagation

`PROXY_DEPLOYMENTS` is a `namespace:deployment` list (conditionally appending `nok-bng:oauth2-proxy` when Keycloak is enabled) that `set-proxy-env`/`unset-proxy-env` iterate to `kubectl set env` + rolling-restart. When adding a new deployment that needs outbound proxy access, add it to this list rather than special-casing it.

## Access points (local Kind deployment)

- BNG portal: `http://bng.nok.local:8080/` (requires `bng.nok.local` in `/etc/hosts` → `127.0.0.1`, or `curl --resolve`)
- Gitea: `http://gitea.nok.local` → `172.19.0.100`
- Keycloak admin: `http://keycloak.nok.local:8080/admin/master/console`

## Documentation map

- `docs/NetOpsKube_Installation_Guide.md` — full install walkthrough.
- `docs/GITEA-AND-FLUX-GITOPS-SETUP.md` — manual step-by-step of the GitOps bootstrap the Makefile automates.
- `docs/TROUBLESHOOTING.md` — operator runbook referenced by `make/troubleshoot.mk` targets.
- `docs/NETWORK-DEVICE-TARGET.md` — `NetworkDeviceTarget` CRD spec/example (SDCIO + gNMIc target config) used by the `nok-controller` in `nok-kpt/nok-base`.
