# ADR 0017: FastAPI Control Plane And Reconciliation Provisioner

## Status

Accepted

## Context

VDIForge needs a backend control plane that authenticates with Keycloak-issued tokens, enforces image and desktop authorization server-side, persists desired desktop state, records audit events, and reconciles desktop requests into KubeVirt resources. The system must not invoke Terraform for each user desktop launch and must not block the initial HTTP request while an Ubuntu VM boots.

The Phase 7 implementation must be demonstrable on the local VirtualBox/Kubernetes/KubeVirt lab without introducing Kafka, RabbitMQ, a service mesh, or another heavy control-plane dependency.

## Decision

Use Python/FastAPI for the API, PostgreSQL for application persistence, Alembic for schema migrations, and a separate long-running provisioner process built from the same backend package. The API records desired state and returns `202 Accepted`; the provisioner reconciles desired state against Kubernetes/KubeVirt using the Kubernetes Python client.

The provisioner runs under the existing `vdiforge-provisioner` ServiceAccount and the namespace-scoped Role in `vdiforge-desktops`. The API ServiceAccount does not mount a Kubernetes API token.

The local lab image for the API/provisioner is built as `localhost/vdiforge-api:0.7.0` and imported into containerd on the platform worker.

## Alternatives Considered

- Synchronous provisioning inside the API request. Rejected because VM boot time is too long and unreliable for a single HTTP request.
- Terraform per desktop launch. Rejected because Terraform owns infrastructure lifecycle, not per-user VM operations.
- Kafka or RabbitMQ for asynchronous provisioning. Deferred because a polling reconciler is sufficient for this MVP and avoids unnecessary infrastructure.
- Shelling out to `kubectl` or `virtctl` from the application. Rejected because the Kubernetes Python client is safer, testable, and easier to constrain.
- SQLite for MVP state. Rejected for the live lab because PostgreSQL better matches the planned multi-pod deployment and audit persistence requirement.

## Consequences

- Phase 7 provides real backend code, persistence, authorization tests, and KubeVirt lifecycle reconciliation.
- PostgreSQL becomes a required local application dependency.
- The provisioner must be carefully tested because its Kubernetes permissions can affect VM lifecycle resources.
- The current local image import workflow is acceptable for the lab but should move to a real registry or CI-built image later.
- Guacamole connection brokering remains a separate Phase 8 design and implementation concern.
