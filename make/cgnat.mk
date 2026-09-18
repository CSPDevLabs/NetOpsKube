###############################################################################
# CG-NAT Makefile
#
# This file contains all CG-NAT-specific configuration, variables, and
# deployment targets. It includes:
#   - CG-NAT package installation
#   - Containerlab deployment and cleanup
#   - GitOps repository initialization and synchronization
#   - Flux source, secret, and Kustomization management
#   - Portal menu updates for CG-NAT
#   - CG-NAT-specific authentication ingress annotations
#
# Shared/common functionality is defined in the main Makefile or other
# shared make/*.mk files.
###############################################################################


FLUX_CGNAT_REPO ?= nok-cgnat-resources
FLUX_CGNAT_SECRET ?= nok-cgnat-auth
CGNAT_MANIFESTS_DIR := $(NOK_CLABS_DIR)/nok-cgnat/nok-manifests
CGNAT_REPO_URL = ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_CGNAT_REPO).git

.PHONY: try-nok-cgnat
try-nok-cgnat: install-cgnat-pkg gitops-cgnat-kustomization portal-enable-cgnat annotate-auth-ingress-cgnat annotate-auth-ingress-gitea ## Deploy the CG-NAT solution

.PHONY: gitops-cgnat-kustomization
gitops-cgnat-kustomization: gitea-create-cgnat-repo gitea-create-grafana-dashboards-repo flux-create-cgnat-secret push-cgnat-manifests push-cgnat-grafana-dashboards flux-create-cgnat-source create-cgnat-kustomizations ## Synchronize CG-NAT manifests with Flux
	@echo "--> GITOPS: CG-NAT repo in sync by Flux"

.PHONY: deploy-clab-cgnat
deploy-clab-cgnat: NOK_CLAB=nok-cgnat
deploy-clab-cgnat: check-tools git-clone-clab check-clab-prerequisites ## Deploys the Containerlab CG-NAT topology
	@echo "--> CLAB: Deploying CG-NAT topology from $(NOK_CLABS_DIR)/nok-cgnat"
	@if [ -d "$(NOK_CLABS_DIR)/nok-cgnat" ]; then \
		cd $(NOK_CLABS_DIR)/nok-cgnat && $(CLAB) deploy -t topo.yaml ;\
	else \
		echo "Error: $(NOK_CLABS_DIR)/nok-cgnat directory not found. Please ensure the nok-clabs repository is cloned and contains the nok-cgnat subdirectory." ;\
		exit 1 ;\
	fi

.PHONY: destroy-clab-cgnat
destroy-clab-cgnat: check-tools git-clone-clab ## Destroys the Containerlab CG-NAT topology and cleans up
	@echo "--> CLAB: Destroying CG-NAT topology from $(NOK_CLABS_DIR)/nok-cgnat"
	@if [ -d "$(NOK_CLABS_DIR)/nok-cgnat" ]; then \
		cd $(NOK_CLABS_DIR)/nok-cgnat && $(CLAB) destroy --cleanup -t topo.yaml ;\
	else \
		echo "Error: $(NOK_CLABS_DIR)/nok-cgnat directory not found. Please ensure the nok-clabs repository is cloned and contains the nok-cgnat subdirectory." ;\
		exit 1 ;\
	fi	
	

.PHONY: install-cgnat-pkg
install-cgnat-pkg: check-tools git-clone-kpt configure-sdcio-kpt ## Installs the CG-NAT kpt package from ./nok-kpt/nok-cgnat
	@$(call INSTALL_KPT_PACKAGE_WITH_SETTERS,$(NOK_KPT_DIR)/nok-cgnat,nok-cgnat,"--reconcile-timeout=5m", "--inventory-policy=adopt")

.PHONY: gitea-create-cgnat-repo
gitea-create-cgnat-repo: wait-for-gitea-ready ## Create the CG-NAT GitOps repository in Gitea
	@echo "--> GITEA: Ensuring repo $(FLUX_CGNAT_REPO) exists"
	@GITOPS_NAMESPACE="$(GITOPS_NAMESPACE)" GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		GITEA_ADMIN_PASS="$(GITEA_ADMIN_PASS)" KUBECTL="$(KUBECTL)" \
		"$(BASE)/scripts/gitea-api.sh" "/repos/$(GITEA_ADMIN_USER)/$(FLUX_CGNAT_REPO)" \
		>/dev/null || \
	GITEA_API_METHOD=POST \
		GITEA_API_DATA='{"name":"$(FLUX_CGNAT_REPO)", "description": "CG-NAT resources for Network Observability and Conf Management","private":false,"auto_init":true}' \
		GITOPS_NAMESPACE="$(GITOPS_NAMESPACE)" GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		GITEA_ADMIN_PASS="$(GITEA_ADMIN_PASS)" KUBECTL="$(KUBECTL)" \
		"$(BASE)/scripts/gitea-api.sh" /user/repos

.PHONY: flux-create-cgnat-secret
flux-create-cgnat-secret: ## Create the Flux Git authentication secret for CG-NAT
	@echo "--> FLUX: Ensuring Git secret $(FLUX_CGNAT_SECRET) exists"
	@if ! $(KUBECTL) get secret $(FLUX_CGNAT_SECRET) -n flux-system > /dev/null 2>&1; then \
		echo "Creating Git secret $(FLUX_CGNAT_SECRET)..."; \
		$(FLUX) create secret git $(FLUX_CGNAT_SECRET) \
		  --url=ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_CGNAT_REPO).git \
		  --ssh-key-algorithm=ed25519 \
		  --private-key-file=$(FLUX_SSH_KEY) \
		  --namespace=flux-system; \
	else \
		echo "Git secret $(FLUX_CGNAT_SECRET) already exists."; \
	fi

.PHONY: flux-create-cgnat-source
flux-create-cgnat-source: ## Create the Flux GitRepository source for CG-NAT (after manifests are pushed)
	@echo "--> FLUX: Ensuring GitRepository source $(FLUX_CGNAT_REPO) exists"
	@if ! $(KUBECTL) get gitrepository $(FLUX_CGNAT_REPO) -n flux-system > /dev/null 2>&1; then \
		echo "Creating GitRepository source $(FLUX_CGNAT_REPO)..."; \
		$(FLUX) create source git $(FLUX_CGNAT_REPO) \
		  --url=ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_CGNAT_REPO).git \
		  --branch=$(FLUX_GIT_BRANCH) \
		  --secret-ref=$(FLUX_CGNAT_SECRET) \
		  --interval=1m \
		  --namespace=flux-system \
		  --wait=false; \
	else \
		echo "GitRepository source $(FLUX_CGNAT_REPO) already exists."; \
	fi
	@echo "--> FLUX: Reconciling GitRepository $(FLUX_CGNAT_REPO) (timeout 10m)"
	@$(FLUX) reconcile source git $(FLUX_CGNAT_REPO) -n flux-system --timeout=10m

.PHONY: push-cgnat-manifests
push-cgnat-manifests: stage-cgnat-manifests ## Push the CG-NAT manifests snapshot to the Gitea repository
	@echo "--> GIT: Forcing full snapshot push of CG-NAT manifests to $(FLUX_CGNAT_REPO)"

	@cd $(BASE)/build/cgnat-manifests-staging && \
		( \
			rm -rf .git && \
			git init -b $(FLUX_GIT_BRANCH) && \
			git remote add origin $(CGNAT_REPO_URL) && \
			git add -A && \
			git commit --allow-empty -m "Authoritative snapshot of CG-NAT manifests" && \
			git config core.sshCommand 'ssh -o IdentitiesOnly=yes -i $(FLUX_SSH_KEY)' && \
			git push --force origin $(FLUX_GIT_BRANCH) \
		)

	@echo "--> GIT: Full snapshot push completed"

.PHONY: create-cgnat-kustomizations
create-cgnat-kustomizations: ## Create Flux Kustomizations for CG-NAT manifests
	@echo "--> FLUX: Ensuring Kustomizations for CG-NAT manifests exist (SDCIO_ENABLED=$(SDCIO_ENABLED_NORM))"
	@for d in $(CGNAT_MANIFESTS_DIR)/*/; do \
		n=$$(basename "$$d"); \
		if [ "$$n" = ".git" ]; then continue; fi; \
		skip=0; \
		if [ "$(SDCIO_ENABLED_NORM)" = "NO" ]; then \
			for s in $(SDCIO_FLUX_SKIP_DIRS); do \
				if [ "$$n" = "$$s" ]; then skip=1; break; fi; \
			done; \
		fi; \
		if [ "$$skip" = "1" ]; then \
			echo "Skipping Kustomization cgnat-$$n (SDCIO disabled)"; \
			continue; \
		fi; \
		echo "Checking Kustomization for $$n..."; \
		if $(FLUX) get kustomization "cgnat-$$n" -n flux-system 2>&1 | grep -q "not found"; then \
			echo "Creating Kustomization for $$n..."; \
			$(FLUX) create kustomization "cgnat-$$n" \
			  --source=GitRepository/$(FLUX_CGNAT_REPO) \
			  --path="./$$n" \
			  --prune=true \
			  --interval=1m \
			  --timeout=1m \
			  --namespace=flux-system; \
		else \
			echo "Kustomization for $$n already exists."; \
		fi; \
	done

.PHONY: portal-enable-cgnat
portal-enable-cgnat: ## Enable the CG-NAT solution in the NetOpsKube Portal
	@echo "--> PORTAL: Enabling CG-NAT menu"
	@$(KUBECTL) get configmap nok-apps-menu-config -n nok-base -o json | \
	jq '.data["menu-config.json"] |= (fromjson | .featured |= map(. + {"openInNewTab": false}) | .solutions |= map(if .id == "nok-cgnat" then .deployed = "yes" | .services |= map(. + {"openInNewTab": false}) else . end) | tojson)' | \
	$(KUBECTL) apply -f -
	@$(KUBECTL) rollout restart deployment/nok-apps-portal-app -n nok-base
