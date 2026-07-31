###############################################################################
# DIA Makefile
#
# This file contains all DIA-specific configuration, variables, and
# deployment targets. It includes:
#   - DIA package installation
#   - Containerlab deployment and cleanup
#   - GitOps repository initialization and synchronization
#   - Grafana dashboard repository management
#   - Flux source, secret, and Kustomization management
#   - Portal menu updates for DIA
#   - DIA-specific authentication ingress annotations
#
# Shared/common functionality is defined in the main Makefile or other
# shared make/*.mk files.
###############################################################################

FLUX_DIA_REPO ?= nok-dia-resources
FLUX_DIA_GRAFANA_REPO ?= grafana-dashboards
FLUX_DIA_SECRET ?= nok-dia-auth
DIA_MANIFESTS_DIR := ./nok-clabs/nok-dia/nok-manifests
DIA_GRAFANA_DIR := ./nok-clabs/nok-dia/grafana-dashboards
DIA_REPO_URL := ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_DIA_REPO).git
DIA_GRAFANA_REPO_URL := ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_DIA_GRAFANA_REPO).git

## Deploy DIA and GitOps
.PHONY: try-nok-dia
try-nok-dia: install-dia-pkg install-git-pkg gitops-init gitops-dia-kustomization portal-enable-dia annotate-auth-ingress-dia

.PHONY: gitops-dia-kustomization
gitops-dia-kustomization: gitea-create-dia-repo gitea-create-dia-grafana-repo flux-create-dia-secret flux-create-dia-source push-dia-manifests push-dia-grafana create-dia-kustomizations
	@echo "--> GITOPS: DIA repo in sync by Flux"

.PHONY: deploy-clab-dia
deploy-clab-dia: check-tools git-clone-clab check-clab-prerequisites ## Deploys the Containerlab DIA topology
	@echo "--> CLAB: Deploying DIA topology from $(NOK_CLABS_DIR)/nok-dia"
	@if [ -d "$(NOK_CLABS_DIR)/nok-dia" ]; then \
		cd $(NOK_CLABS_DIR)/nok-dia && $(CLAB) deploy -t topo.clab.yaml ;\
	else \
		echo "Error: $(NOK_CLABS_DIR)/nok-dia directory not found. Please ensure the nok-clabs repository is cloned and contains the nok-dia subdirectory." ;\
		exit 1 ;\
	fi

.PHONY: destroy-clab-dia
destroy-clab-dia: check-tools git-clone-clab ## Destroys the Containerlab DIA topology and cleans up
	@echo "--> CLAB: Destroying DIA topology from $(NOK_CLABS_DIR)/nok-dia"
	@if [ -d "$(NOK_CLABS_DIR)/nok-dia" ]; then \
		cd $(NOK_CLABS_DIR)/nok-dia && $(CLAB) destroy --cleanup -t topo.clab.yaml ;\
	else \
		echo "Error: $(NOK_CLABS_DIR)/nok-dia directory not found. Please ensure the nok-clabs repository is cloned and contains the nok-dia subdirectory." ;\
		exit 1 ;\
	fi

.PHONY: install-dia-pkg
install-dia-pkg: check-tools git-clone-kpt ## Installs the base kpt package from ./nok-kpt/nok-dia
	@$(call INSTALL_KPT_PACKAGE,$(NOK_KPT_DIR)/nok-dia,nok-dia,"--reconcile-timeout=5m", "--inventory-policy=adopt")

.PHONY: gitea-create-dia-repo
gitea-create-dia-repo:
	@echo "--> GITEA: Ensuring repo $(FLUX_DIA_REPO) exists"
	@$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  http://$(GITEA_HOST)/api/v1/repos/$(GITEA_ADMIN_USER)/$(FLUX_DIA_REPO) \
	  >/dev/null || \
	$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -X POST \
	  -H "Content-Type: application/json" \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  -d '{"name":"$(FLUX_DIA_REPO)", "description": "DIA resources for Network Observability and Conf Management","private":false,"auto_init":true}' \
	  http://$(GITEA_HOST)/api/v1/user/repos

.PHONY: gitea-create-dia-grafana-repo
gitea-create-dia-grafana-repo:
	@echo "--> GITEA: Ensuring repo $(FLUX_DIA_GRAFANA_REPO) exists"
	@$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  http://$(GITEA_HOST)/api/v1/repos/$(GITEA_ADMIN_USER)/$(FLUX_DIA_GRAFANA_REPO) \
	  >/dev/null || \
	$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -X POST \
	  -H "Content-Type: application/json" \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  -d '{"name":"$(FLUX_DIA_GRAFANA_REPO)", "description": "NetOpsKube DIA Grafana Dashboards","private":false,"auto_init":true}' \
	  http://$(GITEA_HOST)/api/v1/user/repos
	
.PHONY: flux-create-dia-secret
flux-create-dia-secret:
	@echo "--> FLUX: Ensuring Git secret $(FLUX_DIA_SECRET) exists"
	@if ! $(KUBECTL) get secret $(FLUX_DIA_SECRET) -n flux-system > /dev/null 2>&1; then \
		echo "Creating Git secret $(FLUX_DIA_SECRET)..."; \
		$(FLUX) create secret git $(FLUX_DIA_SECRET) \
		  --url=ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_DIA_REPO).git \
		  --ssh-key-algorithm=ed25519 \
		  --private-key-file=$(FLUX_SSH_KEY) \
		  --namespace=flux-system; \
	else \
		echo "Git secret $(FLUX_DIA_SECRET) already exists."; \
	fi

.PHONY: flux-create-dia-source
flux-create-dia-source:
	@echo "--> FLUX: Ensuring GitRepository source $(FLUX_DIA_REPO) exists"
	@if ! $(KUBECTL) get gitrepository $(FLUX_DIA_REPO) -n flux-system > /dev/null 2>&1; then \
		echo "Creating GitRepository source $(FLUX_DIA_REPO)..."; \
		$(FLUX) create source git $(FLUX_DIA_REPO) \
		  --url=ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_DIA_REPO).git \
		  --branch=$(FLUX_GIT_BRANCH) \
		  --secret-ref=$(FLUX_DIA_SECRET) \
		  --interval=1m \
		  --namespace=flux-system; \
	else \
		echo "GitRepository source $(FLUX_DIA_REPO) already exists."; \
	fi	

.PHONY: push-dia-manifests
push-dia-manifests:
	@echo "--> GIT: Forcing full snapshot push of DIA manifests to $(FLUX_DIA_REPO)"

	@cd $(DIA_MANIFESTS_DIR) && \
		( \
			rm -rf .git && \
			git init -b $(FLUX_GIT_BRANCH) && \
			git remote add origin $(DIA_REPO_URL) && \
			git add -A && \
			git commit --allow-empty -m "Authoritative snapshot of DIA manifests" && \
			git config core.sshCommand 'ssh -o IdentitiesOnly=yes -i $(FLUX_SSH_KEY)' && \
			git push --force origin $(FLUX_GIT_BRANCH) \
		)

	@echo "--> GIT: Full snapshot push completed"

.PHONY: push-dia-grafana
push-dia-grafana:
	@echo "--> GIT: Forcing full snapshot push of DIA Grafana Dashboards to $(FLUX_DIA_GRAFANA_REPO)"

	@cd $(DIA_GRAFANA_DIR) && \
		( \
			rm -rf .git && \
			git init -b $(FLUX_GIT_BRANCH) && \
			git remote add origin $(DIA_GRAFANA_REPO_URL) && \
			git add -A && \
			git commit --allow-empty -m "Authoritative snapshot of DIA manifests" && \
			git config core.sshCommand 'ssh -o IdentitiesOnly=yes -i $(FLUX_SSH_KEY)' && \
			git push --force origin $(FLUX_GIT_BRANCH) \
		)

	@echo "--> GIT: Full snapshot push completed"

.PHONY: create-dia-kustomizations
create-dia-kustomizations:
	@echo "--> FLUX: Ensuring Kustomizations for DIA manifests exist"
	@for d in $(DIA_MANIFESTS_DIR)/*/; do \
		n=$$(basename "$$d"); \
		if [ "$$n" != ".git" ]; then \
			echo "Checking Kustomization for $$n..."; \
			if $(FLUX) get kustomization "dia-$$n" -n flux-system 2>&1 | grep -q "not found"; then \
				echo "Creating Kustomization for $$n..."; \
				$(FLUX) create kustomization "dia-$$n" \
				  --source=GitRepository/$(FLUX_DIA_REPO) \
				  --path="./$$n" \
				  --prune=true \
				  --interval=1m \
				  --timeout=1m \
				  --namespace=flux-system; \
			else \
				echo "Kustomization for $$n already exists."; \
			fi \
		fi \
	done


.PHONY: portal-enable-dia
portal-enable-dia:
	@echo "--> PORTAL: Enabling DIA menu"
	@$(KUBECTL) get configmap nok-apps-menu-config -n nok-base -o json | \
	jq '.data["menu-config.json"] |= (fromjson | .solutions |= map(if .id == "nok-dia" then .deployed = "yes" else . end) | tojson)' | \
	$(KUBECTL) apply -f -
	@$(KUBECTL) rollout restart deployment/nok-apps-portal-app -n nok-base