# Security Model

This document defines the VDIForge threat model and security controls. Phase 2 local infrastructure controls, Phase 3 Kubernetes foundation controls, Phase 4 Helm platform controls, Phase 5 identity controls, Phase 6 image-pipeline controls, Phase 7 FastAPI control-plane controls, Phase 8 Guacamole remote desktop controls, Phase 9 React portal controls, and Phase 10 API autoscaling controls apply to the current lab. Full Prometheus/Grafana observability remains later-phase work.

## Security Objectives

- Authenticate users through a trusted identity provider.
- Enforce authorization in the backend, not in the browser.
- Prevent cross-user desktop access.
- Limit provisioning permissions in Kubernetes.
- Isolate VDI desktops from platform control services.
- Avoid committing or logging secrets.
- Preserve useful audit evidence for security-relevant activity.

## Trust Boundaries

| Boundary | Description | Control |
| --- | --- | --- |
| Browser to platform | User traffic enters through HTTPS. | TLS, OIDC, CSRF/session controls where applicable. |
| Portal to API | API calls use bearer access tokens. | JWT validation and server-side RBAC. |
| API to Keycloak | API trusts Keycloak issuer metadata and JWKS. | Issuer pinning, JWKS cache, signature validation. |
| API/provisioner to database | Desktop ownership and desired state are stored. | Database credentials in secrets, least privilege, network policy. |
| Provisioner to Kubernetes API | Provisioner creates and deletes VM resources. | Dedicated ServiceAccount, narrow Role/RoleBinding. |
| Guacamole to VDI VM | Remote desktop traffic flows inside the cluster. | NetworkPolicy, short-lived connection authorization. |
| VDI VM to platform | VDI desktops are user workloads. | Deny-by-default policies and no platform credentials in VMs. |

## Threat Model

| Threat | Example | Planned controls |
| --- | --- | --- |
| Unauthorized desktop access | Anonymous user calls desktop APIs. | OIDC required, JWT validation, API authentication middleware. |
| Cross-user desktop access | User guesses another desktop ID or Guacamole connection ID. | Server-side ownership checks, unguessable IDs, connection authorization, no direct RDP/VNC exposure. |
| Privilege escalation | User modifies role claims in browser or request body. | Trust only signed Keycloak tokens and backend state; ignore client-supplied roles. |
| Token theft | Access token leaked from browser, logs, or storage. | Short-lived tokens, no raw JWT logs, TLS, PKCE, no client secret in the browser, and Phase 9 sessionStorage token storage. |
| Compromised VDI VM | Malware in desktop attempts to reach Kubernetes API or database. | NetworkPolicies, no mounted service account token, no platform secrets in images. |
| Compromised provisioning service | Provisioner token used to abuse Kubernetes. | Narrow RBAC, namespace scoping, audit logs, no `cluster-admin`. |
| Kubernetes API abuse | Platform pod has excessive verbs or cluster scope. | Role review, least privilege, negative tests for denied verbs. |
| Malicious or compromised images | Bad package or tampered image offered to users. | Trusted source verification, Packer build logs, Ansible validation, image scanning, promotion gate. |
| Secret exposure | Passwords or private keys committed or logged. | `.gitignore`, secret scanning, structured logging filters, Kubernetes Secrets or external secret store later. |
| Lateral movement | Desktop reaches Keycloak admin, database, monitoring admin, or platform APIs. | Default-deny NetworkPolicies and explicit allow paths. |
| Denial of service | User launches too many desktops or load test creates desktops. | Quotas, resource profiles, admission checks, HPA load test isolated from provisioning. |
| Audit-log tampering | Admin action deletes or modifies audit records. | Append-oriented audit table design, restricted DB permissions, future SIEM forwarding. |

## Authentication Controls

- Keycloak realm: `vdiforge`.
- Frontend client: Authorization Code Flow with PKCE S256.
- Public browser client: no client secret, no implicit flow, no direct access grants, no wildcard redirect URIs, and no wildcard web origins.
- Backend: validate access token signature with Keycloak JWKS.
- Backend validation checks:
  - issuer
  - audience where applicable
  - expiration
  - not-before where available
  - required claims
  - expected signing algorithm
- JWT payloads must not be accepted after simple Base64 decoding.

## Authorization Controls

Application RBAC roles:

```text
vdi-user
vdi-developer
vdi-devops
vdi-admin
```

Authorization is performed in FastAPI for:

- image visibility
- desktop creation
- resource profile selection
- desktop listing
- desktop retrieval
- start, stop, delete
- connection creation
- audit access
- administrative actions

The React UI may hide actions for usability, but all access must be denied by the API if the user lacks permission.

## Kubernetes RBAC

The provisioner is sensitive because it manages KubeVirt resources. It must use a dedicated ServiceAccount.

Phase 3 creates an initial Kubernetes RBAC foundation, and Phase 4 adopts the VDIForge-owned portions into Helm management:

- ServiceAccount `vdiforge-provisioner` in `vdiforge-system`
- Role `vdiforge-provisioner-vdi-manager` in `vdiforge-desktops`
- RoleBinding from the Role to the ServiceAccount

Phase 7 deploys the provisioner application against this privilege boundary.

Conceptual Role scope:

| API group | Resources | Verbs |
| --- | --- | --- |
| `kubevirt.io` | `virtualmachines`, `virtualmachineinstances` | `get`, `list`, `watch`, `create`, `patch`, `update`, `delete` |
| `cdi.kubevirt.io` | `datavolumes` | `get`, `list`, `watch`, `create`, `patch`, `delete` |
| core | `persistentvolumeclaims`, `services`, `events` | `get`, `list`, `watch`, `create`, `patch`, `update`, `delete` |
| core | `secrets` | `get`, `create`, `patch`, `update`, `delete` for per-desktop remote credentials |
| core | `pods` | `get`, `list`, `watch` |

Rules:

- Do not grant `cluster-admin`.
- Prefer namespace-scoped Roles in `vdiforge-desktops`.
- Use ClusterRole only when KubeVirt APIs require cluster-scoped resource access, and keep verbs narrow.
- Do not permit arbitrary Secret listing across namespaces.
- Do not grant Secret access to frontend or Guacamole pods.

## Network Controls

Conceptual allowed paths:

```text
Browser portal -> API
API -> Keycloak
API -> PostgreSQL
Provisioner -> Kubernetes API
Guacamole -> VDI VM
Prometheus -> metrics endpoints
Browser -> Ingress
```

Conceptual denied paths:

- VDI desktop to Kubernetes API
- VDI desktop to Keycloak administration
- VDI desktop to backend database
- VDI desktop to monitoring administration
- direct external access to RDP/VNC ports
- arbitrary cross-user desktop traffic

Calico and Kubernetes NetworkPolicies will enforce namespace and workload-level restrictions. KubeVirt VMI labels should be designed so NetworkPolicies can select desktops by app, owner, and desktop ID where feasible.

Phase 3 proves standard Kubernetes NetworkPolicy enforcement with `scripts/phase3-networkpolicy-test.sh`. The test uses disposable pods to confirm initial traffic, deny ingress, restore an explicit allow rule, and clean up the validation namespace.

Phase 4 adds Helm-managed baseline policies in `vdiforge-system`: default deny for future platform pods, DNS egress, and provisioner-labeled pod egress to the Kubernetes API. It intentionally does not apply a broad default deny to `vdiforge-desktops` yet because KubeVirt VMI networking and remote desktop paths need explicit validation before stronger desktop namespace isolation.

Phase 5 adds Helm-managed identity policies in `keycloak`: default deny, DNS egress, Traefik-to-Keycloak ingress, Keycloak-to-PostgreSQL egress, PostgreSQL ingress from Keycloak only, and a reserved future API-to-Keycloak discovery/JWKS path. The live validation includes an allow/deny test proving arbitrary pods cannot reach Keycloak or PostgreSQL.

Phase 7 enables the API/provisioner policies in `vdiforge-system`: Traefik-to-API ingress, API-to-Keycloak JWKS access, API/provisioner/migration-to-application-PostgreSQL, and PostgreSQL ingress from only those clients. Validation proves an unauthorized namespace cannot reach the API ClusterIP or application PostgreSQL.

Phase 8 enables Guacamole policies in `guacamole`: default deny, DNS egress, Traefik-to-Guacamole web ingress, Guacamole web-to-`guacd`, `guacd` ingress from Guacamole web, and `guacd` egress to VDI desktop pods on TCP 3389. It also enables a narrow `vdiforge-system` egress policy from the provisioner to desktop pods on TCP 3389 so the provisioner can verify the remote desktop port before marking a desktop `READY`. Validation proves the intended Guacamole paths work and unlabeled or unauthorized pods cannot use those paths.

Phase 9 enables the frontend ingress policy in `vdiforge-system`, allowing Traefik to reach the `vdiforge-frontend` Service on TCP 8080. The frontend pod serves static assets only, disables automatic ServiceAccount token mounting, and does not require direct pod-to-pod egress to Keycloak, the API, Guacamole, PostgreSQL, or the Kubernetes API. Browser calls to those services use HTTPS through Traefik.

Phase 10 enables API autoscaling but does not widen the network model. New `vdiforge-api` replicas use the same labels, ServiceAccount, resource limits, ingress path, database access, Keycloak JWKS access, and NetworkPolicy rules as the original API pod.

## Phase 2 Local Infrastructure Security

Current Phase 2 controls:

- The VirtualBox host-only network is private to the workstation and uses `192.168.56.0/24`.
- NAT provides outbound Internet access without intentionally exposing guest services to the public Internet.
- SSH is limited to the local management network.
- Private SSH keys, VM disks, ISOs, Terraform state, and credentials are excluded from Git.
- Password SSH is acceptable only for local bootstrap; key-based SSH should be configured before disabling password login.
- `vdi-worker-02` exposes `/dev/kvm` for future KubeVirt use, but it does not receive Kubernetes credentials or platform control privileges in Phase 2.

Phase 2 does not install Kubernetes, KubeVirt, Keycloak, Guacamole, databases, monitoring, or application workloads.

## Phase 3 Kubernetes Foundation Security

Phase 3 adds these security-relevant controls:

- pinned Kubernetes, Calico, Metrics Server, KubeVirt, CDI, and local-path versions
- Calico CNI with NetworkPolicy support
- NetworkPolicy enforcement validation
- namespace labels for VDIForge foundations
- privileged pod security enforcement only in `vdiforge-desktops`, where KubeVirt launcher pods require it
- baseline pod security enforcement for non-VDIForge desktop namespaces
- initial namespace-scoped provisioner RBAC
- static validation for committed secrets, kubeconfigs, join tokens, and private keys

Phase 3 does not deploy frontend, API, Keycloak, Guacamole, database, Prometheus, Grafana, or desktop image workloads.

## Phase 4 Helm Platform Security

Phase 4 adds these security-relevant controls:

- Helm-managed `vdiforge-api` ServiceAccount with automatic token mounting disabled
- Helm-managed `vdiforge-provisioner` ServiceAccount for future Kubernetes API access
- namespace-scoped provisioner Role and RoleBinding in `vdiforge-desktops`
- no ClusterRoleBinding and no `cluster-admin` grant for VDIForge components
- ResourceQuotas for `vdiforge-system` and `vdiforge-desktops`
- a conservative LimitRange for future platform containers
- baseline NetworkPolicies in `vdiforge-system`
- chart values and ConfigMap conventions that exclude real secrets
- static and live validation for RBAC scope, secret patterns, rendering, and Helm lifecycle behavior

Phase 4 did not deploy Keycloak, Guacamole, FastAPI, React, PostgreSQL, Prometheus, Grafana, or desktop workloads.

## Phase 5 Identity Security

Phase 5 adds these security-relevant controls:

- Keycloak `26.7.2` deployed from the official image.
- PostgreSQL `18.0-alpine` deployed as a single persistent, cluster-internal StatefulSet.
- Traefik chart `41.2.0` deployed as the local HTTPS ingress controller.
- `auth.vdiforge.local` exposed over HTTPS with a generated local development CA.
- Runtime-only Keycloak admin, database, TLS, and demo-user credentials generated under ignored `.local/phase5/` paths.
- `vdiforge` realm imported from sanitized JSON.
- `vdiforge-frontend` public client configured for Authorization Code Flow with PKCE S256.
- `vdiforge-api` audience marker created for future FastAPI token validation.
- JWT tests validate signature, issuer, audience, expiration, required claims, and role claims.
- Negative tests reject invalid credentials, invalid redirect URI, invalid PKCE verifier, tampered JWT, expired JWT, wrong issuer, and wrong audience.
- Demo-user RBAC validation confirms unauthorized role absence.
- Keycloak and PostgreSQL ServiceAccounts disable automatic service account token mounting.

Phase 5 did not implement FastAPI, React, Guacamole, Prometheus, Grafana, desktop authorization, or audit persistence.

## Phase 6 Image Pipeline Security

Phase 6 adds these security-relevant controls:

- Packer `1.16.0`, QEMU plugin `1.1.6`, and Ansible plugin `1.1.6` are pinned.
- The Ubuntu 26.04 LTS amd64 cloud image source is pinned to a published SHA-256 checksum.
- Generated QCOW2 artifacts, checksums, Packer caches, temporary SSH keys, and manifests under `artifacts/` are excluded from Git.
- Packer uses a temporary build SSH key generated under ignored `.local/phase6/`.
- Offline generalization uses `virt-sysprep` to remove the temporary Packer user, temporary sudoers entries, SSH host keys, machine ID, logs, shell history, and temporary files from the final artifact.
- The DevOps image installs Terraform, kubectl, and Helm from pinned binary downloads with SHA-256 checksums.
- The image catalog records role policy but does not implement authorization in the client.
- CDI import uses a temporary host-only HTTP endpoint and validates the artifact checksum.
- The KubeVirt boot proof injects a temporary validation SSH key through cloud-init and removes the disposable VM, DataVolume, and PVC after validation.

Phase 6 does not commit passwords, private SSH keys, kubeconfigs, Kubernetes tokens, OIDC tokens, cloud credentials, or generated disk artifacts.

## Phase 7 API Control Plane Security

Phase 7 adds these security-relevant controls:

- FastAPI validates bearer access tokens with PyJWT and Keycloak JWKS rather than trusting decoded JWT payloads.
- JWT validation checks RS256 signature, issuer `https://auth.vdiforge.local/realms/vdiforge`, audience `vdiforge-api`, expiration, subject, username, and role claims.
- API authorization is server-side for image visibility, desktop launch, ownership reads, start, stop, delete, list-all, and audit access.
- The API ignores client-supplied ownership or role data.
- Desktop launch requires an idempotency key and enforces a bounded per-user active desktop quota.
- Audit events for desktop requests, lifecycle changes, failures, and admin audit access are stored in application PostgreSQL.
- `vdiforge-api` does not mount a Kubernetes ServiceAccount token until Phase 8 requires narrowly scoped Kubernetes reads for remote session brokering.
- `vdiforge-provisioner` uses the namespace-scoped `vdiforge-provisioner-vdi-manager` Role and does not receive cluster-admin.
- Runtime database passwords and API TLS private keys are generated under ignored `.local/phase7` paths and applied as Kubernetes Secrets.
- API/provisioner containers run as non-root where practical with dropped Linux capabilities and read-only root filesystems.

Phase 7 does not expose browser remote desktop credentials and does not deploy Guacamole.

## Phase 8 Remote Desktop Security

Phase 8 adds these security-relevant controls:

- Apache Guacamole `1.6.0` and `guacd` `1.6.0` run in the `guacamole` namespace.
- Guacamole JSON authentication is enabled with a runtime-only 128-bit secret generated outside Git.
- `remote.vdiforge.local` is exposed through Traefik using a generated local TLS certificate signed by the Phase 5 local CA.
- `POST /api/v1/desktops/{id}/connect` requires a valid Keycloak bearer token, owner/admin authorization, and a desktop state of `READY` or `CONNECTED`.
- Non-owners are denied before any Guacamole token is issued.
- Unknown desktop IDs are denied without revealing connection metadata.
- The API returns a short-lived encrypted Guacamole URL and never returns the plaintext RDP password.
- The provisioner creates per-desktop remote credential Secrets and deletes them during desktop cleanup.
- The API ServiceAccount receives only namespace-scoped `get` access to Secrets and Services in `vdiforge-desktops`.
- The provisioner ServiceAccount receives namespace-scoped Secret lifecycle permissions only for per-desktop remote credential management.
- No VDIForge component receives `cluster-admin` or a ClusterRoleBinding.
- Guacamole and `guacd` disable automatic Kubernetes ServiceAccount token mounting.
- The desktop RDP Service remains `ClusterIP`; direct external RDP exposure is not created.
- Connection requests and denials are recorded as audit events without passwords or raw tokens.

Residual Phase 8 security note: Kubernetes RBAC cannot restrict Secret `get` permissions by dynamic name prefix. The MVP compensates with server-side application authorization, explicit audit events, NetworkPolicies, and generated per-desktop credentials. A narrower credential broker or one-time credential flow is a future hardening candidate.

## Phase 9 Web Portal Security

Phase 9 adds these security-relevant controls:

- The React portal authenticates through the existing `vdiforge-frontend` public OIDC client using Authorization Code Flow with PKCE S256.
- The portal has no OIDC client secret and does not use implicit flow or direct access grants.
- Runtime configuration is generated by Helm as public configuration only: API URL, Keycloak authority, public client ID, redirect URIs, and polling interval.
- The frontend image and runtime ConfigMap must not contain passwords, raw JWTs, refresh tokens, Kubernetes credentials, Guacamole secrets, remote desktop credentials, or database credentials.
- Browser access tokens are used only as bearer tokens to FastAPI and are stored in browser `sessionStorage`.
- FastAPI CORS allows the local portal origin `https://vdiforge.local` without making authorization decisions in CORS.
- The frontend ServiceAccount disables automatic Kubernetes API token mounting.
- The frontend container runs non-root with a read-only root filesystem and dropped Linux capabilities.
- The portal opens only the API-returned Guacamole handoff URL and does not reconstruct or decode remote desktop credentials.
- The image role and launch-time cloud-init path now create the XFCE/xrdp session files required for new browser-launched desktops.

Residual Phase 9 security note: browser-held access tokens remain exposed to normal browser risks. Phase 12 should evaluate whether a backend-for-frontend or token exchange pattern is justified for a stronger production design.

## Phase 10 Autoscaling Security

Phase 10 adds these security-relevant controls:

- API autoscaling is implemented by a Helm-managed `autoscaling/v2` HPA for `vdiforge-api`.
- The HPA scales API pod replicas only; it does not create Kubernetes worker nodes, KubeVirt desktops, or additional provisioner workers.
- The dedicated load-test endpoint is disabled by default and enabled only through `values-phase10-local.yaml`.
- `GET /api/v1/health/load-test` requires a valid bearer token and runs through normal FastAPI authentication.
- The load-test endpoint performs bounded CPU work and does not create desktops, write audit events, create KubeVirt resources, or disclose sensitive data.
- The load generator uses authenticated GET requests and is statically checked to avoid `POST /api/v1/desktops`.
- HPA activity is operational infrastructure behavior; it should be investigated through Kubernetes events, HPA status, Metrics Server data, API logs, and Helm values, not through user/security audit events.
- Provisioner HPA is deferred because the current reconciliation loop does not yet have leader election, database row claiming, or another explicit multi-worker coordination mechanism.

Phase 10 does not deploy Prometheus/Grafana, node autoscaling, final CI/CD, SIEM forwarding, or production hardening.

## Secret Handling

Secrets that must not be committed:

- Keycloak admin passwords
- database passwords
- Guacamole database credentials
- Guacamole JSON authentication secret
- per-desktop remote access passwords
- OIDC client secrets
- TLS private keys
- SSH private keys
- raw tokens
- Terraform tfvars containing secrets
- kubeconfigs

Rules:

- Keep demo credentials non-sensitive and documented as disposable.
- Use `.env.example` for variable names only.
- Use Kubernetes Secrets or a later approved secret-management mechanism.
- Do not place secrets in image build logs.
- Do not expose remote desktop credentials to frontend JavaScript.

## Image Security

Golden images must use:

- trusted Ubuntu source media or cloud image sources
- checksum or signature verification where available
- versioned Packer definitions
- Ansible roles for repeatable configuration
- validation after build
- dependency and image scanning where practical
- promotion only after tests pass

Current Phase 6 image security implementation is documented in [Golden Images](GOLDEN-IMAGES.md).

Image rollback affects the catalog entry used for new launches. It does not automatically change running VMs.

## Audit Security

Audit events are security records, not troubleshooting logs. They should record:

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

Required event types include:

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

The MVP can store audit events in PostgreSQL with restricted write behavior. Future phases may forward audit events to a SIEM.

## Residual Risks

- A local single-host lab cannot demonstrate physical failure-domain isolation.
- KubeVirt software emulation may be too slow for a convincing desktop demo.
- The Phase 8 API Secret-read permission is broader than ideal because Kubernetes RBAC cannot select dynamic per-desktop Secret names by prefix.
- Detailed browser disconnect telemetry is not yet implemented.
- Strong tenant isolation is limited in an MVP single-cluster design.
- Local storage failures may affect desktop disk durability.

These risks are acceptable for the portfolio MVP if they remain documented and are validated during later phases.
