# SSO and RBAC Design

VDIForge uses Keycloak for identity and server-side FastAPI authorization for application permissions.

Phase 5 implements the Keycloak/OIDC/RBAC identity foundation. Phase 7 consumes those claims in FastAPI authorization, Phase 8 uses the same server-side authorization boundary before brokering Guacamole remote sessions, and Phase 9 uses the public browser client from the React portal.

## Realm

```text
Realm: vdiforge
```

Demo users:

```text
demo-user
demo-developer
demo-devops
demo-admin
```

Demo identities use disposable local credentials generated outside Git by `scripts/phase5-create-local-secrets.sh`. Real passwords must not be committed.

## OIDC Clients

Phase 5 clients:

| Client | Type | Purpose |
| --- | --- | --- |
| `vdiforge-frontend` | public client | Browser-based React portal using Authorization Code Flow with PKCE. |
| `vdiforge-api` | resource server audience | API audience and role mapping target. |

The frontend client uses Authorization Code Flow with PKCE S256. The implicit flow and direct access grants are disabled. The React portal does not receive a client secret.

## Token Validation

FastAPI must validate:

- token signature using Keycloak JWKS
- issuer matches the configured realm issuer
- expiration
- audience where applicable
- expected token type
- role claims
- subject claim

FastAPI must not accept tokens based on a decoded payload alone.

## Roles

Roles:

```text
vdi-user
vdi-developer
vdi-devops
vdi-admin
```

Role semantics:

| Role | Meaning |
| --- | --- |
| `vdi-user` | Can launch base desktops and manage own desktops. |
| `vdi-developer` | Can launch base and developer desktops and manage own desktops. |
| `vdi-devops` | Can launch base, developer, and DevOps desktops and manage own desktops. |
| `vdi-admin` | Can administer desktops, view audit events, and perform image administrative actions. |

## Permission Matrix

| Capability | User | Developer | DevOps | Admin |
| --- | ---: | ---: | ---: | ---: |
| Launch Ubuntu Base | Yes | Yes | Yes | Yes |
| Launch Ubuntu Developer | No | Yes | Yes | Yes |
| Launch Ubuntu DevOps | No | No | Yes | Yes |
| View own desktops | Yes | Yes | Yes | Yes |
| Delete own desktop | Yes | Yes | Yes | Yes |
| View all desktops | No | No | No | Yes |
| Delete another user's desktop | No | No | No | Yes |
| Administrative audit access | No | No | No | Yes |

## Authorization Model

The backend authorizes every protected operation:

1. Authenticate the request token.
2. Resolve the user ID from trusted claims.
3. Resolve roles from trusted claims.
4. Load backend resource ownership and policy state.
5. Evaluate role, ownership, image access, quota, and desktop state.
6. Permit or deny the operation.
7. Record an audit event for security-relevant outcomes.

The frontend may hide unavailable actions but cannot be the authorization boundary.

## Image Access

Planned mapping:

| Image | Required role |
| --- | --- |
| `ubuntu-base` | `vdi-user`, `vdi-developer`, `vdi-devops`, or `vdi-admin` |
| `ubuntu-developer` | `vdi-developer`, `vdi-devops`, or `vdi-admin` |
| `ubuntu-devops` | `vdi-devops` or `vdi-admin` |

## Authentication vs Authorization vs Kubernetes RBAC

Authentication answers: who is the user?

Application authorization answers: what VDIForge operation may this user perform?

Kubernetes RBAC answers: what Kubernetes API operations may a VDIForge ServiceAccount perform?

These are separate controls. A user with `vdi-devops` is allowed to request an Ubuntu DevOps desktop, but that does not grant the user's browser Kubernetes API privileges.

## Reproducible Keycloak Configuration

Phase 5 uses source-controlled realm import JSON plus a runtime-only admin CLI configuration script:

```text
keycloak/realm/vdiforge-realm.json
helm/vdiforge/files/keycloak/vdiforge-realm.json
scripts/phase5-configure-keycloak.sh
```

The committed realm JSON contains no passwords or client secrets. `scripts/phase5-configure-keycloak.sh` uses generated local secrets to set demo-user credentials after the realm import is available.

Manual admin-console clicking may be useful for inspection, but it is not the source of truth.

## Token Claims

Validated Phase 5 claims:

- `sub` for stable user identity
- `preferred_username` for display
- realm role claims in `roles`
- `aud` for intended audience
- `iss` for issuer
- `exp` for expiration

The Phase 5 PKCE/JWT test validates signature, issuer, audience, expiration, expected role presence, and unauthorized role absence.

Phase 12 keeps this identity model and adds hardening validation:

- Keycloak brute-force protection is enabled for the local lab.
- The browser client remains public and uses PKCE S256.
- Implicit flow and browser client secrets remain disabled.
- Redirect URIs and web origins remain explicit rather than wildcard.
- Token lifetimes and browser storage behavior are documented.
- API security tests continue to reject missing, tampered, expired, wrong-issuer, and wrong-audience tokens.

## Audit Events

Authentication and authorization audit events include:

- `LOGIN_SUCCESS`
- `LOGIN_FAILURE`
- `AUTHORIZATION_DENIED`
- `DESKTOP_CONNECTION_REQUESTED`
- `DESKTOP_CONNECTION_DENIED`
- privileged administrative actions
- desktop connection creation

If Keycloak owns the primary login event, VDIForge should still record application-level authorization denials and security-relevant API actions.

## Open Questions

- Should a future production profile replace the Phase 9/12 browser token-session baseline with a stronger backend-for-frontend or token exchange pattern?
- Should admin API access require a separate admin client audience?

## Phase 5 References

- [Keycloak, OIDC, and RBAC Foundation](KEYCLOAK-OIDC.md)
- [FastAPI VDI Control Plane](API-CONTROL-PLANE.md)
- [Remote Desktop Delivery](REMOTE-DESKTOP.md)
- [ADR 0012: Keycloak OIDC Platform Deployment](ADR/0012-keycloak-oidc-platform.md)
- [ADR 0013: Local Ingress and TLS for Browser-Facing Services](ADR/0013-local-ingress-and-tls.md)
