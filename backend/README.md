# Backend

This directory is reserved for the planned Python FastAPI backend.

## Planned Responsibilities

- OIDC token validation
- server-side RBAC
- image catalog API
- desktop lifecycle API
- desired state persistence
- asynchronous provisioning coordination
- audit event recording
- Prometheus metrics

## Planned API

```text
POST   /api/v1/desktops
GET    /api/v1/desktops
GET    /api/v1/desktops/{id}
POST   /api/v1/desktops/{id}/start
POST   /api/v1/desktops/{id}/stop
DELETE /api/v1/desktops/{id}

GET    /api/v1/images

GET    /api/v1/health
GET    /api/v1/ready

GET    /metrics
```

No backend implementation is present in Phase 1.
