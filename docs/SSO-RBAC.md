# SSO and RBAC Design

VDIForge uses Keycloak for identity and server-side FastAPI authorization for application permissions.

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

Demo identities must use disposable credentials. Real passwords must not be committed.

## OIDC Clients

Planned clients:

| Client | Type | Purpose |
| --- | --- | --- |
| `vdiforge-frontend` | public client | Browser-based React portal using Authorization Code Flow with PKCE. |
| `vdiforge-api` | resource server audience | API audience and role mapping target. |
| `vdiforge-admin` | confidential or service client, if needed later | Reproducible administrative automation. |

The frontend should use Authorization Code Flow with PKCE. The implicit flow should not be used.

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

Planned roles:

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

Later phases should configure Keycloak through source-controlled automation. Acceptable options to evaluate:

- realm import JSON
- Keycloak Operator custom resources
- Keycloak admin API script
- Terraform Keycloak provider if it is maintained and adds reliability

Manual admin-console clicking may be useful for discovery, but the final MVP configuration must be reproducible.

## Token Claims

Preferred claims:

- `sub` for stable user identity
- `preferred_username` for display
- `email` where needed
- realm or client role claims for VDIForge roles
- `aud` for intended audience
- `iss` for issuer
- `exp` for expiration

Role scope mappings should limit access-token roles to the roles needed by the VDIForge clients.

## Audit Events

Authentication and authorization audit events include:

- `LOGIN_SUCCESS`
- `LOGIN_FAILURE`
- `AUTHORIZATION_DENIED`
- privileged administrative actions
- desktop connection creation

If Keycloak owns the primary login event, VDIForge should still record application-level authorization denials and security-relevant API actions.

## Open Questions

- Should roles be realm roles or client roles for the MVP?
- Which Keycloak automation path provides the simplest repeatable local setup?
- How should refresh tokens be handled in the React portal while minimizing token exposure risk?
- Should admin API access require a separate admin client audience?
