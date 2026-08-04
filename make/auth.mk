###############################################################################
# Authentication Makefile
#
# This file contains all authentication-related configuration, variables,
# and deployment targets. It includes:
#   - Optional Keycloak enable/disable configuration
#   - Keycloak repository management
#   - Keycloak and PostgreSQL deployment
#   - OAuth2 Proxy deployment
#   - Portal configuration updates for Keycloak
#   - Authentication ingress annotation for Portal, BNG, and DIA
#
# Shared/common functionality is defined in the main Makefile or other
# shared make/*.mk files.
###############################################################################


# Optional: Set to 'YES' to onboard Keycloak, otherwise 'NO'
KEYCLOAK_ENABLED ?= NO

NOK_KEYCLOAK_DIR ?= $(BASE)/nok-portal-auth
KEYCLOAK_REPO_URL ?= https://github.com/CSPDevLabs/nok-portal-auth
KEYCLOAK_REPO_BRANCH ?= nok-restructure
KEYCLOAK_DIR ?= $(BASE)/nok-portal-auth/keycloak
OAUTH2_PROXY_DIR  ?= $(BASE)/nok-portal-auth/oauth2-proxy


.PHONY: clone-keycloak-repo
clone-keycloak-repo:
	@echo "--> GIT: Ensuring nok-portal-auth repository exists"
	@if [ ! -d "$(NOK_KEYCLOAK_DIR)" ]; then \
		git clone -b $(KEYCLOAK_REPO_BRANCH) $(KEYCLOAK_REPO_URL) $(NOK_KEYCLOAK_DIR) ;\
	else \
		echo "--> GIT: $(NOK_KEYCLOAK_DIR) already exists. Skipping clone." ;\
	fi

.PHONY: deploy-auth
deploy-auth:
	@echo "--> AUTH: Configure nok-portal-auth"

	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/postgres-secret.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/postgres-service.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/postgres-statefulset.yaml
	
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-admin-secret.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-realm-configmap.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-svc.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-deploy.yaml
	@$(KUBECTL) apply -f $(KEYCLOAK_DIR)/keycloak-ingress.yaml

	@$(KUBECTL) apply -f $(OAUTH2_PROXY_DIR)/oauth2-proxy-secret.yaml
	@$(KUBECTL) apply -f $(OAUTH2_PROXY_DIR)/oauth2-proxy-svc.yaml
	@$(KUBECTL) apply -f $(OAUTH2_PROXY_DIR)/oauth2-proxy-deploy.yaml
	@$(KUBECTL) apply -f $(OAUTH2_PROXY_DIR)/oauth2-proxy-ingress.yaml

	@echo "--> AUTH: Deployment completed"

.PHONY: portal-enable-keycloak
portal-enable-keycloak:
	@echo "--> PORTAL: Enabling Keycloak menu"
	@$(KUBECTL) get configmap nok-apps-menu-config -n nok-base -o json | \
	jq '.data["menu-config.json"] |= (fromjson | .featured |= map(if .name == "Keycloak" then . + {"deployed":"yes"} else . end) | tojson)' | \
	$(KUBECTL) apply -f -
	@$(KUBECTL) rollout restart deployment/nok-apps-portal-app -n nok-base


.PHONY: annotate-auth-ingress-bng
annotate-auth-ingress-bng:
	@if [ "$(KEYCLOAK_ENABLED)" = "YES" ]; then \
		if $(KUBECTL) get ingress nok-apps-ingress -n nok-bng >/dev/null 2>&1; then \
			echo "--> AUTH: Annotating nok-bng/nok-apps-ingress"; \
			$(KUBECTL) annotate ingress nok-apps-ingress \
				-n nok-bng \
				nginx.ingress.kubernetes.io/auth-url="http://oauth2-proxy.nok-base.svc.cluster.local/oauth2/auth" \
				nginx.ingress.kubernetes.io/auth-signin="http://bng.nok.local:8080/oauth2/start?rd=\$$escaped_request_uri" \
				--overwrite; \
		else \
			echo "--> AUTH: Ingress nok-bng/nok-apps-ingress not found. Skipping."; \
		fi; \
	else \
		echo "--> AUTH: Keycloak disabled. Skipping BNG ingress annotation."; \
	fi


.PHONY: annotate-auth-ingress-base
annotate-auth-ingress-base:
	@if $(KUBECTL) get ingress nok-apps-portal-ingress -n nok-base >/dev/null 2>&1; then \
		echo "--> AUTH: Annotating nok-base/nok-apps-portal-ingress"; \
		$(KUBECTL) annotate ingress nok-apps-portal-ingress \
			-n nok-base \
			nginx.ingress.kubernetes.io/auth-url="http://oauth2-proxy.nok-base.svc.cluster.local/oauth2/auth" \
			nginx.ingress.kubernetes.io/auth-signin="http://bng.nok.local:8080/oauth2/start?rd=\$$escaped_request_uri" \
			--overwrite; \
	else \
		echo "--> AUTH: Ingress nok-base/nok-apps-portal-ingress not found. Skipping."; \
	fi


.PHONY: annotate-auth-ingress-dia
annotate-auth-ingress-dia:
	@if [ "$(KEYCLOAK_ENABLED)" = "YES" ]; then \
		if $(KUBECTL) get ingress nok-apps-ingress -n nok-dia >/dev/null 2>&1; then \
			echo "--> AUTH: Annotating nok-dia/nok-apps-ingress"; \
			$(KUBECTL) annotate ingress nok-apps-ingress \
				-n nok-dia \
				nginx.ingress.kubernetes.io/auth-url="http://oauth2-proxy.nok-base.svc.cluster.local/oauth2/auth" \
				nginx.ingress.kubernetes.io/auth-signin="http://bng.nok.local:8080/oauth2/start?rd=\$$escaped_request_uri" \
				--overwrite; \
		else \
			echo "--> AUTH: Ingress nok-dia/nok-apps-ingress not found. Skipping."; \
		fi; \
	else \
		echo "--> AUTH: Keycloak disabled. Skipping DIA ingress annotation."; \
	fi



.PHONY: configure-auth

ifeq ($(KEYCLOAK_ENABLED),YES)

configure-auth: clone-keycloak-repo deploy-auth portal-enable-keycloak annotate-auth-ingress-base

else

configure-auth:
	@echo "--> AUTH: Keycloak disabled. Skipping authentication deployment."

endif