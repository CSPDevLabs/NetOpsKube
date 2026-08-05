#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "GITEA_IP derives from KinD prefix and ingress host octet" {
  [ "$(make_var GITEA_IP KIND_NET_PREFIX=172.30.0)" = "172.30.0.100" ]
  [ "$(make_var GITEA_IP KIND_NET_PREFIX=172.19.0)" = "172.19.0.100" ]
}

@test "GITEA_SSH_HOST derives from KinD prefix and Gitea SSH host octet" {
  [ "$(make_var GITEA_SSH_HOST KIND_NET_PREFIX=172.30.0)" = "172.30.0.102" ]
  [ "$(make_var GITEA_SSH_HOST KIND_NET_PREFIX=172.19.0)" = "172.19.0.102" ]
}

@test "KinD LB host octets use expected defaults" {
  [ "$(make_var KIND_LB_INGRESS_HOST)" = "100" ]
  [ "$(make_var KIND_LB_GITEA_SSH_HOST)" = "102" ]
  [ "$(make_var KIND_LB_BNG_SYSLOG_HOST)" = "101" ]
  [ "$(make_var KIND_LB_DIA_SYSLOG_HOST)" = "103" ]
}
