#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "overlay source manifests define portal Gitea menu entry" {
  local menu="${NETOPSKUBE_ROOT}/overlays/nok-bng/portal/portal-menu-config.yaml"
  grep -q '/gitea/nok/nok-bng-resources' "$menu"
  grep -q 'BBM (Self Monitoring)' "$menu"
}

@test "overlay source manifests define gitea-proxy ExternalName service" {
  local svc="${NETOPSKUBE_ROOT}/overlays/nok-bng/portal/portal-gitea-proxy-svc.yaml"
  grep -q 'name: gitea-proxy' "$svc"
  grep -q 'externalName: gitea-http.nok-git.svc.cluster.local' "$svc"
}
