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
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' make/troubleshoot.mk | sort \
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

.PHONY: verify-lb-ips
verify-lb-ips: $(KUBECTL) ## Verify KinD LB prefix, cluster LoadBalancer IPs, and Gitea API reachability
	@IP_PREFIX="$(KIND_NET_PREFIX)" ;\
	EXPECTED_INGRESS="$(KIND_NET_PREFIX).$(KIND_LB_INGRESS_HOST)" ;\
	EXPECTED_GITEA_SSH="$(KIND_NET_PREFIX).$(KIND_LB_GITEA_SSH_HOST)" ;\
	FAIL=0 ;\
	echo "--> VERIFY: KinD LB network prefix is $$IP_PREFIX" ;\
	if [ -z "$$IP_PREFIX" ]; then \
		echo "[FAIL] KinD cluster '$(KIND_CLUSTER_NAME)' not found" ; exit 1 ;\
	fi ;\
	if [ "$(GITEA_IP)" != "$$EXPECTED_INGRESS" ]; then \
		echo "[FAIL] GITEA_IP=$(GITEA_IP) expected $$EXPECTED_INGRESS" ; FAIL=1 ;\
	else \
		echo "[PASS] GITEA_IP=$(GITEA_IP)" ;\
	fi ;\
	if [ "$(GITEA_SSH_HOST)" != "$$EXPECTED_GITEA_SSH" ]; then \
		echo "[FAIL] GITEA_SSH_HOST=$(GITEA_SSH_HOST) expected $$EXPECTED_GITEA_SSH" ; FAIL=1 ;\
	else \
		echo "[PASS] GITEA_SSH_HOST=$(GITEA_SSH_HOST)" ;\
	fi ;\
	for svc_check in \
		"nok-base:ingress-nginx-controller:$$EXPECTED_INGRESS" \
		"nok-git:gitea-ssh:$$EXPECTED_GITEA_SSH" ; do \
		ns=$${svc_check%%:*} ; rest=$${svc_check#*:} ;\
		svc=$${rest%%:*} ; expected=$${rest#*:} ;\
		LB_IP=$$($(KUBECTL) get svc -n $$ns $$svc \
			-o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ;\
		if [ -z "$$LB_IP" ]; then \
			echo "[WARN] $$ns/$$svc LoadBalancer IP not assigned yet" ; FAIL=1 ;\
		elif [ "$$LB_IP" != "$$expected" ]; then \
			echo "[FAIL] $$ns/$$svc LB $$LB_IP expected $$expected" ; FAIL=1 ;\
		else \
			echo "[PASS] $$ns/$$svc LoadBalancer IP $$LB_IP" ;\
		fi ;\
	done ;\
	LB_IP=$$($(KUBECTL) get svc -n nok-base ingress-nginx-controller \
		-o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ;\
	if [ -n "$$LB_IP" ]; then \
		if $(CURL) --resolve $(GITEA_HOST):80:$$LB_IP \
			-u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
			http://$(GITEA_HOST)$(GITEA_HTTP_PATH)/api/v1/version >/dev/null 2>&1; then \
			echo "[PASS] Gitea API reachable at $$LB_IP" ;\
		else \
			echo "[FAIL] Gitea API not reachable at $$LB_IP" ; FAIL=1 ;\
		fi ;\
	fi ;\
	if [ $$FAIL -ne 0 ]; then \
		echo "" ;\
		echo "[FAIL] KinD LB IP verification failed." ;\
		exit 1 ;\
	fi ;\
	echo "" ;\
	echo "--> VERIFY: All KinD LB IP checks passed."
