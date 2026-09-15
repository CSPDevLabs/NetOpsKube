#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "os-shell outputs platform JSON" {
  run make -C "$NETOPSKUBE_ROOT" os-shell
  [ "$status" -eq 0 ]
  [[ "$output" == *'"OS":'* ]]
  [[ "$output" == *'"ARCH":'* ]]
  [[ "$output" == *'"SHELL":'* ]]
}

@test "proxy-env outputs proxy JSON" {
  run make -C "$NETOPSKUBE_ROOT" proxy-env HTTP_PROXY=http://proxy.example:8080
  [ "$status" -eq 0 ]
  [[ "$output" == *'"HTTP_PROXY": "http://proxy.example:8080"'* ]]
  [[ "$output" == *'"NO_PROXY":'* ]]
}
