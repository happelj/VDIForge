# ADR 0003: Keycloak for Identity

## Status

Accepted for MVP architecture.

## Context

VDIForge needs OIDC authentication, SSO-like behavior, demo identities, role claims, and repeatable local setup without paid identity providers. The project should demonstrate OIDC, OAuth 2.0, JWT validation, RBAC, and separation between authentication and authorization.

## Decision

Use Keycloak as the identity provider.

Create realm:

```text
vdiforge
```

Use Authorization Code Flow with PKCE for the React portal. FastAPI validates tokens server-side and enforces application authorization.

Initial roles:

```text
vdi-user
vdi-developer
vdi-devops
vdi-admin
```

## Alternatives Considered

- Paid Okta: rejected for MVP because the initial environment should not require paid identity services.
- Paid Ping Identity: rejected for the same reason.
- Auth0 free tier: possible, but it introduces an external SaaS dependency and weakens local reproducibility.
- Hand-rolled username/password auth: rejected because it would not demonstrate modern OIDC practices and would add avoidable security risk.

## Consequences

- The MVP can run locally with an open-source identity provider.
- Phase 5 automates the initial Keycloak realm, clients, roles, and demo identities through source-controlled realm import plus runtime-only secret injection.
- The API must correctly validate JWTs instead of trusting decoded payloads.
- Keycloak roles are identity claims; VDIForge still owns application authorization and desktop ownership policy.

Phase 5 implementation details are recorded in [ADR 0012](0012-keycloak-oidc-platform.md) and [Keycloak, OIDC, and RBAC Foundation](../KEYCLOAK-OIDC.md).
