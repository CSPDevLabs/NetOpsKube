You can apply nok-tools to get a Linux server for communication testing inside a namespace.

Test whether a port is reachable:
```
nc -vz srl1 57400
```

Check whether services are working:
```
curl --resolve test.nok.dev:8080:127.0.0.1 http://test.nok.dev:8080/gnmic/metrics
```

## Portal: stuck rollout, CrashLoopBackOff, or "Could not load menu configuration"

```bash
cd netopskube
make fix-portal
```

## Portal: apps do not open (Gitea, Grafana, Prometheus show portal HTML or 404)

HAProxy must route app paths to ingress-nginx (not portal nginx). Recipe ingress must use `/nok-bng/*` paths.

```bash
cd netopskube
make fix-portal-apps
```

Verify:

```bash
make test-portal-apps
```

Hard-refresh: `http://bng.nok.local:8080/` (`Ctrl+Shift+R`).

