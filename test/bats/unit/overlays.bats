#!/usr/bin/env bats

load '../../helpers/common.bash'

# Portal in-iframe behaviour is owned by kpt recipe packages (not NetOpsKube overlays).

@test "kpt recipe portal menu opens apps in-portal (not new tab)" {
  local kpt_root
  kpt_root="$(kpt_root_for_tests)"
  local menu="${kpt_root}/nok-base/portal/portal-menu-config.yaml"
  [ -f "$menu" ]
  ! grep -q '"openInNewTab": true' "$menu"
  grep -q '"openInNewTab": false' "$menu"
  grep -q '/gitea/nok' "$menu"
}

@test "kpt recipe defines gitea-proxy ExternalName service" {
  local kpt_root
  kpt_root="$(kpt_root_for_tests)"
  for recipe in nok-bng nok-dia; do
    local svc="${kpt_root}/${recipe}/portal/portal-gitea-proxy-svc.yaml"
    [ -f "$svc" ]
    grep -q 'name: gitea-proxy' "$svc"
    grep -q 'externalName: gitea-http.nok-git.svc.cluster.local' "$svc"
  done
}
