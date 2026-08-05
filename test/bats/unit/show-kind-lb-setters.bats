#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_nok_kpt_fixture
  run_make update-kpt-lb-setters KIND_NET_PREFIX=172.30.0
}

@test "show-kind-lb-setters prints detected prefix and apply-setters values" {
  run_make show-kind-lb-setters KIND_NET_PREFIX=172.30.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"KinD LB network prefix is 172.30.0"* ]]
  [[ "$output" == *"ingress-lb-ip: 172.30.0.100"* ]]
  [[ "$output" == *"metallb-pool-range: 172.30.0.100-172.30.0.120"* ]]
  [[ "$output" == *"gitea-ssh-lb-ip: 172.30.0.102"* ]]
}
