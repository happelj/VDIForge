# Remote Desktop Delivery

Phase 8 implements the browser-based remote desktop delivery foundation for VDIForge. It deploys Apache Guacamole and `guacd`, adds a server-side FastAPI connect endpoint, brokers short-lived Guacamole JSON auth sessions, and validates RDP reachability to KubeVirt desktops. Phase 9 connects this flow to the React portal.

Phase 9 uses the same server-side broker from the portal: the frontend requests `POST /api/v1/desktops/{id}/connect` only for a READY or CONNECTED desktop, then opens the exact returned Guacamole URL without seeing reusable RDP credentials.

Phase 12 preserves this architecture and adds validation around per-desktop credentials, direct RDP exposure, NetworkPolicies, security headers, and audit redaction.

## Status

| Item | Value |
| --- | --- |
| Guacamole image | `guacamole/guacamole:1.6.0` |
| guacd image | `guacamole/guacd:1.6.0` |
| Namespace | `guacamole` |
| Public hostname | `remote.vdiforge.local` |
| Protocol | RDP through `xrdp` |
| API version | `0.14.0` |
| Session TTL | 300 seconds |
| Runtime secret | `vdiforge-guacamole-json-secret` |
| TLS secret | `vdiforge-guacamole-tls` |
| Remote-enabled image | `ubuntu-devops:1.2.0` |

Authoritative references:

- [Apache Guacamole architecture](https://guacamole.apache.org/doc/gug/guacamole-architecture.html)
- [Apache Guacamole Docker deployment](https://guacamole.apache.org/doc/gug/guacamole-docker.html)
- [Apache Guacamole JSON authentication](https://guacamole.apache.org/doc/gug/json-auth.html)
- [Apache Guacamole OpenID Connect authentication](https://guacamole.apache.org/doc/gug/openid-auth.html)

## Architecture

```text
Browser
  |
  | HTTPS
  v
FastAPI /api/v1/desktops/{id}/connect
  |
  | validate JWT, ownership, state
  v
Kubernetes Secret lookup
  |
  | encrypted Guacamole JSON auth token
  v
Apache Guacamole
  |
  v
guacd
  |
  | RDP 3389 inside cluster
  v
KubeVirt desktop Service
  |
  v
Ubuntu VM running xrdp + XFCE
```

The client does not download or boot Ubuntu. Applications execute inside the remote Ubuntu VM. The browser receives the graphical session through Guacamole over HTTPS/WebSocket and sends keyboard and mouse input back to the remote session.

## Protocol Decision

The MVP uses RDP through `xrdp`.

Rationale:

- Guacamole supports RDP and VNC.
- RDP gives a better Linux desktop experience for the current XFCE image than a minimal VNC setup.
- `xrdp` is installed and validated in the Phase 6 image pipeline.
- RDP uses one well-known service port, which is simple to target with Kubernetes Services and NetworkPolicies.
- VNC remains a documented fallback if a later image or client combination exposes RDP-specific issues.

This does not make the MVP equivalent to PCoIP or any commercial VDI protocol.

## Session Brokering

VDIForge uses Guacamole encrypted JSON authentication for dynamic sessions.

Flow:

1. A user authenticates through Keycloak and receives a valid access token.
2. The user calls `POST /api/v1/desktops/{id}/connect`.
3. FastAPI validates the JWT signature, issuer, audience, expiration, and claims.
4. FastAPI verifies owner/admin authorization and requires the desktop to be `READY` or `CONNECTED`.
5. FastAPI reads the per-desktop remote credential Secret from `vdiforge-desktops`.
6. FastAPI creates a short-lived Guacamole JSON payload containing one connection.
7. FastAPI signs and encrypts the payload using a runtime-only 128-bit JSON secret.
8. The API returns a URL like `https://remote.vdiforge.local/?data=<encrypted-token>`.
9. The browser opens Guacamole, and Guacamole validates the JSON token before connecting through `guacd`.

The frontend receives only the encrypted Guacamole handoff token. It does not receive the reusable desktop password.

For Phase 8, `READY` requires the KubeVirt VMI to be running and ready and the internal desktop Service to accept TCP connections on the configured remote desktop port. This avoids exposing a Connect action while `xrdp` is still starting inside the guest.

## Credential Model

The provisioner creates one Kubernetes Secret per desktop:

```text
<kubevirt-vm-name>-remote
```

The Secret contains:

- `username`
- `password`
- cloud-init `userdata`

The KubeVirt VM consumes the same Secret through `cloudInitNoCloud.secretRef`. The generated password is valid for the in-guest `vdiforge` user used by `xrdp`. The provisioner deletes the Secret when the desktop is deleted, and Phase 8 validation checks cleanup.

This is an MVP-local design. Future hardening should consider one-time credentials, stronger credential rotation, or a dedicated session broker service with a narrower Kubernetes Secret read boundary.

## API

Phase 8 adds:

```text
POST /api/v1/desktops/{id}/connect
```

Success response:

```json
{
  "desktop_id": "uuid",
  "connection_url": "https://remote.vdiforge.local/?data=...",
  "expires_at": "2026-08-28T00:00:00Z",
  "protocol": "rdp"
}
```

Expected denials:

| Condition | Result |
| --- | --- |
| Missing or invalid token | `401` |
| Non-owner without admin role | `403 DESKTOP_ACCESS_DENIED` |
| Unknown desktop ID | `404 DESKTOP_NOT_FOUND` |
| Desktop not ready | `409 DESKTOP_NOT_READY` |
| Guacamole JSON key missing or malformed | `503 REMOTE_ACCESS_NOT_CONFIGURED` |

## Helm Deployment

Runtime-only Phase 8 secrets:

```bash
bash scripts/phase8-create-local-secrets.sh
```

Deploy with identity, API, and remote access enabled:

```bash
kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait \
  --wait-for-jobs
```

Phase 8 deploys:

- `vdiforge-guacamole` Deployment and Service
- `vdiforge-guacd` Deployment and Service
- `vdiforge-guacamole` Ingress for `remote.vdiforge.local`
- Guacamole namespace ResourceQuota and LimitRange
- Guacamole NetworkPolicies
- API RBAC to read per-desktop remote Secrets and Services
- API Kubernetes API egress policy

The Guacamole namespace quota permits the steady-state Guacamole and `guacd` pods plus one rolling replacement of each service. Temporary validation probes use explicit tiny resource limits so they do not consume the namespace defaults.

The Phase 8 and Phase 9 local values raise the `vdiforge-desktops` storage quota to `180Gi` and `16` PVCs. This is declared quota, not a claim that the VirtualBox lab has physically independent 180 GiB storage capacity. The higher cap is needed because validation can temporarily hold historical source images, the current remote-enabled source image, CDI scratch space, and one cloned disposable desktop root volume at the same time.

The Phase 9 remote-enabled validation image overrides the general Phase 6 Packer default with a `15G` virtual disk and imports it into a `20Gi` source DataVolume. This keeps the no-cost VirtualBox lab reproducible on the current 60 GiB VDI worker disk while still proving the Guacamole/RDP session path. Larger production images remain a later deployment-sizing decision.

## NetworkPolicy

The `guacamole` namespace is default-deny when the Phase 8 values file is enabled.

Allowed paths:

| Source | Destination | Port | Purpose |
| --- | --- | ---: | --- |
| Traefik | Guacamole web | 8080 | Browser ingress |
| Guacamole web | guacd | 4822 | Guacamole protocol proxy |
| guacd | desktop VM pods | 3389 | RDP to xrdp |
| provisioner | desktop VM pods | 3389 | Internal readiness probe before marking `READY` |
| Guacamole namespace pods | CoreDNS | 53 | Cluster DNS |

The desktop RDP Service remains `ClusterIP`. It is not exposed directly outside the cluster.

## Validation

Static validation:

```powershell
.\scripts\validate-phase8.ps1
```

Live validation from `vdi-control-01`:

```bash
bash scripts/validate-phase8-live.sh
```

The live validator checks:

- cluster regression health
- KubeVirt/CDI/Calico/Metrics health
- CDI scratch storage configured to `vdiforge-local-path` for qcow2 import/conversion
- Helm lint/render/server dry-run
- runtime-only Phase 8 secrets
- Guacamole and guacd rollout health
- trusted HTTPS access to `remote.vdiforge.local`
- Guacamole restart persistence
- NetworkPolicy allow/deny behavior
- `ubuntu-devops:1.2.0` source PVC preparation
- API image `localhost/vdiforge-api:0.14.0`
- desktop launch to `READY`
- VM placement on `vdi-worker-02`
- KVM request on the virt-launcher pod
- internal RDP Service reachability from the guacd network position
- Guacamole JSON auth token acceptance
- cross-user and guessed-ID denial
- stop, restart, reconnect, delete, and cleanup
- audit events without credential leakage

For a manual browser proof, run the E2E helper with `--keep-desktop`, open the generated `connection_url` from `.local/phase8/browser-connection.json`, and then delete the desktop through the API validation helper or API endpoint.

Phase 12 remote desktop security validation is included in:

```bash
bash scripts/validate-phase12-live.sh
```

It proves that per-desktop xrdp credentials are not returned by the API or audit export, desktop RDP Services remain ClusterIP-only, intended Guacamole-to-desktop traffic works, unrelated pod positions cannot reach RDP, and cross-user or guessed-ID connection attempts are denied.

## Limitations

- Detailed browser disconnect/session telemetry remains deferred.
- Phase 9 proves the user-facing Connect button against the same Guacamole handoff path.
- Guacamole uses JSON auth for dynamic connection handoff and does not persist user-managed connections.
- The API can read per-desktop remote credential Secrets in `vdiforge-desktops`; application authorization gates this access. Kubernetes RBAC cannot restrict those reads by dynamic Secret name prefix.
- Actual connect/disconnect telemetry is limited. The API records connection requests and denials, not every browser disconnect.
- Clipboard and file-transfer policy remain conservative and should be revisited during the final demo hardening phase.
- Local TLS still depends on the generated development CA being trusted on the browser client.
- CDI may require scratch space when importing the remote-enabled qcow2 source image. Phase 8 configures CDI `scratchSpaceStorageClass` to `vdiforge-local-path` during source PVC preparation so the conversion path is reproducible in the local lab.
- The Phase 9 validation image is sized for the current local lab, not for long-lived user profile storage.
- Phase 12 confirms per-desktop xrdp credentials are protected and deleted during desktop cleanup, but live rotation of a running desktop is not the default local-lab workflow. Deleting and relaunching the desktop remains the clean credential-rotation path.

## Phase 12 Security Notes

- `POST /api/v1/desktops/{id}/connect` still requires owner/admin authorization and a connectable desktop state.
- Guacamole JSON-auth handoff remains short-lived and opaque to the portal.
- Per-desktop remote credentials are Kubernetes Secrets in `vdiforge-desktops`.
- NetworkPolicy validation proves intended Guacamole-to-desktop RDP access and denies unrelated pod positions.
- Audit records capture connection requests and denials without storing xrdp or Guacamole secret values.
