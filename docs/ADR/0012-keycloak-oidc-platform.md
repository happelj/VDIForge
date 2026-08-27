# ADR 0012: Keycloak OIDC Platform Deployment

## Status

Accepted

## Context

VDIForge needs a working local identity platform before the backend and frontend phases. The platform must provide OIDC discovery, JWKS, Authorization Code Flow with PKCE, demo identities, role claims, and repeatable configuration without committing secrets.

The Phase 5 lab runs on a constrained three-node Kubernetes cluster. `vdi-worker-01` is the platform worker with approximately 6 GiB RAM. The solution must remain free, understandable, and reproducible. It must not introduce unnecessary operators, HA database clusters, or paid identity services.

Current authoritative references used for the decision:

- [Keycloak downloads](https://www.keycloak.org/downloads.html)
- [Keycloak database configuration](https://www.keycloak.org/server/db)
- [Keycloak import/export](https://www.keycloak.org/server/importExport)
- [Keycloak OIDC endpoint guidance](https://www.keycloak.org/securing-apps/oidc-layers)
- [Keycloak health endpoints](https://www.keycloak.org/observability/health)

## Decision

Deploy Keycloak `26.7.2` with the official `quay.io/keycloak/keycloak` image from the VDIForge Helm chart.

Deploy a single PostgreSQL `18.0-alpine` StatefulSet with a `vdiforge-local-path` PVC for lab persistence. PostgreSQL is cluster-internal only and protected with NetworkPolicies.

Use realm import JSON for the reproducible baseline:

```text
keycloak/realm/vdiforge-realm.json
helm/vdiforge/files/keycloak/vdiforge-realm.json
```

Use a post-import admin CLI script only for runtime-sensitive actions that must not be committed, primarily setting generated demo-user passwords.

Define the OIDC model as:

| Client | Type | Purpose |
| --- | --- | --- |
| `vdiforge-frontend` | public | Future React browser client using Authorization Code Flow with PKCE S256 |
| `vdiforge-api` | audience marker | Future FastAPI audience validation target |

Define roles as realm roles with composite inheritance:

```text
vdi-admin -> vdi-devops -> vdi-developer -> vdi-user
```

Schedule Keycloak and PostgreSQL with the platform node label:

```yaml
vdiforge.io/node-role: platform
```

## Alternatives Considered

- Established third-party Keycloak Helm chart: valid for larger deployments, but adds chart-specific abstraction and configuration surface. A small VDIForge-managed chart is clearer for this lab and uses the official image directly.
- Keycloak Operator: powerful, but introduces operator lifecycle and CRDs that are unnecessary for one local realm.
- Keycloak `dev-file` or ephemeral database: simpler to start, but it would lose configuration across ordinary pod recreation and is not suitable for this phase's persistence requirement.
- External PostgreSQL outside the cluster: reasonable in production, but less reproducible for the local lab.
- Terraform Keycloak provider: potentially useful later, but the initial realm import plus admin CLI script is simpler and avoids another provider/state boundary.

## Consequences

- Phase 5 has a real OIDC issuer that later FastAPI and React phases can consume.
- Realm configuration is reviewable in Git while passwords remain runtime-only.
- Keycloak state survives ordinary pod restart/recreation.
- PostgreSQL is not HA and is tied to local-path storage on the platform worker.
- Moving to production should replace the local PostgreSQL design with managed PostgreSQL or an explicitly operated HA design.
- Future phases must keep server-side authorization in VDIForge; Keycloak role claims are identity inputs, not the complete application policy.
