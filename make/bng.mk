###############################################################################
# BNG Makefile
#
# This file contains all BNG-specific configuration, variables, and
# deployment targets. It includes:
#   - BNG package installation
#   - Containerlab deployment and cleanup
#   - GitOps repository initialization and synchronization
#   - Flux source, secret, and Kustomization management
#   - Portal menu updates for BNG
#   - BNG-specific authentication ingress annotations
#
# Shared/common functionality is defined in the main Makefile or other
# shared make/*.mk files.
###############################################################################


FLUX_BNG_REPO ?= nok-bng-resources
FLUX_BNG_SECRET ?= nok-bng-auth
BNG_MANIFESTS_DIR := ./nok-clabs/nok-bng/nok-manifests
BNG_REPO_URL := ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_BNG_REPO).git

## Deploy BNG and GitOps
.PHONY: try-nok-bng
try-nok-bng: install-bng-pkg install-git-pkg gitops-init gitops-bng-kustomization portal-enable-bng annotate-auth-ingress-bng

.PHONY: gitops-bng-kustomization
gitops-bng-kustomization: gitea-create-bng-repo flux-create-bng-secret flux-create-bng-source push-bng-manifests create-bng-kustomizations
	@echo "--> GITOPS: BNG repo in sync by Flux"

.PHONY: deploy-clab-bng
deploy-clab-bng: check-tools git-clone-clab check-clab-prerequisites ## Deploys the Containerlab BNG topology
	@echo "--> CLAB: Deploying BNG topology from $(NOK_CLABS_DIR)/nok-bng"
	@if [ -d "$(NOK_CLABS_DIR)/nok-bng" ]; then \
		cd $(NOK_CLABS_DIR)/nok-bng && $(CLAB) deploy -t topo.yaml ;\
	else \
		echo "Error: $(NOK_CLABS_DIR)/nok-bng directory not found. Please ensure the nok-clabs repository is cloned and contains the nok-bng subdirectory." ;\
		exit 1 ;\
	fi

.PHONY: destroy-clab-bng
destroy-clab-bng: check-tools git-clone-clab ## Destroys the Containerlab BNG topology and cleans up
	@echo "--> CLAB: Destroying BNG topology from $(NOK_CLABS_DIR)/nok-bng"
	@if [ -d "$(NOK_CLABS_DIR)/nok-bng" ]; then \
		cd $(NOK_CLABS_DIR)/nok-bng && $(CLAB) destroy --cleanup -t topo.yaml ;\
	else \
		echo "Error: $(NOK_CLABS_DIR)/nok-bng directory not found. Please ensure the nok-clabs repository is cloned and contains the nok-bng subdirectory." ;\
		exit 1 ;\
	fi	
	

.PHONY: install-bng-pkg
install-bng-pkg: check-tools git-clone-kpt ## Installs the base kpt package from ./nok-kpt/nok-bng
	@$(call INSTALL_KPT_PACKAGE,$(NOK_KPT_DIR)/nok-bng,nok-bng,"--reconcile-timeout=5m", "--inventory-policy=adopt")

.PHONY: gitea-create-bng-repo
gitea-create-bng-repo:
	@echo "--> GITEA: Ensuring repo $(FLUX_BNG_REPO) exists"
	@$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  http://$(GITEA_HOST)/api/v1/repos/$(GITEA_ADMIN_USER)/$(FLUX_BNG_REPO) \
	  >/dev/null || \
	$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -X POST \
	  -H "Content-Type: application/json" \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  -d '{"name":"$(FLUX_BNG_REPO)", "description": "BNG resources for Network Observability and Conf Management","private":false,"auto_init":true}' \
	  http://$(GITEA_HOST)/api/v1/user/repos

.PHONY: flux-create-bng-secret
flux-create-bng-secret:
	@echo "--> FLUX: Ensuring Git secret $(FLUX_BNG_SECRET) exists"
	@if ! $(KUBECTL) get secret $(FLUX_BNG_SECRET) -n flux-system > /dev/null 2>&1; then \
		echo "Creating Git secret $(FLUX_BNG_SECRET)..."; \
		$(FLUX) create secret git $(FLUX_BNG_SECRET) \
		  --url=ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_BNG_REPO).git \
		  --ssh-key-algorithm=ed25519 \
		  --private-key-file=$(FLUX_SSH_KEY) \
		  --namespace=flux-system; \
	else \
		echo "Git secret $(FLUX_BNG_SECRET) already exists."; \
	fi

.PHONY: flux-create-bng-source
flux-create-bng-source:
	@echo "--> FLUX: Ensuring GitRepository source $(FLUX_BNG_REPO) exists"
	@if ! $(KUBECTL) get gitrepository $(FLUX_BNG_REPO) -n flux-system > /dev/null 2>&1; then \
		echo "Creating GitRepository source $(FLUX_BNG_REPO)..."; \
		$(FLUX) create source git $(FLUX_BNG_REPO) \
		  --url=ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_BNG_REPO).git \
		  --branch=$(FLUX_GIT_BRANCH) \
		  --secret-ref=$(FLUX_BNG_SECRET) \
		  --interval=1m \
		  --namespace=flux-system; \
	else \
		echo "GitRepository source $(FLUX_BNG_REPO) already exists."; \
	fi

.PHONY: push-bng-manifests
push-bng-manifests:
	@echo "--> GIT: Forcing full snapshot push of BNG manifests to $(FLUX_BNG_REPO)"

	@cd $(BNG_MANIFESTS_DIR) && \
		( \
			rm -rf .git && \
			git init -b $(FLUX_GIT_BRANCH) && \
			git remote add origin $(BNG_REPO_URL) && \
			git add -A && \
			git commit --allow-empty -m "Authoritative snapshot of BNG manifests" && \
			git config core.sshCommand 'ssh -o IdentitiesOnly=yes -i $(FLUX_SSH_KEY)' && \
			git push --force origin $(FLUX_GIT_BRANCH) \
		)

	@echo "--> GIT: Full snapshot push completed"

.PHONY: create-bng-kustomizations
create-bng-kustomizations:
	@echo "--> FLUX: Ensuring Kustomizations for BNG manifests exist"
	@for d in $(BNG_MANIFESTS_DIR)/*/; do \
		n=$$(basename "$$d"); \
		if [ "$$n" != ".git" ]; then \
			echo "Checking Kustomization for $$n..."; \
			if $(FLUX) get kustomization "bng-$$n" -n flux-system 2>&1 | grep -q "not found"; then \
				echo "Creating Kustomization for $$n..."; \
				$(FLUX) create kustomization "bng-$$n" \
				  --source=GitRepository/$(FLUX_BNG_REPO) \
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

.PHONY: portal-enable-bng
portal-enable-bng:
	@echo "--> PORTAL: Enabling BNG menu"
	@$(KUBECTL) get configmap nok-apps-menu-config -n nok-base -o json | \
	jq '.data["menu-config.json"] |= (fromjson | .solutions |= map(if .id == "nok-bng" then .deployed = "yes" else . end) | tojson)' | \
	$(KUBECTL) apply -f -
	@$(KUBECTL) rollout restart deployment/nok-apps-portal-app -n nok-base