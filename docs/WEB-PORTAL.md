# React Self-Service Portal

Phase 9 implements the user-facing VDIForge portal. It provides authenticated browser workflows for image discovery, desktop launch, lifecycle polling, remote connection handoff, and desktop cleanup while preserving the existing backend, Keycloak, Guacamole, and KubeVirt boundaries.

Phase 12 keeps the Phase 9 portal architecture and adds browser-facing security hardening through Traefik headers, restricted API CORS, and explicit token/session documentation.

## Status

| Item | Value |
| --- | --- |
| Portal URL | `https://vdiforge.local` |
| React | `19.2.8` |
| TypeScript | `6.0.3` |
| Vite | `8.2.2` |
| OIDC client | `oidc-client-ts 3.5.0` |
| Test runner | `Vitest 4.1.10` |
| Browser E2E | `Playwright 1.62.1` |
| Container image | `localhost/vdiforge-frontend:0.9.0` |
| Helm chart | `helm/vdiforge` version `0.12.0` |
| Runtime config | ConfigMap-mounted `/runtime-config.js` |

## Architecture

```text
Browser
  |
  | HTTPS
  v
VDIForge React portal
  |
  +-- OIDC Authorization Code + PKCE --> Keycloak
  |
  +-- HTTPS bearer-token API calls ------> FastAPI
                                               |
                                               v
                                         PostgreSQL / KubeVirt
                                               |
                                               v
                                      Guacamole handoff URL
  |
  +-- exact returned URL ----------------> Apache Guacamole
                                               |
                                               v
                                        Ubuntu desktop VM
```

The portal is a browser client. It is not an authorization authority and receives no Kubernetes ServiceAccount token, Guacamole administrative credentials, xrdp password, PostgreSQL password, or OIDC client secret.

## Frontend Stack

The implementation under [frontend](../frontend) uses:

- React and TypeScript for the browser app
- Vite for local development and production build
- `oidc-client-ts` for Authorization Code Flow with PKCE
- a centralized API client in [frontend/src/api/client.ts](../frontend/src/api/client.ts)
- Vitest and React Testing Library for unit/component tests
- Playwright for browser workflow tests
- an nginx-based non-root production container

Important dependencies are pinned in [frontend/package.json](../frontend/package.json) and locked in [frontend/package-lock.json](../frontend/package-lock.json). TypeScript `6.0.3` is intentionally used instead of the newest TypeScript line because the selected `typescript-eslint` release supports TypeScript versions below `6.1`.

## Runtime Configuration

Static builds do not hardcode environment-specific values into multiple components. The production container serves:

```text
/runtime-config.js
```

Helm mounts this file from ConfigMap `vdiforge-frontend-runtime-config` with:

```yaml
apiBaseUrl: https://api.vdiforge.local
oidcAuthority: https://auth.vdiforge.local/realms/vdiforge
oidcClientId: vdiforge-frontend
oidcRedirectUri: https://vdiforge.local/oidc/callback
oidcPostLogoutRedirectUri: https://vdiforge.local/
sessionPollIntervalMs: 5000
```

Only public endpoints and non-sensitive client settings belong in this config. Secrets must be supplied through server-side Secret mechanisms in later phases, not to the browser.

## Authentication

The portal uses existing Keycloak realm `vdiforge` and public client `vdiforge-frontend`.

Flow:

1. User opens `https://vdiforge.local`.
2. Unauthenticated session shows a sign-in action.
3. The browser redirects to Keycloak using Authorization Code Flow with PKCE S256.
4. Keycloak returns an authorization code to `/oidc/callback`.
5. `oidc-client-ts` exchanges the code using the PKCE verifier.
6. The portal stores session state in browser `sessionStorage`.
7. API calls include the access token in the `Authorization` header.

The portal never uses Implicit Flow and has no client secret. Expired tokens trigger the OIDC client renewal/unload path; if renewal is unavailable, the user is returned to sign in.

## API Client

The centralized API client calls:

```text
GET    /api/v1/images
GET    /api/v1/desktops
POST   /api/v1/desktops
POST   /api/v1/desktops/{id}/connect
POST   /api/v1/desktops/{id}/start
POST   /api/v1/desktops/{id}/stop
DELETE /api/v1/desktops/{id}
```

Launch requests include an `Idempotency-Key`. Error handling maps stable backend codes such as `DESKTOP_QUOTA_EXCEEDED`, `IMAGE_NOT_AUTHORIZED`, `DESKTOP_NOT_READY`, and `INSUFFICIENT_CAPACITY` to safe user-facing messages and preserves `request_id` for troubleshooting.

## Portal Features

The portal implements:

- Dashboard counts from real image and desktop API data
- Image Catalog using only images returned by the API
- launch dialog with backend-supported `small` and `standard` resource profiles
- My Desktops table with image, version, profile, created time, and lifecycle state
- polling only while desktops are in transitional states
- Connect enabled only when the backend reports `READY` or `CONNECTED`
- Stop/Start/Delete state rules with delete confirmation
- loading, empty, success, and error states
- responsive layout and keyboard-accessible semantic controls

Lifecycle states are displayed with friendly labels:

| Backend state | UI label |
| --- | --- |
| `REQUESTED` | Request received |
| `PROVISIONING` | Creating desktop |
| `BOOTING` | Starting Ubuntu |
| `READY` | Ready |
| `CONNECTED` | Connected |
| `STOPPING` | Stopping |
| `STOPPED` | Stopped |
| `TERMINATING` | Deleting |
| `TERMINATED` | Deleted |
| `FAILED` | Failed |

## Connect Behavior

The Connect button calls:

```text
POST /api/v1/desktops/{id}/connect
```

The returned `connection_url` is opened exactly as returned by the API. A valid Phase 8 URL has the form:

```text
https://remote.vdiforge.local/?data=...
```

The portal must not rewrite it to `/#/?data=...`, must not reconstruct it manually, and must not expose plaintext remote desktop credentials.

## Deployment

Phase 9 extends the existing VDIForge Helm release with [helm/vdiforge/values-phase9-local.yaml](../helm/vdiforge/values-phase9-local.yaml).

Runtime prerequisites:

```bash
bash scripts/phase9-create-local-secrets.sh
bash scripts/phase9-build-load-frontend-image.sh
```

Install or upgrade with:

```bash
kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --values ./helm/vdiforge/values-phase9-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait \
  --wait-for-jobs
```

The frontend Deployment targets the platform node role label:

```yaml
vdiforge.io/node-role: platform
```

It does not hardcode `vdi-worker-01`.

## NetworkPolicy

Phase 9 adds only the frontend-specific path:

```text
Traefik -> vdiforge-frontend:8080
```

Browser calls to Keycloak, API, and Guacamole arrive through Traefik from outside the cluster. The frontend pod itself serves static assets and does not need Kubernetes API access, direct Keycloak access, direct API access, or remote desktop network access.

## Phase 8 Graphical Session Fix

Phase 8 exposed an xrdp/XFCE defect where the RDP session could authenticate but failed with:

```text
X server could not be started
```

Phase 9 makes the fix permanent in both paths that can create launchable desktops:

- [ansible/roles/image-desktop/tasks/main.yml](../ansible/roles/image-desktop/tasks/main.yml) installs `xserver-xorg-legacy` and writes `/etc/X11/Xwrapper.config`.
- [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py) ensures the `vdiforge` home directory exists, writes `/home/vdiforge/.xsession` with `startxfce4`, fixes ownership, and restarts `xrdp` and `xrdp-sesman` during cloud-init.

The promoted default remote-enabled image is:

```text
ubuntu-devops:1.2.0
```

Rollback affects only which image version is offered for new launches; already-running VMs are not modified.

## Browser Client Prerequisites

A thin client or browser-only workstation needs only:

- browser
- network reachability to the lab ingress IP
- hosts/DNS mapping for `vdiforge.local`, `auth.vdiforge.local`, `api.vdiforge.local`, and `remote.vdiforge.local`
- trust for the generated local development CA

It does not need Terraform, Ansible, kubectl, Helm, Packer, Python development tooling, or a native Guacamole desktop client.

## Phase 12 Security Notes

- The portal does not contain a client secret.
- OIDC login still uses Authorization Code Flow with PKCE.
- The portal stores OIDC state and active tokens in browser `sessionStorage`, not `localStorage`.
- Logout clears the browser-side OIDC session state.
- The portal opens only the opaque Guacamole URL returned by the API.
- Reusable xrdp credentials are never exposed to frontend JavaScript.
- API calls remain subject to backend authorization, CORS, input validation, rate limiting, and audit logging.
- The portal receives Traefik-managed security headers, including a service-specific CSP compatible with the React static app.

## Validation

Static validation:

```powershell
.\scripts\validate-phase9.ps1
```

Live validation from `vdi-control-01`:

```bash
bash scripts/validate-phase9-live.sh
```

The live validator checks cluster health, Helm rendering, frontend rollout, trusted HTTPS portal access, runtime config secrecy, CORS, OIDC/PKCE, role visibility, unauthorized launch denial, desktop launch and polling to `READY`, exact Guacamole URL handoff, audit visibility, deletion cleanup, and KubeVirt/KVM regression health.

To keep repeat validation practical on the current 60 GiB VDI worker, the live validator skips rebuilding `ubuntu-devops:1.2.0` when the CDI source DataVolume and PVC already exist. After a successful source import, it removes only the imported build-host QCOW2 artifact under the ignored Phase 6 build directory and waits for the `vdi-worker-02` `DiskPressure` condition and taint to clear before launching the portal desktop test. The CDI source PVC remains intact.

Manual browser proof:

1. Open `https://vdiforge.local`.
2. Sign in as `demo-devops`.
3. Confirm Ubuntu DevOps is visible.
4. Launch a desktop.
5. Wait for Ready.
6. Click Connect.
7. Confirm Guacamole opens the XFCE desktop without manual VM remediation.
8. Run the DevOps tool commands inside the remote terminal.
9. Stop, start, reconnect, and delete the desktop.

## Troubleshooting

| Symptom | Likely cause | Checks | Remediation |
| --- | --- | --- | --- |
| `vdiforge.local` does not resolve | Missing Windows hosts entry | `Resolve-DnsName vdiforge.local` | Run/update `scripts/phase5-windows-hosts-and-trust.ps1` or add the host entry manually. |
| Browser rejects TLS | Local CA not trusted | certificate warning details | Trust `.local/phase5/tls/vdiforge-local-ca.crt` on the browser client. |
| Portal loads but API calls fail | CORS, token, or API ingress issue | browser network panel, API logs | Verify `VDIFORGE_CORS_ALLOWED_ORIGINS`, API rollout, and Keycloak token audience. |
| Login loops or callback fails | Keycloak redirect URI mismatch | Keycloak client settings | Ensure `https://vdiforge.local/oidc/callback` is configured for `vdiforge-frontend`. |
| Connect opens Guacamole home instead of desktop | stale or expired JSON-auth URL | API response and Guacamole logs | Request a new connection from the portal after the desktop is Ready. |
| RDP login succeeds but XFCE fails | image/cloud-init session config issue | `virtctl console`, `/var/log/xrdp-sesman.log` | Confirm `/home/vdiforge/.xsession` and `/etc/X11/Xwrapper.config` exist in the guest; rebuild/promote the fixed image. |
| Desktop test is unschedulable with disk pressure | VDI worker root disk is holding image build artifacts plus CDI PVC data | `kubectl describe node vdi-worker-02`, `ssh vdi-worker-02 df -h /` | Confirm the CDI source PVC is `Succeeded`/`Bound`, remove only the already-imported ignored QCOW2 build artifact, wait for the disk-pressure taint to clear, then rerun live validation. |

## Limitations

- The dashboard is a user-facing summary only. Prometheus/Grafana observability is implemented separately by Phase 11.
- API HPA autoscaling is implemented in Phase 10; the portal itself remains a single static frontend Deployment in the local lab.
- Browser disconnect telemetry is still limited to API connection requests; detailed Guacamole session telemetry is deferred.
- The portal uses local lab hostnames and a local development CA, not public DNS or production certificate automation.
- Browser `sessionStorage` is acceptable for the local lab but remains exposed to JavaScript running in the same origin. A backend-for-frontend or token-exchange design remains a possible production enhancement.
