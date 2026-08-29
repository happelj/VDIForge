# Observability and Auditing

VDIForge observability covers metrics, structured logs, audit events, dashboards, and correlation IDs.

Phase 3 implements the Kubernetes resource-metrics foundation through Metrics Server. Phase 7 adds structured backend logs, request IDs, persistent audit events, and a minimal metrics endpoint. Phase 8 adds audit events for remote connection requests and denials. Phase 9 propagates request IDs from browser API calls and validates portal-driven audit events. Phase 10 uses Metrics Server for the `vdiforge-api` HPA and validates desired/current replica behavior.

Phase 11 deploys Prometheus, Grafana, Alertmanager, kube-state-metrics, VDIForge ServiceMonitors, alert rules, and the `VDIForge Overview` dashboard through Helm. The local baseline intentionally disables node-exporter to keep the `monitoring` namespace at baseline Pod Security; node health and capacity panels use kubelet and kube-state metrics. See [Prometheus and Grafana Observability](PROMETHEUS-GRAFANA.md) for operational details.

## Observability Goals

- Show current platform and desktop health.
- Diagnose provisioning failures.
- Separate operational logs from security audit records.
- Support a clear interview demo.
- Leave a path for future SIEM forwarding without requiring a SIEM for the MVP.

## Metrics

Implemented Phase 11 application metrics:

| Metric | Labels | Purpose |
| --- | --- | --- |
| `vdiforge_api_requests_total` | method, route, status_code | Traffic and error analysis. |
| `vdiforge_api_request_duration_seconds` | method, route, status_code | User-facing API latency. |
| `vdiforge_desktop_provision_requests_total` | image_id, result | Accepted, rejected, and replayed launches. |
| `vdiforge_desktop_provision_failures_total` | image_id, reason | Provisioning failure tracking. |
| `vdiforge_desktop_provision_duration_seconds` | image_id, result | P50/P95 provisioning performance. |
| `vdiforge_desktops_active` | none | Current non-terminal desktops. |
| `vdiforge_desktops_by_state` | state | Lifecycle state distribution. |
| `vdiforge_remote_sessions_active` | protocol | Approximate active remote sessions. |
| `vdiforge_provisioner_reconcile_total` | result | Reconciler health. |
| `vdiforge_provisioner_reconcile_failures_total` | reason | Failure mode visibility. |
| `vdiforge_provisioner_reconcile_duration_seconds` | result | Reconcile loop latency. |
| `vdiforge_provisioner_pending_operations` | none | Pending async operations. |

Metrics labels must stay low-cardinality. Do not label by desktop ID, request ID, username, token subject, Guacamole connection ID, raw URL, JWT content, or other unbounded values.

Kubernetes metrics:

- pod CPU/memory
- worker-node CPU/memory
- Kubernetes node health
- pod restarts
- pod Pending counts
- HPA desired/current replicas
- KubeVirt VirtualMachine and VMI phase/condition metrics where available

Metrics Server validation:

```bash
kubectl top nodes
kubectl top pods -A
```

Metrics Server is not a replacement for Prometheus. It provides the Kubernetes resource metrics API used by the Phase 10 API HPA. Phase 11 Prometheus observes HPA status and pod/node metrics but does not become the HPA metrics backend.

Prometheus scrape targets are managed through ServiceMonitors in the existing `monitoring` namespace:

| ServiceMonitor | Target |
| --- | --- |
| `vdiforge-api` | FastAPI `/metrics` on service port `http`. |
| `vdiforge-provisioner` | Provisioner metrics server on port `9102`. |

KubeVirt metrics are integrated by patching the KubeVirt CR with Prometheus Operator monitoring fields.

## Grafana Dashboard Design

Phase 11 dashboard panels:

- active desktops
- provisioning desktops
- failed desktops
- provisioning success rate
- P50/P95 provisioning latency
- API request rate
- API error rate
- API latency
- API replica count
- HPA desired/current replicas
- pod CPU/memory
- worker-node CPU/memory
- Kubernetes node health
- active remote sessions
- pending provisioning operations

Suggested dashboard sections:

1. User-facing status
2. Provisioning health
3. API health
4. Kubernetes capacity
5. Remote access
6. Audit/security summary

## Structured Application Logs

Application logs describe system operation and troubleshooting.

Required fields:

```text
timestamp
level
service
request_id
user_id
operation
resource_id
message
```

Optional fields:

```text
desktop_id
image_id
provisioning_operation_id
status
duration_ms
error_code
retry_count
```

Do not log:

- passwords
- private keys
- raw JWTs
- refresh tokens
- OIDC authorization codes
- database connection strings with passwords
- remote desktop credentials

## Audit Logs

Audit logs describe security-relevant user and administrative actions. They are not a substitute for application logs.

Required fields:

```text
timestamp
event_id
request_id
user_id
action
resource_type
resource_id
source_ip
result
details
```

Potential actions:

```text
LOGIN_SUCCESS
LOGIN_FAILURE
AUTHORIZATION_DENIED
DESKTOP_REQUESTED
DESKTOP_CREATED
DESKTOP_STARTED
DESKTOP_CONNECTED
DESKTOP_CONNECTION_REQUESTED
DESKTOP_CONNECTION_DENIED
DESKTOP_STOPPED
DESKTOP_DELETED
DESKTOP_FAILED
IMAGE_PROMOTED
```

Audit details must be structured JSON and must not contain secrets.

## Correlation IDs

Every user-triggered operation should receive a request ID.

```text
Browser
   |
FastAPI
   |
Provisioner
   |
Kubernetes/KubeVirt
   |
Audit Event
```

Propagation plan:

- Browser sends or receives `X-Request-ID`.
- FastAPI validates or generates the request ID.
- API writes the request ID into application logs and audit events.
- ProvisioningOperation stores the request ID.
- Provisioner logs and metrics include the request ID.
- Kubernetes resources receive labels or annotations where safe.

Labels and annotations must avoid storing sensitive data.

## Alerting Candidates

Phase 11 alert rules:

- `VDIForgeAPIDown`
- `VDIForgeHighAPIErrorRate`
- `VDIForgeHighProvisionFailureRate`
- `VDIForgeSlowProvisioning`
- `KubernetesNodeNotReady`
- `VDIWorkerHighMemory`

Alertmanager is deployed without an external receiver in the local lab. Notification integrations are deferred because they require external credentials.

## Retention

Initial local retention is short and lab-friendly:

| Item | Phase 11 setting |
| --- | --- |
| Prometheus retention time | 3 days |
| Prometheus retention size | 3 GiB |
| Prometheus storage | 5 GiB local-path PVC |
| Alertmanager storage | 1 GiB local-path PVC |
| Grafana storage | 2 GiB local-path PVC |

Later phases should define:

- application log retention
- audit event retention
- backup/export behavior for audit records
- privacy handling for user identifiers

## Demo Requirements

The final demo should show:

- a desktop launch request ID
- status changes in the portal
- corresponding API/provisioner logs
- Kubernetes or KubeVirt resource state
- Phase 10 HPA desired/current replica changes during controlled API load
- a Grafana dashboard panel changing
- an audit event for desktop launch, remote connection request, denial, or deletion

## Open Questions

- Should audit events be stored only in PostgreSQL for MVP or also written to append-only JSON logs?
- Should Grafana authenticate through Keycloak OIDC in Phase 12, and how should Grafana roles map to VDIForge roles?
- What application log collection path should be added before SIEM forwarding is considered?
