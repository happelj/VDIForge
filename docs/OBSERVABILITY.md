# Observability and Auditing

VDIForge observability covers metrics, structured logs, audit events, dashboards, and correlation IDs.

Phase 3 implements the Kubernetes resource-metrics foundation through Metrics Server. Phase 7 adds structured backend logs, request IDs, persistent audit events, and a minimal Prometheus-compatible `/metrics` endpoint for desktop counters. Phase 8 adds audit events for remote connection requests and denials. Phase 9 propagates request IDs from browser API calls and validates portal-driven audit events. Phase 10 uses Metrics Server for the `vdiforge-api` HPA and validates desired/current replica behavior. Prometheus, Grafana, full API latency/rate instrumentation, active-session metrics, and dashboards remain later-phase work.

## Observability Goals

- Show current platform and desktop health.
- Diagnose provisioning failures.
- Separate operational logs from security audit records.
- Support a clear interview demo.
- Leave a path for future SIEM forwarding without requiring a SIEM for the MVP.

## Metrics

Planned application metrics:

| Metric concept | Labels | Purpose |
| --- | --- | --- |
| API request rate | method, route, status | Traffic and error analysis. |
| API latency | method, route, status | User-facing API performance. |
| Active desktops | image, profile | Capacity and demo state. |
| Provisioning desktops | image, profile | Queue and lifecycle visibility. |
| Failed desktops | image, failure_reason | Failure tracking. |
| Provisioning success rate | image, profile | Image and provisioner reliability. |
| Provisioning latency | image, profile | P50/P95 provisioning performance. |
| Active remote sessions | protocol | Remote access usage. |
| Provisioner reconciliations | result | Reconciler health. |
| Provisioner retry count | failure_reason | Failure mode visibility. |

Kubernetes metrics:

- pod CPU/memory
- worker-node CPU/memory
- Kubernetes node health
- pod restarts
- pod Pending counts
- HPA desired/current replicas
- KubeVirt VirtualMachine and VMI phase/condition metrics where available

Phase 3 Metrics Server validation:

```bash
kubectl top nodes
kubectl top pods -A
```

Metrics Server is not a replacement for Prometheus. It provides the Kubernetes resource metrics API used by the Phase 10 API HPA.

## Grafana Dashboard Design

Initial dashboard panels:

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

MVP alerting can be documentation-only until monitoring is implemented. Candidate alerts:

- API error rate above threshold
- API P95 latency above threshold
- provisioner reconciliation failures
- desktop provisioning timeout rate
- KubeVirt unavailable
- worker node NotReady
- pod CrashLoopBackOff
- storage usage high
- Keycloak unavailable
- Guacamole unavailable

## Retention

Initial local retention can be short and lab-friendly. Later phases should define:

- Prometheus retention duration
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

- Which KubeVirt metrics are available from the selected installation without extra exporters?
- Should audit events be stored only in PostgreSQL for MVP or also written to append-only JSON logs?
- What retention duration is appropriate for an interview lab?
