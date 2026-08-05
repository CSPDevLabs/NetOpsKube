#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "git-clone-kpt skips clone when nok-kpt already exists" {
  local kpt_dir="${BATS_TEST_TMPDIR}/nok-kpt"
  mkdir -p "$kpt_dir"
  run make -C "$NETOPSKUBE_ROOT" git-clone-kpt NOK_KPT_DIR="$kpt_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists. Skipping clone"* ]]
  [[ "$output" == *"feat/ip-setters"* ]]
}

@test "git-clone-clab skips clone when nok-clabs already exists" {
  local clabs_dir="${BATS_TEST_TMPDIR}/nok-clabs"
  mkdir -p "$clabs_dir"
  run make -C "$NETOPSKUBE_ROOT" git-clone-clab NOK_CLABS_DIR="$clabs_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists. Skipping clone"* ]]
}
