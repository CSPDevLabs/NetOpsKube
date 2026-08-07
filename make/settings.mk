# ==============================================================================
# settings.mk
#
# Global configuration for the NetOpsKube Makefile.
#
# This file contains shared variables, tool versions, repository locations,
# proxy configuration, OS detection, download URLs, GitOps settings, and
# reusable helper macros used by all solution-specific Makefiles (base, BNG,
# DIA, authentication, etc.).
#
# Most users only need to modify configuration variables (cluster name, proxy,
# repository locations, or tool versions). The remaining macros and helper
# functions are intended for internal Makefile use.
# ==============================================================================


# --- Configuration Variables ---
BASE ?= $(shell pwd)
# i.e Darwin / Linux
UNAME := $(shell uname)
# Lowercase - sane version
OS := $(shell echo "$(UNAME)" | tr '[:upper:]' '[:lower:]')

# Force bash on supported platforms only: macOS (Darwin), Ubuntu LTS, Rocky Linux.
# Other systems keep Make's default SHELL (/bin/sh) to avoid silent assumptions!
# Tested on Rocky Linux 9.7 and Ubuntu 24.04.4 LTS
DISTRO_ID := $(shell . /etc/os-release 2>/dev/null && echo $$ID)
ifeq ($(UNAME),Darwin)
SHELL := /bin/bash
else ifeq ($(DISTRO_ID),ubuntu)
SHELL := /bin/bash
else ifeq ($(DISTRO_ID),rocky)
SHELL := /bin/bash
endif

ARCH_QUERY := $(shell uname -m)
ifeq ($(ARCH_QUERY), x86_64)
	ARCH := amd64
else ifeq ($(ARCH_QUERY),$(filter $(ARCH_QUERY), arm64 aarch64))
	ARCH := arm64
else
	ARCH := $(ARCH_QUERY)
endif


# --- Proxy Settings ---
# Make sure environment variables are set before using them `export HTTP_PROXY=...`
# Proxy settings: inherited from the shell. Set HTTP_PROXY / HTTPS_PROXY /
# NO_PROXY in your environment before running the Makefile.
export HTTP_PROXY ?=
export HTTPS_PROXY ?=
# NO_PROXY_LOOPBACK := 127.0.0.1,localhost,::1
# NO_PROXY_RFC1918  := 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16
# NO_PROXY_SUFFIXES := .nok.local,.svc,.svc.cluster.local
# NO_PROXY_SHORT    := gitea.nok.local,bbm-grafana-svc,bbm-grafana-svc.nok-bbm,bbm-grafana-svc.nok-bbm.svc,bbm-grafana-svc.nok-bbm.svc.cluster.local,bbm-prometheus-svc,bbm-prometheus-svc.nok-bbm,bbm-prometheus-svc.nok-bbm.svc,bbm-prometheus-svc.nok-bbm.svc.cluster.local
# NO_PROXY := $(NO_PROXY_LOOPBACK),$(NO_PROXY_RFC1918),$(NO_PROXY_SUFFIXES),$(NO_PROXY_SHORT)
export NO_PROXY := 127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16,gitea.nok.local,.nok.local,.svc,.svc.cluster.local,bbm-grafana-svc,bbm-grafana-svc.nok-bbm,bbm-grafana-svc.nok-bbm.svc,bbm-grafana-svc.nok-bbm.svc.cluster.local,bbm-prometheus-svc,bbm-prometheus-svc.nok-bbm,bbm-prometheus-svc.nok-bbm.svc,bbm-prometheus-svc.nok-bbm.svc.cluster.local,bng.nok.local


KIND_CLUSTER_NAME ?= nok-demo
KIND_CONFIG_REAL_LOC ?= build/kind-cluster.yaml
KIND_LAUNCH_CONFIG ?= /tmp/kind-config-$(KIND_CLUSTER_NAME).yaml

# KinD Docker network prefix (e.g. 172.18.0). LB IPs are written into nok-kpt
# apply-setters.yaml before package install (CSPDevLabs/kpt#27).
KIND_LB_DEFAULT_PREFIX ?= 172.18.0
KIND_NET_PREFIX = $(shell docker inspect \
	-f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
	$(KIND_CLUSTER_NAME)-control-plane 2>/dev/null | \
	awk -F. '{print $$1 "." $$2 "." $$3}')

# Host octets for LoadBalancer services on the KinD Docker /24 (kpt#27 setters).
KIND_LB_INGRESS_HOST ?= 100
KIND_LB_BNG_SYSLOG_HOST ?= 101
KIND_LB_GITEA_SSH_HOST ?= 102
KIND_LB_DIA_SYSLOG_HOST ?= 103
KIND_LB_BLACKBOX_HOST ?= 111
KIND_LB_POOL_START ?= 100
KIND_LB_POOL_END ?= 120

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


# --- Git Repository Configuration ---
# Define the SROS image and license file for the BNG deployment
SRLINUX_IMAGE ?= registry.srlinux.dev/pub/nokia_srsim:25.10.R1
SRSIM_LICENSE_FILE ?= $(NOK_CLABS_DIR)/nok-bng/srsim-lic-25.txt

NOK_KPT_DIR ?= $(BASE)/nok-kpt
KPT_REPO_URL ?= https://github.com/CSPDevLabs/kpt
KPT_REPO_BRANCH ?= nok-restructure

NOK_CLABS_DIR ?= $(BASE)/nok-clabs
CLABS_REPO_URL ?= https://github.com/CSPDevLabs/nok-clabs

# Internal helper for output indentation
INDENT_OUT ?= sed 's/^/    /'
### Curl options:
CURL := curl --silent --fail --show-error --noproxy "bng.nok.local"

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
GITEA_HOST ?= bng.nok.local
GITEA_HTTP_PATH ?= /gitea
GITEA_IP = $(KIND_NET_PREFIX).$(KIND_LB_INGRESS_HOST)
GITEA_SSH_HOST = $(KIND_NET_PREFIX).$(KIND_LB_GITEA_SSH_HOST)
GITEA_ADMIN_USER ?= nok
GITEA_ADMIN_PASS ?= N0kP4ssw0rd
GITEA_ADMIN_EMAIL ?= nok@example.com

FLUX_GIT_REPO ?= flux-bootstrap
FLUX_GIT_BRANCH ?= main
FLUX_CLUSTER_PATH ?= clusters/NetOpsKube
FLUX_SSH_KEY ?= $(HOME)/.ssh/flux_ed25519

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

# Runs kpt fn render (pipeline apply-setters.yaml) then kpt live apply.
# LB IPs must be written first via update-kpt-lb-setters.
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

.PHONY: os-shell 
os-shell: ## Verify the OS, ARCH, SHELL, DISTRO_ID, and ARCH_QUERY, output as JSON
	@echo "{"
	@echo "    \"OS\": \"$(OS)\","
	@echo "    \"UNAME\": \"$(UNAME)\","
	@echo "    \"ARCH\": \"$(ARCH)\","
	@echo "    \"SHELL\": \"$(SHELL)\","
	@echo "    \"DISTRO_ID\": \"$(DISTRO_ID)\","
	@echo "    \"ARCH_QUERY\": \"$(ARCH_QUERY)\""
	@echo "}"

.PHONY: proxy-env
proxy-env: ## Verify proxy environment variables are set
	@echo "{"
	@echo "    \"HTTP_PROXY\": \"$(HTTP_PROXY)\","
	@echo "    \"HTTPS_PROXY\": \"$(HTTPS_PROXY)\","
	@echo "    \"NO_PROXY\": \"$(NO_PROXY)\""
	@echo "}"

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
