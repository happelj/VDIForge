# ADR 0022: Security and Audit Hardening

## Status

Accepted

## Context

By Phase 11, VDIForge has a working local VDI platform with Kubernetes, KubeVirt, Helm, Keycloak, FastAPI, PostgreSQL, Guacamole, React, HPA, Prometheus, and Grafana. The platform already enforces core identity, authorization, and network boundaries, but the implementation needs a focused security-hardening pass before CI/CD and final demo polish.

The local lab must remain free, reproducible, and understandable. It should not introduce enterprise-only infrastructure such as a Vault cluster, SIEM, WAF, service mesh, or external KMS solely to claim production-grade security.

## Decision

Phase 12 will harden the existing architecture with practical local-lab controls:

- strengthen and validate Keycloak realm security settings while retaining OIDC Authorization Code Flow with PKCE
- keep browser token handling in the existing public-client React model and document the `sessionStorage` tradeoff
- add security headers through FastAPI middleware and Traefik header middlewares
- restrict CORS to the expected portal origin
- add lab-appropriate in-process API rate limiting for high-impact desktop operations
- add stricter Pydantic and path-parameter validation for user-controlled inputs
- add centralized log redaction and audit detail redaction
- add tamper-evident hash chaining to application audit events
- add admin-only JSON Lines audit export for SIEM readiness
- validate VDIForge Kubernetes RBAC and NetworkPolicies with positive and negative tests
- add dependency and custom-container scanning with free tools

Phase 12 will not deploy a production SIEM, external secrets manager, Vault cluster, enterprise WAF, service mesh, cloud KMS, or Phase 13 GitHub Actions workflows.

## Alternatives Considered

- **Backend-for-frontend session architecture now.** This would reduce browser token exposure but would require a larger authentication redesign and additional session/CSRF controls. It is deferred because the current public-client PKCE model is suitable for the local portfolio lab and already validates token claims server-side.
- **External secrets manager or Vault cluster.** This would improve secret lifecycle management but adds operational complexity and is outside the zero-cost, reliable-demonstration goal.
- **Distributed rate limiting.** Redis or another shared limiter would make limits consistent across HPA replicas, but the current risk is covered acceptably by quota, idempotency, authentication, and in-process throttling for the small lab.
- **Immutable external audit sink.** A SIEM or object-lock storage target would improve audit durability, but Phase 12 implements a simpler hash chain and export path while documenting local database limitations.

## Consequences

- The platform has stronger guardrails without changing the major architecture.
- Security validation becomes repeatable through Phase 12 scripts.
- Audit records are tamper-evident and exportable, but not protected from a fully privileged database administrator in the local lab.
- API rate limiting is intentionally limited by HPA pod locality and should be revisited before production.
- Phase 13 can wire the static portions of these validations into GitHub Actions without needing to redesign the controls.
