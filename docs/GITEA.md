


Identify the Gitea Pod
First, you need to find the exact name of your Gitea pod.

```bash
export GITEA_POD_NAME=$(kubectl get pods -n nok-git -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')
```

```bash
kubectl exec -it $GITEA_POD_NAME -n nok-git -- gitea admin user create \
  --username nok \
  --password "N0kP4ssw0rd" \
  --email "nok@example.com" \
  --must-change-password=false
``` 



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
gitea.nok.local/api/v1/user/repos
```

```bash
export SSH_PUB_KEY=$(cat ~/.ssh/id_ed25519.pub )
curl -X POST \
  -H "Content-Type: application/json" \
  -u "nok:N0kP4ssw0rd" \
  -d "{
    \"title\": \"flux ssh key\",
    \"key\": \"$SSH_PUB_KEY\"
  }" \
  gitea.nok.local/api/v1/user/keys
```

Test connectivity
```
ssh -T -i ~/.ssh/id_ed25519 git@172.18.0.102
```

Install flux
```
curl -s https://fluxcd.io/install.sh | sudo bash
```

```bash
 flux bootstrap git -s \
  --url=ssh://git@172.18.0.102/nok/flux-bootstrap.git \
  --private-key-file=$HOME/.ssh/id_ed25519 \
  --branch=main \
  --path=clusters/NetOpsKube
``` 

Create repo for BNG targets and configurations

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
gitea.nok.local/api/v1/user/repos
```
```bash
flux create secret git nok-bng-auth \
  --url=ssh://git@172.18.0.102/nok/nok-bng-resources.git \
  --ssh-key-algorithm=ed25519 \
  --private-key-file=$HOME/.ssh/id_ed25519 \
  --namespace=flux-system
```


```bash
flux create source git nok-bng-resources \
  --url=ssh://git@172.18.0.102/nok/nok-bng-resources.git \
  --branch=main \
  --secret-ref=nok-bng-auth \
  --interval=1m \
  --namespace=flux-system
```

Create resources running `./build/populate-git-bng-repo.sh`

Go to the root folder of the repo and run
```bash
for d in */; do n=${d%/}; [ "$n" != ".git" ] && flux create kustomization "$n" --source=GitRepository/nok-bng-resources --path="./$n" --prune=true --interval=1m --namespace=flux-system; done
```




