# VDIForge Backend

Phase 7 implements the first VDIForge backend service. The same Python package runs as either the FastAPI API or the asynchronous KubeVirt provisioner.

## Components

| Path | Purpose |
| --- | --- |
| `app/main.py` | FastAPI application factory and request-ID middleware. |
| `app/api` | REST routes, dependencies, and consistent API errors. |
| `app/auth` | Keycloak JWT validation and RBAC helpers. |
| `app/models` | SQLAlchemy persistence models. |
| `app/services` | image catalog, desktop lifecycle, quota, and ownership logic. |
| `app/provisioning` | KubeVirt/CDI reconciliation through the Kubernetes Python client. |
| `app/audit` | audit-event persistence. |
| `alembic` | PostgreSQL schema migrations. |
| `tests` | Phase 7 unit/component tests. |

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
DELETE /api/v1/desktops/{id}
GET    /api/v1/audit-events
GET    /metrics
```

Protected endpoints require a valid Keycloak bearer token. Authorization is enforced server-side.

## Local Checks

```powershell
.\scripts\validate-phase7.ps1
```

## Runtime

The Helm chart deploys:

- `vdiforge-api` Deployment and Service
- `vdiforge-provisioner` Deployment
- `vdiforge-app-postgres` StatefulSet and Service
- `vdiforge-api-migrations` Job

The live lab uses image `localhost/vdiforge-api:0.7.0`, imported into containerd on `vdi-worker-01`.

Because the lab reuses that local image tag, restart `vdiforge-api` and `vdiforge-provisioner` after importing a rebuilt image. The provisioner creates the per-desktop `DataVolume`, `VirtualMachine`, and Service before waiting for clone readiness so `WaitForFirstConsumer` storage can bind on the VDI worker.
