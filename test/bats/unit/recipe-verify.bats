#!/usr/bin/env bats

load '../../helpers/common.bash'

@test "recipe-verify targets are listed in help-recipe-verify" {
  run make -C "$NETOPSKUBE_ROOT" help-recipe-verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"verify-recipe-bng"* ]]
  [[ "$output" == *"verify-recipe-dia"* ]]
  [[ "$output" == *"verify-recipe-cgnat"* ]]
  [[ "$output" == *"verify-recipe-pods"* ]]
  [[ "$output" == *"verify-recipe-metrics"* ]]
  [[ "$output" == *"verify-recipe-controller"* ]]
}

@test "verify-recipe fails for unknown recipe name" {
  run make -C "$NETOPSKUBE_ROOT" verify-recipe RECIPE=unknown 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"RECIPE must be bng, dia, or cgnat"* ]]
}

@test "NOK_VERIFY_BEFORE_PUBLISH defaults to no" {
  [ "$(make_var NOK_VERIFY_BEFORE_PUBLISH)" = "no" ]
}

@test "NOK_RECIPE_VERIFY_LEVEL defaults to install" {
  [ "$(make_var NOK_RECIPE_VERIFY_LEVEL)" = "install" ]
}

@test "FLUX_DIA_KUST_PREFIX defaults to dia-" {
  [ "$(make_var FLUX_DIA_KUST_PREFIX)" = "dia-" ]
}
