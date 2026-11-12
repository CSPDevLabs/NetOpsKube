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

# ------------------------------------------------------------------------------
# IPFIX BNG Integration Paths
# ------------------------------------------------------------------------------

BNG_IPFIX_DIR ?= $(BASE)/nok-kpt/nok-ipfix/nok-bng
BNG_IPFIX_GRAFANA_DATASOURCE_MANIFEST ?= $(BNG_IPFIX_DIR)/grafana/datasource/ipfix-postgres-ds.yaml
BNG_IPFIX_GRAFANA_DASHBOARD_JSON ?= $(BNG_IPFIX_DIR)/grafana/manifests/ipfix-flow-analytics.json
BNG_IPFIX_GRAFANA_DASHBOARD_MANIFEST ?= $(BNG_IPFIX_DIR)/grafana/manifests/ipfix-flow-analytics.yaml

# ------------------------------------------------------------------------------
# Grafana Configuration
# ------------------------------------------------------------------------------

BNG_IPFIX_GRAFANA_NAMESPACE ?= nok-bng

# Reuse the existing shared Grafana dashboard repository.
BNG_IPFIX_GRAFANA_REPO ?= grafana-dashboards
BNG_IPFIX_GRAFANA_REPO_PREFIX ?= bng
BNG_IPFIX_GRAFANA_STAGING ?= $(BASE)/build/ipfix-grafana-staging
BNG_IPFIX_GRAFANA_PUSH_SCRIPT ?= $(BASE)/scripts/push-ipfix-grafana-dashboard.sh

# ------------------------------------------------------------------------------
# SDCIO Configuration
# ------------------------------------------------------------------------------

BNG_IPFIX_SDCIO_CONFIG_FILES ?= \
	sdcio-config-bng1-ipfix.yaml \
	sdcio-config-bng2-ipfix.yaml
BNG_IPFIX_SDCIO_PUSH_SCRIPT ?= $(BASE)/scripts/push-ipfix-sdcio-config.sh
BNG_IPFIX_SDCIO_REPO ?= nok-bng-resources
BNG_IPFIX_SDCIO_REPO_OWNER ?= nok

# ------------------------------------------------------------------------------
# Grafana Datasource Repository
# ------------------------------------------------------------------------------

BNG_IPFIX_DATASOURCE_REPO ?= nok-bng-resources
BNG_IPFIX_DATASOURCE_REPO_OWNER ?= nok
BNG_IPFIX_DATASOURCE_REPO_PATH ?= grafana/datasources/ipfix-postgres-ds.yaml

.PHONY: try-nok-bng
try-nok-bng: install-bng-pkg gitops-bng-kustomization portal-enable-bng annotate-auth-ingress-bng ## Deploy the BNG solution

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
		  --namespace=flux-system; \
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
	jq '.data["menu-config.json"] |= (fromjson | .featured |= map(if .name == "BBM" then .openInNewTab = false else . end) | .solutions |= map(if .id == "nok-bng" then .deployed = "yes" | .services |= map(if .name == "Grafana" then .openInNewTab = false else . end) else . end) | tojson)' | \
	$(KUBECTL) apply -f -
	@$(KUBECTL) rollout restart deployment/nok-apps-portal-app -n nok-base




# ------------------------------------------------------------------------------
# IPFIX Integration
# ------------------------------------------------------------------------------
# IPFIX Grafana Dashboard Push
# ------------------------------------------------------------------------------

.PHONY: push-ipfix-grafana-dashboard
push-ipfix-grafana-dashboard: ## Push IPFIX dashboard to the shared BNG dashboard directory
	@if ! echo "$(IPFIX_ENABLED)" | grep -Eiq '^(yes|true|1)$$'; then \
		echo "--> IPFIX: Disabled; skipping Grafana dashboard push"; \
		exit 0; \
	fi
	@if [ ! -f "$(BNG_IPFIX_GRAFANA_DASHBOARD_JSON)" ]; then \
		echo "[ERROR] IPFIX dashboard not found: $(BNG_IPFIX_GRAFANA_DASHBOARD_JSON)" >&2; \
		exit 1; \
	fi
	@GRAFANA_DASHBOARDS_STAGING="$(BNG_IPFIX_GRAFANA_STAGING)" \
		FLUX_GRAFANA_REPO="$(BNG_IPFIX_GRAFANA_REPO)" \
		FLUX_GIT_BRANCH="$(FLUX_GIT_BRANCH)" \
		GITEA_SSH_HOST="$(GITEA_SSH_HOST)" \
		GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		FLUX_SSH_KEY="$(FLUX_SSH_KEY)" \
		BNG_IPFIX_GRAFANA_DASHBOARD="$(notdir $(BNG_IPFIX_GRAFANA_DASHBOARD_JSON))" \
		BNG_IPFIX_GRAFANA_SOURCE_DIR="$(dir $(BNG_IPFIX_GRAFANA_DASHBOARD_JSON))" \
		BNG_IPFIX_GRAFANA_REPO_PREFIX="$(BNG_IPFIX_GRAFANA_REPO_PREFIX)" \
		bash "$(BNG_IPFIX_GRAFANA_PUSH_SCRIPT)"

# ------------------------------------------------------------------------------
# IPFIX Grafana Dashboard
# ------------------------------------------------------------------------------

.PHONY: apply-ipfix-grafana-dashboard
apply-ipfix-grafana-dashboard: ## Apply the IPFIX GrafanaDashboard resource
	@if ! echo "$(IPFIX_ENABLED)" | grep -Eiq '^(yes|true|1)$$'; then \
		echo "--> IPFIX: Disabled; skipping GrafanaDashboard apply"; \
		exit 0; \
	fi

	@if [ ! -f "$(BNG_IPFIX_GRAFANA_DASHBOARD_MANIFEST)" ]; then \
		echo "[ERROR] IPFIX GrafanaDashboard manifest not found: $(BNG_IPFIX_GRAFANA_DASHBOARD_MANIFEST)" >&2; \
		exit 1; \
	fi

	@if [ ! -f "$(BNG_IPFIX_GRAFANA_DASHBOARD_JSON)" ]; then \
		echo "[ERROR] IPFIX dashboard JSON not found: $(BNG_IPFIX_GRAFANA_DASHBOARD_JSON)" >&2; \
		exit 1; \
	fi

	@echo "--> IPFIX: Applying Grafana dashboard ConfigMap"

	@$(KUBECTL) create configmap ipfix-dashboard-json \
		--from-file=$(BNG_IPFIX_GRAFANA_DASHBOARD_JSON) \
		-n $(BNG_IPFIX_GRAFANA_NAMESPACE) \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -

	@echo "--> IPFIX: Applying GrafanaDashboard manifest"
	@$(KUBECTL) apply -f "$(BNG_IPFIX_GRAFANA_DASHBOARD_MANIFEST)"

	@echo "--> IPFIX: Grafana dashboard resources applied successfully"


# ------------------------------------------------------------------------------
# SDCIO IPFIX Config Push
# ------------------------------------------------------------------------------

.PHONY: push-ipfix-sdcio-config
push-ipfix-sdcio-config: ## Push SDCIO IPFIX config manifest(s) to Gitea
	@if ! echo "$(IPFIX_ENABLED)" | grep -Eiq '^(yes|true|1)$$'; then \
		echo "--> IPFIX: Disabled; skipping SDCIO config push"; \
		exit 0; \
	fi
	@if [ -z "$(strip $(BNG_IPFIX_SDCIO_CONFIG_FILES))" ]; then \
		echo "[ERROR] No SDCIO config files specified." >&2; \
		exit 1; \
	fi
	@if [ ! -f "$(BNG_IPFIX_SDCIO_PUSH_SCRIPT)" ]; then \
		echo "[ERROR] Push script not found: $(BNG_IPFIX_SDCIO_PUSH_SCRIPT)" >&2; \
		exit 1; \
	fi
	@for file in $(BNG_IPFIX_SDCIO_CONFIG_FILES); do \
		if [ ! -f "$(BNG_IPFIX_DIR)/sdcio/$$file" ]; then \
			echo "[ERROR] SDCIO config not found: $(BNG_IPFIX_DIR)/sdcio/$$file" >&2; \
			exit 1; \
		fi; \
	done
	@GITEA_SSH_HOST="$(GITEA_SSH_HOST)" \
		FLUX_SSH_KEY="$(FLUX_SSH_KEY)" \
		FLUX_GIT_BRANCH="$(FLUX_GIT_BRANCH)" \
		GITEA_REPO_OWNER="$(BNG_IPFIX_SDCIO_REPO_OWNER)" \
		GITEA_REPO_NAME="$(BNG_IPFIX_SDCIO_REPO)" \
		BNG_IPFIX_SDCIO_SOURCE_DIR="$(BNG_IPFIX_DIR)/sdcio" \
		BNG_IPFIX_SDCIO_CONFIG_FILES="$(BNG_IPFIX_SDCIO_CONFIG_FILES)" \
		bash "$(BNG_IPFIX_SDCIO_PUSH_SCRIPT)"


# ------------------------------------------------------------------------------
# IPFIX Grafana Datasource Push
# ------------------------------------------------------------------------------

.PHONY: push-ipfix-grafana-datasource
push-ipfix-grafana-datasource: ## Push IPFIX Grafana datasource to Gitea
	@if ! echo "$(IPFIX_ENABLED)" | grep -Eiq '^(yes|true|1)$$'; then \
		echo "--> IPFIX: Disabled; skipping Grafana datasource push"; \
		exit 0; \
	fi
	@if [ ! -f "$(BNG_IPFIX_GRAFANA_DATASOURCE_MANIFEST)" ]; then \
		echo "[ERROR] Datasource manifest not found: $(BNG_IPFIX_GRAFANA_DATASOURCE_MANIFEST)" >&2; \
		exit 1; \
	fi
	@if [ ! -f "$(FLUX_SSH_KEY)" ]; then \
		echo "[ERROR] SSH key not found: $(FLUX_SSH_KEY)" >&2; \
		exit 1; \
	fi
	@set -eu; \
	STAGING_DIR=$$(mktemp -d "$${TMPDIR:-/tmp}/ipfix-datasource.XXXXXX"); \
	trap 'rm -rf "$$STAGING_DIR"' EXIT; \
	printf -v SSH_KEY_QUOTED '%q' "$(FLUX_SSH_KEY)"; \
	export GIT_SSH_COMMAND="ssh -i $$SSH_KEY_QUOTED -o IdentitiesOnly=yes"; \
	REPO_URL="ssh://git@$(GITEA_SSH_HOST)/$(BNG_IPFIX_DATASOURCE_REPO_OWNER)/$(BNG_IPFIX_DATASOURCE_REPO).git"; \
	echo "--> Grafana: Cloning $(BNG_IPFIX_DATASOURCE_REPO_OWNER)/$(BNG_IPFIX_DATASOURCE_REPO)"; \
	git clone --branch "$(FLUX_GIT_BRANCH)" --single-branch "$$REPO_URL" "$$STAGING_DIR/repo"; \
	cd "$$STAGING_DIR/repo"; \
	DEST="$(BNG_IPFIX_DATASOURCE_REPO_PATH)"; \
	mkdir -p "$$(dirname "$$DEST")"; \
	install -m 0644 "$(BNG_IPFIX_GRAFANA_DATASOURCE_MANIFEST)" "$$DEST"; \
	git add -- "$$DEST"; \
	if git diff --cached --quiet; then \
		echo "--> Grafana: No datasource changes to push"; \
		exit 0; \
	fi; \
	git diff --cached --check; \
	git diff --cached --stat; \
	if ! git var GIT_AUTHOR_IDENT >/dev/null 2>&1; then \
		echo "[ERROR] Configure git user.name and user.email before pushing" >&2; \
		exit 1; \
	fi; \
	git commit -m "Add IPFIX PostgreSQL Grafana datasource"; \
	git push origin "HEAD:$(FLUX_GIT_BRANCH)"; \
	echo "--> Grafana: Datasource pushed to $(BNG_IPFIX_DATASOURCE_REPO_OWNER)/$(BNG_IPFIX_DATASOURCE_REPO)/$$DEST"


# ------------------------------------------------------------------------------
# Deploy IPFIX Pipeline
# ------------------------------------------------------------------------------

.PHONY: configure-ipfix-bng
configure-ipfix-bng: ## Configure and publish all BNG-specific IPFIX integrations
	@set -e; \
	if ! echo "$(IPFIX_ENABLED)" | grep -Eiq '^(yes|true|1)$$'; then \
		echo ""; \
		echo "============================================================"; \
		echo " IPFIX is disabled. Skipping complete BNG pipeline."; \
		echo " Set IPFIX_ENABLED=YES to enable it."; \
		echo "============================================================"; \
		exit 0; \
	fi; \
	echo ""; \
	echo "============================================================"; \
	echo " Deploying complete BNG IPFIX pipeline"; \
	echo "============================================================"; \
	echo ""; \
	echo " [1/5] Publishing SDCIO configuration"; \
	$(MAKE) --no-print-directory push-ipfix-sdcio-config; \
	echo ""; \
	echo " [2/5] Publishing Grafana PostgreSQL datasource"; \
	$(MAKE) --no-print-directory push-ipfix-grafana-datasource; \
	echo ""; \
	echo " [3/5] Publishing IPFIX Grafana dashboard"; \
	$(MAKE) --no-print-directory push-ipfix-grafana-dashboard; \
	echo ""; \
	echo " [4/5] Applying GrafanaDashboard resource"; \
	$(MAKE) --no-print-directory apply-ipfix-grafana-dashboard; \
	echo ""; \
	echo " [5/5] Checking IPFIX deployment status"; \
	$(MAKE) --no-print-directory status-ipfix; \
	echo ""; \
	echo "============================================================"; \
	echo " BNG IPFIX pipeline workflow completed successfully"; \
	echo "============================================================"