# NetOpsKube


## Create Cluster

```bash
git clone https://github.com/CSPDevLabs/NetOpsKube # Clone Reop for CLuster
cd NetOpsKube
make try-nok # install KinD cluster
```

## Install Base Packages

```bash
cd NetOpsKube
git clone https://github.com/CSPDevLabs/kpt
cd kpt/nok-base
../../tools/kpt live apply .  --reconcile-timeout=5m --inventory-policy=adopt
```

Note: still needs to work coreDNS forward setup to consul

## Install BNG use Case

```bash
cd NetOpsKube/kpt/nok-bng
../../tools/kpt live apply .  --reconcile-timeout=5m
```

## Forward Service
Forward access to port 8080 on the server running KinD Kubernetes
```bash
nohup kubectl port-forward --namespace=nok-base service/ingress-nginx-controller --address 0.0.0.0 8080:80 > /dev/null &
```

You can access the BNG service at http://bng.nok.local:8080/
- Add bng.nok.local to the address server in /etc/hosts for your browser to find