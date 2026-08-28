#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_nok_kpt_fixture
}

@test "apply-kpt-overlays patches Gitea for portal sub-path access" {
  run_make apply-kpt-overlays
  [ "$status" -eq 0 ]

  local manifest="$FIXTURE_NOK_KPT/nok-git/gitea/gitea-manifest-standalone.yaml"
  grep -q 'DOMAIN=bng.nok.local' "$manifest"
  grep -q 'ROOT_URL=http://bng.nok.local:8080/gitea/' "$manifest"
  grep -q 'SSH_DOMAIN=bng.nok.local' "$manifest"
  grep -q 'SERVE_FROM_SUB_PATH=true' "$manifest"
  ! grep -q 'git.example.com' "$manifest"
}

@test "apply-kpt-overlays removes standalone Gitea ingress manifest" {
  run_make apply-kpt-overlays
  [ "$status" -eq 0 ]
  [ ! -f "$FIXTURE_NOK_KPT/nok-git/gitea/ingress.yaml" ]
}

@test "apply-kpt-overlays copies NetOpsKube overlay manifests into nok-kpt" {
  run_make apply-kpt-overlays
  [ "$status" -eq 0 ]

  [ -f "$FIXTURE_NOK_KPT/nok-bng/ingress/ingress.yaml" ]
  grep -q '/gitea' "$FIXTURE_NOK_KPT/nok-bng/ingress/ingress.yaml"
  [ -f "$FIXTURE_NOK_KPT/nok-bng/portal/portal-gitea-proxy-svc.yaml" ]
}

@test "apply-kpt-overlays is idempotent for Gitea sub-path settings" {
  run_make apply-kpt-overlays
  [ "$status" -eq 0 ]
  run_make apply-kpt-overlays
  [ "$status" -eq 0 ]

  local count
  count="$(grep -c 'SERVE_FROM_SUB_PATH=true' "$FIXTURE_NOK_KPT/nok-git/gitea/gitea-manifest-standalone.yaml")"
  [ "$count" -eq 1 ]
}

@test "apply-kpt-overlays skips when overlays directory is missing" {
  local empty_base="${BATS_TEST_TMPDIR}/empty-base"
  mkdir -p "$empty_base"
  run make -C "$NETOPSKUBE_ROOT" apply-kpt-overlays \
    BASE="$empty_base" NOK_KPT_DIR="$FIXTURE_NOK_KPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No overlays directory, skipping"* ]]
}

@test "apply-kpt-overlays fails when nok-kpt directory is missing" {
  run make -C "$NETOPSKUBE_ROOT" apply-kpt-overlays \
    NOK_KPT_DIR="/tmp/nok-kpt-missing-$$"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
