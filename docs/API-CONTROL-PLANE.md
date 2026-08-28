# FastAPI VDI Control Plane

Phase 7 implements the first VDIForge application service: a FastAPI API, PostgreSQL persistence, and an asynchronous provisioner that reconciles VDIForge desktop records into KubeVirt resources.

This phase does not implement Guacamole, React, Prometheus/Grafana, HPA, or production VDI remote access. A desktop reaching `READY` means KubeVirt boot readiness for the managed VM, not browser remote-session availability.

## Version Pins

| Component | Version | Scope | Reference |
| --- | --- | --- | --- |
| Python runtime | 3.14.4 slim | API/provisioner container base | [Python Docker image](https://hub.docker.com/_/python) |
| FastAPI | 0.141.1 | API framework | [FastAPI PyPI](https://pypi.org/project/fastapi/) |
| Pydantic | 2.13.4 | API schema validation | [Pydantic PyPI](https://pypi.org/project/pydantic/) |
| SQLAlchemy | 2.0.52 | ORM | [SQLAlchemy PyPI](https://pypi.org/project/SQLAlchemy/) |
| Alembic | 1.19.1 | database migrations | [Alembic PyPI](https://pypi.org/project/alembic/) |
| psycopg | 3.3.4 | PostgreSQL driver | [psycopg PyPI](https://pypi.org/project/psycopg/) |
| PyJWT | 2.13.0 | JWT validation | [PyJWT PyPI](https://pypi.org/project/PyJWT/) |
| Kubernetes Python client | 36.0.2 | Kubernetes/KubeVirt API access | [kubernetes PyPI](https://pypi.org/project/kubernetes/) |
| PostgreSQL | 18.0-alpine | application state | [PostgreSQL image](https://hub.docker.com/_/postgres) |

## Components

| Component | Location | Responsibility |
| --- | --- | --- |
| FastAPI API | [backend/app](../backend/app) | validates tokens, enforces RBAC/ownership/quotas, exposes image and desktop APIs |
| Alembic migrations | [backend/alembic](../backend/alembic) | creates desktop, operation, and audit-event tables |
| Provisioner | [backend/app/provisioning](../backend/app/provisioning) | reconciles desired desktop state to Kubernetes/KubeVirt resources |
| Helm deployment | [helm/vdiforge](../helm/vdiforge) | deploys API, provisioner, app PostgreSQL, migration job, ingress, and NetworkPolicies |
| Validation | [scripts/validate-phase7.ps1](../scripts/validate-phase7.ps1), [scripts/validate-phase7-live.sh](../scripts/validate-phase7-live.sh) | static and live Phase 7 checks |

## API Surface

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/api/v1/health` | no | process health |
| `GET` | `/api/v1/ready` | no | database and image-catalog readiness |
| `GET` | `/api/v1/images` | yes | list launchable images authorized for caller roles |
| `POST` | `/api/v1/desktops` | yes | request a desktop asynchronously |
| `GET` | `/api/v1/desktops` | yes | list caller-owned desktops; admins may pass `all_users=true` |
| `GET` | `/api/v1/desktops/{id}` | yes | retrieve a desktop if owner or admin |
| `POST` | `/api/v1/desktops/{id}/start` | yes | request start/restart |
| `POST` | `/api/v1/desktops/{id}/stop` | yes | request stop |
| `DELETE` | `/api/v1/desktops/{id}` | yes | request deletion and cleanup |
| `GET` | `/api/v1/audit-events` | admin | inspect audit events |
| `GET` | `/metrics` | no | minimal Prometheus-compatible desktop counters |

API errors use:

```json
{
  "error": {
    "code": "STABLE_ERROR_CODE",
    "message": "Human-readable message.",
    "request_id": "correlation-id"
  }
}
```

## Authorization

FastAPI validates bearer access tokens against Keycloak:

- RS256 signature through the Keycloak JWKS endpoint
- issuer `https://auth.vdiforge.local/realms/vdiforge`
- audience `vdiforge-api`
- expiration
- subject and username claims
- role claims from `roles` and `realm_access.roles`

The validated issuer remains the browser-facing URL:

```text
https://auth.vdiforge.local/realms/vdiforge
```

Inside the cluster, the API uses an explicit internal JWKS URL:

```text
http://vdiforge-keycloak.keycloak.svc.cluster.local:8080/realms/vdiforge/protocol/openid-connect/certs
```

This keeps token issuer validation aligned with browser/OIDC flows while avoiding dependence on the Windows hosts file from inside Kubernetes pods.

Authorization is server-side. The API ignores client-supplied owners or roles.

Phase 7 launchable image state:

| Image | Version | Catalog lifecycle | Source PVC | Launchable |
| --- | --- | --- | --- | --- |
| `ubuntu-base` | `1.0.0` | `candidate` | not created | no |
| `ubuntu-developer` | `1.0.0` | `candidate` | not created | no |
| `ubuntu-devops` | `1.0.0` | `available` | `vdiforge-golden-ubuntu-devops-1-0-0` | yes for `vdi-devops` and `vdi-admin` |

## Desktop State

The database stores desired and observed state separately.

```mermaid
stateDiagram-v2
  [*] --> REQUESTED
  REQUESTED --> PROVISIONING
  PROVISIONING --> BOOTING
  BOOTING --> READY
  READY --> STOPPING
  STOPPING --> STOPPED
  STOPPED --> PROVISIONING
  READY --> TERMINATING
  STOPPED --> TERMINATING
  TERMINATING --> TERMINATED
  REQUESTED --> FAILED
  PROVISIONING --> FAILED
  BOOTING --> FAILED
```

The Phase 7 API also defines `CONNECTED` as a future state for Phase 8 remote-session integration.

## Provisioning

The launch request returns `202 Accepted` after the database record is created. The provisioner separately reconciles:

1. source golden PVC exists
2. per-desktop CDI `DataVolume` is cloned from the source PVC
3. KubeVirt `VirtualMachine` is created with `runStrategy: Always`
4. ClusterIP Service is created for future SSH/RDP access inside the cluster
5. desktop remains `PROVISIONING` until the `DataVolume` is ready
6. VMI readiness updates the desktop to `READY`

The local `vdiforge-local-path` StorageClass uses `WaitForFirstConsumer`, so the provisioner creates the `VirtualMachine` and Service before waiting for the `DataVolume` clone to finish. This gives Kubernetes a scheduled consumer, allows the PVC to bind on `vdi-worker-02`, and avoids a storage/provisioning deadlock.

Kubernetes operations use the Kubernetes Python client. The backend application does not shell out to `kubectl` or `virtctl`.

## Deployment

Run from `vdi-control-01` after the repository has been copied or cloned there:

```bash
bash scripts/phase7-create-local-secrets.sh
bash scripts/phase7-prepare-golden-source.sh
bash scripts/phase7-build-load-image.sh
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait \
  --wait-for-jobs
```

If Podman or Buildah is present on `vdi-worker-01`, `phase7-build-load-image.sh` builds there over SSH. If neither builder exists, the script uses a temporary BuildKit validation pod and imports the resulting image into containerd on the platform worker. The build/import helper uses temporary privileged validation pods in `vdiforge-desktops`, not `vdiforge-system`, because `vdiforge-system` intentionally enforces baseline pod security while `vdiforge-desktops` is the namespace where KubeVirt privileged launcher behavior is already permitted.

The Phase 7 live validator deletes the previous `vdiforge-api-migrations` Job before Helm upgrade because Kubernetes Job pod templates are immutable. After importing the same local image tag, it restarts the API and provisioner Deployments so the cluster actually runs the freshly loaded image.

The API ingress is:

```text
https://api.vdiforge.local
```

The Windows hosts-file helper now includes `api.vdiforge.local`:

```powershell
.\scripts\phase5-windows-hosts-and-trust.ps1
```

## Security Boundary

- `vdiforge-api` ServiceAccount has `automountServiceAccountToken: false`.
- `vdiforge-provisioner` ServiceAccount has namespace-scoped access to KubeVirt, CDI, PVC, Service, Event, and Pod read resources in `vdiforge-desktops`.
- No VDIForge component receives `cluster-admin`.
- PostgreSQL is ClusterIP-only.
- Runtime database passwords and TLS private keys are generated under `.local/phase7` and committed only as Kubernetes Secrets in the live lab, not as repository files.
- `vdiforge-system` remains default deny; explicit policies allow DNS, Traefik-to-API, API-to-Keycloak, API/provisioner/migration-to-app-PostgreSQL, and provisioner-to-Kubernetes API.
- Provisioner Kubernetes API egress allows both the in-cluster API Service IP `10.96.0.1:443` and the control-plane endpoint `192.168.56.10:6443` for the current kubeadm lab.

## Validation

Static validation:

```powershell
.\scripts\validate-phase7.ps1
```

Live validation from `vdi-control-01`:

```bash
bash scripts/validate-phase7-live.sh
```

Live validation proves:

- cluster health remains intact
- Helm lint/render/server dry-run succeeds
- runtime-only secrets exist
- the `ubuntu-devops:1.0.0` golden source PVC exists
- API image is built and loaded on the platform worker
- API, provisioner, migration job, and app PostgreSQL deploy
- API health and readiness work through trusted HTTPS
- RBAC denies privilege escalation
- NetworkPolicy denies unauthorized direct database and API ClusterIP access
- OIDC tokens are accepted by the API
- unauthorized image launch is denied
- idempotency and quota checks work
- desktop launch reaches KubeVirt `READY` on `vdi-worker-02`
- virt-launcher requests `devices.kubevirt.io/kvm`
- stop, restart, delete, and Kubernetes cleanup pass
- audit events persist after API pod restart

The final Phase 7 live validation passed with Helm release revision `56`, KubeVirt hardware acceleration classified as `KUBEVIRT_KVM_VERIFIED`, and the disposable desktop VM scheduled on `vdi-worker-02` with a `devices.kubevirt.io/kvm` request.

## Limitations

- Only `ubuntu-devops:1.0.0` is launchable in Phase 7.
- The source golden PVC consumes local-path storage and is not physically highly available.
- The API exposes a minimal `/metrics` endpoint; full Prometheus/Grafana dashboards remain Phase 11.
- Browser remote desktop access is not implemented until Phase 8.
- The API image is a local lab image imported into containerd on `vdi-worker-01`; a registry workflow is deferred.
