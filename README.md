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
git clone https://github.com/CSPDevLabs/kpt nok-kpt
cd nok-kpt/nok-base
../../tools/kpt live apply .  --reconcile-timeout=5m --inventory-policy=adopt
```
 To delete apps and services in nok-base, use `kpt live destroy .`



Check if coredns is forwarding to consul:
```bash
kubectl get configmap coredns -n kube-system -o yaml
```

the result should be somethinglike:
```yaml
apiVersion: v1
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30 {
           disable success cluster.local
           disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
    # block to forward .consul queries to your Consul service
    consul:53 {
        forward . 10.96.181.225:8600
    }
kind: ConfigMap
metadata:
  creationTimestamp: "2025-11-22T17:11:06Z"
  name: coredns
  namespace: kube-system
  resourceVersion: "735"
  uid: 524fc3be-28c3-4aa9-818f-8a5fbcc5cd01
```

## Deploy containerlab instance for bng
```bash
cd ~
git clone https://github.com/CSPDevLabs/nok-clabs
cd nok-clabs/nok-bng
clab deploy -t topo.yaml
```

Inspect containerlab if it is up and running


## Install BNG use Case

If you change the IP addresses of the containerlab routers and hosts, you need to modify this file in advance: `nok-kpt/nok-bng/targets/targets.yaml`


```bash
cd NetOpsKube/nok-kpt/nok-bng
../../tools/kpt live apply .  --reconcile-timeout=5m
```



## Forward Service
Forward access to port 8080 on the server running KinD Kubernetes
```bash
nohup kubectl port-forward --namespace=nok-base service/ingress-nginx-controller --address 0.0.0.0 8080:80 > /dev/null &
```

You can access the BNG service at http://bng.nok.local:8080/
- Add bng.nok.local to the address server in /etc/hosts for your browser to find