# ==============================================================================
# Deployment Flow
# ==============================================================================
#
# The deployment is intentionally split into three phases:
#
#   1. make try-nok
#      - Creates the KinD cluster.
#      - Installs shared infrastructure (MetalLB, Prometheus Operator,
#        GNMIc Operator, BBM, Flux, Gitea, authentication, etc.).
#
#   2. make try-nok-bng
#      - Deploys the BNG solution and its GitOps resources.
#
#   3. make try-nok-dia
#      - Deploys the DIA solution and its GitOps resources.
#
# IMPORTANT:
# Both BNG and DIA install independent monitoring stacks (Prometheus,
# Alertmanager, Grafana, ServiceMonitors, etc.) into their own namespaces.
# Although the resources are namespaced, some supporting resources are
# cluster-scoped (for example ClusterRoles, ClusterRoleBindings and CRDs
# managed by the Prometheus Operator).
#
#
# Expected usage:
#
#     make try-nok
#     make try-nok-bng
#     make try-nok-dia
#
# or
#
#     make try-nok
#     make try-nok-dia
#     make try-nok-bng
#
# Both sequences should result in functional BNG and DIA deployments.
# ==============================================================================


include make/settings.mk
include make/troubleshoot.mk
include make/bng.mk
include make/dia.mk
include make/auth.mk

# Deployments (namespace:name) that receive proxy env via set-proxy-env / unset-proxy-env.
PROXY_DEPLOYMENTS := \
nok-bbm:coredns-updater \
nok-bbm:blackbox-exporter \
nok-base:grafana-operator-controller-manager \
nok-base:config-server

ifneq ($(filter YES yes Yes,$(KEYCLOAK_ENABLED)),)
PROXY_DEPLOYMENTS += \
	nok-base:oauth2-proxy
endif

## Deploy Base Apps, clone kpt and clab repos, install base packages / load balancer / prometheus and gnmic operators, port forward
.PHONY: try-nok
try-nok: check-tools cluster-up cluster-wait-for-node-ready generate-portal-pv git-clone-clab install-base-pkg install-lb-pkg install-prom-oper install-gnmic-oper start-ingress-port-forward install-bbm-pkg install-base-final configure-auth

## Create Gitea admin, create Flux repo, add SSH key, bootstrap Flux
.PHONY: gitops-init
gitops-init: gitea-create-admin gitea-create-flux-repo gitea-add-ssh-key  flux-bootstrap 
	@echo "--> GITOPS: Cluster is now managed by Flux"

.PHONY: generate-portal-pv
generate-portal-pv:
	@echo "--> PORTAL: Syncing portal files into Kind node"
	@docker exec $(KIND_CLUSTER_NAME)-control-plane rm -rf /portal
	@docker cp $(NOK_KPT_DIR)/nok-base/portal $(KIND_CLUSTER_NAME)-control-plane:/portal
	@echo "--> PORTAL: Portal files synchronized"

.PHONY: cluster-up
cluster-up: $(KIND_CONFIG_REAL_LOC) ## Bring up the KinD cluster
	@echo "--> KIND: Ensuring control-plane exists"
	@{ \
		cp $(KIND_CONFIG_REAL_LOC) $(KIND_LAUNCH_CONFIG) ;\
		if [ ! -z "$(KIND_API_SERVER_ADDRESS)" ]; then \
			echo "--> KIND: Setting API server address to $(KIND_API_SERVER_ADDRESS)" ;\
			$(YQ) eval ".networking.apiServerAddress = \"$(KIND_API_SERVER_ADDRESS)\"" -i $(KIND_LAUNCH_CONFIG) ;\
		fi ;\
		if [[ "$(NO_HOST_PORT_MAPPINGS)" == "yes" ]]; then \
			echo "--> KIND: Host port maps removed" ;\
			$(YQ) eval "del(.nodes[0].extraPortMappings)" -i $(KIND_LAUNCH_CONFIG) ;\
		else \
			echo "--> KIND: Host port map 0.0.0.0:$(EXT_HTTPS_PORT) added" ;\
			$(YQ) eval ".nodes[0].extraPortMappings[0].hostPort = $(EXT_HTTPS_PORT)" -i $(KIND_LAUNCH_CONFIG) ;\
		fi ;\
		MATCHED=0 ;\
		for cluster_name in $$($(KIND) get clusters); do \
			if [[ "$${cluster_name}" == "$(KIND_CLUSTER_NAME)" ]]; then \
				MATCHED=1 ;\
			fi ;\
		done ;\
		if [[ "$${MATCHED}" == "0" ]]; then \
			echo "--> KIND: Creating cluster named $(KIND_CLUSTER_NAME)..." ;\
			$(KIND) create cluster --name $(KIND_CLUSTER_NAME) --config $(KIND_LAUNCH_CONFIG) 2>&1 | $(INDENT_OUT) ;\
		else \
			echo "--> KIND: Cluster named $(KIND_CLUSTER_NAME) already exists" ;\
		fi ;\
	}
	@$(MAKE) update-kpt-lb-setters

.PHONY: update-kpt-lb-setters
update-kpt-lb-setters: git-clone-kpt $(YQ) ## Write KinD LB IPs into nok-kpt apply-setters.yaml (kpt#27)
	@IP_PREFIX="$(KIND_NET_PREFIX)" ;\
	if [ -z "$$IP_PREFIX" ]; then \
		echo "Error: KinD cluster '$(KIND_CLUSTER_NAME)' not found — cannot detect network prefix" ;\
		exit 1 ;\
	fi ;\
	if [ ! -d "$(NOK_KPT_DIR)" ]; then \
		echo "Error: $(NOK_KPT_DIR) not found — run 'make git-clone-kpt' first" ;\
		exit 1 ;\
	fi ;\
	echo "--> KPT: KinD LB prefix $$IP_PREFIX → apply-setters.yaml (template: $(KIND_LB_DEFAULT_PREFIX))" ;\
	$(YQ) eval '.data."metallb-pool-range" = "'$$IP_PREFIX'.$(KIND_LB_POOL_START)-'$$IP_PREFIX'.$(KIND_LB_POOL_END)"' \
		-i $(NOK_KPT_DIR)/nok-lb/apply-setters.yaml ;\
	$(YQ) eval '.data."ingress-lb-ip" = "'$$IP_PREFIX'.$(KIND_LB_INGRESS_HOST)"' \
		-i $(NOK_KPT_DIR)/nok-base/apply-setters.yaml ;\
	$(YQ) eval '.data."syslog-lb-ip" = "'$$IP_PREFIX'.$(KIND_LB_BNG_SYSLOG_HOST)"' \
		-i $(NOK_KPT_DIR)/nok-bng/apply-setters.yaml ;\
	$(YQ) eval '.data."syslog-lb-ip" = "'$$IP_PREFIX'.$(KIND_LB_DIA_SYSLOG_HOST)"' \
		-i $(NOK_KPT_DIR)/nok-dia/apply-setters.yaml ;\
	$(YQ) eval '.data."gitea-ssh-lb-ip" = "'$$IP_PREFIX'.$(KIND_LB_GITEA_SSH_HOST)"' \
		-i $(NOK_KPT_DIR)/nok-git/apply-setters.yaml ;\
	$(YQ) eval '.data."blackbox-lb-ip" = "'$$IP_PREFIX'.$(KIND_LB_BLACKBOX_HOST)"' \
		-i $(NOK_KPT_DIR)/nok-bbm/apply-setters.yaml

.PHONY: show-kind-lb-setters
show-kind-lb-setters: ## Show KinD LB prefix and apply-setters.yaml values (kpt#27)
	@IP_PREFIX="$(KIND_NET_PREFIX)" ;\
	if [ -z "$$IP_PREFIX" ]; then \
		echo "Error: KinD cluster '$(KIND_CLUSTER_NAME)' not found" ; exit 1 ;\
	fi ;\
	echo "--> KIND: KinD LB network prefix is $$IP_PREFIX (template: $(KIND_LB_DEFAULT_PREFIX))" ;\
	echo "--> KPT: apply-setters.yaml values (run 'make update-kpt-lb-setters' to refresh):" ;\
	for pkg in nok-lb nok-base nok-bng nok-dia nok-git nok-bbm; do \
		f="$(NOK_KPT_DIR)/$$pkg/apply-setters.yaml" ;\
		if [ -f "$$f" ]; then \
			echo "    $$pkg:" ;\
			$(YQ) eval '.data | to_entries | .[] | "      " + .key + ": " + .value' "$$f" ;\
		fi ;\
	done

.PHONY: cluster-wait-for-node-ready
cluster-wait-for-node-ready: ## Wait for the Kubernetes control plane node to be ready
	@echo "--> KIND: Waiting for k8s node to be ready"
	@{ \
		START=$$(date +%s) ;\
		$(KUBECTL) wait --for=condition=Ready node/$(KIND_CLUSTER_NAME)-control-plane --timeout=300s 2>&1 | $(INDENT_OUT) ;\
		echo "--> KIND: Node ready check took $$(( $$(date +%s) - $$START ))s" ;\
	}

.PHONY: delete-cluster
delete-cluster: ## Delete the KinD cluster
	@echo "--> KIND: Deleting cluster $(KIND_CLUSTER_NAME)..."
	@$(KIND) delete cluster --name $(KIND_CLUSTER_NAME) || true
	@rm -f $(KIND_LAUNCH_CONFIG)

.PHONY: check-tools
check-tools: $(KIND) $(KUBECTL) $(YQ) $(HELM) $(KPT) $(K9S) $(GH) $(CLAB) $(FLUX) create-tool-aliases ## Ensure all required tools are present and aliased
	@echo "--> All required tools found or downloaded."

.PHONY: create-tool-aliases
create-tool-aliases: $(TOOLS) ## Create aliases for versioned binaries in the tools directory
	@echo "--> TOOLS: Creating aliases for versioned binaries"
	@{ \
		cd $(TOOLS) &&																	 \
		for binary_path in $(DOWNLOAD_TOOLS_LIST); do										 \
			binary_name=$$(basename $$binary_path)											;\
			tool_name=$$(echo $$binary_name | cut -d'-' -f1)							;\
			if [[ -f "$$binary_name" && -x "$$binary_name" && "$$binary_name" == *"-"* ]]; then	 \
				echo "    Creating alias: $$tool_name -> $$binary_name"						;\
				ln -sf "$$binary_name" "$$tool_name"											;\
			fi																			;\
		done																			;\
	}
	@echo "--> TOOLS: To add the tools to your path, paste this in your shell: export PATH=\$$PATH:$(TOOLS)"

.PHONY: help
help: ## Display this help message
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

	

# --- Git Clone Targets ---

## Clones the CSPDevLabs/kpt repository into ./nok-kpt
.PHONY: git-clone-kpt
git-clone-kpt:
	@echo "--> GIT: Cloning $(KPT_REPO_URL) ($(KPT_REPO_BRANCH)) into $(NOK_KPT_DIR)"
	@if [ ! -d "$(NOK_KPT_DIR)" ]; then \
		git clone -b $(KPT_REPO_BRANCH) $(KPT_REPO_URL) $(NOK_KPT_DIR) ;\
	else \
		echo "--> GIT: $(NOK_KPT_DIR) already exists. Skipping clone." ;\
		echo "--> GIT: Ensure branch $(KPT_REPO_BRANCH) is checked out (override with NOK_KPT_DIR for a local kpt checkout)." ;\
	fi

## Clones the CSPDevLabs/nok-clabs repository into ./nok-clabs
.PHONY: git-clone-clab
git-clone-clab:
	@echo "--> GIT: Cloning $(CLABS_REPO_URL) into $(NOK_CLABS_DIR)"
	@if [ ! -d "$(NOK_CLABS_DIR)" ]; then \
		git clone -b nok-restructure $(CLABS_REPO_URL) $(NOK_CLABS_DIR) ;\
	else \
		echo "--> GIT: $(NOK_CLABS_DIR) already exists. Skipping clone." ;\
	fi

## Checks for required Docker image and SROS license file for Containerlab
.PHONY: check-clab-prerequisites
check-clab-prerequisites:
	@echo "--> CLAB: Checking prerequisites for CLAB deployment..."
	@{ \
		if [ -z "$$(docker images -q $(SRLINUX_IMAGE) 2> /dev/null)" ]; then \
			echo "Error: Required Docker image '$(SRLINUX_IMAGE)' not found locally." ;\
			echo "Please pull the image using: docker pull $(SRLINUX_IMAGE)" ;\
			exit 1 ;\
		fi ;\
		echo "--> CLAB: Docker image '$(SRLINUX_IMAGE)' found." ;\
		if [ ! -f "$(SRSIM_LICENSE_FILE)" ]; then \
			echo "Error: Nokia SROS license file '$(SRSIM_LICENSE_FILE)' not found." ;\
			echo "Please ensure the license file is placed at this location." ;\
			exit 1 ;\
		fi ;\
		echo "--> CLAB: Nokia SROS license file found." ;\
	}


# --- Directory Creation Rules ---
$(BASE):
	@mkdir -p $(BASE)

$(TOOLS):
	@mkdir -p $(TOOLS)

# --- Default KinD Configuration File (build/kind-cluster.yaml) ---
# This file defines the basic structure for your KinD cluster.
# It will be copied and modified by the Makefile.
#
# To customize, modify this file or override KIND_CONFIG_REAL_LOC.
#
# A single-node cluster with a control-plane node.
# The extraPortMappings will be handled by the Makefile based on variables.
#
$(KIND_CONFIG_REAL_LOC):
	@mkdir -p $(dir $(KIND_CONFIG_REAL_LOC)) # Ensure the build directory exists
	@echo "Creating default $(KIND_CONFIG_REAL_LOC)..."
	@echo "kind: Cluster" > $(KIND_CONFIG_REAL_LOC)
	@echo "apiVersion: kind.x-k8s.io/v1alpha4" >> $(KIND_CONFIG_REAL_LOC)
	@echo "nodes:" >> $(KIND_CONFIG_REAL_LOC)
	@echo "- role: control-plane" >> $(KIND_CONFIG_REAL_LOC)
	@echo "  extraPortMappings:" >> $(KIND_CONFIG_REAL_LOC)
	@echo "    - containerPort: 6443" >> $(KIND_CONFIG_REAL_LOC)
	@echo "      hostPort: $(EXT_HTTPS_PORT)" >> $(KIND_CONFIG_REAL_LOC) # Use the variable here
	@echo "      listenAddress: \"0.0.0.0\"" >> $(KIND_CONFIG_REAL_LOC)
	@echo "      protocol: tcp" >> $(KIND_CONFIG_REAL_LOC)
	@echo "  kubeadmConfigPatches:" >> $(KIND_CONFIG_REAL_LOC)
	@echo "    - |" >> $(KIND_CONFIG_REAL_LOC)
	@echo "      kind: InitConfiguration" >> $(KIND_CONFIG_REAL_LOC)
	@echo "      nodeRegistration:" >> $(KIND_CONFIG_REAL_LOC)
	@echo "        kubeletExtraArgs:" >> $(KIND_CONFIG_REAL_LOC)
	@echo "          node-labels: \"ingress-ready=true\"" >> $(KIND_CONFIG_REAL_LOC)
	@echo "          authorization-mode: \"AlwaysAllow\"" >> $(KIND_CONFIG_REAL_LOC)
	@echo "    - |" >> $(KIND_CONFIG_REAL_LOC) # Add this new patch for ClusterConfiguration
	@echo "      kind: ClusterConfiguration" >> $(KIND_CONFIG_REAL_LOC)
	@echo "      apiServer:" >> $(KIND_CONFIG_REAL_LOC)
	@echo "        certSANs:" >> $(KIND_CONFIG_REAL_LOC)
	@echo "          - \"0.0.0.0\"" >> $(KIND_CONFIG_REAL_LOC) # Explicitly add 0.0.0.0 to SANs
	@echo "networking:" >> $(KIND_CONFIG_REAL_LOC)
	@echo "  apiServerPort: 6443" >> $(KIND_CONFIG_REAL_LOC)
	@echo "  podSubnet: \"10.244.0.0/16\"" >> $(KIND_CONFIG_REAL_LOC)
	@echo "  serviceSubnet: \"10.96.0.0/12\"" >> $(KIND_CONFIG_REAL_LOC)




# --- KPT Package Installation ---

.PHONY: start-ingress-port-forward
start-ingress-port-forward: ## Starts background port-forward for ingress-nginx-controller
	@echo "--> K8S: Waiting for ingress-nginx-controller pod in namespace 'nok-base' to be ready..."
	$(KUBECTL) wait --namespace=nok-base --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=5m
	@echo "--> K8S: Starting ingress-nginx-controller port-forward (0.0.0.0:8080 -> 80)..."
	nohup $(KUBECTL) port-forward --namespace=nok-base service/ingress-nginx-controller --address 0.0.0.0 8080:80 > /dev/null 2>&1 &
	@echo "--> K8S: Ingress port-forward started in background."
	@echo "    To stop it, find the process using 'ps aux | grep \"kubectl port-forward\"' and 'kill <PID>'."

## Installs the base kpt package from ./nok-kpt/nok-base
.PHONY: install-base-pkg
install-base-pkg: update-kpt-lb-setters
	@$(call INSTALL_KPT_PACKAGE_WITH_SETTERS,$(NOK_KPT_DIR)/nok-base,nok-base,"--reconcile-timeout=5m", "--inventory-policy=adopt")	

.PHONY: install-base-final
install-base-final: update-kpt-lb-setters
	@$(call INSTALL_KPT_PACKAGE_WITH_SETTERS,$(NOK_KPT_DIR)/nok-base,nok-base,"--reconcile-timeout=5m", "--inventory-policy=adopt")	

## Installs the base kpt package from ./nok-kpt/nok-git
.PHONY: install-git-pkg
install-git-pkg: install-lb-pkg
	@$(call INSTALL_KPT_PACKAGE_WITH_SETTERS,$(NOK_KPT_DIR)/nok-git,nok-git,"--reconcile-timeout=5m", "--inventory-policy=adopt")

## Installs the base kpt package from ./nok-kpt/nok-lb
.PHONY: install-lb-pkg
install-lb-pkg: wait-for-metallb-ready
	@$(call INSTALL_KPT_PACKAGE_WITH_SETTERS,$(NOK_KPT_DIR)/nok-lb,nok-lb,"--reconcile-timeout=5m", "")		

.PHONY: wait-for-metallb-ready
wait-for-metallb-ready: ## Wait for the Kubernetes Metallb node to be ready
	@echo "--> KIND: Waiting for Metallb Controller to be ready"
	@{ \
		START=$$(date +%s) ; \
		$(KUBECTL) wait --for=condition=available deployment/controller -n metallb-system --timeout=5m --timeout=5m ; \
		echo "--> KIND: Node ready check took $$(( $$(date +%s) - $$START ))s" ; \
	}	

## Installs the BBM (self-monitotoring and observability) kpt package from ./nok-kpt/nok-bbm
.PHONY: install-bbm-pkg
install-bbm-pkg:
	@echo "--> INSTALL: [\033[1;34mBBM\033[0m] - Applying kpt package with setters"
	@$(call INSTALL_KPT_PACKAGE_WITH_SETTERS,$(NOK_KPT_DIR)/nok-bbm,nok-bbm,"--reconcile-timeout=5m", "--inventory-policy=adopt")

.PHONY: install-mcp-bng-pkg
install-mcp-bng-pkg: ## check-tools git-clone-kpt install-base-pkg install-lb-pkg ## Installs the MCP controller kpt package from ./nok-kpt/nok-base-mcp-bng
	@echo -e "--> INSTALL: [\033[1;34mMCP BNG\033[0m] - Checking prerequisites..."
	@if ! $(KUBECTL) version --client &>/dev/null; then \
		echo "[ERROR]: kubectl is not working or not configured. Please ensure your kubeconfig is set." >&2; \
		exit 1; \
	fi
	@if [ ! -f "$(NOK_KPT_DIR)/nok-base-mcp-bng/Kptfile" ]; then \
		echo "[ERROR]: MCP BNG kpt package not found at $(NOK_KPT_DIR)/nok-base-mcp-bng" >&2; \
		exit 1; \
	fi
	@$(call INSTALL_KPT_PACKAGE_WITH_SETTERS,$(NOK_KPT_DIR)/nok-base-mcp-bng,nok-base-mcp-bng,"--reconcile-timeout=5m", "--inventory-policy=adopt")


.PHONY: install-prom-oper
install-prom-oper: $(KUBECTL) ## Installs the Prometheus Operator manifest
	@echo -e "--> INSTALL: [\033[1;34mPrometheus Operator\033[0m] - Checking prerequisites..."
	@if ! $(KUBECTL) version --client &>/dev/null; then \
		echo "[ERROR]: kubectl is not working or not configured. Please ensure your kubeconfig is set." >&2; \
		exit 1; \
	fi
	@if [ ! -f "./nok-kpt/nok-base-prometheus-oper/manifest-prometheus-oper.yaml" ]; then \
		echo "[ERROR]: Prometheus Operator manifest not found at ./nok-kpt/nok-base-prometheus-oper/manifest-prometheus-oper.yaml" >&2; \
		exit 1; \
	fi
	@echo -e "--> INSTALL: [\033[1;34mPrometheus Operator\033[0m] - Applying manifest..."
	@$(KUBECTL) apply --server-side -f ./nok-kpt/nok-base-prometheus-oper/manifest-prometheus-oper.yaml
	@echo -e "--> INSTALL: [\033[0;32mPrometheus Operator\033[0m] - Manifest applied successfully."

.PHONY: install-gnmic-oper
install-gnmic-oper: $(KUBECTL) ## Installs the GNMIc Operator manifest
	@echo -e "--> INSTALL: [\033[1;34mGNMIc Operator\033[0m] - Checking prerequisites..."
	@if ! $(KUBECTL) version --client &>/dev/null; then \
		echo "[ERROR]: kubectl is not working or not configured. Please ensure your kubeconfig is set." >&2; \
		exit 1; \
	fi
	@if [ ! -f "./nok-kpt/nok-base-gnmic-oper/install.yaml" ]; then \
		echo "[ERROR]: GNMIc Operator manifest not found at ./nok-kpt/nok-base-gnmic-oper/install.yaml" >&2; \
		exit 1; \
	fi
	@echo -e "--> INSTALL: [\033[1;34mGNMIc Operator\033[0m] - Applying manifest..."
	@$(KUBECTL) create -f ./nok-kpt/nok-base-gnmic-oper/install.yaml
	@echo -e "--> INSTALL: [\033[0;32mGNMIc Operator\033[0m] - Manifest applied successfully."

.PHONY: gitea-create-admin
gitea-create-admin:
	@echo "--> GITEA: Ensuring admin user exists"
	@POD="$(call GET_GITEA_POD)" ;\
	if [ -z "$$POD" ]; then \
		echo "[ERROR] Gitea pod not found" ; exit 1 ;\
	fi ;\
	if $(KUBECTL) exec -n $(GITOPS_NAMESPACE) $$POD -- \
	     curl -sf http://localhost:3000/api/v1/users/$(GITEA_ADMIN_USER) >/dev/null; then \
		echo "--> GITEA: User $(GITEA_ADMIN_USER) already exists, skipping"; \
	else \
		echo "--> GITEA: Creating admin user $(GITEA_ADMIN_USER)"; \
		$(KUBECTL) exec -n $(GITOPS_NAMESPACE) $$POD -- \
		  gitea admin user create \
		    --username $(GITEA_ADMIN_USER) \
		    --password "$(GITEA_ADMIN_PASS)" \
		    --email "$(GITEA_ADMIN_EMAIL)" \
		    --must-change-password=false ;\
	fi

.PHONY: gitea-create-flux-repo
gitea-create-flux-repo:
	@echo "--> GITEA: Waiting for API to become available (max 3 minutes)"
	@set -e; \
	timeout=180; \
	while [ $$timeout -gt 0 ]; do \
		if $(CURL) --silent --fail \
			--resolve $(GITEA_HOST):80:$(GITEA_IP) \
			-u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
			http://$(GITEA_HOST)$(GITEA_HTTP_PATH)/api/v1/user/repos \
			>/dev/null; then \
			echo "--> GITEA: API is available"; \
			break; \
		fi; \
		timeout=$$((timeout - 5)); \
		sleep 5; \
	done; \
	if [ $$timeout -le 0 ]; then \
		echo "ERROR: Gitea API not available after 3 minutes"; \
		exit 1; \
	fi

	@echo "--> GITEA: Ensuring repo $(FLUX_GIT_REPO) exists"
	@$(CURL) --silent --fail \
	  --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  http://$(GITEA_HOST)$(GITEA_HTTP_PATH)/api/v1/repos/$(GITEA_ADMIN_USER)/$(FLUX_GIT_REPO) \
	  >/dev/null || \
	$(CURL) --silent --fail \
	  --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -X POST \
	  -H "Content-Type: application/json" \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  -d '{"name":"$(FLUX_GIT_REPO)","private":false,"auto_init":true}' \
	  http://$(GITEA_HOST)$(GITEA_HTTP_PATH)/api/v1/user/repos


.PHONY: gitea-add-ssh-key
gitea-add-ssh-key:
	@set -e; \
	echo "--> GITEA: Ensuring SSH key is registered"; \
	\
	if [ ! -f "$(FLUX_SSH_KEY).pub" ]; then \
		echo "--> GITEA: SSH key not found, generating new ed25519 key at $(FLUX_SSH_KEY)"; \
		ssh-keygen -t ed25519 -f "$(FLUX_SSH_KEY)" -N "" -q; \
	else \
		echo "--> GITEA: SSH key found at $(FLUX_SSH_KEY).pub"; \
	fi; \
	\
	if ssh-keygen -F "$(GITEA_SSH_HOST)" >/dev/null 2>&1; then \
		echo "--> GITEA: Removing $(GITEA_SSH_HOST) from ~/.ssh/known_hosts"; \
		ssh-keygen -R "$(GITEA_SSH_HOST)" >/dev/null; \
	else \
		echo "--> GITEA: $(GITEA_SSH_HOST) not found in ~/.ssh/known_hosts, skipping removal"; \
	fi; \
	\
	SSH_KEY="$$(cat $(FLUX_SSH_KEY).pub)"; \
	echo "--> SSH: Using Public Key: $$SSH_KEY"; \
	if $(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	     -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	     http://$(GITEA_HOST)$(GITEA_HTTP_PATH)/api/v1/user/keys | \
	     jq -r '.[].key' | grep -Fxq "$$SSH_KEY"; then \
		echo "--> GITEA: SSH key already registered, skipping"; \
	else \
		echo "--> GITEA: Registering SSH key"; \
		$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) -X POST \
		  -H "Content-Type: application/json" \
		  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
		  -d "{\"title\":\"flux ssh key\",\"key\":\"$$SSH_KEY\"}" \
		  http://$(GITEA_HOST)$(GITEA_HTTP_PATH)/api/v1/user/keys; \
	fi; \
	\
	echo "--> GITEA: Ensuring $(GITEA_SSH_HOST) is in ~/.ssh/known_hosts"; \
	if ! ssh-keygen -F "$(GITEA_SSH_HOST)" >/dev/null 2>&1; then \
		ssh-keyscan -H "$(GITEA_SSH_HOST)" >> ~/.ssh/known_hosts 2>/dev/null; \
	fi; \
	\
	echo "--> GITEA: Verifying SSH authentication (non-fatal)"; \
	ssh -T -i "$(FLUX_SSH_KEY)" -o BatchMode=yes -o ConnectTimeout=5 git@"$(GITEA_SSH_HOST)" || true

.PHONY: flux-bootstrap
flux-bootstrap: check-tools gitea-create-admin gitea-create-flux-repo gitea-add-ssh-key
	@echo "--> GITEA: Ensuring repository $(FLUX_GIT_REPO) exists"
	@$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  http://$(GITEA_HOST)$(GITEA_HTTP_PATH)/api/v1/repos/$(GITEA_ADMIN_USER)/$(FLUX_GIT_REPO) \
	  >/dev/null || \
	@echo "--> FLUX: Bootstrapping cluster"

	@echo "--> SSH: Loading key into agent (prompts once if passphrase-protected)"
	@SSH_KEY="$$(cat "$(FLUX_SSH_KEY).pub")"; \
	echo "--> SSH: Using Public Key: $$SSH_KEY";

	@$(FLUX) check --pre

	@$(FLUX) bootstrap git \
	  --url=ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_GIT_REPO).git \
	  --branch=$(FLUX_GIT_BRANCH) \
	  --path=$(FLUX_CLUSTER_PATH) \
	  --private-key-file=$(FLUX_SSH_KEY) \
	  --ssh-key-algorithm=ed25519 \
	  --silent \
	  --verbose  

.PHONY: set-proxy-env
set-proxy-env:
	@echo "--> PROXY: Applying proxy env to deployments"
	@for item in $(PROXY_DEPLOYMENTS); do \
		NS=$$(echo $$item | cut -d: -f1); \
		DEP=$$(echo $$item | cut -d: -f2); \
		\
		if ! $(KUBECTL) get deployment $$DEP -n $$NS >/dev/null 2>&1; then \
			echo "--> Skipping $$DEP (not found in namespace $$NS)"; \
			continue; \
		fi; \
		\
		echo "Updating $$DEP in namespace $$NS"; \
		$(KUBECTL) set env deployment $$DEP \
			HTTP_PROXY="$(HTTP_PROXY)" \
			HTTPS_PROXY="$(HTTPS_PROXY)" \
			NO_PROXY="$(NO_PROXY)" \
			http_proxy="$(HTTP_PROXY)" \
			https_proxy="$(HTTPS_PROXY)" \
			no_proxy="$(NO_PROXY)" \
			-n $$NS --overwrite; \
		\
		echo "--> Restarting $$DEP"; \
		$(KUBECTL) rollout restart deployment $$DEP -n $$NS; \
		\
		echo "--> Waiting for rollout to complete"; \
		$(KUBECTL) rollout status deployment $$DEP -n $$NS --timeout=120s; \
	done


.PHONY: unset-proxy-env
unset-proxy-env:
	@echo "--> PROXY: Removing proxy env from deployments"
	@for item in $(PROXY_DEPLOYMENTS); do \
		NS=$$(echo $$item | cut -d: -f1); \
		DEP=$$(echo $$item | cut -d: -f2); \
		echo "Cleaning $$DEP in namespace $$NS"; \
		$(KUBECTL) set env deployment $$DEP \
			HTTP_PROXY- HTTPS_PROXY- NO_PROXY- \
			http_proxy- https_proxy- no_proxy- \
			-n $$NS; \
		echo "Rolling out restart for $$DEP"; \
		$(KUBECTL) rollout restart deployment $$DEP -n $$NS; \
	done


.PHONY: backup-deployments
backup-deployments:
	@mkdir -p backup
	@for item in $(PROXY_DEPLOYMENTS); do \
		NS=$$(echo $$item | cut -d: -f1); \
		DEP=$$(echo $$item | cut -d: -f2); \
		$(KUBECTL) get deployment $$DEP -n $$NS -o yaml > backup/$$NS-$$DEP.yaml; \
	done