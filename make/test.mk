# ----------------------------------------------------------------------------
# Test targets (BATS)
#
# Unit tests are fast and do not require a KinD cluster.
# Integration / smoke tests require a deployed environment.
# See test/README.md
# ----------------------------------------------------------------------------

BATS ?= bats
TEST_DIR ?= $(BASE)/test

.PHONY: test test-unit test-integration test-smoke test-coverage test-recipe-bng test-recipe-dia test-recipes test-kpt test-epic9
test: test-unit test-coverage ## Run default test suite and verify 100% unit scope coverage

test-unit: check-tools ## Run BATS unit tests (no cluster required)
	@command -v $(BATS) >/dev/null 2>&1 || { \
		echo "Error: 'bats' not found. Install with: sudo apt install bats"; \
		exit 1; \
	}
	@echo "--> TEST: Running BATS unit tests"
	@TERM=$${TERM:-dumb} $(BATS) $(TEST_DIR)/bats/unit/
	@echo ""
	@echo "--> TEST: Unit tests completed successfully."

test-coverage: ## Verify 100% unit-test scope coverage (see test/coverage/unit-scope.txt)
	@chmod +x $(TEST_DIR)/scripts/verify-coverage.sh
	@$(TEST_DIR)/scripts/verify-coverage.sh

test-integration: check-tools ## Run BATS integration tests (cluster required)
	@command -v $(BATS) >/dev/null 2>&1 || { \
		echo "Error: 'bats' not found. Install with: sudo apt install bats"; \
		exit 1; \
	}
	@echo "--> TEST: Running BATS integration tests"
	@TERM=$${TERM:-dumb} $(BATS) $(TEST_DIR)/bats/integration/
	@echo ""
	@echo "--> TEST: Integration tests completed successfully."

test-smoke: check-tools ## Run Makefile smoke verifications (cluster required)
	@echo "--> TEST: Running smoke checks"
	@$(MAKE) verify-lb-ips
	@echo ""
	@echo "--> TEST: Smoke checks completed successfully."

test-recipe-bng: check-tools ## Run BNG recipe integration checks (cluster required; NOK_RECIPE_VERIFY_LEVEL=install|full)
	@echo "--> TEST: Running BNG recipe verification (level=$(NOK_RECIPE_VERIFY_LEVEL))"
	@$(MAKE) verify-recipe-bng NOK_RECIPE_VERIFY_LEVEL=$(NOK_RECIPE_VERIFY_LEVEL)
	@echo ""
	@echo "--> TEST: BNG recipe checks completed successfully."

test-recipe-dia: check-tools ## Run DIA recipe integration checks (cluster required; NOK_RECIPE_VERIFY_LEVEL=install|full)
	@echo "--> TEST: Running DIA recipe verification (level=$(NOK_RECIPE_VERIFY_LEVEL))"
	@$(MAKE) verify-recipe-dia NOK_RECIPE_VERIFY_LEVEL=$(NOK_RECIPE_VERIFY_LEVEL)
	@echo ""
	@echo "--> TEST: DIA recipe checks completed successfully."

test-recipes: test-recipe-bng test-recipe-dia ## Run install-level checks for BNG and DIA recipes

KPT_VALIDATE_DIR ?= $(dir $(NOK_KPT_DIR))
test-kpt: ## Run kpt recipe package validation (Epic 9; sibling kpt repo or NOK_KPT_DIR)
	@if [ -x "$(KPT_VALIDATE_DIR)/test/validate-recipes.sh" ]; then \
		echo "--> TEST: Running kpt recipe validation in $(KPT_VALIDATE_DIR)"; \
		YQ="$(YQ)" "$(KPT_VALIDATE_DIR)/test/validate-recipes.sh"; \
	elif [ -x "$(BASE)/../kpt/test/validate-recipes.sh" ]; then \
		echo "--> TEST: Running kpt recipe validation in $(BASE)/../kpt"; \
		YQ="$(YQ)" "$(BASE)/../kpt/test/validate-recipes.sh"; \
	else \
		echo "[WARN] kpt validate-recipes.sh not found — skip (set KPT_VALIDATE_DIR)"; \
	fi

test-epic9: test test-kpt ## Epic 9 gate: NetOpsKube unit tests + kpt package validation (no cluster)
