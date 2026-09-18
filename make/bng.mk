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
BNG_MANIFESTS_DIR := $(NOK_CLABS_DIR)/nok-bng/nok-manifests
BNG_REPO_URL = ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_BNG_REPO).git

.PHONY: try-nok-bng
try-nok-bng: install-bng-pkg gitops-bng-kustomization portal-enable-bng annotate-auth-ingress-bng annotate-auth-ingress-gitea ## Deploy the BNG solution

.PHONY: gitops-bng-kustomization
gitops-bng-kustomization: gitea-create-bng-repo gitea-create-grafana-dashboards-repo flux-create-bng-secret push-bng-manifests push-bng-grafana-dashboards flux-create-bng-source create-bng-kustomizations ## Synchronize BNG manifests with Flux
	@echo "--> GITOPS: BNG repo in sync by Flux"

.PHONY: deploy-clab-bng
deploy-clab-bng: NOK_CLAB=nok-bng
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
install-bng-pkg: check-tools git-clone-kpt configure-sdcio-kpt ## Installs the BNG kpt package from ./nok-kpt/nok-bng
	@$(call INSTALL_KPT_PACKAGE_WITH_SETTERS,$(NOK_KPT_DIR)/nok-bng,nok-bng,"--reconcile-timeout=5m", "--inventory-policy=adopt")

.PHONY: gitea-create-bng-repo
gitea-create-bng-repo: wait-for-gitea-ready ## Create the BNG GitOps repository in Gitea
	@echo "--> GITEA: Ensuring repo $(FLUX_BNG_REPO) exists"
	@GITOPS_NAMESPACE="$(GITOPS_NAMESPACE)" GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		GITEA_ADMIN_PASS="$(GITEA_ADMIN_PASS)" KUBECTL="$(KUBECTL)" \
		"$(BASE)/scripts/gitea-api.sh" "/repos/$(GITEA_ADMIN_USER)/$(FLUX_BNG_REPO)" \
		>/dev/null || \
	GITEA_API_METHOD=POST \
		GITEA_API_DATA='{"name":"$(FLUX_BNG_REPO)", "description": "BNG resources for Network Observability and Conf Management","private":false,"auto_init":true}' \
		GITOPS_NAMESPACE="$(GITOPS_NAMESPACE)" GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		GITEA_ADMIN_PASS="$(GITEA_ADMIN_PASS)" KUBECTL="$(KUBECTL)" \
		"$(BASE)/scripts/gitea-api.sh" /user/repos

.PHONY: flux-create-bng-secret
flux-create-bng-secret: ## Create the Flux Git authentication secret for BNG
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
flux-create-bng-source: ## Create the Flux GitRepository source for BNG (after manifests are pushed)
	@echo "--> FLUX: Ensuring GitRepository source $(FLUX_BNG_REPO) exists"
	@if ! $(KUBECTL) get gitrepository $(FLUX_BNG_REPO) -n flux-system > /dev/null 2>&1; then \
		echo "Creating GitRepository source $(FLUX_BNG_REPO)..."; \
		$(FLUX) create source git $(FLUX_BNG_REPO) \
		  --url=ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_BNG_REPO).git \
		  --branch=$(FLUX_GIT_BRANCH) \
		  --secret-ref=$(FLUX_BNG_SECRET) \
		  --interval=1m \
		  --namespace=flux-system \
		  --wait=false; \
	else \
		echo "GitRepository source $(FLUX_BNG_REPO) already exists."; \
	fi
	@echo "--> FLUX: Reconciling GitRepository $(FLUX_BNG_REPO) (timeout 10m)"
	@$(FLUX) reconcile source git $(FLUX_BNG_REPO) -n flux-system --timeout=10m

.PHONY: push-bng-manifests
push-bng-manifests: stage-bng-manifests ## Push the BNG manifests snapshot to the Gitea repository
	@echo "--> GIT: Forcing full snapshot push of BNG manifests to $(FLUX_BNG_REPO)"

	@cd $(BASE)/build/bng-manifests-staging && \
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
create-bng-kustomizations: ## Create Flux Kustomizations for BNG manifests
	@echo "--> FLUX: Ensuring Kustomizations for BNG manifests exist (SDCIO_ENABLED=$(SDCIO_ENABLED_NORM))"
	@for d in $(BNG_MANIFESTS_DIR)/*/; do \
		n=$$(basename "$$d"); \
		if [ "$$n" = ".git" ]; then continue; fi; \
		skip=0; \
		if [ "$(SDCIO_ENABLED_NORM)" = "NO" ]; then \
			for s in $(SDCIO_FLUX_SKIP_DIRS); do \
				if [ "$$n" = "$$s" ]; then skip=1; break; fi; \
			done; \
		fi; \
		if [ "$$skip" = "1" ]; then \
			echo "Skipping Kustomization bng-$$n (SDCIO disabled)"; \
			continue; \
		fi; \
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
		fi; \
	done

.PHONY: portal-enable-bng
portal-enable-bng: ## Enable the BNG solution in the NetOpsKube Portal
	@echo "--> PORTAL: Enabling BNG menu"
	@$(KUBECTL) get configmap nok-apps-menu-config -n nok-base -o json | \
	jq '.data["menu-config.json"] |= (fromjson | .featured |= map(. + {"openInNewTab": false}) | .solutions |= map(if .id == "nok-bng" then .deployed = "yes" | .services |= map(. + {"openInNewTab": false}) else . end) | tojson)' | \
	$(KUBECTL) apply -f -
	@$(KUBECTL) rollout restart deployment/nok-apps-portal-app -n nok-base
