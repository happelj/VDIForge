# ADR 0019: React Portal Runtime Configuration and Deployment

## Status

Accepted

## Context

Phase 9 adds the first user-facing browser application. The portal must use the existing Keycloak public client, call the existing FastAPI API, and open Guacamole handoff URLs without receiving reusable remote desktop credentials. The same static frontend image should remain portable across local and future environments, so environment-specific hostnames and poll intervals should not be baked into source code or copied across multiple components.

## Decision

VDIForge will deploy the React/TypeScript portal as a static production build served by nginx from image `localhost/vdiforge-frontend:0.9.0`.

The Helm chart will mount a ConfigMap-generated `/runtime-config.js` containing only public, non-sensitive values:

- API base URL
- Keycloak issuer/authority URL
- public OIDC client ID
- redirect and post-logout redirect URIs
- lifecycle polling interval

The portal will use `oidc-client-ts` with Authorization Code Flow and PKCE for the existing public `vdiforge-frontend` client. Access tokens are used only as bearer tokens to the API. The frontend does not receive a client secret, Kubernetes ServiceAccount token, Guacamole admin credential, xrdp password, or PostgreSQL credential.

The portal Deployment is Helm-managed, uses the `vdiforge.io/node-role=platform` placement convention, and exposes `https://vdiforge.local` through the existing Traefik/local-CA ingress pattern.

## Alternatives Considered

- Build environment-specific bundles: rejected because every hostname or redirect change would require a rebuild and would make local and future environments diverge.
- Server-side rendered frontend framework: rejected because Phase 9 needs a straightforward authenticated single-page portal, not a separate application server.
- Store OIDC/client configuration in Kubernetes Secret: rejected because these values are public browser configuration, while placing them in Secret could imply confidentiality that does not exist.
- Give the frontend pod Kubernetes API credentials: rejected because the browser portal serves static assets and all privileged operations must flow through FastAPI.
- Reconstruct Guacamole URLs in the frontend: rejected because the Phase 8 broker already returns the authoritative short-lived URL and reconstructing it risks malformed `/#/?data=` links or credential leakage.

## Consequences

- The same frontend image can move between local and future environments by changing Helm values.
- Runtime configuration remains inspectable and must never contain secrets.
- Backend CORS must explicitly allow the portal origin.
- Operators should update portal endpoint changes through Helm values, not by editing the deployed ConfigMap manually.
- Future phases can add HPA, observability, and stronger security headers without changing the core portal/API contract.
