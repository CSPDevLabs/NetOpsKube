# Auth (HAProxy + Keycloak)

Authentication uses **HAProxy + Keycloak** (common-platform pattern). oauth2-proxy is **not** used.

See [AUTH-FLOW.md](AUTH-FLOW.md).

## Enable on deploy

```bash
make KEYCLOAK_ENABLED=YES try-nok-bng
```

Or apply on a running cluster:

```bash
make KEYCLOAK_ENABLED=YES apply-haproxy-auth
make sync-portal-files
make strip-oauth2-ingress-auth
make test-auth
```

## Login

- Portal: http://bng.nok.local:8080/
- Login: http://bng.nok.local:8080/login
- User: `nokuser` / `Nokpswd@123`

## Key paths

| Component | Location |
|-----------|----------|
| HAProxy gateway | `manifests/auth/haproxy/` |
| Keycloak | `manifests/auth/keycloak/` |
| Portal static | `kpt/nok-base/portal/` |
