# --- Configuration Variables ---
KIND_CLUSTER_NAME ?= nok-demo
KIND_CONFIG_REAL_LOC ?= build/kind-cluster.yaml
KIND_LAUNCH_CONFIG ?= /tmp/kind-config-$(KIND_CLUSTER_NAME).yaml

# Optional: Set API server address if you need to access it from outside Docker
# KIND_API_SERVER_ADDRESS ?= 127.0.0.1

# Optional: Set to 'yes' to disable host port mappings, otherwise 'no'
NO_HOST_PORT_MAPPINGS ?= no
EXT_HTTPS_PORT ?= 5443 # Port to map for external HTTPS access if NO_HOST_PORT_MAPPINGS is 'no'

# --- Tool Paths (assume they are in PATH by default) ---
KIND ?= kind
KUBECTL ?= kubectl
YQ ?= yq

# Internal helper for output indentation
INDENT_OUT ?= sed 's/^/    /'

# --- Phony Targets ---
.PHONY: all
all: kind ## Default target: Create and wait for the KinD cluster

.PHONY: kind
kind: check-tools cluster cluster-wait-for-node-ready ## Launch a single node KinD cluster (K8S inside Docker)

.PHONY: cluster
cluster: $(KIND_CONFIG_REAL_LOC) ## Create the KinD cluster if it doesn't exist
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

.PHONY: cluster-wait-for-node-ready
cluster-wait-for-node-ready: ## Wait for the Kubernetes control plane node to be ready
	@echo "--> KIND: Waiting for k8s node to be ready"
	@{ \
		START=$$(date +%s) ;\
		$(KUBECTL) wait --for=condition=Ready node/$(KIND_CLUSTER_NAME)-control-plane --timeout=300s ;\
		echo "--> KIND: Node ready check took $$(( $$(date +%s) - $$START ))s" ;\
	}

.PHONY: delete-cluster
delete-cluster: ## Delete the KinD cluster
	@echo "--> KIND: Deleting cluster $(KIND_CLUSTER_NAME)..."
	@$(KIND) delete cluster --name $(KIND_CLUSTER_NAME) || true
	@rm -f $(KIND_LAUNCH_CONFIG)

.PHONY: check-tools
check-tools: ## Check if required tools (kind, kubectl, yq) are installed
	@echo "--> Checking for required tools..."
	@command -v $(KIND) >/dev/null 2>&1 || { echo >&2 "Error: $(KIND) is not installed. Please install it (https://kind.sigs.k8s.io/docs/user/quick-start/#installation)."; exit 1; }
	@command -v $(KUBECTL) >/dev/null 2>&1 || { echo >&2 "Error: $(KUBECTL) is not installed. Please install it (https://kubernetes.io/docs/tasks/tools/install-kubectl/)."; exit 1; }
	@command -v $(YQ) >/dev/null 2>&1 || { echo >&2 "Error: $(YQ) is not installed. Please install it (https://mikefarah.gitbook.io/yq/#install)."; exit 1; }
	@echo "--> All required tools found."

.PHONY: help
help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

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