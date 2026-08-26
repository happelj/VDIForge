# VDIForge Requirements

This document defines formal Phase 1 requirements for later implementation phases. Each requirement is intended to support traceability:

```text
Requirement -> Implementation -> Test -> Evidence -> PASS / FAIL
```

## Functional Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| FR-001 | The portal shall authenticate users through Keycloak using OIDC Authorization Code Flow with PKCE. | OIDC integration test with redirect and code exchange. |
| FR-002 | The API shall reject protected requests that do not include a valid bearer access token. | API negative authentication test. |
| FR-003 | The API shall validate JWT signature, issuer, expiration, and expected audience before using token claims. | Unit and integration tests using valid and invalid tokens. |
| FR-004 | The API shall derive user identity and roles only from trusted token claims or trusted backend state. | Authorization unit test and request body tampering test. |
| FR-005 | The image catalog endpoint shall return only images authorized for the authenticated user. | RBAC image listing tests for all demo roles. |
| FR-006 | The launch endpoint shall accept an image ID, approved resource profile, and idempotency key. | API contract test. |
| FR-007 | The launch endpoint shall validate image authorization, resource profile authorization, quotas, and ownership before creating desired state. | API authorization and quota tests. |
| FR-008 | Desktop provisioning shall be asynchronous and shall not keep the initial HTTP request open while an Ubuntu VM boots. | Integration test verifies 202 response before VM readiness. |
| FR-009 | The provisioner shall create or update KubeVirt VirtualMachine resources through the Kubernetes API. | Kubernetes integration test. |
| FR-010 | The provisioner shall manage related PersistentVolumeClaim or DataVolume and Service resources needed for desktop startup and access. | Kubernetes resource assertion test. |
| FR-011 | The API shall expose desktop states using REQUESTED, PROVISIONING, BOOTING, READY, CONNECTED, STOPPING, TERMINATED, and FAILED. | Lifecycle unit and integration tests. |
| FR-012 | A desktop shall record desired state and observed KubeVirt state separately. | Database model and reconciler tests. |
| FR-013 | A normal user shall list and retrieve only desktops owned by that user. | Ownership access tests. |
| FR-014 | An admin shall be able to list all desktops. | Admin authorization test. |
| FR-015 | A normal user shall delete only desktops owned by that user. | Ownership delete tests. |
| FR-016 | An admin shall be able to delete another user's desktop. | Admin delete authorization test. |
| FR-017 | The connect action shall be available only for desktops in READY or CONNECTED states. | API state transition tests. |
| FR-018 | The connect action shall require owner or admin authorization before creating any Guacamole session context. | Connection authorization tests. |
| FR-019 | The frontend shall not receive reusable remote desktop credentials. | Browser/API response inspection test. |
| FR-020 | Desktop deletion shall clean up KubeVirt and Kubernetes resources associated with the desktop. | Cleanup integration test. |
| FR-021 | The backend shall expose `/api/v1/health` for basic process health. | Health endpoint test. |
| FR-022 | The backend shall expose `/api/v1/ready` for dependency readiness. | Readiness endpoint test. |
| FR-023 | The backend shall expose `/metrics` in Prometheus-compatible format. | Metrics scrape test. |
| FR-024 | The system shall record audit events for security-relevant user and administrative actions. | Audit persistence tests. |
| FR-025 | The image catalog shall include Ubuntu Base, Ubuntu Developer, and Ubuntu DevOps variants. | Image catalog seed validation. |
| FR-026 | The thin-client demo shall prove that Terraform, Helm, kubectl, Python, and Git execute inside the remote Ubuntu DevOps VM. | Demo checklist evidence. |

## Non-Functional Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| NFR-001 | The MVP lab shall be runnable with free and open-source software, assuming suitable existing hardware. | Bill-of-materials review. |
| NFR-002 | The MVP shall not require paid AWS resources, AWS bare-metal instances, commercial VMware, Windows licensing, PCoIP licensing, paid Okta, or paid Ping Identity. | Architecture review. |
| NFR-003 | Platform components shall use pinned versions or explicit version ranges approved by an ADR. | Manifest and dependency review. |
| NFR-004 | Infrastructure code shall not commit Terraform state, tfvars containing secrets, generated plans, or provider caches. | Git scan and `.gitignore` validation. |
| NFR-005 | Host configuration shall be idempotent so Ansible playbooks can be rerun without unintended changes. | Ansible idempotency test. |
| NFR-006 | Application deployment shall be repeatable through Helm. | Helm install/upgrade test. |
| NFR-007 | User desktop launch shall not invoke Terraform during the request path. | Code review and integration test. |
| NFR-008 | The system shall avoid Kafka, RabbitMQ, service mesh, OpenStack, Ceph, Vault clusters, Argo CD, Crossplane, and Elasticsearch unless a later ADR justifies the addition. | Architecture review. |
| NFR-009 | API errors shall include a stable error code and request ID. | API error contract tests. |
| NFR-010 | Provisioning retries shall use bounded retry counts and backoff. | Reconciler unit tests. |
| NFR-011 | Provisioning operations shall time out desktops that do not reach expected states within configured limits. | Failure integration test. |
| NFR-012 | Resource requests and limits shall be defined for platform pods. | Kubernetes manifest validation. |
| NFR-013 | The local three-node topology shall be documented as non-HA. | Documentation review. |
| NFR-014 | Future production deployment differences shall be documented separately from MVP requirements. | Documentation review. |

## Security Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| SEC-001 | Authorization decisions shall be enforced server-side by FastAPI. | Authorization tests and code review. |
| SEC-002 | Frontend-hidden buttons shall not be treated as security controls. | Authorization bypass tests. |
| SEC-003 | The provisioner ServiceAccount shall not use `cluster-admin`. | Kubernetes RBAC manifest review. |
| SEC-004 | The provisioner ServiceAccount shall be limited to required verbs and resources in VDI namespaces. | RBAC review and negative Kubernetes API test. |
| SEC-005 | Kubernetes NetworkPolicies shall restrict platform and desktop communication to required paths. | NetworkPolicy connectivity tests. |
| SEC-006 | VDI desktops shall not automatically have privileged access to the Kubernetes API. | In-VM network and credential test. |
| SEC-007 | VDI desktops shall not automatically access Keycloak administration, backend database, monitoring administration, or platform control services. | NetworkPolicy negative tests. |
| SEC-008 | Secrets shall be supplied through approved secret mechanisms and shall not be committed. | Secret scan. |
| SEC-009 | Application logs shall not contain passwords, private keys, raw JWTs, refresh tokens, or similar secrets. | Log redaction tests. |
| SEC-010 | Audit events shall record authorization denials and privileged administrative actions. | Audit integration tests. |
| SEC-011 | Containers shall run as non-root where practical. | Kubernetes security context review. |
| SEC-012 | Images shall be built from trusted Ubuntu sources with checksum or signature verification. | Packer pipeline validation. |
| SEC-013 | Image promotion shall require validation and security checks before the image is offered for launches. | Image pipeline test evidence. |
| SEC-014 | API input shall be validated with Pydantic models before business logic executes. | API validation tests. |
| SEC-015 | TLS shall protect browser-facing endpoints. | Ingress/TLS validation. |
| SEC-016 | Guacamole connection identifiers or URLs shall not allow cross-user desktop access. | Connection guessing negative tests. |

## Observability Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| OBS-001 | The API shall emit Prometheus metrics for request rate, error rate, and latency. | Metrics test and scrape validation. |
| OBS-002 | The API shall emit desktop lifecycle metrics including active, provisioning, and failed desktops. | Metrics integration test. |
| OBS-003 | The provisioner shall emit metrics for provisioning success rate and provisioning latency. | Metrics integration test. |
| OBS-004 | Grafana dashboards shall include P50/P95 provisioning latency. | Dashboard JSON review. |
| OBS-005 | Grafana dashboards shall include API replica count and HPA desired/current replicas. | Dashboard JSON review. |
| OBS-006 | Grafana dashboards shall include pod CPU/memory and worker-node CPU/memory. | Dashboard JSON review. |
| OBS-007 | Grafana dashboards shall include Kubernetes node health and active remote sessions. | Dashboard JSON review. |
| OBS-008 | Application logs shall include timestamp, level, service, request ID, user ID where known, operation, resource ID where relevant, and message. | Log schema test. |
| OBS-009 | Audit events shall include timestamp, event ID, request ID, user ID, action, resource type, resource ID, source IP, result, and details. | Audit schema test. |
| OBS-010 | Request IDs shall propagate from browser/API requests through provisioning and audit records. | Correlation integration test. |

## Operations Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| OPS-001 | A runbook shall document Kubernetes node NotReady troubleshooting. | Runbook review. |
| OPS-002 | A runbook shall document pod Pending and CrashLoopBackOff troubleshooting. | Runbook review. |
| OPS-003 | A runbook shall document insufficient CPU, memory, and storage troubleshooting. | Runbook review. |
| OPS-004 | A runbook shall document Keycloak unavailable, authentication failure, and authorization failure troubleshooting. | Runbook review. |
| OPS-005 | A runbook shall document Guacamole unavailable and VDI connection failure troubleshooting. | Runbook review. |
| OPS-006 | A runbook shall document desktop stuck PROVISIONING and BOOTING troubleshooting. | Runbook review. |
| OPS-007 | A runbook shall document VM boot failure, image unavailable, and provisioning timeout troubleshooting. | Runbook review. |
| OPS-008 | A runbook shall document DNS and TLS troubleshooting. | Runbook review. |
| OPS-009 | CI shall run Phase 1 repository validation on push and pull request. | GitHub Actions workflow review. |
| OPS-010 | Later CI shall include Python lint/tests, frontend lint/tests, Terraform fmt/validate, Ansible lint, Packer validate, Helm lint, manifest validation, dependency scanning, security scanning, and container build validation. | CI design review. |
| OPS-011 | The final demo shall include a pre-flight checklist. | Demo document review. |
| OPS-012 | Phase completion shall include repository validation before merge to `main`. | Git workflow evidence. |

## Requirement Quality Rules

- Every requirement ID must be unique.
- Requirements should describe observable behavior or verifiable design constraints.
- Later phases should create a traceability matrix mapping these IDs to implementation, tests, evidence, and status.
- If a requirement changes, the same ID should be updated intentionally rather than duplicated under a new meaning.
