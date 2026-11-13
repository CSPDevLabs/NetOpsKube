# ==============================================================================
# IPFIX Deployment
#
# Deploys the IPFIX flow-monitoring pipeline into an existing KinD Kubernetes
# cluster.
#
# Components:
#   - Namespace:      nok-ipfix
#   - GoFlow2:        IPFIX collector and Kafka producer
#   - Kafka:          Flow-event streaming
#   - PostgreSQL:     Flow-record persistence
#   - Consumer:       Kafka-to-PostgreSQL processing
#
# Usage:
#   make deploy-ipfix CLUSTER_ID=bng-1
#   make status-ipfix
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

IPFIX_ENABLED ?= NO

IPFIX_REPO_URL ?= https://github.com/CSPDevLabs/ipfix-consumer.git
IPFIX_DIR ?= $(BASE)/nok-ipfix
IPFIX_NAMESPACE ?= nok-ipfix

IPFIX_CONFIG_FILE ?= $(IPFIX_DIR)/clusters.conf
IPFIX_GENERATOR_SCRIPT ?= $(IPFIX_DIR)/scripts/generate-ipfix-manifests.sh

IPFIX_KAFKA_READY_TIMEOUT ?= 180s
IPFIX_POSTGRES_READY_TIMEOUT ?= 180s
IPFIX_JOB_TIMEOUT ?= 180s
IPFIX_DEPLOYMENT_TIMEOUT ?= 180s

# Shared resource names

IPFIX_KAFKA_STATEFULSET ?= kafka
IPFIX_KAFKA_SERVICE ?= kafka

IPFIX_POSTGRES_SECRET ?= ipfix-postgres-secret
IPFIX_POSTGRES_HEADLESS_SERVICE ?= ipfix-postgres-headless
IPFIX_POSTGRES_STATEFULSET ?= ipfix-postgres
IPFIX_POSTGRES_SERVICE ?= ipfix-postgres

IPFIX_SCHEMA_JOB ?= ipfix-postgres-schema
IPFIX_DLQ_JOB ?= kafka-create-topic-ipfix-dlq

IPFIX_CONSUMER_DEPLOYMENT ?= ipfix-consumer

# ------------------------------------------------------------------------------
# Generated Manifest Patterns
# ------------------------------------------------------------------------------

IPFIX_GENERATED_GOFLOW_DEPLOYMENTS ?= $(IPFIX_DIR)/goflow/deployment-*.yaml
IPFIX_GENERATED_GOFLOW_SERVICES ?= $(IPFIX_DIR)/goflow/service-*.yaml
IPFIX_GENERATED_KAFKA_TOPICS ?= $(IPFIX_DIR)/kafka/topic-ipfix-*.yaml

# ------------------------------------------------------------------------------
# Clone IPFIX Consumer Repository
# ------------------------------------------------------------------------------

.PHONY: ensure-ipfix-repository

ensure-ipfix-repository: ## Clone IPFIX consumer repository if missing
	@set -eu; \
	echo ""; \
	echo "--> IPFIX: Checking repository"; \
	if [ -d "$(IPFIX_DIR)/.git" ] || [ -f "$(IPFIX_DIR)/.git" ]; then \
		if ! command -v git >/dev/null 2>&1; then \
			echo "[ERROR] Git is required to validate the IPFIX repository." >&2; \
			exit 1; \
		fi; \
		repo_root=$$(git -C "$(IPFIX_DIR)" rev-parse --show-toplevel 2>/dev/null || true); \
		expected_dir=$$(cd "$(IPFIX_DIR)" && pwd -P); \
		if [ "$$repo_root" != "$$expected_dir" ]; then \
			echo "[ERROR] Invalid Git repository: $(IPFIX_DIR)" >&2; \
			exit 1; \
		fi; \
		echo "--> IPFIX: Repository already exists"; \
	elif [ -d "$(IPFIX_DIR)" ] && [ -n "$$(ls -A "$(IPFIX_DIR)")" ]; then \
		echo "[ERROR] Directory exists but is not an IPFIX Git repository: $(IPFIX_DIR)" >&2; \
		exit 1; \
	else \
		if ! command -v git >/dev/null 2>&1; then \
			echo "[ERROR] Git is required to clone the IPFIX repository." >&2; \
			exit 1; \
		fi; \
		echo "--> IPFIX: Cloning $(IPFIX_REPO_URL)"; \
		mkdir -p "$(BASE)"; \
		git clone "$(IPFIX_REPO_URL)" "$(IPFIX_DIR)"; \
		echo "--> IPFIX: Repository cloned successfully"; \
	fi; \
	echo ""

# ------------------------------------------------------------------------------
# Generate IPFIX Manifests
# ------------------------------------------------------------------------------

.PHONY: generate-ipfix-manifests

generate-ipfix-manifests: ensure-ipfix-repository ## Generate GoFlow2 and Kafka manifests from clusters.conf
	@set -eu; \
	echo ""; \
	echo "============================================================"; \
	echo " IPFIX: Generating cluster-specific manifests"; \
	echo "============================================================"; \
	if [ ! -f "$(IPFIX_CONFIG_FILE)" ] || [ ! -r "$(IPFIX_CONFIG_FILE)" ]; then \
		echo "[ERROR] Configuration file missing or unreadable: $(IPFIX_CONFIG_FILE)" >&2; \
		exit 1; \
	fi; \
	if [ ! -f "$(IPFIX_GENERATOR_SCRIPT)" ] || [ ! -r "$(IPFIX_GENERATOR_SCRIPT)" ]; then \
		echo "[ERROR] Generator script missing or unreadable: $(IPFIX_GENERATOR_SCRIPT)" >&2; \
		exit 1; \
	fi; \
	echo "--> IPFIX: Configuration: $(IPFIX_CONFIG_FILE)"; \
	echo "--> IPFIX: Generator: $(IPFIX_GENERATOR_SCRIPT)"; \
	bash "$(IPFIX_GENERATOR_SCRIPT)" "$(IPFIX_CONFIG_FILE)"; \
	echo ""; \
	echo "--> IPFIX: Manifest generation completed successfully"

# ------------------------------------------------------------------------------
# Prerequisite Checks
# ------------------------------------------------------------------------------

.PHONY: check-ipfix-prerequisites

check-ipfix-prerequisites: ## Validate generated IPFIX manifests, tools and Kubernetes connectivity
	@set -eu; \
	echo "--> IPFIX: Checking prerequisites"; \
	if ! command -v "$(firstword $(KUBECTL))" >/dev/null 2>&1; then \
		echo "[ERROR] kubectl command not found: $(KUBECTL)" >&2; \
		exit 1; \
	fi; \
	if [ ! -d "$(IPFIX_DIR)" ]; then \
		echo "[ERROR] IPFIX directory not found: $(IPFIX_DIR)" >&2; \
		exit 1; \
	fi; \
	for file in \
		"$(IPFIX_DIR)/goflow/namespace.yaml" \
		"$(IPFIX_DIR)/kafka/statefulset.yaml" \
		"$(IPFIX_DIR)/kafka/service.yaml" \
		"$(IPFIX_DIR)/kafka/topic-ipfix-dlq.yaml" \
		"$(IPFIX_DIR)/postgres/postgres-secret.yaml" \
		"$(IPFIX_DIR)/postgres/headless-service.yaml" \
		"$(IPFIX_DIR)/postgres/statefulset.yaml" \
		"$(IPFIX_DIR)/postgres/service.yaml" \
		"$(IPFIX_DIR)/postgres/postgres-schema.yaml" \
		"$(IPFIX_DIR)/consumer/deployment.yaml"; do \
		if [ ! -f "$$file" ]; then \
			echo "[ERROR] Required manifest not found: $$file" >&2; \
			exit 1; \
		fi; \
	done; \
	goflow_deployment_count=0; \
	for file in $(IPFIX_GENERATED_GOFLOW_DEPLOYMENTS); do \
		[ -f "$$file" ] || continue; \
		goflow_deployment_count=$$((goflow_deployment_count + 1)); \
	done; \
	goflow_service_count=0; \
	for file in $(IPFIX_GENERATED_GOFLOW_SERVICES); do \
		[ -f "$$file" ] || continue; \
		goflow_service_count=$$((goflow_service_count + 1)); \
	done; \
	if [ "$$goflow_deployment_count" -eq 0 ]; then \
		echo "[ERROR] No generated GoFlow2 deployments found." >&2; \
		exit 1; \
	fi; \
	if [ "$$goflow_service_count" -ne "$$goflow_deployment_count" ]; then \
		echo "[ERROR] GoFlow2 deployment/service count mismatch." >&2; \
		exit 1; \
	fi; \
	topic_count=0; \
	for file in $(IPFIX_GENERATED_KAFKA_TOPICS); do \
		[ -f "$$file" ] || continue; \
		topic_count=$$((topic_count + 1)); \
	done; \
	if [ "$$topic_count" -eq 0 ]; then \
		echo "[ERROR] No generated Kafka topic manifests found." >&2; \
		exit 1; \
	fi; \
	echo "--> IPFIX: GoFlow2 deployments: $$goflow_deployment_count"; \
	echo "--> IPFIX: GoFlow2 services: $$goflow_service_count"; \
	echo "--> IPFIX: Kafka topic manifests: $$topic_count"; \
	echo "--> IPFIX: Checking Kubernetes API connectivity"; \
	$(KUBECTL) cluster-info >/dev/null; \
	echo "--> IPFIX: Prerequisites verified"

# ------------------------------------------------------------------------------
# Main Deployment
# ------------------------------------------------------------------------------

.PHONY: deploy-ipfix

deploy-ipfix: ## Deploy one explicitly requested IPFIX cluster
	@set -eu; \
	echo ""; \
	echo "============================================================"; \
	echo " IPFIX: Cluster-specific deployment"; \
	echo "============================================================"; \
	cluster_id="$(CLUSTER_ID)"; \
	if [ -z "$$cluster_id" ]; then \
		echo "[ERROR] CLUSTER_ID is mandatory."; \
		echo ""; \
		echo "Usage: make deploy-ipfix CLUSTER_ID=<cluster-id>"; \
		exit 1; \
	fi; \
	if ! printf '%s\n' "$$cluster_id" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$$'; then \
		echo "[ERROR] Invalid cluster ID: $$cluster_id" >&2; \
		exit 1; \
	fi; \
	if [ "$${#cluster_id}" -gt 38 ]; then \
		echo "[ERROR] Cluster ID exceeds the maximum length of 38 characters." >&2; \
		exit 1; \
	fi; \
	echo "--> IPFIX: Requested cluster: $$cluster_id"; \
	$(MAKE) ensure-ipfix-repository; \
	if [ ! -f "$(IPFIX_CONFIG_FILE)" ] || [ ! -r "$(IPFIX_CONFIG_FILE)" ]; then \
		echo "[ERROR] Configuration file missing or unreadable: $(IPFIX_CONFIG_FILE)" >&2; \
		exit 1; \
	fi; \
	if ! awk -F'|' -v id="$$cluster_id" ' \
		function trim(s) { \
			gsub(/^[[:space:]]+|[[:space:]]+$$/, "", s); \
			return s; \
		} \
		{ \
			sub(/\r$$/, ""); \
			if (trim($$0) == "" || trim($$0) ~ /^#/) next; \
			if (NF == 3 && trim($$1) == id) found = 1; \
		} \
		END { exit !found } \
	' "$(IPFIX_CONFIG_FILE)"; then \
		echo "[ERROR] Cluster '$$cluster_id' does not exist in clusters.conf."; \
		echo "[ERROR] Add the cluster configuration before deployment."; \
		exit 1; \
	fi; \
	echo "--> IPFIX: Cluster found in clusters.conf"; \
	$(MAKE) generate-ipfix-manifests; \
	$(MAKE) check-ipfix-prerequisites; \
	deployment_file="$(IPFIX_DIR)/goflow/deployment-$$cluster_id.yaml"; \
	service_file="$(IPFIX_DIR)/goflow/service-$$cluster_id.yaml"; \
	topic_file="$(IPFIX_DIR)/kafka/topic-ipfix-$$cluster_id.yaml"; \
	for file in "$$deployment_file" "$$service_file" "$$topic_file"; do \
		if [ ! -f "$$file" ]; then \
			echo "[ERROR] Required cluster manifest not found: $$file" >&2; \
			exit 1; \
		fi; \
	done; \
	deployment_name=$$($(KUBECTL) create --dry-run=client \
		-f "$$deployment_file" \
		-o jsonpath='{.metadata.name}'); \
	service_name=$$($(KUBECTL) create --dry-run=client \
		-f "$$service_file" \
		-o jsonpath='{.metadata.name}'); \
	topic_job_name=$$($(KUBECTL) create --dry-run=client \
		-f "$$topic_file" \
		-o jsonpath='{.metadata.name}'); \
	if [ -z "$$deployment_name" ] || \
	   [ -z "$$service_name" ] || \
	   [ -z "$$topic_job_name" ]; then \
		echo "[ERROR] Unable to determine resource names from cluster manifests." >&2; \
		exit 1; \
	fi; \
	echo ""; \
	echo "--> IPFIX: Deployment: $$deployment_name"; \
	echo "--> IPFIX: Service: $$service_name"; \
	echo "--> IPFIX: Kafka topic Job: $$topic_job_name"; \
	deployment_exists=0; \
	service_exists=0; \
	topic_job_exists=0; \
	$(KUBECTL) get deployment "$$deployment_name" \
		-n "$(IPFIX_NAMESPACE)" >/dev/null 2>&1 && deployment_exists=1 || true; \
	$(KUBECTL) get service "$$service_name" \
		-n "$(IPFIX_NAMESPACE)" >/dev/null 2>&1 && service_exists=1 || true; \
	$(KUBECTL) get job "$$topic_job_name" \
		-n "$(IPFIX_NAMESPACE)" >/dev/null 2>&1 && topic_job_exists=1 || true; \
	if [ "$$deployment_exists" -eq 1 ] && \
	   [ "$$service_exists" -eq 1 ] && \
	   [ "$$topic_job_exists" -eq 1 ]; then \
		echo ""; \
		echo "============================================================"; \
		echo " IPFIX: Cluster already deployed"; \
		echo " Cluster ID: $$cluster_id"; \
		echo "============================================================"; \
		echo "[INFO] GoFlow2 Deployment already exists."; \
		echo "[INFO] GoFlow2 Service already exists."; \
		echo "[INFO] Kafka topic initialization Job already exists."; \
		echo "[INFO] No resources were modified."; \
		exit 0; \
	fi; \
	echo ""; \
	echo "--> IPFIX: Cluster is not fully deployed."; \
	echo "--> IPFIX: Missing resources will be created only."; \
	create_if_missing() { \
		resource_type="$$1"; \
		resource_name="$$2"; \
		manifest_file="$$3"; \
		if $(KUBECTL) get "$$resource_type" "$$resource_name" \
			-n "$(IPFIX_NAMESPACE)" >/dev/null 2>&1; then \
			echo "[INFO] $$resource_type/$$resource_name already exists. Skipping."; \
		else \
			echo "--> IPFIX: Creating $$resource_type/$$resource_name"; \
			$(KUBECTL) create -f "$$manifest_file"; \
		fi; \
	}; \
	echo ""; \
	echo "============================================================"; \
	echo " IPFIX: Checking shared infrastructure"; \
	echo "============================================================"; \
	if $(KUBECTL) get namespace "$(IPFIX_NAMESPACE)" >/dev/null 2>&1; then \
		echo "[INFO] Namespace $(IPFIX_NAMESPACE) already exists. Skipping."; \
	else \
		echo "--> IPFIX: Creating namespace"; \
		$(KUBECTL) create -f "$(IPFIX_DIR)/goflow/namespace.yaml"; \
	fi; \
	create_if_missing secret "$(IPFIX_POSTGRES_SECRET)" \
		"$(IPFIX_DIR)/postgres/postgres-secret.yaml"; \
	create_if_missing service "$(IPFIX_KAFKA_SERVICE)" \
		"$(IPFIX_DIR)/kafka/service.yaml"; \
	create_if_missing statefulset "$(IPFIX_KAFKA_STATEFULSET)" \
		"$(IPFIX_DIR)/kafka/statefulset.yaml"; \
	create_if_missing service "$(IPFIX_POSTGRES_HEADLESS_SERVICE)" \
		"$(IPFIX_DIR)/postgres/headless-service.yaml"; \
	create_if_missing service "$(IPFIX_POSTGRES_SERVICE)" \
		"$(IPFIX_DIR)/postgres/service.yaml"; \
	create_if_missing statefulset "$(IPFIX_POSTGRES_STATEFULSET)" \
		"$(IPFIX_DIR)/postgres/statefulset.yaml"; \
	echo ""; \
	echo "--> IPFIX: Waiting for Kafka readiness"; \
	$(KUBECTL) rollout status \
		statefulset/"$(IPFIX_KAFKA_STATEFULSET)" \
		-n "$(IPFIX_NAMESPACE)" \
		--timeout="$(IPFIX_KAFKA_READY_TIMEOUT)"; \
	echo "--> IPFIX: Waiting for PostgreSQL readiness"; \
	$(KUBECTL) rollout status \
		statefulset/"$(IPFIX_POSTGRES_STATEFULSET)" \
		-n "$(IPFIX_NAMESPACE)" \
		--timeout="$(IPFIX_POSTGRES_READY_TIMEOUT)"; \
	create_if_missing job "$(IPFIX_DLQ_JOB)" \
		"$(IPFIX_DIR)/kafka/topic-ipfix-dlq.yaml"; \
	echo "--> IPFIX: Waiting for Kafka DLQ topic initialization"; \
	$(KUBECTL) wait \
		--for=condition=complete \
		job/"$(IPFIX_DLQ_JOB)" \
		-n "$(IPFIX_NAMESPACE)" \
		--timeout="$(IPFIX_JOB_TIMEOUT)"; \
	create_if_missing job "$(IPFIX_SCHEMA_JOB)" \
		"$(IPFIX_DIR)/postgres/postgres-schema.yaml"; \
	echo "--> IPFIX: Waiting for PostgreSQL schema Job"; \
	$(KUBECTL) wait \
		--for=condition=complete \
		job/"$(IPFIX_SCHEMA_JOB)" \
		-n "$(IPFIX_NAMESPACE)" \
		--timeout="$(IPFIX_JOB_TIMEOUT)"; \
	create_if_missing deployment "$(IPFIX_CONSUMER_DEPLOYMENT)" \
		"$(IPFIX_DIR)/consumer/deployment.yaml"; \
	echo "--> IPFIX: Waiting for Kafka consumer readiness"; \
	$(KUBECTL) rollout status \
		deployment/"$(IPFIX_CONSUMER_DEPLOYMENT)" \
		-n "$(IPFIX_NAMESPACE)" \
		--timeout="$(IPFIX_DEPLOYMENT_TIMEOUT)"; \
	echo ""; \
	echo "============================================================"; \
	echo " IPFIX: Deploying cluster $$cluster_id"; \
	echo "============================================================"; \
	if [ "$$topic_job_exists" -eq 1 ]; then \
		echo "[INFO] Kafka topic Job $$topic_job_name already exists. Skipping."; \
	else \
		echo "--> IPFIX: Creating Kafka topic"; \
		$(KUBECTL) create -f "$$topic_file"; \
	fi; \
	echo "--> IPFIX: Waiting for Kafka topic initialization"; \
	$(KUBECTL) wait \
		--for=condition=complete \
		job/"$$topic_job_name" \
		-n "$(IPFIX_NAMESPACE)" \
		--timeout="$(IPFIX_JOB_TIMEOUT)"; \
	if [ "$$deployment_exists" -eq 1 ]; then \
		echo "[INFO] GoFlow2 Deployment $$deployment_name already exists. Skipping."; \
	else \
		echo "--> IPFIX: Creating GoFlow2 Deployment"; \
		$(KUBECTL) create -f "$$deployment_file"; \
	fi; \
	echo "--> IPFIX: Waiting for GoFlow2 Deployment"; \
	$(KUBECTL) rollout status \
		deployment/"$$deployment_name" \
		-n "$(IPFIX_NAMESPACE)" \
		--timeout="$(IPFIX_DEPLOYMENT_TIMEOUT)"; \
	if [ "$$service_exists" -eq 1 ]; then \
		echo "[INFO] GoFlow2 Service $$service_name already exists. Skipping."; \
	else \
		echo "--> IPFIX: Creating GoFlow2 Service"; \
		$(KUBECTL) create -f "$$service_file"; \
	fi; \
	echo ""; \
	echo "============================================================"; \
	echo " IPFIX: Cluster deployment completed successfully"; \
	echo " Cluster ID: $$cluster_id"; \
	echo "============================================================"; \
	echo ""; \
	$(MAKE) status-ipfix

# ------------------------------------------------------------------------------
# Status
# ------------------------------------------------------------------------------

.PHONY: status-ipfix

status-ipfix: ## Show IPFIX workloads, PVCs and recent events
	@echo "--> IPFIX: Deployments, StatefulSets, Services and Jobs"
	@$(KUBECTL) get deployments,statefulsets,services,jobs \
		-n $(IPFIX_NAMESPACE)
	@echo ""
	@echo "--> IPFIX: Pods"
	@$(KUBECTL) get pods -o wide -n $(IPFIX_NAMESPACE)
	@echo ""
	@echo "--> IPFIX: Persistent volume claims"
	@$(KUBECTL) get pvc -n $(IPFIX_NAMESPACE)
	@echo ""
