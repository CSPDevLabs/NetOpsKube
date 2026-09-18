#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_nok_kpt_fixture
}

@test "apply-kpt-overlays copies NetOpsKube overlay manifests into nok-kpt" {
  run_make apply-kpt-overlays
  [ "$status" -eq 0 ]

  [ -f "$FIXTURE_NOK_KPT/nok-bng/ingress/ingress.yaml" ]
  grep -q '/gitea' "$FIXTURE_NOK_KPT/nok-bng/ingress/ingress.yaml"
  [ -f "$FIXTURE_NOK_KPT/nok-bng/portal/portal-gitea-proxy-svc.yaml" ]
  [ -f "$FIXTURE_NOK_KPT/nok-cgnat/ingress/ingress.yaml" ]
  grep -q '/nok-cgnat/prometheus' "$FIXTURE_NOK_KPT/nok-cgnat/ingress/ingress.yaml"
}

@test "apply-kpt-overlays skips when overlays directory is missing" {
  local empty_base="${BATS_TEST_TMPDIR}/empty-base"
  mkdir -p "$empty_base"
  run make -C "$NETOPSKUBE_ROOT" apply-kpt-overlays \
    BASE="$empty_base" NOK_KPT_DIR="$FIXTURE_NOK_KPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No overlays directory, skipping"* ]]
}

@test "apply-kpt-overlays fails when nok-kpt directory is not a checkout" {
  local bad_kpt="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}/bats-$$}/not-kpt"
  mkdir -p "$bad_kpt"
  run make -C "$NETOPSKUBE_ROOT" apply-kpt-overlays \
    NOK_KPT_DIR="$bad_kpt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a kpt checkout"* ]]
}

@test "patch-gitea-kpt-manifest patches Gitea for portal sub-path access" {
  run_make patch-gitea-kpt-manifest
  [ "$status" -eq 0 ]

  local manifest="$FIXTURE_NOK_KPT/nok-git/gitea/gitea-manifest-standalone.yaml"
  grep -q 'DOMAIN=bng.nok.local' "$manifest"
  grep -q 'ROOT_URL=http://bng.nok.local:8080/gitea/' "$manifest"
  grep -q 'SSH_DOMAIN=bng.nok.local' "$manifest"
  grep -q 'SERVE_FROM_SUB_PATH=true' "$manifest"
  ! grep -q 'git.example.com' "$manifest"
}

@test "patch-gitea-kpt-manifest removes standalone Gitea ingress manifest" {
  run_make patch-gitea-kpt-manifest
  [ "$status" -eq 0 ]
  [ ! -f "$FIXTURE_NOK_KPT/nok-git/gitea/ingress.yaml" ]
}

@test "patch-gitea-kpt-manifest is idempotent for Gitea sub-path settings" {
  run_make patch-gitea-kpt-manifest
  [ "$status" -eq 0 ]
  run_make patch-gitea-kpt-manifest
  [ "$status" -eq 0 ]

  local count
  count="$(grep -c 'SERVE_FROM_SUB_PATH=true' "$FIXTURE_NOK_KPT/nok-git/gitea/gitea-manifest-standalone.yaml")"
  [ "$count" -eq 1 ]
}
