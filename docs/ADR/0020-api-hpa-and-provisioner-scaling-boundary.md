# ADR 0020: API HPA and Provisioner Scaling Boundary

## Status

Accepted

## Context

Phase 10 must demonstrate real Kubernetes HorizontalPodAutoscaler behavior without creating large numbers of VDI desktops or destabilizing the small local lab. The primary autoscaling target is the FastAPI API because it is stateless between requests and stores durable state in PostgreSQL.

The provisioner is more sensitive. It reconciles VDIForge desktop records into CDI DataVolumes, KubeVirt VirtualMachines, Services, and Secrets. The current reconciler is idempotent enough for a single active worker, but it does not yet have leader election, database row claiming, row locks, or another work-partitioning mechanism.

## Decision

Implement a Helm-managed `autoscaling/v2` HPA for `vdiforge-api` only.

The local Phase 10 values enable:

- `minReplicas: 1`
- `maxReplicas: 3`
- CPU target `50%`
- API CPU request `100m`
- API CPU limit `500m`
- bounded scale-up behavior
- 60-second scale-down stabilization

The API receives a protected, local/test-gated `GET /api/v1/health/load-test` endpoint so the HPA can be exercised with authenticated read-only traffic. The endpoint is disabled by default and does not create desktops.

Do not enable provisioner HPA in Phase 10. Leave `provisioner.autoscaling.enabled: false` and document the concurrency requirements for a later phase.

## Alternatives Considered

- Scale the provisioner immediately: rejected because multiple replicas could reconcile the same desktop records without a work-claiming boundary.
- Use desktop launch traffic to trigger autoscaling: rejected because it could create costly or unstable VM churn and would mix autoscaling validation with provisioning validation.
- Use only unauthenticated `/health` requests: rejected because it would not prove token validation, JWKS behavior, or realistic API middleware behavior under multiple replicas.
- Add queue infrastructure for provisioner work: rejected for Phase 10 because it would expand scope beyond autoscaling validation.
- Implement node autoscaling: rejected because the local VirtualBox lab has fixed worker capacity and no infrastructure automation for adding nodes dynamically.

## Consequences

- Phase 10 demonstrates real pod autoscaling for the API while preserving desktop capacity and cluster stability.
- API replicas can validate Keycloak tokens independently and share application state through PostgreSQL.
- HPA behavior remains configurable through Helm values.
- Provisioner throughput remains single-replica until a future concurrency design is implemented.
- Phase 11 should add Prometheus/Grafana visibility for HPA desired/current replicas, API request metrics, pod CPU/memory, and capacity pressure.
