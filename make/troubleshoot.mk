# ----------------------------------------------------------------------------
# Troubleshooting targets
#
# Included from the top-level Makefile. Relies on $(KUBECTL) being defined.
# Run `make help-troubleshoot` to list targets in this file only.
# See docs/TROUBLESHOOTING.md for the operator runbook.
# ----------------------------------------------------------------------------

BNG_NAMESPACE ?= nok-bng

.PHONY: help-troubleshoot
help-troubleshoot: ## List troubleshooting targets only
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(lastword $(MAKEFILE_LIST)) | sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: verify-gnmic-subscriptions
verify-gnmic-subscriptions: $(KUBECTL) ## Show gNMIc Target subscription status per collector cluster; non-zero exit if any sub is not 'running'
	@echo "--> GNMIC: Verifying Target subscriptions in namespace '$(BNG_NAMESPACE)'"
	@TARGETS=$$($(KUBECTL) get targets.operator.gnmic.dev -n $(BNG_NAMESPACE) -o jsonpath='{.items[*].metadata.name}'); \
	if [ -z "$$TARGETS" ]; then \
		echo "[WARN] No gNMIc Targets found in $(BNG_NAMESPACE)"; \
		exit 0; \
	fi; \
	BAD=0; \
	printf "%-30s %-20s %-12s %-45s %s\n" "TARGET" "CLUSTER" "CONN" "SUBSCRIPTION" "STATE"; \
	for t in $$TARGETS; do \
		ROWS=$$($(KUBECTL) get targets.operator.gnmic.dev -n $(BNG_NAMESPACE) $$t -o json \
			| jq -r --arg t "$$t" '.status.clusterStates // {} \
				| to_entries[] \
				| . as $$c \
				| (.value.subscriptions // {"<none>":"<none>"}) \
				| to_entries[] \
				| [$$t, $$c.key, ($$c.value.connectionState // "?"), .key, .value] | @tsv'); \
		if [ -z "$$ROWS" ]; then \
			printf "%-30s %-20s %-12s %-45s %s\n" "$$t" "-" "-" "<no clusterStates>" "-"; \
			BAD=1; \
			continue; \
		fi; \
		echo "$$ROWS" | while IFS=$$'\t' read -r tgt cluster conn sub state; do \
			if [ "$$state" = "running" ]; then \
				printf "%-30s %-20s %-12s %-45s \033[0;32m%s\033[0m\n" "$$tgt" "$$cluster" "$$conn" "$$sub" "$$state"; \
			else \
				printf "%-30s %-20s %-12s %-45s \033[0;31m%s\033[0m\n" "$$tgt" "$$cluster" "$$conn" "$$sub" "$$state"; \
			fi; \
		done; \
		if echo "$$ROWS" | awk -F'\t' '$$5!="running"{exit 0} END{exit 1}'; then BAD=1; fi; \
	done; \
	if [ $$BAD -ne 0 ]; then \
		echo ""; \
		echo "[FAIL] One or more subscriptions are not in 'running' state."; \
		echo "       Tip: 'make restart-gnmic-collector' to force a re-subscribe (see docs/TROUBLESHOOTING.md)."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "--> GNMIC: All subscriptions are running on all clusters."

.PHONY: restart-gnmic-collector
restart-gnmic-collector: $(KUBECTL) ## Restart gNMIc collector pods in BNG_NAMESPACE to force re-subscribe (use COLLECTOR=<name> to restrict)
	@echo "--> GNMIC: Restarting collector pod(s) in '$(BNG_NAMESPACE)'"
	@if [ -n "$(COLLECTOR)" ]; then \
		echo "    Deleting pod $(COLLECTOR)"; \
		$(KUBECTL) -n $(BNG_NAMESPACE) delete pod $(COLLECTOR); \
	else \
		PODS=$$($(KUBECTL) -n $(BNG_NAMESPACE) get pods -l app.kubernetes.io/name=gnmic -o jsonpath='{.items[*].metadata.name}'); \
		if [ -z "$$PODS" ]; then \
			echo "[ERROR] No gnmic collector pods found (label app.kubernetes.io/name=gnmic) in $(BNG_NAMESPACE)" >&2; \
			exit 1; \
		fi; \
		for p in $$PODS; do echo "    Deleting pod $$p"; $(KUBECTL) -n $(BNG_NAMESPACE) delete pod $$p; done; \
	fi
	@echo "--> GNMIC: Run 'make verify-gnmic-subscriptions' once pods are Ready to confirm recovery."
