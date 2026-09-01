# Deploy-time options: SDCIO, Prometheus/gNMIc tuning, Grafana dashboard delivery.
# Included from the root Makefile.

# --- SDCIO optional deployment ---
# Flux manifest subdirs skipped when SDCIO_ENABLED=NO
SDCIO_FLUX_SKIP_DIRS := sdcio schemas

# --- Prometheus / gNMIc tuning (see docs/PROMETHEUS-GNMIC-TUNING.md) ---
PROM_RETENTION ?= 24h
PROM_RETENTION_SIZE ?=
PROM_STORAGE_SIZE ?=
PROM_STORAGE_SIZE_BBM ?= 10Gi
GNMIC_REPLICAS ?= 1
GNMIC_CPU_REQUEST ?=
GNMIC_MEMORY_REQUEST ?=
GNMIC_CPU_LIMIT ?=
GNMIC_MEMORY_LIMIT ?=

# --- Grafana dashboard delivery ---
# gitea: in-cluster Gitea (proxy-restricted environments)
# upstream: raw.githubusercontent.com (offline from cluster without proxy)
GRAFANA_DASHBOARD_SOURCE ?= gitea
GRAFANA_DASHBOARD_GITEA_BASE ?= http://gitea-http.nok-git.svc.cluster.local:3000/nok/$(FLUX_GRAFANA_REPO)/raw/branch/main
GRAFANA_DASHBOARD_UPSTREAM_BASE ?= https://raw.githubusercontent.com/CSPDevLabs/nok-clabs/refs/heads/main

FLUX_GRAFANA_REPO ?= grafana-dashboards
BNG_GRAFANA_DIR := ./nok-clabs/nok-bng/grafana-dashboards
BNG_GRAFANA_REPO_PREFIX ?= bng
DIA_GRAFANA_REPO_PREFIX ?=
GRAFANA_DASHBOARDS_STAGING ?= $(BASE)/build/grafana-dashboards-staging

.PHONY: configure-sdcio-kpt
configure-sdcio-kpt: ## Toggle SDCIO resources in kpt packages via .krmignore
ifneq ($(filter YES yes Yes,$(SDCIO_ENABLED)),)
	@echo "--> SDCIO: enabled (platform + recipe exporters)"
	@rm -f $(NOK_KPT_DIR)/nok-base/sdcio/.krmignore \
		$(NOK_KPT_DIR)/nok-bng/ndt-sdcio-visual/.krmignore \
		$(NOK_KPT_DIR)/nok-dia/ndt-sdcio-visual/.krmignore
else
	@echo "--> SDCIO: disabled — excluding SDCIO from kpt apply"
	@mkdir -p $(NOK_KPT_DIR)/nok-base/sdcio \
		$(NOK_KPT_DIR)/nok-bng/ndt-sdcio-visual \
		$(NOK_KPT_DIR)/nok-dia/ndt-sdcio-visual
	@echo "*" > $(NOK_KPT_DIR)/nok-base/sdcio/.krmignore
	@echo "*" > $(NOK_KPT_DIR)/nok-bng/ndt-sdcio-visual/.krmignore
	@echo "*" > $(NOK_KPT_DIR)/nok-dia/ndt-sdcio-visual/.krmignore
endif

.PHONY: update-kpt-tuning-setters
update-kpt-tuning-setters: $(YQ) ## Write Prometheus tuning into nok-bbm apply-setters.yaml
	@if [ ! -f "$(NOK_KPT_DIR)/nok-bbm/apply-setters.yaml" ]; then \
		echo "Error: $(NOK_KPT_DIR)/nok-bbm/apply-setters.yaml not found" ; exit 1 ; \
	fi
	@echo "--> KPT: Prometheus tuning → nok-bbm/apply-setters.yaml"
	@$(YQ) eval '.data."prometheus-retention" = "$(PROM_RETENTION)"' \
		-i $(NOK_KPT_DIR)/nok-bbm/apply-setters.yaml
	@$(YQ) eval '.data."prometheus-storage-size" = "$(PROM_STORAGE_SIZE_BBM)"' \
		-i $(NOK_KPT_DIR)/nok-bbm/apply-setters.yaml
	@PROM_CR="$(NOK_KPT_DIR)/nok-bbm/prometheus/prometheus-cr.yaml" ; \
	if [ -n "$(PROM_RETENTION_SIZE)" ]; then \
		$(YQ) eval '.spec.retentionSize = "$(PROM_RETENTION_SIZE)"' -i "$$PROM_CR" ; \
	else \
		$(YQ) eval 'del(.spec.retentionSize)' -i "$$PROM_CR" ; \
	fi

define SDCIO_SKIP_DIR
$(if $(filter YES yes Yes,$(SDCIO_ENABLED)),,$(filter $(1),$(SDCIO_FLUX_SKIP_DIRS)))
endef

define APPLY_RECIPE_TUNING
	@echo "--> TUNING: Applying Prometheus/gNMIc settings to $(1) manifests"
	@PROM_FILE="$(1)/prometheus/prometheus.yaml" ; \
	if [ -f "$$PROM_FILE" ]; then \
		$(YQ) eval '.spec.retention = "$(PROM_RETENTION)"' -i "$$PROM_FILE" ; \
		if [ -n "$(PROM_RETENTION_SIZE)" ]; then \
			$(YQ) eval '.spec.retentionSize = "$(PROM_RETENTION_SIZE)"' -i "$$PROM_FILE" ; \
		else \
			$(YQ) eval 'del(.spec.retentionSize)' -i "$$PROM_FILE" ; \
		fi ; \
		if [ -n "$(PROM_STORAGE_SIZE)" ]; then \
			$(YQ) eval '.spec.storage.volumeClaimTemplate.spec.resources.requests.storage = "$(PROM_STORAGE_SIZE)"' -i "$$PROM_FILE" ; \
		fi ; \
	fi
	@for cluster in $(1)/gnmic/clusters/*.yaml; do \
		[ -f "$$cluster" ] || continue ; \
		$(YQ) eval '.spec.replicas = $(GNMIC_REPLICAS)' -i "$$cluster" ; \
		if [ -n "$(GNMIC_CPU_REQUEST)" ]; then \
			$(YQ) eval '.spec.resources.requests.cpu = "$(GNMIC_CPU_REQUEST)"' -i "$$cluster" ; \
		fi ; \
		if [ -n "$(GNMIC_MEMORY_REQUEST)" ]; then \
			$(YQ) eval '.spec.resources.requests.memory = "$(GNMIC_MEMORY_REQUEST)"' -i "$$cluster" ; \
		fi ; \
		if [ -n "$(GNMIC_CPU_LIMIT)" ]; then \
			$(YQ) eval '.spec.resources.limits.cpu = "$(GNMIC_CPU_LIMIT)"' -i "$$cluster" ; \
		fi ; \
		if [ -n "$(GNMIC_MEMORY_LIMIT)" ]; then \
			$(YQ) eval '.spec.resources.limits.memory = "$(GNMIC_MEMORY_LIMIT)"' -i "$$cluster" ; \
		fi ; \
	done
endef

define PATCH_GRAFANA_DASHBOARD_URLS
	@DASH_DIR="$(1)/grafana/dashboards" ; \
	if [ ! -d "$$DASH_DIR" ]; then exit 0; fi ; \
	for cr in $$DASH_DIR/*.yaml; do \
		[ -f "$$cr" ] || continue ; \
		name=$$($(YQ) eval '.metadata.name' "$$cr") ; \
		if [ "$(GRAFANA_DASHBOARD_SOURCE)" = "upstream" ]; then \
			base="$(GRAFANA_DASHBOARD_UPSTREAM_BASE)/$(2)/grafana-dashboards" ; \
			url="$$base/$$name.json" ; \
		else \
			prefix="$(3)" ; \
			if [ -n "$$prefix" ]; then path="$$prefix/$$name.json" ; else path="$$name.json" ; fi ; \
			url="$(GRAFANA_DASHBOARD_GITEA_BASE)/$$path" ; \
		fi ; \
		$(YQ) eval '.spec.url = "'"$$url"'"' -i "$$cr" ; \
	done
endef

define STAGE_RECIPE_MANIFESTS
	@rm -rf "$(1)" ; \
	mkdir -p "$(1)" ; \
	rsync -a --exclude '.git' "$(2)/" "$(1)/" ; \
	$(call APPLY_RECIPE_TUNING,$(1)) ; \
	$(call PATCH_GRAFANA_DASHBOARD_URLS,$(1),$(3),$(4))
endef

.PHONY: stage-bng-manifests stage-dia-manifests
stage-bng-manifests:
	$(call STAGE_RECIPE_MANIFESTS,$(BASE)/build/bng-manifests-staging,$(BNG_MANIFESTS_DIR),nok-bng,$(BNG_GRAFANA_REPO_PREFIX))

stage-dia-manifests:
	$(call STAGE_RECIPE_MANIFESTS,$(BASE)/build/dia-manifests-staging,$(DIA_MANIFESTS_DIR),nok-dia,$(DIA_GRAFANA_REPO_PREFIX))

.PHONY: push-grafana-dashboards
push-grafana-dashboards: ## Push BNG + DIA Grafana JSON to in-cluster Gitea repo
	@echo "--> GIT: Pushing Grafana dashboards to $(FLUX_GRAFANA_REPO)"
	@rm -rf $(GRAFANA_DASHBOARDS_STAGING)
	@mkdir -p $(GRAFANA_DASHBOARDS_STAGING)/$(BNG_GRAFANA_REPO_PREFIX)
	@cp $(BNG_GRAFANA_DIR)/*.json $(GRAFANA_DASHBOARDS_STAGING)/$(BNG_GRAFANA_REPO_PREFIX)/
	@cp $(DIA_GRAFANA_DIR)/*.json $(GRAFANA_DASHBOARDS_STAGING)/
	@cd $(GRAFANA_DASHBOARDS_STAGING) && \
		( \
			rm -rf .git && \
			git init -b $(FLUX_GIT_BRANCH) && \
			git remote add origin ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_GRAFANA_REPO).git && \
			git add -A && \
			git commit --allow-empty -m "Grafana dashboards (BNG + DIA)" && \
			git config core.sshCommand 'ssh -o IdentitiesOnly=yes -i $(FLUX_SSH_KEY)' && \
			git push --force origin $(FLUX_GIT_BRANCH) \
		)
	@echo "--> GIT: Grafana dashboards push completed"

.PHONY: gitea-create-grafana-dashboards-repo
gitea-create-grafana-dashboards-repo: ## Ensure grafana-dashboards Gitea repo exists (BNG + DIA)
	@echo "--> GITEA: Ensuring repo $(FLUX_GRAFANA_REPO) exists"
	@$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  http://$(GITEA_HOST)$(GITEA_HTTP_PATH)/api/v1/repos/$(GITEA_ADMIN_USER)/$(FLUX_GRAFANA_REPO) \
	  >/dev/null || \
	$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -X POST \
	  -H "Content-Type: application/json" \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  -d '{"name":"$(FLUX_GRAFANA_REPO)", "description": "NetOpsKube Grafana dashboards (BNG + DIA)","private":false,"auto_init":true}' \
	  http://$(GITEA_HOST)$(GITEA_HTTP_PATH)/api/v1/user/repos
