#!/usr/bin/env bats

load '../../helpers/common.bash'

# bats test_tags=req:DIAG-01
@test "os-shell outputs platform JSON" {
  run make -C "$NETOPSKUBE_ROOT" os-shell
  [ "$status" -eq 0 ]
  [[ "$output" == *'"OS":'* ]]
  [[ "$output" == *'"ARCH":'* ]]
  [[ "$output" == *'"SHELL":'* ]]
}

# bats test_tags=req:DIAG-01
@test "proxy-env outputs proxy JSON" {
  run make -C "$NETOPSKUBE_ROOT" proxy-env HTTP_PROXY=http://proxy.example:8080
  [ "$status" -eq 0 ]
  [[ "$output" == *'"HTTP_PROXY": "http://proxy.example:8080"'* ]]
  [[ "$output" == *'"NO_PROXY":'* ]]
}
