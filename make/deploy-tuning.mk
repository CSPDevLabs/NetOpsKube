# Deploy-time options: SDCIO, Prometheus/gNMIc tuning, Grafana dashboard delivery.
# Included from the root Makefile (next to make/troubleshoot.mk).

# Normalise SDCIO_ENABLED once (YES/yes/Yes → enabled; anything else → disabled).
SDCIO_ENABLED_BOOL := $(if $(filter YES yes Yes,$(SDCIO_ENABLED)),1,0)
SDCIO_ENABLED_NORM := $(if $(filter 1,$(SDCIO_ENABLED_BOOL)),YES,NO)

# Flux manifest subdirs skipped when SDCIO is disabled
SDCIO_FLUX_SKIP_DIRS := sdcio schemas

# --- Prometheus / gNMIc tuning (see docs/PROMETHEUS-GNMIC-TUNING.md) ---
PROM_RETENTION ?= 24h
PROM_RETENTION_SIZE ?=
PROM_STORAGE_SIZE ?=
GNMIC_REPLICAS ?= 1
GNMIC_CPU_REQUEST ?=
GNMIC_MEMORY_REQUEST ?=
GNMIC_CPU_LIMIT ?=
GNMIC_MEMORY_LIMIT ?=

# --- Grafana dashboard delivery ---
# gitea: in-cluster Gitea (proxy-restricted environments)
# upstream: raw.githubusercontent.com (offline from cluster without proxy)
GRAFANA_DASHBOARD_SOURCE ?= gitea
# Default GRAFANA_DASHBOARD_GITEA_BASE is set in the root Makefile (after Gitea variables).
GRAFANA_DASHBOARD_UPSTREAM_BASE ?= https://raw.githubusercontent.com/CSPDevLabs/nok-clabs/refs/heads/main

FLUX_GRAFANA_REPO ?= grafana-dashboards
BNG_GRAFANA_REPO_PREFIX ?= bng
DIA_GRAFANA_REPO_PREFIX ?= dia
CGNAT_GRAFANA_REPO_PREFIX ?= cgnat
GRAFANA_DASHBOARDS_STAGING ?= $(BASE)/build/grafana-dashboards-staging

STAGE_RECIPE_SCRIPT := $(BASE)/scripts/stage-recipe-manifests.sh
PUSH_GRAFANA_SCRIPT := $(BASE)/scripts/push-grafana-dashboards.sh

define REQUIRE_KPT_CHECKOUT
@if [ ! -f "$(NOK_KPT_DIR)/nok-base/Kptfile" ]; then \
	echo "Error: $(NOK_KPT_DIR) is not a kpt checkout — run 'make git-clone-kpt' first" ; \
	exit 1 ; \
fi
endef

.PHONY: configure-sdcio-kpt
configure-sdcio-kpt: ## Toggle SDCIO resources in kpt packages via .krmignore
	$(REQUIRE_KPT_CHECKOUT)
ifeq ($(SDCIO_ENABLED_BOOL),1)
	@echo "--> SDCIO: enabled (platform + recipe exporters)"
	@rm -f $(NOK_KPT_DIR)/nok-base/sdcio/.krmignore \
		$(NOK_KPT_DIR)/nok-bng/ndt-sdcio-visual/.krmignore \
		$(NOK_KPT_DIR)/nok-dia/ndt-sdcio-visual/.krmignore \
		$(NOK_KPT_DIR)/nok-cgnat/ndt-sdcio-visual/.krmignore
else
	@echo "--> SDCIO: disabled — excluding SDCIO from kpt apply"
	@for dir in nok-base/sdcio nok-bng/ndt-sdcio-visual nok-dia/ndt-sdcio-visual nok-cgnat/ndt-sdcio-visual; do \
		if [ -d "$(NOK_KPT_DIR)/$$dir" ]; then \
			echo "*" > "$(NOK_KPT_DIR)/$$dir/.krmignore" ; \
		fi ; \
	done
endif

.PHONY: update-kpt-tuning-setters
update-kpt-tuning-setters: $(YQ) ## Patch BBM Prometheus CR retention (recipe tuning uses manifest staging)
	$(REQUIRE_KPT_CHECKOUT)
	@PROM_CR="$(NOK_KPT_DIR)/nok-bbm/prometheus/prometheus-cr.yaml" ; \
	if [ ! -f "$$PROM_CR" ]; then \
		echo "Error: $$PROM_CR not found" ; exit 1 ; \
	fi ; \
	echo "--> KPT: Prometheus retention → nok-bbm/prometheus/prometheus-cr.yaml" ; \
	$(YQ) eval '.spec.retention = "$(PROM_RETENTION)"' -i "$$PROM_CR" ; \
	if [ -n "$(PROM_RETENTION_SIZE)" ]; then \
		$(YQ) eval '.spec.retentionSize = "$(PROM_RETENTION_SIZE)"' -i "$$PROM_CR" ; \
	else \
		$(YQ) eval 'del(.spec.retentionSize)' -i "$$PROM_CR" ; \
	fi

define SDCIO_SKIP_DIR
$(if $(filter 1,$(SDCIO_ENABLED_BOOL)),,$(filter $(1),$(SDCIO_FLUX_SKIP_DIRS)))
endef

.PHONY: stage-bng-manifests stage-dia-manifests stage-cgnat-manifests
stage-bng-manifests: $(YQ) ## Stage BNG manifests (copy, tune, patch Grafana URLs)
	@STAGING_DIR="$(BASE)/build/bng-manifests-staging" \
		SRC_DIR="$(BNG_MANIFESTS_DIR)" \
		RECIPE_LABEL="nok-bng" \
		GRAFANA_PREFIX="$(BNG_GRAFANA_REPO_PREFIX)" \
		YQ="$(YQ)" \
		PROM_RETENTION="$(PROM_RETENTION)" \
		PROM_RETENTION_SIZE="$(PROM_RETENTION_SIZE)" \
		PROM_STORAGE_SIZE="$(PROM_STORAGE_SIZE)" \
		GNMIC_REPLICAS="$(GNMIC_REPLICAS)" \
		GNMIC_CPU_REQUEST="$(GNMIC_CPU_REQUEST)" \
		GNMIC_MEMORY_REQUEST="$(GNMIC_MEMORY_REQUEST)" \
		GNMIC_CPU_LIMIT="$(GNMIC_CPU_LIMIT)" \
		GNMIC_MEMORY_LIMIT="$(GNMIC_MEMORY_LIMIT)" \
		GRAFANA_DASHBOARD_SOURCE="$(GRAFANA_DASHBOARD_SOURCE)" \
		GRAFANA_DASHBOARD_GITEA_BASE="$(GRAFANA_DASHBOARD_GITEA_BASE)" \
		GRAFANA_DASHBOARD_UPSTREAM_BASE="$(GRAFANA_DASHBOARD_UPSTREAM_BASE)" \
		bash "$(STAGE_RECIPE_SCRIPT)"

stage-dia-manifests: $(YQ) ## Stage DIA manifests (copy, tune, patch Grafana URLs)
	@STAGING_DIR="$(BASE)/build/dia-manifests-staging" \
		SRC_DIR="$(DIA_MANIFESTS_DIR)" \
		RECIPE_LABEL="nok-dia" \
		GRAFANA_PREFIX="$(DIA_GRAFANA_REPO_PREFIX)" \
		YQ="$(YQ)" \
		PROM_RETENTION="$(PROM_RETENTION)" \
		PROM_RETENTION_SIZE="$(PROM_RETENTION_SIZE)" \
		PROM_STORAGE_SIZE="$(PROM_STORAGE_SIZE)" \
		GNMIC_REPLICAS="$(GNMIC_REPLICAS)" \
		GNMIC_CPU_REQUEST="$(GNMIC_CPU_REQUEST)" \
		GNMIC_MEMORY_REQUEST="$(GNMIC_MEMORY_REQUEST)" \
		GNMIC_CPU_LIMIT="$(GNMIC_CPU_LIMIT)" \
		GNMIC_MEMORY_LIMIT="$(GNMIC_MEMORY_LIMIT)" \
		GRAFANA_DASHBOARD_SOURCE="$(GRAFANA_DASHBOARD_SOURCE)" \
		GRAFANA_DASHBOARD_GITEA_BASE="$(GRAFANA_DASHBOARD_GITEA_BASE)" \
		GRAFANA_DASHBOARD_UPSTREAM_BASE="$(GRAFANA_DASHBOARD_UPSTREAM_BASE)" \
		bash "$(STAGE_RECIPE_SCRIPT)"

stage-cgnat-manifests: $(YQ) ## Stage CG-NAT manifests (copy, tune, patch Grafana URLs)
	@STAGING_DIR="$(BASE)/build/cgnat-manifests-staging" \
		SRC_DIR="$(CGNAT_MANIFESTS_DIR)" \
		RECIPE_LABEL="nok-cgnat" \
		GRAFANA_PREFIX="$(CGNAT_GRAFANA_REPO_PREFIX)" \
		YQ="$(YQ)" \
		PROM_RETENTION="$(PROM_RETENTION)" \
		PROM_RETENTION_SIZE="$(PROM_RETENTION_SIZE)" \
		PROM_STORAGE_SIZE="$(PROM_STORAGE_SIZE)" \
		GNMIC_REPLICAS="$(GNMIC_REPLICAS)" \
		GNMIC_CPU_REQUEST="$(GNMIC_CPU_REQUEST)" \
		GNMIC_MEMORY_REQUEST="$(GNMIC_MEMORY_REQUEST)" \
		GNMIC_CPU_LIMIT="$(GNMIC_CPU_LIMIT)" \
		GNMIC_MEMORY_LIMIT="$(GNMIC_MEMORY_LIMIT)" \
		GRAFANA_DASHBOARD_SOURCE="$(GRAFANA_DASHBOARD_SOURCE)" \
		GRAFANA_DASHBOARD_GITEA_BASE="$(GRAFANA_DASHBOARD_GITEA_BASE)" \
		GRAFANA_DASHBOARD_UPSTREAM_BASE="$(GRAFANA_DASHBOARD_UPSTREAM_BASE)" \
		bash "$(STAGE_RECIPE_SCRIPT)"

.PHONY: push-bng-grafana-dashboards push-dia-grafana-dashboards push-cgnat-grafana-dashboards push-grafana-dashboards
push-bng-grafana-dashboards: ## Push BNG Grafana JSON to in-cluster Gitea repo
	@GRAFANA_DASHBOARDS_STAGING="$(GRAFANA_DASHBOARDS_STAGING)" \
		FLUX_GRAFANA_REPO="$(FLUX_GRAFANA_REPO)" \
		FLUX_GIT_BRANCH="$(FLUX_GIT_BRANCH)" \
		GITEA_SSH_HOST="$(GITEA_SSH_HOST)" \
		GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		FLUX_SSH_KEY="$(FLUX_SSH_KEY)" \
		NOK_CLABS_DIR="$(NOK_CLABS_DIR)" \
		BNG_GRAFANA_REPO_PREFIX="$(BNG_GRAFANA_REPO_PREFIX)" \
		DIA_GRAFANA_REPO_PREFIX="$(DIA_GRAFANA_REPO_PREFIX)" \
		CGNAT_GRAFANA_REPO_PREFIX="$(CGNAT_GRAFANA_REPO_PREFIX)" \
		bash "$(PUSH_GRAFANA_SCRIPT)" bng

push-dia-grafana-dashboards: ## Push DIA Grafana JSON to in-cluster Gitea repo
	@GRAFANA_DASHBOARDS_STAGING="$(GRAFANA_DASHBOARDS_STAGING)" \
		FLUX_GRAFANA_REPO="$(FLUX_GRAFANA_REPO)" \
		FLUX_GIT_BRANCH="$(FLUX_GIT_BRANCH)" \
		GITEA_SSH_HOST="$(GITEA_SSH_HOST)" \
		GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		FLUX_SSH_KEY="$(FLUX_SSH_KEY)" \
		NOK_CLABS_DIR="$(NOK_CLABS_DIR)" \
		BNG_GRAFANA_REPO_PREFIX="$(BNG_GRAFANA_REPO_PREFIX)" \
		DIA_GRAFANA_REPO_PREFIX="$(DIA_GRAFANA_REPO_PREFIX)" \
		CGNAT_GRAFANA_REPO_PREFIX="$(CGNAT_GRAFANA_REPO_PREFIX)" \
		bash "$(PUSH_GRAFANA_SCRIPT)" dia

push-cgnat-grafana-dashboards: ## Push CG-NAT Grafana JSON to in-cluster Gitea repo
	@GRAFANA_DASHBOARDS_STAGING="$(GRAFANA_DASHBOARDS_STAGING)" \
		FLUX_GRAFANA_REPO="$(FLUX_GRAFANA_REPO)" \
		FLUX_GIT_BRANCH="$(FLUX_GIT_BRANCH)" \
		GITEA_SSH_HOST="$(GITEA_SSH_HOST)" \
		GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		FLUX_SSH_KEY="$(FLUX_SSH_KEY)" \
		NOK_CLABS_DIR="$(NOK_CLABS_DIR)" \
		BNG_GRAFANA_REPO_PREFIX="$(BNG_GRAFANA_REPO_PREFIX)" \
		DIA_GRAFANA_REPO_PREFIX="$(DIA_GRAFANA_REPO_PREFIX)" \
		CGNAT_GRAFANA_REPO_PREFIX="$(CGNAT_GRAFANA_REPO_PREFIX)" \
		bash "$(PUSH_GRAFANA_SCRIPT)" cgnat

push-grafana-dashboards: push-bng-grafana-dashboards push-dia-grafana-dashboards push-cgnat-grafana-dashboards ## Push recipe Grafana JSON

.PHONY: gitea-create-grafana-dashboards-repo
gitea-create-grafana-dashboards-repo: wait-for-gitea-ready ## Ensure grafana-dashboards Gitea repo exists (BNG + DIA + CG-NAT)
	@echo "--> GITEA: Ensuring repo $(FLUX_GRAFANA_REPO) exists"
	@GITOPS_NAMESPACE="$(GITOPS_NAMESPACE)" GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		GITEA_ADMIN_PASS="$(GITEA_ADMIN_PASS)" KUBECTL="$(KUBECTL)" \
		"$(BASE)/scripts/gitea-api.sh" "/repos/$(GITEA_ADMIN_USER)/$(FLUX_GRAFANA_REPO)" \
		>/dev/null || \
	GITEA_API_METHOD=POST \
		GITEA_API_DATA='{"name":"$(FLUX_GRAFANA_REPO)", "description": "NetOpsKube Grafana dashboards (BNG + DIA + CG-NAT)","private":false,"auto_init":true}' \
		GITOPS_NAMESPACE="$(GITOPS_NAMESPACE)" GITEA_ADMIN_USER="$(GITEA_ADMIN_USER)" \
		GITEA_ADMIN_PASS="$(GITEA_ADMIN_PASS)" KUBECTL="$(KUBECTL)" \
		"$(BASE)/scripts/gitea-api.sh" /user/repos
