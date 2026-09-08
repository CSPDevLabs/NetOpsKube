###############################################################################
# Unified portal menu updates (nok-restructure: portal in nok-base).
###############################################################################

.PHONY: sync-portal-files
sync-portal-files: ## Update portal HTML/CSS/JS via ConfigMap (reliable; no docker cp)
	@PORTAL_DIR="$(abspath $(BASE)/../kpt/nok-base/portal)" bash scripts/apply-portal-static.sh

.PHONY: fix-portal
fix-portal: ## Recover stuck portal rollout / CrashLoop / missing menu-config
	@PORTAL_DIR="$(abspath $(BASE)/../kpt/nok-base/portal)" bash scripts/fix-portal.sh

.PHONY: fix-portal-apps
fix-portal-apps: ## Fix HAProxy routing + ingress paths so portal apps open
	@bash scripts/fix-portal-apps.sh

.PHONY: fix-app-subpaths
fix-app-subpaths: ## Fix Grafana/Prometheus subpath URLs for portal iframe
	@bash scripts/fix-app-subpaths.sh

.PHONY: test-portal-apps
test-portal-apps: ## Smoke-test Gitea/BBM/BNG app paths via HAProxy
	@bash scripts/test-portal-apps.sh

.PHONY: apply-portal-nginx-config
apply-portal-nginx-config: sync-portal-files

.PHONY: portal-enable-bng
portal-enable-bng:
	@echo "--> PORTAL: Enabling BNG menu"
	@$(KUBECTL) get configmap nok-apps-menu-config -n nok-base -o json | \
	jq '.data["menu-config.json"] |= (fromjson | .solutions |= map(if .id == "nok-bng" then .deployed = "yes" else . end) | tojson)' | \
	$(KUBECTL) apply -f -
	@bash scripts/sync-portal-menu-static.sh

.PHONY: portal-enable-dia
portal-enable-dia:
	@echo "--> PORTAL: Enabling DIA menu"
	@$(KUBECTL) get configmap nok-apps-menu-config -n nok-base -o json | \
	jq '.data["menu-config.json"] |= (fromjson | .solutions |= map(if .id == "nok-dia" then .deployed = "yes" else . end) | tojson)' | \
	$(KUBECTL) apply -f -
	@bash scripts/sync-portal-menu-static.sh
