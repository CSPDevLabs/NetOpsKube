#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_nok_kpt_fixture
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
