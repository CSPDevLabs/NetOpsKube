#!/usr/bin/env bats

load '../../helpers/common.bash'

setup() {
  setup_nok_kpt_fixture
}

@test "update-kpt-lb-setters writes LB IPs for a non-default KinD prefix" {
  run_make update-kpt-lb-setters KIND_NET_PREFIX=172.30.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"172.30.0"* ]]

  [ "$(yq_get "$FIXTURE_NOK_KPT/nok-lb/apply-setters.yaml" metallb-pool-range)" = "172.30.0.100-172.30.0.120" ]
  [ "$(yq_get "$FIXTURE_NOK_KPT/nok-base/apply-setters.yaml" ingress-lb-ip)" = "172.30.0.100" ]
  [ "$(yq_get "$FIXTURE_NOK_KPT/nok-bng/apply-setters.yaml" syslog-lb-ip)" = "172.30.0.101" ]
  [ "$(yq_get "$FIXTURE_NOK_KPT/nok-dia/apply-setters.yaml" syslog-lb-ip)" = "172.30.0.103" ]
  [ "$(yq_get "$FIXTURE_NOK_KPT/nok-git/apply-setters.yaml" gitea-ssh-lb-ip)" = "172.30.0.102" ]
}

@test "update-kpt-lb-setters overwrites an existing prefix idempotently" {
  run_make update-kpt-lb-setters KIND_NET_PREFIX=172.19.0
  [ "$status" -eq 0 ]
  run_make update-kpt-lb-setters KIND_NET_PREFIX=172.30.0
  [ "$status" -eq 0 ]
  [ "$(yq_get "$FIXTURE_NOK_KPT/nok-base/apply-setters.yaml" ingress-lb-ip)" = "172.30.0.100" ]
}

@test "update-kpt-lb-setters fails when KinD prefix is empty" {
  run_make update-kpt-lb-setters KIND_NET_PREFIX=""
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot detect network prefix"* ]]
}

@test "update-kpt-lb-setters fails when nok-kpt directory is missing" {
  run make -C "$NETOPSKUBE_ROOT" update-kpt-lb-setters \
    KIND_NET_PREFIX=172.30.0 NOK_KPT_DIR="/tmp/nok-kpt-does-not-exist-$$"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
