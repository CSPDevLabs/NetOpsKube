###############################################################################
# Authentication (Keycloak + HAProxy gateway) — common-platform pattern.
# No oauth2-proxy. See docs/AUTH-FLOW.md.
###############################################################################

KEYCLOAK_ENABLED ?= NO

NOK_KEYCLOAK_DIR ?= $(BASE)/manifests/auth
KEYCLOAK_REPO_URL ?= https://github.com/CSPDevLabs/nok-portal-auth
KEYCLOAK_REPO_BRANCH ?= nok-restructure
KEYCLOAK_DIR ?= $(BASE)/manifests/auth/keycloak
HAPROXY_DIR ?= $(BASE)/manifests/auth/haproxy
AUTH_COREDNS_DIR ?= $(BASE)/manifests/auth/coredns

.PHONY: clone-keycloak-repo
clone-keycloak-repo:
	@echo "--> GIT: Ensuring nok-portal-auth repository exists ($(KEYCLOAK_REPO_BRANCH))"
	@if [ ! -d "$(NOK_KEYCLOAK_DIR)" ]; then \
		git clone -b $(KEYCLOAK_REPO_BRANCH) $(KEYCLOAK_REPO_URL) $(NOK_KEYCLOAK_DIR) ;\
	else \
		echo "--> GIT: $(NOK_KEYCLOAK_DIR) already exists. Skipping clone." ;\
		echo "--> GIT: Expected branch $(KEYCLOAK_REPO_BRANCH) (run 'make sync-keycloak-repo' to align)." ;\
	fi

.PHONY: sync-keycloak-repo
sync-keycloak-repo:
	@echo "--> GIT: Syncing nok-portal-auth to $(KEYCLOAK_REPO_BRANCH)"
	@if [ ! -d "$(NOK_KEYCLOAK_DIR)/.git" ]; then \
		$(MAKE) clone-keycloak-repo ;\
	else \
		cd $(NOK_KEYCLOAK_DIR) && git fetch origin && git checkout $(KEYCLOAK_REPO_BRANCH) && git pull --ff-only origin $(KEYCLOAK_REPO_BRANCH) ;\
	fi

.PHONY: apply-keycloak-coredns
apply-keycloak-coredns:
	@echo "--> AUTH: Applying CoreDNS hosts entry for bng.nok.local"
	@$(KUBECTL) apply -f $(AUTH_COREDNS_DIR)/coredns-configmap.yaml
	@$(KUBECTL) rollout restart deployment/coredns -n kube-system

.PHONY: deploy-haproxy-gateway
deploy-haproxy-gateway:
	@echo "--> AUTH: HAProxy gateway (/auth → Keycloak, / → portal)"
	@$(KUBECTL) apply -f $(HAPROXY_DIR)/haproxy-configmap.yaml
	@$(KUBECTL) apply -f $(HAPROXY_DIR)/haproxy-svc.yaml
	@$(KUBECTL) apply -f $(HAPROXY_DIR)/haproxy-deploy.yaml
	@$(KUBECTL) rollout status deployment/nok-haproxy -n nok-base --timeout=120s
	@$(KUBECTL) delete ingress keycloak-ingress oauth2-proxy-ingress nok-apps-portal-ingress \
		-n nok-base --ignore-not-found --wait=true
	@$(KUBECTL) apply -f $(HAPROXY_DIR)/gateway-ingress.yaml
	@$(KUBECTL) delete deployment oauth2-proxy -n nok-base --ignore-not-found --wait=true
	@$(KUBECTL) delete svc oauth2-proxy -n nok-base --ignore-not-found --wait=true

.PHONY: deploy-auth
deploy-auth:
	@echo "--> AUTH: Keycloak + HAProxy (no oauth2-proxy)"
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/postgres-secret.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/postgres-service.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/postgres-statefulset.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-admin-secret.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-realm-configmap.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-proxy-headers.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-svc.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-deploy.yaml
	@$(MAKE) deploy-haproxy-gateway
	@$(MAKE) apply-keycloak-coredns
	@$(KUBECTL) rollout restart deployment/keycloak -n nok-base
	@$(KUBECTL) rollout status deployment/keycloak -n nok-base --timeout=300s
	@echo "--> AUTH: Deployment completed"

.PHONY: strip-oauth2-ingress-auth apply-haproxy-auth test-auth
strip-oauth2-ingress-auth: ## Remove nginx auth-url pointing at deleted oauth2-proxy
	bash scripts/strip-oauth2-ingress-auth.sh

apply-haproxy-auth: ## Switch live cluster to HAProxy gateway
	bash scripts/apply-haproxy-auth.sh

test-auth: ## Smoke-test HAProxy + Keycloak login
	bash scripts/test-auth-haproxy.sh

.PHONY: reconfigure-auth
reconfigure-auth: deploy-auth portal-enable-keycloak apply-portal-haproxy-auth annotate-auth-ingress-bbm apply-portal-nginx-config

.PHONY: apply-portal-haproxy-auth
apply-portal-haproxy-auth:
	bash scripts/apply-portal-haproxy-auth.sh

.PHONY: portal-enable-keycloak
portal-enable-keycloak: apply-portal-haproxy-auth

.PHONY: annotate-auth-ingress-bng
annotate-auth-ingress-bng:
	@if [ "$(KEYCLOAK_ENABLED)" = "YES" ]; then \
		bash scripts/strip-oauth2-ingress-auth.sh; \
	fi

.PHONY: annotate-auth-ingress-dia
annotate-auth-ingress-dia: annotate-auth-ingress-bng

.PHONY: annotate-auth-ingress-bbm
annotate-auth-ingress-bbm:
	@if [ "$(KEYCLOAK_ENABLED)" = "YES" ]; then \
		if $(KUBECTL) get ingress bbm-ingress -n nok-bbm >/dev/null 2>&1; then \
			echo "--> AUTH: Clearing legacy nginx auth-url from BBM ingress"; \
			$(KUBECTL) annotate ingress bbm-ingress -n nok-bbm \
				netopskube.io/bbm-oauth="true" \
				nginx.ingress.kubernetes.io/auth-url- \
				nginx.ingress.kubernetes.io/auth-signin- \
				--overwrite; \
		fi; \
	fi

.PHONY: annotate-auth-ingress-gitea
annotate-auth-ingress-gitea:
	@if [ "$(KEYCLOAK_ENABLED)" = "YES" ]; then \
		if $(KUBECTL) get ingress nok-gitea-ingress -n nok-git >/dev/null 2>&1; then \
			$(KUBECTL) annotate ingress nok-gitea-ingress -n nok-git netopskube.io/bbm-oauth="true" --overwrite; \
		fi; \
	fi

.PHONY: configure-auth

ifeq ($(KEYCLOAK_ENABLED),YES)

configure-auth: deploy-auth portal-enable-keycloak annotate-auth-ingress-bng annotate-auth-ingress-bbm apply-portal-nginx-config

else

configure-auth:
	@echo "--> AUTH: Keycloak disabled. Skipping authentication deployment."

endif
