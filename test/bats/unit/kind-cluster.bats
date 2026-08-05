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
