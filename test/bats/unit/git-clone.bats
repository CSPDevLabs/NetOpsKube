#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "git-clone-kpt skips clone when nok-kpt already exists" {
  local kpt_dir="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}/bats-$$}/nok-kpt"
  mkdir -p "$kpt_dir/nok-base"
  touch "$kpt_dir/nok-base/Kptfile"
  run make -C "$NETOPSKUBE_ROOT" git-clone-kpt NOK_KPT_DIR="$kpt_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already a kpt checkout"* ]]
  [[ "$output" == *"main"* ]]
}

@test "git-clone-clab skips clone when nok-clabs already exists" {
  local clabs_dir="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}/bats-$$}/nok-clabs"
  mkdir -p "$clabs_dir"
  run make -C "$NETOPSKUBE_ROOT" git-clone-clab NOK_CLABS_DIR="$clabs_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists. Skipping clone"* ]]
}
