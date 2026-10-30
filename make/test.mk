# ----------------------------------------------------------------------------
# Test targets (BATS)
#
# Unit tests are fast and do not require a KinD cluster.
# Integration / smoke tests require a deployed environment.
# See docs/TESTING.md
# ----------------------------------------------------------------------------

TEST_DIR ?= $(BASE)/test

.PHONY: test test-unit test-integration test-smoke test-requirements test-recipe-bng test-recipe-dia test-recipes test-kpt
test: test-unit test-requirements ## Run unit tests and verify all documented requirements

test-unit: $(YQ) $(BATS) ## Run BATS unit tests (no cluster required)
	@echo "--> TEST: Running BATS unit tests"
	@KPT_ROOT="$${KPT_ROOT:-$(NOK_KPT_DIR)}" TERM=$${TERM:-dumb} $(BATS) $(TEST_DIR)/bats/unit/
	@echo ""
	@echo "--> TEST: Unit tests completed successfully."

test-requirements: ## Verify unit tests are tagged for every documented requirement
	@bash $(TEST_DIR)/scripts/verify-requirements.sh

test-integration: check-tools $(BATS) ## Run BATS integration tests (cluster required)
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

KPT_VALIDATE_DIR ?= $(NOK_KPT_DIR)
test-kpt: $(YQ) ## Run kpt recipe package validation (NOK_KPT_DIR or KPT_VALIDATE_DIR)
	@if [ -x "$(KPT_VALIDATE_DIR)/test/validate-recipes.sh" ]; then \
		echo "--> TEST: Running kpt recipe validation in $(KPT_VALIDATE_DIR)"; \
		YQ="$(YQ)" "$(KPT_VALIDATE_DIR)/test/validate-recipes.sh"; \
	else \
		echo "Error: kpt validate-recipes.sh not found in $(KPT_VALIDATE_DIR) (set KPT_VALIDATE_DIR to a kpt checkout)" >&2; \
		exit 1; \
	fi
