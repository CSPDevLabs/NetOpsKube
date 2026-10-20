# BATS test contribution guide

The operator testing commands are documented in [docs/TESTING.md](../docs/TESTING.md).
This file describes where tests live, which NetOpsKube behavior they cover,
and how to add or update unit tests.

## Layout and source mapping

| BATS file | NetOpsKube behavior/source |
|---|---|
| `unit/check-clab-prerequisites.bats` | `check-clab-prerequisites` target in `Makefile` |
| `unit/dia-kustomizations.bats` | `create-dia-kustomizations` target in `make/dia.mk` |
| `unit/git-clone.bats` | `git-clone-kpt` and `git-clone-clab` targets in `Makefile` |
| `unit/kind-cluster.bats` | Kind config generation in `Makefile` and `build/kind-cluster.yaml` |
| `unit/makefile-vars.bats` | Defaults and derived addresses in `make/settings.mk` |
| `unit/makefile.bats` | Help and test target definitions in `Makefile` and `make/test.mk` |
| `unit/patch-gitea-kpt-manifest.bats` | Gitea manifest patching script |
| `unit/platform.bats` | `os-shell` and `proxy-env` in `make/settings.mk` |
| `unit/recipe-verify.bats` | Recipe verification configuration in `make/recipe-verify.mk` |
| `unit/recipe-health.bats` | Recipe pod health check in `make/recipe-verify.mk` |
| `unit/show-kind-lb-setters.bats` | `show-kind-lb-setters` in `Makefile` |
| `unit/troubleshoot.bats` | Troubleshooting targets and gNMI subscription checks |
| `unit/test-requirements.bats` | kpt validation and requirement-check input handling |
| `unit/update-kpt-lb-setters.bats` | `update-kpt-lb-setters` in `Makefile` |
| `integration/` | Checks that require a deployed cluster |

## Adding a unit test

1. Add the test to the matching `test/bats/unit/*.bats` file.
2. Add a documented behavior to `test/unit-tests-requirements.md` if needed.
3. Tag each test with the requirement it verifies:

   ```bash
   # bats test_tags=req:LB-01
   @test "update-kpt-lb-setters writes addresses for the detected prefix" {
     # assertions
   }
   ```

4. Run `make test` from the repository root. The requirement check fails if a
   unit test has no tag, a tag refers to an unknown ID, or a requirement has no
   tagged test.

Use the shared helpers in `test/helpers/common.bash` for Make invocations,
temporary kpt fixtures, and command mocks. Never mutate the actual kpt
checkout in a unit test; copy required packages into `BATS_TEST_TMPDIR`.

Use integration tests only for behavior that requires a deployed cluster.
Integration tests should skip by default and run only when
`NOK_RUN_INTEGRATION_TESTS=yes` is set.
