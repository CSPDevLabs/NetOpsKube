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
#   make deploy-ipfix
#   make status-ipfix
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

IPFIX_ENABLED ?= YES

IPFIX_DIR ?= $(BASE)/nok-ipfix
IPFIX_NAMESPACE ?= nok-ipfix

IPFIX_CONFIG_FILE ?= $(IPFIX_DIR)/clusters.conf
IPFIX_GENERATOR_SCRIPT ?= $(IPFIX_DIR)/scripts/generate-ipfix-manifests.sh

IPFIX_KAFKA_READY_TIMEOUT ?= 180s
IPFIX_POSTGRES_READY_TIMEOUT ?= 180s
IPFIX_JOB_TIMEOUT ?= 180s
IPFIX_DEPLOYMENT_TIMEOUT ?= 180s

IPFIX_KAFKA_STATEFULSET ?= kafka
IPFIX_POSTGRES_STATEFULSET ?= ipfix-postgres

IPFIX_SCHEMA_JOB ?= ipfix-postgres-schema

IPFIX_GOFLOW2_DEPLOYMENT ?= goflow2
IPFIX_CONSUMER_DEPLOYMENT ?= ipfix-consumer

# ------------------------------------------------------------------------------
# Generated Manifest Patterns
# ------------------------------------------------------------------------------

IPFIX_GENERATED_GOFLOW_DEPLOYMENTS ?= $(IPFIX_DIR)/goflow/deployment-*.yaml
IPFIX_GENERATED_GOFLOW_SERVICES ?= $(IPFIX_DIR)/goflow/service-*.yaml
IPFIX_GENERATED_KAFKA_TOPICS ?= $(IPFIX_DIR)/kafka/topic-ipfix-*.yaml

# ------------------------------------------------------------------------------
# Generate IPFIX Manifests
# ------------------------------------------------------------------------------

.PHONY: generate-ipfix-manifests

generate-ipfix-manifests: ## Generate GoFlow2 and Kafka manifests from clusters.conf
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
		"$(IPFIX_DIR)/kafka/kafka.yaml" \
		"$(IPFIX_DIR)/postgres/postgres-secret.yaml" \
		"$(IPFIX_DIR)/postgres/postgres.yaml" \
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
	if [ -f "$(IPFIX_DIR)/kafka/topic-ipfix-dlq.yaml" ]; then \
		echo "--> IPFIX: Static DLQ manifest found"; \
	fi; \
	echo "--> IPFIX: GoFlow2 deployments: $$goflow_deployment_count"; \
	echo "--> IPFIX: GoFlow2 services: $$goflow_service_count"; \
	echo "--> IPFIX: Generated Kafka topics: $$topic_count"; \
	echo "--> IPFIX: Checking Kubernetes API connectivity"; \
	$(KUBECTL) cluster-info >/dev/null; \
	echo "--> IPFIX: Prerequisites verified"


# ------------------------------------------------------------------------------
# Main Deployment
# ------------------------------------------------------------------------------


.PHONY: deploy-ipfix
deploy-ipfix: generate-ipfix-manifests check-ipfix-prerequisites ## Deploy the complete IPFIX pipeline
	@set -e; \
	echo ""; \
	echo "============================================================"; \
	echo " IPFIX: Deploying flow-monitoring pipeline"; \
	echo " Namespace: $(IPFIX_NAMESPACE)"; \
	echo " KinD cluster: $(KIND_CLUSTER_NAME)"; \
	echo "============================================================"; \
	echo ""; \
	echo "--> IPFIX: Applying namespace"; \
	$(KUBECTL) apply -f "$(IPFIX_DIR)/goflow/namespace.yaml"; \
	echo "--> IPFIX: Applying PostgreSQL credentials"; \
	$(KUBECTL) apply -f "$(IPFIX_DIR)/postgres/postgres-secret.yaml"; \
	echo ""; \
	echo "--> IPFIX: Deploying Kafka"; \
	$(KUBECTL) apply -f "$(IPFIX_DIR)/kafka/kafka.yaml"; \
	echo "--> IPFIX: Deploying PostgreSQL"; \
	$(KUBECTL) apply -f "$(IPFIX_DIR)/postgres/postgres.yaml"; \
	echo ""; \
	echo "--> IPFIX: Waiting for Kafka StatefulSet rollout"; \
	$(KUBECTL) rollout status \
		statefulset/$(IPFIX_KAFKA_STATEFULSET) \
		-n $(IPFIX_NAMESPACE) \
		--timeout=$(IPFIX_KAFKA_READY_TIMEOUT); \
	echo "--> IPFIX: Waiting for PostgreSQL StatefulSet rollout"; \
	$(KUBECTL) rollout status \
		statefulset/$(IPFIX_POSTGRES_STATEFULSET) \
		-n $(IPFIX_NAMESPACE) \
		--timeout=$(IPFIX_POSTGRES_READY_TIMEOUT); \
	echo ""; \
	echo "--> IPFIX: Initializing PostgreSQL schema"; \
	$(KUBECTL) delete job "$(IPFIX_SCHEMA_JOB)" \
		-n $(IPFIX_NAMESPACE) \
		--ignore-not-found=true; \
	$(KUBECTL) apply -f "$(IPFIX_DIR)/postgres/postgres-schema.yaml"; \
	$(KUBECTL) wait \
		--for=condition=complete \
		job/$(IPFIX_SCHEMA_JOB) \
		-n $(IPFIX_NAMESPACE) \
		--timeout=$(IPFIX_JOB_TIMEOUT); \
	echo ""; \
	echo "--> IPFIX: Discovering and initializing Kafka topics"; \
	topic_count=0; \
	for file in "$(IPFIX_DIR)"/kafka/topic-*.yaml; do \
		[ -f "$$file" ] || continue; \
		job_name=$$($(KUBECTL) create \
			--dry-run=client \
			-f "$$file" \
			-o jsonpath='{.metadata.name}'); \
		if [ -z "$$job_name" ]; then \
			echo "[ERROR] Unable to determine Job name from $$file" >&2; \
			exit 1; \
		fi; \
		echo ""; \
		echo "--> IPFIX: Initializing topic using $$file (Job: $$job_name)"; \
		$(KUBECTL) delete job "$$job_name" \
			-n $(IPFIX_NAMESPACE) \
			--ignore-not-found=true; \
		$(KUBECTL) apply -f "$$file"; \
		$(KUBECTL) wait \
			--for=condition=complete \
			job/"$$job_name" \
			-n $(IPFIX_NAMESPACE) \
			--timeout=$(IPFIX_JOB_TIMEOUT); \
		topic_count=$$((topic_count + 1)); \
	done; \
	echo ""; \
	echo "--> IPFIX: Successfully initialized $$topic_count Kafka topic job(s)"; \
	echo ""; \
	echo "--> IPFIX: Deploying GoFlow2 collectors and Services"; \
	goflow_deployment_count=0; \
	goflow_service_count=0; \
	for file in "$(IPFIX_DIR)"/goflow/deployment-*.yaml; do \
		[ -f "$$file" ] || continue; \
		echo "--> IPFIX: Applying GoFlow2 deployment: $$file"; \
		$(KUBECTL) apply -f "$$file"; \
		deployment_name=$$($(KUBECTL) create \
			--dry-run=client \
			-f "$$file" \
			-o jsonpath='{.metadata.name}'); \
		if [ -z "$$deployment_name" ]; then \
			echo "[ERROR] Unable to determine Deployment name from $$file" >&2; \
			exit 1; \
		fi; \
		echo "--> IPFIX: Waiting for $$deployment_name rollout"; \
		$(KUBECTL) rollout status \
			deployment/"$$deployment_name" \
			-n $(IPFIX_NAMESPACE) \
			--timeout=$(IPFIX_DEPLOYMENT_TIMEOUT); \
		goflow_deployment_count=$$((goflow_deployment_count + 1)); \
	done; \
	for file in "$(IPFIX_DIR)"/goflow/service-*.yaml; do \
		[ -f "$$file" ] || continue; \
		echo "--> IPFIX: Applying GoFlow2 service: $$file"; \
		$(KUBECTL) apply -f "$$file"; \
		goflow_service_count=$$((goflow_service_count + 1)); \
	done; \
	echo ""; \
	echo "--> IPFIX: Applied $$goflow_deployment_count GoFlow2 deployment(s) and $$goflow_service_count service(s)"; \
	echo ""; \
	echo "--> IPFIX: Deploying Kafka consumer"; \
	$(KUBECTL) apply -f "$(IPFIX_DIR)/consumer/deployment.yaml"; \
	echo "--> IPFIX: Waiting for consumer rollout"; \
	$(KUBECTL) rollout status \
		deployment/$(IPFIX_CONSUMER_DEPLOYMENT) \
		-n $(IPFIX_NAMESPACE) \
		--timeout=$(IPFIX_DEPLOYMENT_TIMEOUT); \
	echo ""; \
	$(MAKE) status-ipfix; \
	echo ""; \
	echo "============================================================"; \
	echo " IPFIX: Deployment completed successfully"; \
	echo "============================================================"; \



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