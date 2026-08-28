# Security Model

This document defines the VDIForge threat model and security controls. Phase 2 local infrastructure controls, Phase 3 Kubernetes foundation controls, Phase 4 Helm platform controls, Phase 5 identity controls, and Phase 6 image-pipeline controls apply to the current lab. FastAPI application authorization, Guacamole, audit persistence, and application observability remain later-phase work.

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
| Token theft | Access token leaked from browser, logs, or storage. | Short-lived tokens, no raw JWT logs, TLS, secure browser storage pattern in later frontend design. |
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

This is a placeholder privilege boundary for later application phases; no provisioner application is deployed in Phase 3 or Phase 4.

Conceptual Role scope:

| API group | Resources | Verbs |
| --- | --- | --- |
| `kubevirt.io` | `virtualmachines`, `virtualmachineinstances` | `get`, `list`, `watch`, `create`, `patch`, `update`, `delete` |
| `cdi.kubevirt.io` | `datavolumes` | `get`, `list`, `watch`, `create`, `patch`, `delete` |
| core | `persistentvolumeclaims`, `services`, `events` | `get`, `list`, `watch`, `create`, `patch`, `delete` |
| core | `secrets` | `get`, `create`, `patch`, `delete` only if runtime credential storage cannot be avoided |

Rules:

- Do not grant `cluster-admin`.
- Prefer namespace-scoped Roles in `vdiforge-desktops`.
- Use ClusterRole only when KubeVirt APIs require cluster-scoped resource access, and keep verbs narrow.
- Do not permit arbitrary Secret listing across namespaces.

## Network Controls

Conceptual allowed paths:

```text
Frontend -> API
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

Phase 4 adds Helm-managed baseline policies in `vdiforge-system`: default deny for future platform pods, DNS egress, and provisioner-labeled pod egress to the Kubernetes API. It intentionally does not apply a broad default deny to `vdiforge-desktops` yet because Guacamole and VM labels/ports are not implemented.

Phase 5 adds Helm-managed identity policies in `keycloak`: default deny, DNS egress, Traefik-to-Keycloak ingress, Keycloak-to-PostgreSQL egress, PostgreSQL ingress from Keycloak only, and a reserved future API-to-Keycloak discovery/JWKS path. The live validation includes an allow/deny test proving arbitrary pods cannot reach Keycloak or PostgreSQL.

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

Phase 4 does not deploy Keycloak, Guacamole, FastAPI, React, PostgreSQL, Prometheus, Grafana, or desktop workloads.

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

Phase 5 still does not implement FastAPI, React, Guacamole, Prometheus, Grafana, desktop authorization, or audit persistence.

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

## Secret Handling

Secrets that must not be committed:

- Keycloak admin passwords
- database passwords
- Guacamole database credentials
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
DESKTOP_STOPPED
DESKTOP_DELETED
DESKTOP_FAILED
IMAGE_PROMOTED
```

The MVP can store audit events in PostgreSQL with restricted write behavior. Future phases may forward audit events to a SIEM.

## Residual Risks

- A local single-host lab cannot demonstrate physical failure-domain isolation.
- KubeVirt software emulation may be too slow for a convincing desktop demo.
- Guacamole dynamic connection handling requires careful design to avoid exposing backend credentials.
- Strong tenant isolation is limited in an MVP single-cluster design.
- Local storage failures may affect desktop disk durability.

These risks are acceptable for the portfolio MVP if they remain documented and are validated during later phases.
