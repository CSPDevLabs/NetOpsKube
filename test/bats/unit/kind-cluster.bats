#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "kind cluster config keeps expected pod and service subnets" {
  local config="${NETOPSKUBE_ROOT}/build/kind-cluster.yaml"
  grep -q 'podSubnet: "10.244.0.0/16"' "$config"
  grep -q 'serviceSubnet: "10.96.0.0/12"' "$config"
}

@test "kind cluster config uses dual stack networking" {
  local config="${NETOPSKUBE_ROOT}/build/kind-cluster.yaml"
  grep -q 'ipFamily: dual' "$config"
}

@test "generated kind cluster config includes ingress-ready node labels" {
  local config="${BATS_TEST_TMPDIR}/kind-cluster.yaml"
  run make -C "$NETOPSKUBE_ROOT" "$config" KIND_CONFIG_REAL_LOC="$config" EXT_HTTPS_PORT=5443
  [ "$status" -eq 0 ]
  grep -q 'ingress-ready=true' "$config"
  grep -q 'hostPort: 5443' "$config"
  grep -q 'podSubnet: "10.244.0.0/16"' "$config"
}
