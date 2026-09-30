#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_nok_kpt_fixture
}

@test "patch-gitea-kpt-manifest replaces bundled Gitea image with pullable default" {
  run_make patch-gitea-kpt-manifest
  [ "$status" -eq 0 ]

  local manifest="$FIXTURE_NOK_KPT/nok-git/gitea/gitea-manifest-standalone.yaml"
  local expected_image
  expected_image="$(make_var GITEA_IMAGE)"
  grep -q "$expected_image" "$manifest"
  ! grep -q 'docker.gitea.com/gitea:1.25.4-rootless' "$manifest"
}

@test "patch-gitea-kpt-manifest is idempotent" {
  run_make patch-gitea-kpt-manifest
  [ "$status" -eq 0 ]
  run_make patch-gitea-kpt-manifest
  [ "$status" -eq 0 ]

  local manifest="$FIXTURE_NOK_KPT/nok-git/gitea/gitea-manifest-standalone.yaml"
  local expected_image
  expected_image="$(make_var GITEA_IMAGE)"
  local count
  count="$(grep -c "$expected_image" "$manifest" || true)"
  [ "$count" -ge 1 ]
}
