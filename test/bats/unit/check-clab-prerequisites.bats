#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "check-clab-prerequisites passes when image and license exist" {
  mock_docker_with_image
  local license="${BATS_TEST_TMPDIR}/srsim-lic.txt"
  touch "$license"
  run make -C "$NETOPSKUBE_ROOT" check-clab-prerequisites SRSIM_LICENSE_FILE="$license"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker image"* ]]
  [[ "$output" == *"found."* ]]
  [[ "$output" == *"Nokia SROS license file found."* ]]
}

@test "check-clab-prerequisites fails when license file is missing" {
  mock_docker_with_image
  run make -C "$NETOPSKUBE_ROOT" check-clab-prerequisites \
    SRSIM_LICENSE_FILE="${BATS_TEST_TMPDIR}/missing-license.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"license file"* ]]
  [[ "$output" == *"not found"* ]]
}
