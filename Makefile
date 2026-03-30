# --- Configuration Variables ---
SHELL := /bin/bash
BASE ?= $(shell pwd)
# i.e Darwin / Linux
UNAME := $(shell uname)
# Lowercase - sane version
OS := $(shell echo "$(UNAME)" | tr '[:upper:]' '[:lower:]')

ARCH_QUERY := $(shell uname -m)
ifeq ($(ARCH_QUERY), x86_64)
	ARCH := amd64
else ifeq ($(ARCH_QUERY),$(filter $(ARCH_QUERY), arm64 aarch64))
	ARCH := arm64
else
	ARCH := $(ARCH_QUERY)
endif


KIND_CLUSTER_NAME ?= nok-demo
KIND_CONFIG_REAL_LOC ?= build/kind-cluster.yaml
KIND_LAUNCH_CONFIG ?= /tmp/kind-config-$(KIND_CLUSTER_NAME).yaml

# Optional: Set API server address if you need to access it from outside Docker
# KIND_API_SERVER_ADDRESS ?= 127.0.0.1

# Optional: Set to 'yes' to disable host port mappings, otherwise 'no'
NO_HOST_PORT_MAPPINGS ?= no
EXT_HTTPS_PORT ?= 5443 # Port to map for external HTTPS access if NO_HOST_PORT_MAPPINGS is 'no'

# --- Tool Paths (now managed by Makefile) ---
TOOLS ?= $(BASE)/tools
KIND ?= $(TOOLS)/kind
KUBECTL ?= $(TOOLS)/kubectl
YQ ?= $(TOOLS)/yq
HELM ?= $(TOOLS)/helm
KPT ?= $(TOOLS)/kpt
K9S ?= $(TOOLS)/k9s
GH ?= $(TOOLS)/gh
CLAB ?= $(TOOLS)/clab
FLUX ?= $(TOOLS)/flux


# Optional proxy settings for docker build
HTTP_PROXY ?=
HTTPS_PROXY ?=
NO_PROXY ?= localhost,127.0.0.1,.cluster.local,10.0.0.0/8

# --- Git Repository Configuration ---
SRLINUX_IMAGE ?= registry.srlinux.dev/pub/nokia_srsim:25.10.R1
SRSIM_LICENSE_FILE ?= $(NOK_CLABS_DIR)/nok-bng/srsim-lic-25.txt

NOK_KPT_DIR ?= $(BASE)/nok-kpt
KPT_REPO_URL ?= -b mau-nanog97 https://github.com/CSPDevLabs/kpt

NOK_CLABS_DIR ?= $(BASE)/nok-clabs
CLABS_REPO_URL ?= https://github.com/CSPDevLabs/nok-clabs

# Internal helper for output indentation
INDENT_OUT ?= sed 's/^/    /'
### Curl options:
CURL := curl --silent --fail --show-error

## Tools versions
### ---------------------------------------------------------------------------|
GH_VERSION ?= 2.67.0
HELM_VERSION ?= v3.17.0
KIND_VERSION ?= v0.29.0
KPT_VERSION ?= v1.0.0-beta.57
KUBECTL_VERSION ?= v1.33.1
K9S_VERSION ?= v0.32.4
YQ_VERSION ?= v4.42.1
CLAB_VERSION ?= 0.72.0
FLUX_VERSION ?= 2.3.0

### Tool Locations
### ---------------------------------------------------------------------------|
KIND_SRC ?= https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-$(OS)-$(ARCH)
KUBECTL_SRC ?= https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl
HELM_SRC ?= https://get.helm.sh/helm-$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz
KPT_SRC ?= https://github.com/GoogleContainerTools/kpt/releases/download/$(KPT_VERSION)/kpt_$(OS)_$(ARCH)
K9S_SRC ?= https://github.com/derailed/k9s/releases/download/$(K9S_VERSION)/k9s_$(UNAME)_$(ARCH).tar.gz
YQ_SRC ?= https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH)
CLAB_SRC ?= https://github.com/srl-labs/containerlab/releases/download/v$(CLAB_VERSION)/containerlab_$(CLAB_VERSION)_$(OS)_$(ARCH).tar.gz
FLUX_SRC ?= https://github.com/fluxcd/flux2/releases/download/v$(FLUX_VERSION)/flux_$(FLUX_VERSION)_$(OS)_$(ARCH).tar.gz

# GH_SRC needs special handling for OS/ARCH mapping
ifeq ($(OS),darwin)
    GH_OS_ARCH := macOS_$(ARCH)
    GH_EXT := zip
else
    GH_OS_ARCH := $(OS)_$(ARCH)
    GH_EXT := tar.gz
endif
GH_SRC ?= https://github.com/cli/cli/releases/download/v$(GH_VERSION)/gh_$(GH_VERSION)_$(GH_OS_ARCH).$(GH_EXT)

DOWNLOAD_TOOLS_LIST := $(KIND) $(KUBECTL) $(HELM) $(KPT) $(K9S) $(YQ) $(GH) $(CLAB) $(FLUX)

# --- Flux & Gitea GitOps Configuration ---
GITOPS_NAMESPACE ?= nok-git
GITEA_HOST ?= gitea.nok.local
GITEA_IP ?= 172.19.0.100
GITEA_SSH_HOST ?= 172.19.0.102
GITEA_ADMIN_USER ?= nok
GITEA_ADMIN_PASS ?= N0kP4ssw0rd
GITEA_ADMIN_EMAIL ?= nok@example.com

FLUX_GIT_REPO ?= flux-bootstrap
FLUX_BNG_REPO ?= nok-bng-resources
FLUX_BNG_SECRET ?= nok-bng-auth
FLUX_GIT_BRANCH ?= main
FLUX_CLUSTER_PATH ?= clusters/NetOpsKube
FLUX_SSH_KEY ?= $(HOME)/.ssh/flux_ed25519

BNG_MANIFESTS_DIR := ./nok-clabs/nok-bng/nok-manifests
BNG_REPO_URL := ssh://git@$(GITEA_SSH_HOST)/$(GITEA_ADMIN_USER)/$(FLUX_BNG_REPO).git

define GET_GITEA_POD
$(shell $(KUBECTL) get pods -n $(GITOPS_NAMESPACE) \
  -l app.kubernetes.io/name=gitea \
  -o jsonpath='{.items[0].metadata.name}')
endef

# --- Macros for tool downloading ---
define download-bin
    $(info --> INFO: Downloading $(2))
	if test ! -f $(1); then $(CURL) -Lo $(1) $(2) >/dev/null && chmod a+x $(1); fi
endef

define download-bin-from-archive
	$(info --> INFO: Downloading $(2))
	if test ! -f $(1); then $(CURL) -L --output - $(2) | tar -x$(5) $(if $(6),--strip-components $(6)) -C $(3) $(4) >/dev/null && chmod a+x $(1); fi
endef

KPT_LIVE_INIT_FORCE ?= 0 # Set to 1 to force re-initialization of kpt packages

define INSTALL_KPT_PACKAGE
	{	\
		echo -e "--> INSTALL: [\033[1;34m$2\033[0m] - Applying kpt package"									;\
		pushd $1 &>/dev/null || (echo "[ERROR]: Failed to switch cwd to $2" && exit 1)						;\
		if [[ ! -f resourcegroup.yaml ]] || [[ $(KPT_LIVE_INIT_FORCE) -eq 1 ]]; then						 \
			$(KPT) live init --force 2>&1 | $(INDENT_OUT)													;\
		else																								 \
			echo -e "--> INSTALL: [\033[1;34m$2\033[0m] - Resource group found, don't re-init this package"	;\
		fi																									;\
		$(KPT) live apply $3 $4 2>&1 | $(INDENT_OUT)                                                   		;\
		popd &>/dev/null || (echo "[ERROR]: Failed to switch back from $2" && exit 1)						;\
		echo -e "--> INSTALL: [\033[0;32m$2\033[0m] - Applied and reconciled package"						;\
	}
endef

# The same as INSTALL_KPT_PACKAGE, but also runs kpt fn render to apply setters.
define INSTALL_KPT_PACKAGE_WITH_SETTERS
	{	\
		echo -e "--> INSTALL: [\033[1;34m$2\033[0m] - Applying kpt package"									;\
		pushd $1 &>/dev/null || (echo "[ERROR]: Failed to switch cwd to $2" && exit 1)						;\
		if [[ ! -f resourcegroup.yaml ]] || [[ $(KPT_LIVE_INIT_FORCE) -eq 1 ]]; then						 \
			$(KPT) live init --force 2>&1 | $(INDENT_OUT)													;\
		else																								 \
			echo -e "--> INSTALL: [\033[1;34m$2\033[0m] - Resource group found, don't re-init this package"	;\
		fi																									;\
		$(KPT) fn render 2>&1 | $(INDENT_OUT)																;\
		$(KPT) live apply $3 $4 2>&1 | $(INDENT_OUT)                                                   		;\
		popd &>/dev/null || (echo "[ERROR]: Failed to switch back from $2" && exit 1)						;\
		echo -e "--> INSTALL: [\033[0;32m$2\033[0m] - Applied and reconciled package"						;\
	}
endef

.PHONY: try-nok
try-nok: check-tools cluster-up git-clone-kpt git-clone-clab install-base-pkg install-lb-pkg install-prom-oper install-gnmic-oper start-ingress-port-forward install-bbm-pkg ## Deploy Base Apps, clone kpt and clab repos, install base packages / load balancer / prometheus and gnmic operators, port forward

.PHONY: try-nok-bng
try-nok-bng: try-nok install-bng-pkg install-git-pkg configure-auth configure-auth-ingress gitops-init gitops-bng-kustomization install-bbm-pkg ## Deploy BNG and GitOps

.PHONY: gitops-init
gitops-init: gitea-create-admin gitea-create-flux-repo gitea-add-ssh-key  flux-bootstrap ## Create Gitea admin, create Flux repo, add SSH key, bootstrap Flux
	@echo "--> GITOPS: Cluster is now managed by Flux"

.PHONY: gitops-bng-kustomization
gitops-bng-kustomization: gitea-create-bng-repo flux-create-bng-secret flux-create-bng-source push-bng-manifests create-bng-kustomizations
	@echo "--> GITOPS: BNG repo in sync by Flux"

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
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

# --- Tool Download Rules ---
$(KIND): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring kind is present in $(KIND))
	@$(call download-bin,$(KIND),$(KIND_SRC))

$(KUBECTL): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring kubectl is present in $(KUBECTL))
	@$(call download-bin,$(KUBECTL),$(KUBECTL_SRC))

$(HELM): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring helm is present in $(HELM))
	@$(call download-bin-from-archive,$(HELM),$(HELM_SRC),$(TOOLS),$(OS)-$(ARCH)/helm,z,1)

$(KPT): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring kpt is present in $(KPT))
	@$(call download-bin,$(KPT),$(KPT_SRC))

$(K9S): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring k9s is present in $(K9S))
	@$(call download-bin-from-archive,$(K9S),$(K9S_SRC),$(TOOLS),k9s,z)

$(YQ): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring yq is present in $(YQ))
	@$(call download-bin,$(YQ),$(YQ_SRC))

$(GH): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring gh is present in $(GH))
	@$(call download-bin-from-archive,$(GH),$(GH_SRC),$(TOOLS),gh_$(GH_VERSION)_$(GH_OS_ARCH)/bin/gh,z,2)

$(CLAB): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring containerlab is present in $(CLAB))
	@if test ! -f $(CLAB); then \
		echo "    Downloading $(CLAB_SRC)..." ;\
		TEMP_DIR=$$(mktemp -d) ;\
		$(CURL) -L --output - $(CLAB_SRC) | tar -xz -C $$TEMP_DIR >/dev/null ;\
		mv $$TEMP_DIR/containerlab $(CLAB) ;\
		chmod a+x $(CLAB) ;\
		rm -rf $$TEMP_DIR ;\
	fi
$(FLUX): | $(BASE) $(TOOLS) ; $(info --> TOOLS: Ensuring flux is present in $(FLUX))
	@if test ! -f $(FLUX); then \
		echo "    Downloading $(FLUX_SRC)..." ;\
		TEMP_DIR=$$(mktemp -d) ;\
		$(CURL) -L --output - $(FLUX_SRC) | tar -xz -C $$TEMP_DIR >/dev/null ;\
		mv $$TEMP_DIR/flux $(FLUX) ;\
		chmod a+x $(FLUX) ;\
		rm -rf $$TEMP_DIR ;\
	fi	

# --- Git Clone Targets ---
.PHONY: git-clone-kpt
git-clone-kpt: ## Clones the CSPDevLabs/kpt repository into ./nok-kpt
	@echo "--> GIT: Cloning $(KPT_REPO_URL) into $(NOK_KPT_DIR)"
	@if [ ! -d "$(NOK_KPT_DIR)" ]; then \
		git clone $(KPT_REPO_URL) $(NOK_KPT_DIR) ;\
	else \
		echo "--> GIT: $(NOK_KPT_DIR) already exists. Skipping clone." ;\
	fi

.PHONY: git-clone-clab
git-clone-clab: ## Clones the CSPDevLabs/nok-clabs repository into ./nok-clabs
	@echo "--> GIT: Cloning $(CLABS_REPO_URL) into $(NOK_CLABS_DIR)"
	@if [ ! -d "$(NOK_CLABS_DIR)" ]; then \
		git clone $(CLABS_REPO_URL) $(NOK_CLABS_DIR) ;\
	else \
		echo "--> GIT: $(NOK_CLABS_DIR) already exists. Skipping clone." ;\
	fi

.PHONY: check-clab-prerequisites
check-clab-prerequisites: ## Checks for required Docker image and SROS license file for Containerlab BNG
	@echo "--> CLAB: Checking prerequisites for BNG deployment..."
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

.PHONY: install-base-pkg
install-base-pkg: ## Installs the base kpt package from ./nok-kpt/nok-base
	@$(call INSTALL_KPT_PACKAGE,$(NOK_KPT_DIR)/nok-base,nok-base,"--reconcile-timeout=5m", "--inventory-policy=adopt")	

.PHONY: install-bbm-pkg
install-bbm-pkg: ## Installs the BBM (self-monitotoring and observability) kpt package from ./nok-kpt/nok-bbm
	@echo "--> INSTALL: [\033[1;34mBBM\033[0m] - Applying kpt package with setters"
	@$(call INSTALL_KPT_PACKAGE_WITH_SETTERS,$(NOK_KPT_DIR)/nok-bbm,nok-bbm,"--reconcile-timeout=5m", "--inventory-policy=adopt")	

.PHONY: wait-for-metallb-ready
wait-for-metallb-ready: ## Wait for the Kubernetes Metallb node to be ready
	@echo "--> KIND: Waiting for Metallb Controller to be ready"
	@{ \
		START=$$(date +%s) ; \
		$(KUBECTL) wait --for=condition=available deployment/controller -n metallb-system --timeout=5m --timeout=5m ; \
		echo "--> KIND: Node ready check took $$(( $$(date +%s) - $$START ))s" ; \
	}

.PHONY: install-lb-pkg
install-lb-pkg: check-tools git-clone-kpt install-base-pkg wait-for-metallb-ready ## Installs the base kpt package from ./nok-kpt/nok-lb
	@$(call INSTALL_KPT_PACKAGE,$(NOK_KPT_DIR)/nok-lb,nok-lb,"--reconcile-timeout=5m", "")		

.PHONY: install-bng-pkg
install-bng-pkg: check-tools git-clone-kpt install-base-pkg install-lb-pkg ## Installs the base kpt package from ./nok-kpt/nok-bng
	@$(call INSTALL_KPT_PACKAGE,$(NOK_KPT_DIR)/nok-bng,nok-bng,"--reconcile-timeout=5m", "--inventory-policy=adopt")		

.PHONY: install-git-pkg
install-git-pkg: check-tools git-clone-kpt install-base-pkg install-lb-pkg ## Installs the base kpt package from ./nok-kpt/nok-bng
	@$(call INSTALL_KPT_PACKAGE,$(NOK_KPT_DIR)/nok-git,nok-git,"--reconcile-timeout=5m", "--inventory-policy=adopt")	


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
	@$(KUBECTL) create -f ./nok-kpt/nok-base-prometheus-oper/manifest-prometheus-oper.yaml
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
			http://$(GITEA_HOST)/api/v1/user/repos \
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
	  http://$(GITEA_HOST)/api/v1/repos/$(GITEA_ADMIN_USER)/$(FLUX_GIT_REPO) \
	  >/dev/null || \
	$(CURL) --silent --fail \
	  --resolve $(GITEA_HOST):80:$(GITEA_IP) \
	  -X POST \
	  -H "Content-Type: application/json" \
	  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
	  -d '{"name":"$(FLUX_GIT_REPO)","private":false,"auto_init":true}' \
	  http://$(GITEA_HOST)/api/v1/user/repos


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
	     http://$(GITEA_HOST)/api/v1/user/keys | \
	     jq -r '.[].key' | grep -Fxq "$$SSH_KEY"; then \
		echo "--> GITEA: SSH key already registered, skipping"; \
	else \
		echo "--> GITEA: Registering SSH key"; \
		$(CURL) --resolve $(GITEA_HOST):80:$(GITEA_IP) -X POST \
		  -H "Content-Type: application/json" \
		  -u "$(GITEA_ADMIN_USER):$(GITEA_ADMIN_PASS)" \
		  -d "{\"title\":\"flux ssh key\",\"key\":\"$$SSH_KEY\"}" \
		  http://$(GITEA_HOST)/api/v1/user/keys; \
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
	  http://$(GITEA_HOST)/api/v1/repos/$(GITEA_ADMIN_USER)/$(FLUX_GIT_REPO) \
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
			git config --global user.email "nok@example.com" && \
			git config --global user.name "nok" && \
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
			if $(FLUX) get kustomization "$$n" -n flux-system 2>&1 | grep -q "not found"; then \
				echo "Creating Kustomization for $$n..."; \
				$(FLUX) create kustomization "$$n" \
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

PORTAL_DIR ?= $(NOK_KPT_DIR)/nok-bng/portal

.PHONY: configure-auth
configure-auth:
	@echo "--> AUTH: Building flask-auth-service image"
	@$(KUBECTL) apply -f $(PORTAL_DIR)/portal-auth-secret.yaml
	@BUILD_ARGS=""
	@if [ -n "$(HTTP_PROXY)" ]; then BUILD_ARGS="$$BUILD_ARGS --build-arg HTTP_PROXY=$(HTTP_PROXY)"; fi; \
	if [ -n "$(HTTPS_PROXY)" ]; then BUILD_ARGS="$$BUILD_ARGS --build-arg HTTPS_PROXY=$(HTTPS_PROXY)"; fi; \
	if [ -n "$(NO_PROXY)" ]; then BUILD_ARGS="$$BUILD_ARGS --build-arg NO_PROXY=$(NO_PROXY)"; fi; \
	cd $(PORTAL_DIR) && docker build $$BUILD_ARGS -t flask-auth-service .

	@echo "--> AUTH: Loading image into Kind cluster"
	@$(KIND) load docker-image flask-auth-service --name $(KIND_CLUSTER_NAME)

	@echo "--> AUTH: Applying Kubernetes manifests"
	@$(KUBECTL) apply -f $(PORTAL_DIR)/portal-auth-svc.yaml
	@$(KUBECTL) apply -f $(PORTAL_DIR)/portal-auth-deploy.yaml
	@$(KUBECTL) apply -f $(PORTAL_DIR)/portal-ingress.yaml

	@echo "--> AUTH: Deployment completed"

AUTH_SIGNIN ?= http://bng.nok.local:8080/login?rd=$$$$request_uri
AUTH_URL ?= http://portal-auth.nok-bng.svc.cluster.local/auth

.PHONY: configure-auth-ingress
configure-auth-ingress: ## Add authentication annotations to ingresses

	@echo "--> AUTH: Adding auth annotations to nok-apps-ingress"
	@$(KUBECTL) annotate ingress nok-apps-ingress \
	-n nok-bng \
	nginx.ingress.kubernetes.io/auth-signin="$(AUTH_SIGNIN)" \
	nginx.ingress.kubernetes.io/auth-url="$(AUTH_URL)" \
	--overwrite

	@echo "--> AUTH: Adding auth annotations to nok-apps-portal-ingress"
	@$(KUBECTL) annotate ingress nok-apps-portal-ingress \
	-n nok-bng \
	nginx.ingress.kubernetes.io/auth-signin="$(AUTH_SIGNIN)" \
	nginx.ingress.kubernetes.io/auth-url="$(AUTH_URL)" \
	--overwrite

	@echo "--> AUTH: Ingress authentication annotations applied"
