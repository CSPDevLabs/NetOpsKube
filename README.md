# NetOpsKube - NetOps Kubernetes Project

This collaborative open-source project establishes a Kubernetes Cluster and a foundational platform for deploying various NetOps applications, including Observability and Configuration Management. It integrates popular tools such as Grafana, Prometheus, Loki, gnmic, and rsyslog, alongside emerging solutions like SDCIO (Kubenet).

## Key Advantages

- **Simplified Access:** Provides unified access to applications through a single portal, supporting both visualization and API interactions.
- **Robust Lifecycle Management:** Offers close control over the lifecycle of releases and deployed use cases.
- **Production Readiness:** Ensures high resilience and production readiness through multi-replica application deployments and exposed services.
- **Unified Security:** Implements consistent security and access control mechanisms across all components.
- **Flexibility:**  Its fully open-source nature allows for extensive modification and adaptation to diverse network environments.
- **Portability:** Leverages Kubernetes to provide enhanced portability across different infrastructures.
- **CI/CD Integration:** Facilitates seamless CI/CD workflows by utilizing the Kubernetes ecosystem and GitOps repositories as the single source of truth.


## Setup

This Makefile automates the setup of a local Kubernetes environment using Kind, manages necessary command-line tools, clones Git repositories, and deploys Kubernetes applications via KPT, including integration with Containerlab.

### Introduction to the Makefile
This Makefile serves as a comprehensive automation script for setting up a development and testing environment centered around Kubernetes and network emulation. It streamlines the process of acquiring required tools, provisioning a local Kubernetes cluster (Kind), managing external Git repositories, deploying Kubernetes applications using KPT (Kubernetes Package Toolkit), and integrating with Containerlab for network topology deployments.

### General Requirements
To successfully run these Makefile targets, the following general requirements must be met:

- **Operating System:** A Linux or macOS environment is expected, as indicated by the UNAME and OS variables.
Docker: Docker must be installed and running, as Kind uses Docker containers for cluster nodes and Containerlab relies on Docker for network emulation.
- **Git:** Git must be installed to clone the necessary repositories.
- **Internet Connectivity:** Required for downloading tools and cloning Git repositories.
- **Nokia SRLinux Image & License (for deploy-bng):**
   - The registry.srlinux.dev/pub/nokia_srsim:25.10.R1 Docker image must be locally available (docker pull registry.srlinux.dev/pub/nokia_srsim:25.10.R1).
   - A valid Nokia SROS license file must be present at the path specified by SRSIM_LICENSE_FILE (default: $(NOK_CLABS_DIR)/nok-bng/srsim-lic-25.txt).
- **IP Segments:** This deployment uses **172.18.0.0/24** Network for KinD and Services, and **172.21.20.0/24** for containerlab   

### High-Level Functionality
The Makefile orchestrates several key areas:
- **Tool Management:** It automatically downloads, installs, and manages versions of essential command-line tools like kind, kubectl, helm, kpt, yq, k9s, gh, and containerlab into a dedicated tools/ directory.
- **sudo Access:** Needs sudo privileges for containerlab montly (for `make try-nok` shouldn't be required, just acess to docker would be suffice)
- **Kubernetes Cluster Lifecycle (Kind):** It provides targets to create, configure, and delete a local Kubernetes cluster using Kind, including dynamic configuration of API server addresses and port mappings.
- ***Git Repository Management:** It handles the cloning of specific Git repositories (**CSPDevLabs/kpt** and **CSPDevLabs/nok-clabs**) which contain the Kubernetes manifests and Containerlab topologies.
- **KPT Package Deployment:** It defines a macro (INSTALL_KPT_PACKAGE) to simplify the deployment and reconciliation of Kubernetes resource packages using kpt live apply, ensuring applications are correctly installed and managed within the cluster.
- **Containerlab Integration:** It includes targets to deploy and destroy network topologies defined in Containerlab, specifically for a Nokia BNG (Broadband Network Gateway) setup, and checks for necessary Docker images and license files.
- **Service Exposure:** It includes a mechanism to port-forward the ingress controller service, making applications accessible from the host machine.

### Key Targets: try-nok and deploy-bng
The Makefile does not define an all target. The most comprehensive targets for setting up the environment are try-nok and deploy-bng.

#### make try-nok
Purpose: This target sets up the foundational Kubernetes environment, including the Kind cluster and core services like an ingress controller and a load balancer. It prepares the cluster for subsequent application deployments.

#### make deploy-bng
Purpose: This target extends the try-nok setup by deploying the Nokia BNG (Broadband Network Gateway) application within the Kubernetes cluster and provisioning its associated Containerlab network topology. 

## Create Cluster

You can deploy the cluster and base app using:
```bash
git clone https://github.com/CSPDevLabs/NetOpsKube # Clone Reop for CLuster
cd NetOpsKube
make try-nok # install KinD cluster and Base Packages
```

## Destroy Cluster
Destroy the full setup via:
```bash
make delete-cluster
```

## Deploy Cluster and BNG all together
Deploy Cluster , Base Apps , BNG Apps and Containerlab (requires license file and docker image, check requirements on above sections for details)
```bash
sudo make deploy bng
```

To generate BNG subscribe sessions and traffic:
```bash
sudo docker exec -it clab-sros-bngt-bngblaster bash -c 'bngblaster -C pppoe.json -I -l dhcp'
```
This use case is based in a previous clab deployment. More details at https://github.com/CSPDevLabs/sros_bng_observability

### Acess to Apps
You can access the BNG service at http://bng.nok.local:8080/
- Add bng.nok.local to the address server in /etc/hosts for your browser to find

BNG use case can be tested locally via:
```bash
curl --resolve bng.nok.local:8080:127.0.0.1 http://bng.nok.local:8080
```