

1. Identify the Gitea Pod
First, you need to find the exact name of your Gitea pod.

```bash
export GITEA_POD_NAME=$(kubectl get pods -n nok-base -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')
```

```bash
kubectl exec -it $GITEA_POD_NAME -n nok-base -- gitea admin user create \
  --username nok \
  --password "YourSecurePasswordHere" \
  --email "nok@example.com" \
  --must-change-password false
```


Install flux
```
curl -s https://fluxcd.io/install.sh | sudo bash
```
add `~/.ssh/id_ed25519.pub` to `nok` user profile settings for access

Test connectivity
```
ssh -T -i ~/.ssh/id_ed25519 git@172.18.0.102
```

Create repo `/nok/flux-bootstrap.git`

```bash
 flux bootstrap git \
  --url=ssh://git@172.18.0.102/nok/flux-bootstrap.git \
  --private-key-file=$HOME/.ssh/id_ed25519 \
  --branch=main \
  --path=clusters/NetOpsKube
``` 

Create repo `/nok/bng-sdcio-targets.git`

```bash
flux create source git bng-sdcio \
  --url=ssh://git@172.18.0.102/nok/bng-sdcio-targets.git \
  --branch=main \
  --secret-ref=bng-sdcio-auth \
  --interval=1m \
  --namespace=flux-system
```

```bash
flux create kustomization bng-sdcio \
  --source=GitRepository/bng-sdcio \
  --path="./" \
  --prune=true \
  --interval=1m \
  --namespace=flux-system
```  




. Obtain an Admin API Token: To perform administrative actions like creating users and repositories, you need an API token from an existing Gitea administrator user. If you don't have an admin user yet, you might need to use kubectl exec once to create an initial admin user and generate a token.

```bash
kubectl exec -it $GITEA_POD_NAME -n nok-base -- gitea admin user create \
  --username admin_api \
  --password "AdminApiPassword" \
  --email "admin_api@example.com" \
  --must-change-password false \
  --admin
kubectl exec -it $GITEA_POD_NAME -n nok-base -- gitea admin user generate-access-token \
  --username admin_api \
  --token-name "api-automation-token"  
```  

3. Create the User nok via Gitea API: Use curl to send a POST request to the Gitea API to create the user.

```bash
GITEA_URL="http://gitea.nok.local" # Or https if you have TLS configured
GITEA_TOKEN="ced2d43795cc5f796a6c0f3069bb955c3ac673bd" # Replace with your actual token

curl -X POST "${GITEA_URL}/api/v1/admin/users" \
  -H "Authorization: token ${GITEA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
        "username": "nok2",
        "email": "nok2@example.com",
        "password": "YourSecurePasswordForNok",
        "must_change_password": false,
        "send_notify": false,
        "source_id": 0,
        "login_name": "nok",
        "restricted": false,
        "prohibit_login": false,
        "active": true,
        "admin": false
      }'
```    