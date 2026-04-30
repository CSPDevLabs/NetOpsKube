# NetOpsKube Installation Guide

This collaborative open-source project establishes a Kubernetes Cluster and a foundational platform for deploying various NetOps applications, including Observability and Configuration Management. It integrates popular tools such as Grafana, Prometheus, Loki, gnmic, and rsyslog, alongside emerging solutions like SDCIO (Kubenet).

## Key Advantages

- **Simplified Access:** Provides unified access to applications through a single portal, supporting both visualization and API interactions.
- **Robust Lifecycle Management:** Offers close control over the lifecycle of releases and deployed use cases.
- **Production Readiness:** Ensures high resilience and production readiness through multi-replica application deployments and exposed services.
- **Unified Security:** Implements consistent security and access control mechanisms across all components.
- **Flexibility:**  Its fully open-source nature allows for extensive modification and adaptation to diverse network environments.
- **Portability:** Leverages Kubernetes to provide enhanced portability across different infrastructures.
- **CI/CD Integration:** Facilitates seamless CI/CD workflows by utilizing the Kubernetes ecosystem and GitOps repositories as the single source of truth.

## Prerequisite
To successfully run the Makefile targets, ensure the following requirements are met:

### Operating System
   - A Linux or macOS environment is required.
### Docker
   - Docker must be installed and running.
   - Kind (Kubernetes in Docker) uses Docker containers for cluster nodes. Containerlab relies on Docker for network emulation.
   - Create the Docker group (if not already present)
     ```bash
     sudo groupadd docker
     ```
     Add your user to the Docker group
     ```bash
     sudo usermod -aG docker $USER
     ```
     Apply the changes. You need to refresh your session:
     ```bash
     newgrp docker
     ```
     Or simply log out and log back in.
     Verify
     ```bash
     docker run hello-world
     ```
     If it runs without sudo, you're good.

### Git
   - Git must be installed to clone the required repositories.
   - Set your Git identity globally on your system
     ```bash
     git config --global user.name "nokuser"
     git config --global user.email "nokuser@example.com"
     ```
### Internet Connectivity
   Required for:
   - Downloading tools
   - Pulling Docker images
   - Cloning Git repositories
### DNS Configuration
   - DNS must be properly configured on the host system.
   - The system should be able to resolve:
     - External registries (e.g., registry.srlinux.dev)
     - Git repositories
     - Package repositories
   - You can verify DNS resolution using:
     - nslookup <domain>
### Proxy Configuration (If Behind a Corporate Firewall)
If the environment is behind a proxy, ensure proxy settings are correctly configured for the following components:
#### System-wide Proxy (Linux/macOS)
Configure http_proxy, https_proxy, and no_proxy environment variables. Update below files.
   ```bash
   ubuntu@nokia:~/kube_project/NetOpsKube$ cat /etc/environment
   http_proxy="http://<proxy-ip>:<port>"
   https_proxy="http://<proxy-ip>:<port>"
   ftp_proxy="http://<proxy-ip>:<port>"
   HTTP_PROXY="http://<proxy-ip>:<port>"
   HTTPS_PROXY="http://<proxy-ip>:<port>"
   FTP_PROXY="http://<proxy-ip>:<port>"
   no_proxy="127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16,gitea.nok.local,*.nok.local"
   NO_PROXY="127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16,gitea.nok.local,*.nok.local"
   ubuntu@nokia:~/kube_project/NetOpsKube$
   ```

   ```bash
   ubuntu@nokia:~/kube_project/NetOpsKube$ cat /etc/profile.d/proxy.sh
   export http_proxy="http://<proxy-ip>:<port>"
   export https_proxy="http://<proxy-ip>:<port>"
   export ftp_proxy="http://<proxy-ip>:<port>"
   export HTTP_PROXY="http://<proxy-ip>:<port>"
   export HTTPS_PROXY="http://<proxy-ip>:<port>"
   export FTP_PROXY="http://<proxy-ip>:<port>"
   export no_proxy="127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16,gitea.nok.local,*.nok.local"
   export NO_PROXY="127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16,gitea.nok.local,*.nok.local"
   ubuntu@nokia:~/kube_project/NetOpsKube$
   ```

#### Package Managers
Ensure proxy settings are properly configured in the respective package manager configuration files if required.
   - For Debian/Ubuntu (apt)
     Example:
     ```bash
     ubuntu@nokia:/etc/apt/apt.conf.d$ cat 95proxy
     Acquire::http::Proxy "http://<proxy-ip>:<port>";
     Acquire::https::Proxy "http://<proxy-ip>:<port>";
     ubuntu@nokia:/etc/apt/apt.conf.d$
     ```
   - For RHEL/CentOS (yum / dnf)
     ```bash
     sudo vi /etc/yum.conf

     proxy=http://<proxy-ip>:<port>
     proxy_username=<username>
     proxy_password=<password>
     ```
     
#### Docker
   - Docker daemon must be configured with proxy settings if running behind a proxy.
   - Configure proxy in /etc/systemd/system/docker.service.d/http-proxy.conf
      ```bash
      ubuntu@nokia:~/kube_project/NetOpsKube$ cat /etc/systemd/system/docker.service.d/http-proxy.conf
      [Service]
      Environment="HTTP_PROXY=http://<proxy-ip>:<port>"
      Environment="HTTPS_PROXY=http://<proxy-ip>:<port>"
      Environment="FTP_PROXY=http://<proxy-ip>:<port>"
      Environment="NO_PROXY=127.0.0.1,localhost,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16,gitea.nok.local,*.nok.local"
      ubuntu@nokia:~/kube_project/NetOpsKube$
      ```
   - Restart Docker after configuration.
     ```bash
     sudo systemctl daemon-reload
     sudo systemctl restart docker
     ```

### Nokia SRLinux Image & License (Required for BNG cluster deployment)
   - The following Docker image must be available locally.
      ```bash
      registry.srlinux.dev/pub/nokia_srsim:25.10.R1
      ```
   - Pull it using below command.
      ```bash
      docker pull registry.srlinux.dev/pub/nokia_srsim:25.10.R1
      ```
   - A valid Nokia SROS license file must be present at the path specified by SRSIM_LICENSE_FILE. Default path is $(NOK_CLABS_DIR)/nok-bng/srsim-lic-25.txt

### IP Address Segments
This deployment uses the following network ranges:
   - 172.18.0.0/24 → KinD cluster and services
   - 172.21.20.0/24 → Containerlab topology


### Makefile Updates
The Makefile serves as a comprehensive automation script for setting up a development and testing environment centered around Kubernetes and network emulation. It streamlines the process of acquiring required tools, provisioning a local Kubernetes cluster (Kind), managing external Git repositories, deploying Kubernetes applications using KPT (Kubernetes Package Toolkit), and integrating with Containerlab for network topology deployments.

#### High-Level Functionality
The Makefile orchestrates several key areas:
- **Tool Management:** It automatically downloads, installs, and manages versions of essential command-line tools like kind, kubectl, helm, kpt, yq, k9s, gh, and containerlab into a dedicated tools/ directory.
- **sudo Access:** Needs sudo privileges for containerlab
- **Kubernetes Cluster Lifecycle (Kind):** It provides targets to create, configure, and delete a local Kubernetes cluster using Kind, including dynamic configuration of API server addresses and port mappings.
- ***Git Repository Management:** It handles the cloning of specific Git repositories (**CSPDevLabs/kpt** and **CSPDevLabs/nok-clabs**) which contain the Kubernetes manifests and Containerlab topologies.
- **KPT Package Deployment:** It defines a macro (INSTALL_KPT_PACKAGE) to simplify the deployment and reconciliation of Kubernetes resource packages using kpt live apply, ensuring applications are correctly installed and managed within the cluster.
- **Containerlab Integration:** It includes targets to deploy and destroy network topologies defined in Containerlab, specifically for a Nokia BNG (Broadband Network Gateway) setup, and checks for necessary Docker images and license files.
- **Service Exposure:** It includes a mechanism to port-forward the ingress controller service, making applications accessible from the host machine.

Add below line at the beginning of the Makefile if you are using Linux environment.

```bash
SHELL := /bin/bash
```
#### Proxy Configuration
In environments where outbound internet access is restricted, you may need to configure HTTP/HTTPS proxy settings for certain workloads.
 
Proxy values can be configured in the Makefile by updating the following variables:
```bash
HTTP_PROXY  ?= http://<proxy-ip>:<port>
HTTPS_PROXY ?= http://<proxy-ip>:<port>
NO_PROXY    ?= 127.0.0.1,localhost,::1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.96.0.0/12,10.244.0.0/16,.nok.local,gitea.nok.local
```

### Update Gitea IP on /etc/hosts. 

Note: BNG cluster details will be automatically updated.

```bash
172.18.0.100    gitea.nok.local
```
Example:
```bash
ubuntu@nokia:~/kube_project/NetOpsKube$ cat /etc/hosts
127.0.0.1 localhost
172.18.0.100    gitea.nok.local
..........

ubuntu@nokia:~/kube_project/NetOpsKube$
```

## Start Installation
Clone the NetOpsKube repository.
```bash
git clone https://github.com/CSPDevLabs/NetOpsKube.git
cd NetOpsKube
```

### make try-nok-bng

This target sets up the foundational Kubernetes environment, including the Kind cluster and core services like an ingress controller and a load balancer. It prepares the cluster for subsequent application deployments.

Export proxy settings before if required.

```bash
ubuntu@nokia:~/kube_project/NetOpsKube$ make try-nok-bng
--> TOOLS: Creating aliases for versioned binaries
--> TOOLS: To add the tools to your path, paste this in your shell: export PATH=$PATH:/home/ubuntu/kube_project/NetOpsKube/tools
--> All required tools found or downloaded.
--> KIND: Ensuring control-plane exists
--> KIND: Host port map 0.0.0.0:5443  added
No kind clusters found.
--> KIND: Creating cluster named nok-demo...
    Creating cluster "nok-demo" ...
    ............................
Creating Kustomization for secrets...
✚ generating Kustomization
► applying Kustomization
✔ Kustomization created
◎ waiting for Kustomization reconciliation
✔ Kustomization secrets is ready
✔ applied revision main@sha1:ffbb4d7ff2a84e30fa3a96f64635f0371506d437
--> GITOPS: BNG repo in sync by Flux
ubuntu@nokia:~/kube_project/NetOpsKube$
```

### make deploy-clab-bng

Please make sure to copy the license file beforehand.

```bash
cp srsim-lic-25.txt /home/ubuntu/kube_project/NetOpsKube/nok-clabs/nok-bng/srsim-lic-25.txt
```

“This containerlab command requires root privileges or root via SUID to run, effective UID: 1000 SUID: 1000”

Use “sudo”.
```bash
nokuser@admin:~/kube_project/NetOpsKube$ sudo make deploy-clab-bng
[sudo] password for nokuser:
--> TOOLS: Creating aliases for versioned binaries
--> TOOLS: To add the tools to your path, paste this in your shell: export PATH=$PATH:/home/nokuser/kube_project/NetOpsKube/tools
--> All required tools found or downloaded.
--> GIT: Cloning https://github.com/CSPDevLabs/nok-clabs into /home/nokuser/kube_project/NetOpsKube/nok-clabs
--> GIT: /home/nokuser/kube_project/NetOpsKube/nok-clabs already exists. Skipping clone.
--> CLAB: Checking prerequisites for BNG deployment...
--> CLAB: Docker image 'registry.srlinux.dev/pub/nokia_srsim:25.10.R1' found.
--> CLAB: Nokia SROS license file found.
........................
14:38:50 INFO containerlab version
  🎉=
  │ A newer containerlab version (0.74.3) is available!
  │ Release notes: https://containerlab.dev/rn/0.74/#0743
  │ Run 'clab version upgrade' or see https://containerlab.dev/install/ for other installation options.
╭───────────────────────────┬───────────────────────────────────────────────┬─────────┬────────────────╮
│            Name           │                   Kind/Image                  │  State  │ IPv4/6 Address │
├───────────────────────────┼───────────────────────────────────────────────┼─────────┼────────────────┤
│ clab-sros-bngt-agg        │ nokia_srsim                                   │ running │ 172.21.20.21   │
│                           │ registry.srlinux.dev/pub/nokia_srsim:25.10.R1 │         │ N/A            │
├───────────────────────────┼───────────────────────────────────────────────┼─────────┼────────────────┤
│ clab-sros-bngt-bng1       │ nokia_srsim                                   │ running │ 172.21.20.11   │
│                           │ registry.srlinux.dev/pub/nokia_srsim:25.10.R1 │         │ N/A            │
├───────────────────────────┼───────────────────────────────────────────────┼─────────┼────────────────┤
│ clab-sros-bngt-bng2       │ nokia_srsim                                   │ running │ 172.21.20.12   │
│                           │ registry.srlinux.dev/pub/nokia_srsim:25.10.R1 │         │ N/A            │
├───────────────────────────┼───────────────────────────────────────────────┼─────────┼────────────────┤
│ clab-sros-bngt-bngblaster │ linux                                         │ running │ 172.21.20.112  │
│                           │ azyablov/bng-blaster:latest                   │         │ N/A            │
├───────────────────────────┼───────────────────────────────────────────────┼─────────┼────────────────┤
│ clab-sros-bngt-core       │ nokia_srsim                                   │ running │ 172.21.20.22   │
│                           │ registry.srlinux.dev/pub/nokia_srsim:25.10.R1 │         │ N/A            │
├───────────────────────────┼───────────────────────────────────────────────┼─────────┼────────────────┤
│ clab-sros-bngt-radius     │ linux                                         │ running │ 172.21.20.111  │
│                           │ freeradius/freeradius-server:3.2.3            │         │ N/A            │
╰───────────────────────────┴───────────────────────────────────────────────┴─────────┴────────────────╯
```

### Apply Proxy to Deployments
Run the following command to apply proxy environment variables to required deployments.
```bash
make set-proxy-env
```

### Remove / Rollback Proxy
If incorrect proxy values are applied, you can remove them using below command.
```bash
make unset-proxy-env
```

### Delete cluster
Delete the full setup using below commands.
```bash
make delete-cluster
make destroy-clab-bng
```

### Update portal username/password
Update NOK portal credentials using below command.
```bash
make update-portal-auth
```

##  Verify whether all pods are in 'Running' state.

```bash
ubuntu@nokia:~/kube_project/NetOpsKube$ kubectl get pods -A
NAMESPACE            NAME                                                   READY   STATUS    RESTARTS      AGE
flux-system          helm-controller-6846747549-4kcn2                       1/1     Running   0             42h
flux-system          kustomize-controller-b8bf66b9-mtt2t                    1/1     Running   0             42h
flux-system          notification-controller-6c4f7967c9-jzrvx               1/1     Running   0             42h
flux-system          source-controller-6c6b49bf65-zskdd                     1/1     Running   0             42h
kube-system          coredns-5b6498457-fm2wt                                1/1     Running   0             17s
kube-system          coredns-5b6498457-zd72z                                1/1     Running   0             17s
kube-system          etcd-nok-demo-control-plane                            1/1     Running   0             42h
kube-system          kindnet-q2vb6                                          1/1     Running   0             42h
kube-system          kube-apiserver-nok-demo-control-plane                  1/1     Running   0             42h
kube-system          kube-controller-manager-nok-demo-control-plane         1/1     Running   0             42h
kube-system          kube-proxy-s57r2                                       1/1     Running   0             42h
kube-system          kube-scheduler-nok-demo-control-plane                  1/1     Running   0             42h
local-path-storage   local-path-provisioner-7dc846544d-cqxtx                1/1     Running   0             42h
metallb-system       controller-58fdf44d87-k6xtc                            1/1     Running   0             42h
metallb-system       speaker-d595v                                          1/1     Running   0             42h
nok-base             cert-manager-776494b6cf-5mft8                          1/1     Running   0             42h
nok-base             cert-manager-cainjector-6cf76fc759-42qs4               1/1     Running   0             42h
nok-base             cert-manager-webhook-7bfbfdc97c-tg8fl                  1/1     Running   0             42h
nok-base             config-server-6ff7bd7c8c-zhrgg                         2/2     Running   1 (42h ago)   42h
nok-base             gnmic-controller-manager-76779bd584-54zk7              1/1     Running   0             42h
nok-base             grafana-operator-controller-manager-7bc9b55b98-8lxv7   1/1     Running   0             19h
nok-base             ingress-nginx-controller-7dfff6b6ff-ts98k              1/1     Running   0             42h
nok-base             nok-controller-6444559b75-pn72f                        1/1     Running   0             42h
nok-base             prometheus-operator-7bcd847884-srlqg                   1/1     Running   0             42h
nok-bbm              bbm-grafana-75bc4d5689-c4psv                           1/1     Running   0             19h
nok-bbm              bbm-prometheus-deployment-75644bbddc-l6tr9             1/1     Running   0             42h
nok-bbm              blackbox-exporter-5546fb9cc8-ftj2v                     1/1     Running   0             42h
nok-bbm              coredns-updater-79996677c9-9k7pz                       1/1     Running   0             19h
nok-bbm              kube-state-metrics-5c7d674fdd-kztbn                    1/1     Running   0             42h
nok-bng              alertmanager-6554788546-vnpw4                          1/1     Running   0             42h
nok-bng              fluent-bit-56c9794c54-8q8bn                            1/1     Running   0             42h
nok-bng              gnmic-bng-metrics-0                                    1/1     Running   0             42h
nok-bng              gnmic-bng-state-0                                      1/1     Running   0             42h
nok-bng              grafana-deployment-647758584d-7zsnw                    1/1     Running   0             19h
nok-bng              lightweight-linux-58bcd4fc78-jdlxz                     1/1     Running   0             42h
nok-bng              loki-89fb79f49-l754g                                   1/1     Running   0             42h
nok-bng              ndt-metrics-exporter-54b77c6948-hrn44                  1/1     Running   0             42h
nok-bng              nok-apps-portal-app-69f8c6b469-tq56h                   1/1     Running   0             42h
nok-bng              portal-auth-67d76fc559-cxxnf                           1/1     Running   0             42h
nok-bng              prometheus-nok-bng-0                                   2/2     Running   0             42h
nok-bng              promtail-75875d67c5-j78bc                              1/1     Running   0             42h
nok-bng              sdcio-metrics-exporter-7569cdb844-pbbhm                1/1     Running   0             42h
nok-bng              syslog-ng-7d6c64d8b4-vhwz8                             1/1     Running   0             42h
nok-git              gitea-f696c4569-gvg8m                                  1/1     Running   0             42h
nok-git              gitea-postgresql-0                                     1/1     Running   0             42h
nok-git              gitea-valkey-primary-0                                 1/1     Running   0             42h
ubuntu@nokia:~/kube_project/NetOpsKube$
```

## Open portal
Add entries for "bng.nok.local" and "gitea.nok.local" in the /etc/hosts file of your local machine (e.g., your Windows laptop), mapping them to the IP address of the Ubuntu host. This allows your browser to resolve the URLs correctly.

### NOK Portal
http://bng.nok.local:8080/login

Login Credentials:

```bash
Username: admin
Password: admin123
```

### Gitea Portal
http://gitea.nok.local:8080

Login Credentials:
```bash
email: nok@example.com
password "N0kP4ssw0rd"
```