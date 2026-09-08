# Authentication flow (HAProxy + Keycloak)

NetOpsKube uses **HAProxy** as the edge gateway and **Keycloak** for login — the same pattern as [common-platform](https://github.com/CSPDevLabs/common-platform). There is **no oauth2-proxy**.

## Architecture

```text
Browser (:8080 port-forward)
    ↓
ingress-nginx (gateway)
    ↓
nok-haproxy
    ├── /login, /auth/  → redirect to netopskube OIDC login
    ├── /auth/*         → Keycloak (themed login)
    ├── /, /menu-config.json, /styles.css, … → Portal nginx
    └── /gitea, /bbm, /nok-bng/*, … → ingress-nginx → app services
```

## URLs

| Purpose | URL |
|---------|-----|
| Portal home | http://bng.nok.local:8080/ |
| Login | http://bng.nok.local:8080/login |
| Keycloak realm admin | http://bng.nok.local:8080/auth/admin/netopskube/console/ |
| Master admin (bootstrap) | http://bng.nok.local:8080/auth/admin/master/console/ |

**Do not use** bare `http://bng.nok.local:8080/auth/` in bookmarks — HAProxy redirects it to the netopskube login flow.

## Default users

| Account | Username | Password | Use |
|---------|----------|----------|-----|
| Portal user | `nokuser` | `Nokpswd@123` | Realm `netopskube` login |
| Keycloak admin | `admin` | `admin` | Master console only |

## Deploy / update

```bash
cd netopskube
make KEYCLOAK_ENABLED=YES apply-haproxy-auth
# or full deploy:
make KEYCLOAK_ENABLED=YES try-nok-bng
```

Refresh portal static files after kpt portal changes:

```bash
bash scripts/apply-portal-static.sh
```

## Verify

```bash
bash scripts/test-auth-haproxy.sh
```

## Files

| Path | Role |
|------|------|
| `manifests/auth/haproxy/` | HAProxy gateway |
| `manifests/auth/keycloak/` | Keycloak + realm |
| `make/auth.mk` | `deploy-auth`, `apply-haproxy-auth` |
| `scripts/apply-haproxy-auth.sh` | Live cluster migration |
| `kpt/nok-base/portal/` | Portal HTML + menu |

## App ingress auth (Grafana, BBM, Prometheus)

nginx `auth-url` annotations that pointed at **oauth2-proxy** cause **500** after oauth2-proxy is removed (auth subrequest DNS failure).

Strip them after auth migration:

```bash
make strip-oauth2-ingress-auth
```

Or as part of `make apply-haproxy-auth`.

Per-app JWT protection (common-platform style) can be added later via HAProxy.
