# ----------------------------------------------------------------------------
# Per-recipe integration verification (Epic 9)
#
# Validates recipe health after deploy: pod availability, portal /healthz,
# Prometheus readiness, and (full level) gNMIc subscriptions + metrics flow.
#
# Usage:
#   make verify-recipe-bng
#   make verify-recipe-dia
#   make verify-recipe RECIPE=bng NOK_RECIPE_VERIFY_LEVEL=full
#
# Set NOK_VERIFY_BEFORE_PUBLISH=no to skip checks before git push targets.
# See test/README.md and docs/TROUBLESHOOTING.md
# ----------------------------------------------------------------------------

RECIPE ?= bng
NOK_VERIFY_BEFORE_PUBLISH ?= yes
NOK_RECIPE_VERIFY_LEVEL ?= install
PORTAL_HOST ?= bng.nok.local
INGRESS_LOCAL_PORT ?= 8080
RECIPE_POD_WAIT_TIMEOUT ?= 5m

ifeq ($(RECIPE),bng)
  RECIPE_NS := nok-bng
  RECIPE_LABEL := BNG
else ifeq ($(RECIPE),dia)
  RECIPE_NS := nok-dia
  RECIPE_LABEL := DIA
else
  $(error RECIPE must be bng or dia (got '$(RECIPE)'))
endif

.PHONY: help-recipe-verify
help-recipe-verify: ## List per-recipe verification targets
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## .*$$' make/recipe-verify.mk | sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-35s\033[0m %s\n", $$1, $$2}'

.PHONY: verify-recipe-bng verify-recipe-dia verify-recipe
verify-recipe-bng: ## Run install-level checks for the BNG recipe (set NOK_RECIPE_VERIFY_LEVEL=full for metrics)
	@$(MAKE) verify-recipe RECIPE=bng

verify-recipe-dia: ## Run install-level checks for the DIA recipe (set NOK_RECIPE_VERIFY_LEVEL=full for metrics)
	@$(MAKE) verify-recipe RECIPE=dia

verify-recipe: check-tools ## Verify recipe health (RECIPE=bng|dia, NOK_RECIPE_VERIFY_LEVEL=install|full)
	@echo "--> RECIPE [$(RECIPE_LABEL)]: Starting $(NOK_RECIPE_VERIFY_LEVEL)-level verification in namespace '$(RECIPE_NS)'"
	@$(MAKE) verify-recipe-controller
	@$(MAKE) verify-recipe-pods RECIPE=$(RECIPE)
	@$(MAKE) verify-recipe-portal-health RECIPE=$(RECIPE)
	@$(MAKE) verify-recipe-prometheus-ready RECIPE=$(RECIPE)
	@if [ "$(NOK_RECIPE_VERIFY_LEVEL)" = "full" ]; then \
		$(MAKE) verify-recipe-gnmic-subscriptions RECIPE=$(RECIPE); \
		$(MAKE) verify-recipe-metrics RECIPE=$(RECIPE); \
	fi
	@echo ""
	@echo "--> RECIPE [$(RECIPE_LABEL)]: All $(NOK_RECIPE_VERIFY_LEVEL)-level checks passed."

.PHONY: verify-recipe-pods
verify-recipe-pods: $(KUBECTL) ## Wait for recipe namespace pods to be Running/Completed
	@echo "--> RECIPE [$(RECIPE_LABEL)]: Checking pod availability in '$(RECIPE_NS)'"
	@if ! $(KUBECTL) get namespace $(RECIPE_NS) >/dev/null 2>&1; then \
		echo "[FAIL] Namespace '$(RECIPE_NS)' does not exist. Run install-$(RECIPE)-pkg first." >&2; \
		exit 1; \
	fi
	@DEPLOYS=$$($(KUBECTL) get deploy -n $(RECIPE_NS) -o name 2>/dev/null); \
	if [ -n "$$DEPLOYS" ]; then \
		echo "    Waiting for deployments to become Available..."; \
		$(KUBECTL) wait --for=condition=Available deployment --all -n $(RECIPE_NS) --timeout=$(RECIPE_POD_WAIT_TIMEOUT); \
	fi
	@BAD=$$($(KUBECTL) get pods -n $(RECIPE_NS) --no-headers 2>/dev/null \
		| awk '$$3!="Running" && $$3!="Completed" && $$3!="Succeeded" {print $$1 " (" $$3 ")"}'); \
	if [ -n "$$BAD" ]; then \
		echo "[FAIL] Pods not ready in $(RECIPE_NS):"; \
		echo "$$BAD" | sed 's/^/    /'; \
		exit 1; \
	fi
	@COUNT=$$($(KUBECTL) get pods -n $(RECIPE_NS) --no-headers 2>/dev/null | wc -l); \
	echo "[PASS] $$COUNT pod(s) Running/Completed in $(RECIPE_NS)"

.PHONY: verify-recipe-portal-health
verify-recipe-portal-health: $(KUBECTL) ## HTTP GET /healthz on the recipe portal ingress
	@echo "--> RECIPE [$(RECIPE_LABEL)]: Checking portal /healthz"
	@LB_IP=$$($(KUBECTL) get svc -n nok-base ingress-nginx-controller \
		-o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	if [ -z "$$LB_IP" ]; then \
		LB_IP="$(GITEA_IP)"; \
	fi; \
	if [ -z "$$LB_IP" ]; then \
		echo "[FAIL] Ingress LoadBalancer IP not available" >&2; \
		exit 1; \
	fi; \
	if $(CURL) --resolve $(PORTAL_HOST):$(INGRESS_LOCAL_PORT):127.0.0.1 \
		http://$(PORTAL_HOST):$(INGRESS_LOCAL_PORT)/healthz >/dev/null 2>&1; then \
		echo "[PASS] Portal /healthz via localhost:$(INGRESS_LOCAL_PORT)"; \
	elif $(CURL) --resolve $(PORTAL_HOST):80:$$LB_IP \
		http://$(PORTAL_HOST)/healthz >/dev/null 2>&1; then \
		echo "[PASS] Portal /healthz via ingress LB $$LB_IP"; \
	else \
		echo "[FAIL] Portal /healthz not reachable (tried :$(INGRESS_LOCAL_PORT) and LB $$LB_IP)" >&2; \
		exit 1; \
	fi

.PHONY: verify-recipe-prometheus-ready
verify-recipe-prometheus-ready: $(KUBECTL) ## Confirm Prometheus pod is ready in the recipe namespace
	@echo "--> RECIPE [$(RECIPE_LABEL)]: Checking Prometheus readiness"
	@PROM_POD=$$($(KUBECTL) get pods -n $(RECIPE_NS) \
		-l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$PROM_POD" ]; then \
		echo "[FAIL] No Prometheus pod found in $(RECIPE_NS)" >&2; \
		exit 1; \
	fi; \
	READY=$$($(KUBECTL) get pod -n $(RECIPE_NS) "$$PROM_POD" \
		-o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null); \
	if [ "$$READY" != "True" ]; then \
		echo "[FAIL] Prometheus pod $$PROM_POD is not Ready (status=$$READY)" >&2; \
		exit 1; \
	fi; \
	echo "[PASS] Prometheus pod $$PROM_POD is Ready"

.PHONY: verify-recipe-controller
verify-recipe-controller: $(KUBECTL) ## Confirm nok-controller is ready and /targets responds (nok-base)
	@echo "--> RECIPE: Checking nok-controller (platform)"
	@if ! $(KUBECTL) get deployment nok-controller -n nok-base >/dev/null 2>&1; then \
		echo "[FAIL] nok-controller deployment not found in nok-base" >&2; \
		exit 1; \
	fi; \
	$(KUBECTL) wait --for=condition=Available deployment/nok-controller -n nok-base --timeout=$(RECIPE_POD_WAIT_TIMEOUT); \
	EP=$$($(KUBECTL) get endpoints nok-controller -n nok-base -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null); \
	if [ -z "$$EP" ]; then \
		echo "[FAIL] nok-controller has no ready endpoints" >&2; \
		exit 1; \
	fi; \
	if $(KUBECTL) exec -n nok-base deploy/nok-controller -- wget -qO- http://127.0.0.1:8080/targets >/dev/null 2>&1; then \
		echo "[PASS] nok-controller deployment ready; /targets HTTP OK"; \
	else \
		echo "[PASS] nok-controller deployment ready (endpoint $$EP; HTTP probe skipped)"; \
	fi

.PHONY: verify-recipe-gnmic-subscriptions
verify-recipe-gnmic-subscriptions: $(KUBECTL) ## Verify gNMIc Target subscriptions are running (full level)
	@echo "--> RECIPE [$(RECIPE_LABEL)]: Checking gNMIc subscriptions"
	@$(MAKE) verify-gnmic-subscriptions BNG_NAMESPACE=$(RECIPE_NS)

.PHONY: verify-recipe-metrics
verify-recipe-metrics: $(KUBECTL) ## Verify Prometheus is scraping gNMIc metrics (full level)
	@echo "--> RECIPE [$(RECIPE_LABEL)]: Checking gNMIc metrics in Prometheus"
	@PROM_POD=$$($(KUBECTL) get pods -n $(RECIPE_NS) \
		-l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$PROM_POD" ]; then \
		echo "[FAIL] No Prometheus pod in $(RECIPE_NS)" >&2; \
		exit 1; \
	fi; \
	TARGETS_JSON=$$($(KUBECTL) exec -n $(RECIPE_NS) "$$PROM_POD" -c prometheus -- \
		wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null); \
	GNMIC_UP=$$(echo "$$TARGETS_JSON" | jq -r \
		'.data.activeTargets[] | select(.labels.job // "" | test("gnmic"; "i")) | select(.health=="up") | .labels.job' \
		| head -1); \
	if [ -n "$$GNMIC_UP" ]; then \
		echo "[PASS] gNMIc Prometheus target '$$GNMIC_UP' is up"; \
	else \
		echo "[FAIL] No healthy gNMIc Prometheus scrape targets in $(RECIPE_NS)" >&2; \
		echo "       Deploy containerlab and wait for gNMIc subscriptions before full-level verify." >&2; \
		exit 1; \
	fi; \
	SAMPLE_COUNT=$$($(KUBECTL) exec -n $(RECIPE_NS) "$$PROM_POD" -c prometheus -- \
		wget -qO- 'http://localhost:9090/api/v1/query?query=count({job=~".*gnmic.*"})' 2>/dev/null \
		| jq -r '.data.result[0].value[1] // "0"'); \
	if [ "$$SAMPLE_COUNT" = "0" ] || [ "$$SAMPLE_COUNT" = "null" ]; then \
		echo "[FAIL] No gNMIc metric series found in Prometheus" >&2; \
		exit 1; \
	fi; \
	echo "[PASS] Prometheus reports $$SAMPLE_COUNT gNMIc metric series"

# Gate manifest publishing on recipe health (Epic 9 — surface broken recipes before publish)
.PHONY: verify-before-publish-bng verify-before-publish-dia
verify-before-publish-bng:
	@if [ "$(NOK_VERIFY_BEFORE_PUBLISH)" = "yes" ]; then \
		$(MAKE) verify-recipe RECIPE=bng NOK_RECIPE_VERIFY_LEVEL=install; \
	else \
		echo "--> RECIPE [BNG]: Skipping pre-publish verification (NOK_VERIFY_BEFORE_PUBLISH=no)"; \
	fi

verify-before-publish-dia:
	@if [ "$(NOK_VERIFY_BEFORE_PUBLISH)" = "yes" ]; then \
		$(MAKE) verify-recipe RECIPE=dia NOK_RECIPE_VERIFY_LEVEL=install; \
	else \
		echo "--> RECIPE [DIA]: Skipping pre-publish verification (NOK_VERIFY_BEFORE_PUBLISH=no)"; \
	fi
