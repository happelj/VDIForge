# ADR 0018: Guacamole JSON Session Brokering

## Status

Accepted

## Context

VDIForge needs browser-based access to KubeVirt Ubuntu desktops without exposing reusable RDP credentials or requiring the React frontend to manage Guacamole administrative state. The Phase 8 implementation must run in the existing local Kubernetes lab, preserve server-side authorization, and avoid introducing a second application database or a custom Guacamole extension unless clearly necessary.

Apache Guacamole supports encrypted JSON authentication. The Guacamole web application receives a signed and encrypted JSON payload that defines the user, expiration time, and one or more connection definitions. This fits the VDIForge model where the FastAPI backend already owns identity validation, desktop ownership, quotas, and lifecycle state.

Guacamole's OpenID Connect extension was considered, but OIDC authenticates the user to Guacamole and still requires another source of connection data. VDIForge still needs to create per-desktop connection context after checking application ownership.

## Decision

Use Apache Guacamole `1.6.0` with the JSON authentication extension for Phase 8.

FastAPI provides:

- `POST /api/v1/desktops/{id}/connect`
- JWT validation against Keycloak
- owner/admin authorization
- desktop state validation
- short-lived encrypted Guacamole JSON tokens
- audit events for connection requests and denials

The provisioner creates a per-desktop Kubernetes Secret containing the remote username, generated password, and cloud-init user data. KubeVirt consumes the Secret during VM boot. FastAPI reads the Secret only after authorization succeeds and only returns an encrypted Guacamole URL, not the plaintext password.

The MVP protocol is RDP through `xrdp`. VNC remains a fallback option if later validation shows RDP-specific blockers.

## Alternatives Considered

- Guacamole OIDC only: rejected because it authenticates the Guacamole user but does not solve dynamic per-desktop connection authorization or connection definition management.
- Guacamole database-backed manual connections: rejected for the MVP because persistent connection records increase cleanup and cross-user authorization risk.
- Custom Guacamole extension: deferred because JSON auth satisfies the Phase 8 need with less custom code.
- Expose RDP/VNC directly to users: rejected because users could attempt to bypass VDIForge ownership checks.
- Browser-native VNC client: rejected for the MVP because Guacamole already provides a mature browser gateway and supports both RDP and VNC.
- PCoIP: rejected because the MVP must remain free and open-source and PCoIP is not equivalent to Guacamole/RDP.

## Consequences

- VDIForge keeps the authoritative authorization decision in FastAPI.
- The frontend receives only a short-lived encrypted handoff URL.
- The Guacamole JSON secret becomes sensitive runtime configuration and must never be committed.
- API Kubernetes RBAC must include narrowly scoped read access to per-desktop Secrets and Services in `vdiforge-desktops`.
- Kubernetes RBAC cannot limit Secret reads by dynamic object prefix, so application authorization and audit logging are important compensating controls.
- Guacamole does not need its own database for Phase 8 dynamic connections.
- Actual session-disconnect telemetry remains deferred; Phase 8 records connection requests and denials.
