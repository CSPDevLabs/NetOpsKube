## Gitea: `make preload-gitea-image` / `kind load` digest errors

**Symptom:** `ctr: content digest sha256:…: not found` when loading `docker.io/gitea/gitea:…` into KinD, often after `docker pull --platform linux/amd64`.

**Cause:** The Gitea image index lists amd64, arm64, and riscv64; after `docker pull --platform linux/amd64` only amd64 layers exist. `kind load docker-image` runs `ctr import --all-platforms`, which looks for the other manifests and fails ([kind#3795](https://github.com/kubernetes-sigs/kind/issues/3795)).

**Fix:** Use `make preload-gitea-image` (single-platform save + `ctr import` without `--all-platforms`), or manually:

```bash
platform=linux/amd64   # or linux/arm64 on aarch64 hosts
node=nok-demo-control-plane
docker pull --platform "$platform" docker.io/gitea/gitea:1.25.4-rootless
docker image save --platform "$platform" docker.io/gitea/gitea:1.25.4-rootless | \
  docker exec -i "$node" ctr --namespace=k8s.io images import --snapshotter=overlayfs -
```

Override image or platform: `GITEA_IMAGE=… GITEA_IMAGE_PLATFORM=linux/amd64 make preload-gitea-image`. See [DEPLOY-OPTIONS.md](DEPLOY-OPTIONS.md#gitea-image-kind-corporate-networks).

---

You can apply nok-tools to get a Linux server for communication testing inside a namespace.

Test whether a port is reachable:
```
nc -vz srl1 57400
```

Check whether services are working:
```
curl --resolve test.nok.dev:8080:127.0.0.1 http://test.nok.dev:8080/gnmic/metrics
```

