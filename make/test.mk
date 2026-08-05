# ----------------------------------------------------------------------------
# Test targets (BATS)
#
# Unit tests are fast and do not require a KinD cluster.
# Integration / smoke tests require a deployed environment.
# See test/README.md
# ----------------------------------------------------------------------------

BATS ?= bats
TEST_DIR ?= $(BASE)/test

.PHONY: test test-unit test-integration test-smoke test-coverage
test: test-unit test-coverage ## Run default test suite and verify 100% unit scope coverage

test-unit: check-tools ## Run BATS unit tests (no cluster required)
	@command -v $(BATS) >/dev/null 2>&1 || { \
		echo "Error: 'bats' not found. Install with: sudo apt install bats"; \
		exit 1; \
	}
	@echo "--> TEST: Running BATS unit tests"
	@$(BATS) --pretty $(TEST_DIR)/bats/unit/
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
	@$(BATS) --pretty $(TEST_DIR)/bats/integration/
	@echo ""
	@echo "--> TEST: Integration tests completed successfully."

test-smoke: check-tools ## Run Makefile smoke verifications (cluster required)
	@echo "--> TEST: Running smoke checks"
	@$(MAKE) verify-lb-ips
	@echo ""
	@echo "--> TEST: Smoke checks completed successfully."
