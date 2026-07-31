
# Gitea and Flux GitOps Setup
This guide details the process of establishing a Gitea instance as a Git repository for Flux, followed by the installation and configuration of Flux to manage Kubernetes resources using GitOps principles.

**Requirements:**
- Add  `172.18.0.100    gitea.nok.local` to your `/etc/hosts`

## 1. Gitea Setup
This section covers the necessary steps to configure your Gitea instance, including user creation, repository setup, and SSH key management.

### 1.1 Identify Gitea Pod
First, retrieve the exact name of your Gitea Kubernetes pod. This name is essential for executing commands directly within the Gitea container.

```bash
export GITEA_POD_NAME=$(kubectl get pods -n nok-git -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')
```
### 1.2 Create Gitea Admin User
Create a dedicated admin user within Gitea. This user will be used for programmatic access, such as creating repositories and adding SSH keys.

```bash
kubectl exec -it $GITEA_POD_NAME -n nok-git -- gitea admin user create \
  --username nok \
  --password "N0kP4ssw0rd" \
  --email "nok@example.com" \
  --must-change-password=false
``` 

### 1.3 Create Flux Bootstrap Repository
Create a new repository in Gitea named flux-bootstrap. This repository will store the Flux configuration and manifests for bootstrapping your cluster.

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -u "nok:N0kP4ssw0rd" \
  -d '{
    "name": "flux-bootstrap",
    "description": "Flux Bootstrap files.",
    "private": false,
    "auto_init": true
  }' \
http://gitea.nok.local/api/v1/user/repos
```

### 1.4 Add SSH Public Key to Gitea
Add the SSH public key that Flux will use to authenticate with Gitea via SSH.
By default this repository uses `~/.ssh/flux_ed25519` via `FLUX_SSH_KEY`.
If you prefer your own key (for example `~/.ssh/id_ed25519`), set `FLUX_SSH_KEY` accordingly and use it consistently in all Flux steps.

```bash
export FLUX_SSH_KEY="${FLUX_SSH_KEY:-$HOME/.ssh/flux_ed25519}"
export SSH_PUB_KEY=$(cat "${FLUX_SSH_KEY}.pub")
curl -X POST \
  -H "Content-Type: application/json" \
  -u "nok:N0kP4ssw0rd" \
  -d "{
    \"title\": \"flux ssh key\",
    \"key\": \"$SSH_PUB_KEY\"
  }" \
  http://gitea.nok.local/api/v1/user/keys
```
### 1.5 Test SSH Connectivity
Verify that SSH connectivity to Gitea is working correctly using your private key.

```
export FLUX_SSH_KEY="${FLUX_SSH_KEY:-$HOME/.ssh/flux_ed25519}"
ssh -T -i "$FLUX_SSH_KEY" git@172.18.0.102
```
## 2. Flux Installation and Configuration
This section details the installation of the Flux CLI and the configuration of Flux to manage your Kubernetes cluster.

### 2.1 Install Flux CLI
Install the Flux command-line interface (CLI) tool on your local machine. This tool is used to interact with Flux and perform bootstrapping operations.

```
curl -s https://fluxcd.io/install.sh | sudo bash
```

### 2.2 Bootstrap Flux
Bootstrap Flux onto your Kubernetes cluster. This command installs the Flux controllers and configures them to synchronize with the flux-bootstrap repository you created earlier.

```bash
export FLUX_SSH_KEY="${FLUX_SSH_KEY:-$HOME/.ssh/flux_ed25519}"
 flux bootstrap git -s \
  --url=ssh://git@172.18.0.102/nok/flux-bootstrap.git \
  --private-key-file=$FLUX_SSH_KEY \
  --branch=main \
  --path=clusters/NetOpsKube
``` 

### 2.3 Create Repository for BNG Targets
Create a new repository in Gitea specifically for BNG (Broadband Network Gateway) target configurations and resources.

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -u "nok:N0kP4ssw0rd" \
  -d '{
    "name": "nok-bng-resources",
    "description": "BNG resources for Network Observability and Conf Management",
    "private": false,
    "auto_init": true
  }' \
http://gitea.nok.local/api/v1/user/repos
```
### 2.4 Create Git Secret for BNG Resources
Create a Kubernetes secret in the flux-system namespace that holds the SSH private key for Flux to authenticate with the nok-bng-resources repository.

```bash
export FLUX_SSH_KEY="${FLUX_SSH_KEY:-$HOME/.ssh/flux_ed25519}"
flux create secret git nok-bng-auth \
  --url=ssh://git@172.18.0.102/nok/nok-bng-resources.git \
  --ssh-key-algorithm=ed25519 \
  --private-key-file=$FLUX_SSH_KEY \
  --namespace=flux-system
```
### 2.5 Create Git Repository Source for BNG Resources
Define a GitRepository source in Flux that points to the nok-bng-resources repository. This tells Flux where to find the BNG configurations.

```bash
flux create source git nok-bng-resources \
  --url=ssh://git@172.18.0.102/nok/nok-bng-resources.git \
  --branch=main \
  --secret-ref=nok-bng-auth \
  --interval=1m \
  --namespace=flux-system
```

### 2.6 Populate BNG Repository and Create Kustomizations
Populate and push the BNG manifests from this repository using the built-in Makefile target:

```bash
make push-bng-manifests
```

Then create Kustomization resources in Flux for each subdirectory in `nok-clabs/nok-bng/nok-manifests`.

Navigate to the root folder of your `nok-bng-resources` repository clone:

```bash
cd nok-bng-resources

for d in */; do 
  n=${d%/};  
  if [ "$n" != ".git" ]; then
    flux create kustomization "$n" \
      --source=GitRepository/nok-bng-resources \
      --path="./$n" \
      --prune=true \
      --interval=1m \
      --namespace=flux-system; 
  fi
done
```




