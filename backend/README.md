# VDIForge Backend

Phase 7 implements the first VDIForge backend service. Phase 8 extends it with Apache Guacamole session brokering. Phase 9 adds browser-portal support through CORS for `https://vdiforge.local` and the `ubuntu-devops:1.2.0` launch path. Phase 10 adds a protected, local/test-gated load endpoint for API HPA validation. The same Python package runs as either the FastAPI API or the asynchronous KubeVirt provisioner.

## Components

| Path | Purpose |
| --- | --- |
| `app/main.py` | FastAPI application factory and request-ID middleware. |
| `app/api` | REST routes, dependencies, and consistent API errors. |
| `app/auth` | Keycloak JWT validation and RBAC helpers. |
| `app/models` | SQLAlchemy persistence models. |
| `app/services` | image catalog, desktop lifecycle, quota, ownership logic, and Guacamole remote-session brokering. |
| `app/provisioning` | KubeVirt/CDI reconciliation through the Kubernetes Python client. |
| `app/audit` | audit-event persistence. |
| `alembic` | PostgreSQL schema migrations. |
| `tests` | Backend unit/component tests for API, authorization, provisioning, remote access, CORS, and audit behavior. |

## API

```text
GET    /api/v1/health
GET    /api/v1/ready
GET    /api/v1/images
POST   /api/v1/desktops
GET    /api/v1/desktops
GET    /api/v1/desktops/{id}
POST   /api/v1/desktops/{id}/start
POST   /api/v1/desktops/{id}/stop
POST   /api/v1/desktops/{id}/connect
DELETE /api/v1/desktops/{id}
GET    /api/v1/audit-events
GET    /api/v1/health/load-test
GET    /metrics
```

Protected endpoints require a valid Keycloak bearer token. Authorization is enforced server-side.

`GET /api/v1/health/load-test` is disabled by default. It is enabled only by Phase 10 local Helm values and performs bounded CPU work for autoscaling validation without creating desktops or returning sensitive data.

## Local Checks

```powershell
.\scripts\validate-phase10.ps1
```

## Runtime

The Helm chart deploys:

- `vdiforge-api` Deployment and Service
- `vdiforge-provisioner` Deployment
- `vdiforge-app-postgres` StatefulSet and Service
- `vdiforge-api-migrations` Job

The live lab uses image `localhost/vdiforge-api:0.10.0`, imported into containerd on `vdi-worker-01`.

Because the lab reuses local image tags, restart `vdiforge-api` and `vdiforge-provisioner` after importing a rebuilt image. The provisioner creates the per-desktop remote Secret, `DataVolume`, `VirtualMachine`, and Service before waiting for clone readiness so `WaitForFirstConsumer` storage can bind on the VDI worker.
