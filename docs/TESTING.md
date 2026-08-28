# Testing Strategy

VDIForge will use requirements-driven testing. Later phases should trace tests back to [REQUIREMENTS.md](REQUIREMENTS.md).

## Test Pyramid

| Layer | Purpose | Examples |
| --- | --- | --- |
| Unit | Fast feedback on isolated logic. | Pydantic validation, RBAC decisions, lifecycle transitions. |
| Component | Validate service behavior with mocked dependencies. | API routes with mock OIDC/JWKS, provisioner reconciliation with fake Kubernetes client. |
| Integration | Validate real dependencies. | PostgreSQL, Keycloak, Kubernetes API, KubeVirt resources. |
| End-to-end | Validate user workflow. | Authenticate, launch desktop, connect, delete, verify cleanup. |
| Failure | Validate graceful degradation. | Image unavailable, insufficient capacity, token invalid, VM stuck booting. |

## Backend Tests

Phase 7 Python tests cover:

- model validation
- API request validation
- JWT validation
- OIDC metadata handling
- RBAC permission matrix
- desktop ownership enforcement
- idempotency keys
- lifecycle state transitions
- error response format
- audit event creation
- metrics output

Run the Phase 7 backend checks through the repository validator:

```powershell
.\scripts\validate-phase7.ps1
```

## Frontend Tests

Planned React tests:

- OIDC login redirect behavior
- authenticated/unauthenticated route states
- image catalog rendering based on API results
- launch form validation
- desktop lifecycle status rendering
- disabled or hidden controls for usability
- connect button state
- error states

Frontend tests must not be treated as authorization proof. Backend authorization tests are required.

## API Integration Tests

Planned integration tests:

- health and readiness endpoints
- image listing by role
- desktop create/list/get/delete
- admin list/delete behavior
- negative tests for cross-user desktop access
- quota and resource profile checks
- consistent request IDs in responses and logs
- audit events for create, connect, delete, and denied access

## OIDC and Authorization Tests

Required cases:

- Authorization Code Flow with PKCE succeeds
- OIDC discovery endpoint is reachable
- JWKS endpoint is reachable
- signed access token is obtained
- signature validates against JWKS
- missing token denied
- expired token denied
- wrong issuer denied
- wrong audience denied
- invalid signature denied
- valid token accepted
- invalid redirect URI denied
- invalid PKCE verifier denied
- demo identity role claims are correct
- unauthorized role claims are absent
- user cannot request unauthorized image
- user cannot retrieve another user's desktop
- admin can view all desktops
- frontend-supplied user ID or role is ignored

Phase 5 implements the identity-provider side of these tests with `scripts/phase5-oidc-pkce-test.py`. Phase 7 adds backend API authorization tests and a live OIDC/API/KubeVirt workflow through `scripts/phase7-api-e2e-test.py`.

## Kubernetes and KubeVirt Tests

Phase 3 foundation tests:

- kubeadm cluster reaches three Ready nodes
- containerd is active and configured for Kubernetes CRI
- Calico reports Available and pod networking works
- NetworkPolicy deny and allow behavior is proven with disposable resources
- CoreDNS rollout is healthy
- Metrics Server returns node and pod metrics
- local-path StorageClass exists
- CDI is available
- KubeVirt is available
- `vdi-worker-02` exposes `devices.kubevirt.io/kvm` to KubeVirt
- disposable CirrOS VM creates, boots, schedules on `vdi-worker-02`, requests KVM, stops, restarts, deletes, and cleans up

Phase 7 VDIForge application tests:

- provisioner can create required KubeVirt resources
- provisioner cannot perform disallowed Kubernetes API operations
- VirtualMachine reaches expected phases
- PVC or DataVolume is created and cleaned up
- Service is created only for the owning desktop
- image launch is denied when the caller lacks the required role
- launch idempotency replays the original desktop when inputs match
- active desktop quota rejects a second launch for the same non-admin user
- admin-only audit access is enforced

Later remote desktop tests:

- NetworkPolicies allow Guacamole to desktop remote port
- NetworkPolicies deny direct unauthorized access
- failed scheduling transitions desktop to `FAILED` after timeout

## Infrastructure Validation

Phase 2 local infrastructure validation:

```powershell
.\scripts\validate-phase2.ps1
```

Static checks include required files, Terraform formatting and validation, VirtualBox metadata, host-only adapter configuration, `.gitignore` coverage, and secret-pattern scanning.

Live checks are optional because they require key-based non-interactive SSH:

```powershell
.\scripts\validate-phase2.ps1 -Live
```

Manual Phase 2 evidence recorded in [LOCAL-INFRASTRUCTURE.md](LOCAL-INFRASTRUCTURE.md):

- host SSH to `vdi-control-01`, `vdi-worker-01`, and `vdi-worker-02`
- node-to-node ping matrix
- outbound connectivity on all three nodes
- `svm` CPU flags and `/dev/kvm` on `vdi-worker-02`
- Ansible syntax check, `ansible-lint`, Ansible ping, and idempotency run from `vdi-control-01`

Terraform:

```bash
terraform fmt -check
terraform validate
```

Ansible:

```bash
ansible-lint
ansible-playbook --syntax-check
```

The current Windows host does not have a native Ansible control environment. Phase 2 ran these checks from `vdi-control-01` as a temporary Ubuntu VM controller.

Phase 3 static validation:

```powershell
.\scripts\validate-phase3.ps1
```

Phase 3 live validation from `vdi-control-01`:

```bash
cd ~/vdiforge-phase3-validation
bash scripts/validate-phase3-live.sh
```

The live validator runs Ansible syntax/lint checks, cluster health checks, node label checks, Calico/CoreDNS/Metrics Server/KubeVirt/CDI checks, storage checks, NetworkPolicy validation, KVM resource validation, and the disposable KubeVirt VM lifecycle test.

Latest Phase 3 evidence:

```text
Ansible syntax: PASS
ansible-lint: PASS
Final idempotency rerun: changed=0, failed=0, unreachable=0 on all nodes
Phase 3 live validation: PASS
KubeVirt KVM result: KUBEVIRT_KVM_VERIFIED
Disposable VM lifecycle: create, boot, stop, restart, delete, cleanup PASS
```

Packer:

```bash
packer fmt -check
packer validate
```

Helm:

```bash
helm lint ./helm/vdiforge
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --kube-version 1.36.4
```

Phase 4 static validation:

```powershell
.\scripts\validate-phase4.ps1
```

Phase 4 live validation from `vdi-control-01`:

```bash
cd ~/vdiforge-phase4-validation
bash scripts/validate-phase4-live.sh
```

The Phase 4 live validator checks Helm v4.2.4, chart linting, chart rendering, Helm server dry-run validation, node/add-on health, release install, safe upgrade, repeated upgrade, rollback, expected resources, least-privilege RBAC patterns, ResourceQuotas, LimitRange, NetworkPolicies, and continued KubeVirt/KVM availability.

Phase 5 static validation:

```powershell
.\scripts\validate-phase5.ps1
```

Phase 5 live validation from `vdi-control-01`:

```bash
cd ~/vdiforge-phase5-validation
bash scripts/validate-phase5-live.sh
```

The Phase 5 live validator checks Helm rendering, Traefik ingress, runtime-only secret generation, Keycloak/PostgreSQL readiness, platform-worker placement, trusted HTTPS discovery, JWKS, Authorization Code Flow with PKCE, JWT signature/issuer/audience/expiration validation, RBAC role claims, negative security cases, persistence after Keycloak pod recreation, identity NetworkPolicy enforcement, and Phase 1-4 regression health.

Run the focused OIDC helper directly when troubleshooting:

```bash
python3 scripts/phase5-oidc-pkce-test.py \
  --env .local/phase5/phase5.env \
  --ca .local/phase5/tls/vdiforge-local-ca.crt \
  --resolve-ip 192.168.56.11
```

Kubernetes manifests:

```bash
kubectl apply --dry-run=server -f <manifest>
```

These commands become active as each area gains implementation files.

## API Control Plane Validation

Phase 7 static validation:

```powershell
.\scripts\validate-phase7.ps1
```

Phase 7 live validation from `vdi-control-01`:

```bash
cd ~/vdiforge-phase7-validation
bash scripts/validate-phase7-live.sh
```

The Phase 7 live validator checks cluster regression health, Helm lint/render/server dry-run, runtime-only secrets, app PostgreSQL, API/provisioner rollout, trusted HTTPS API health/readiness, least-privilege RBAC, NetworkPolicy denial from an unauthorized namespace, Keycloak-issued token acceptance, image RBAC, idempotency, quota enforcement, ownership checks, KubeVirt `DataVolume`/`VirtualMachine`/Service reconciliation, `vdi-worker-02` placement, KVM resource requests, stop/start/delete lifecycle, cleanup, audit events, and API restart persistence.

## Image Validation

Phase 6 static validation:

```powershell
.\scripts\validate-phase6.ps1
```

Phase 6 live validation from `vdi-control-01`:

```bash
cd ~/vdiforge-phase6-validation
bash scripts/validate-phase6-live.sh
```

The Phase 6 live validator checks:

- all three Kubernetes nodes remain Ready
- Calico, CoreDNS, Metrics Server, KubeVirt, CDI, storage, Helm foundation, Keycloak, PostgreSQL, and Traefik remain healthy
- `vdi-worker-02` still exposes the KubeVirt KVM device resource
- image catalog policy validates
- no generated disk artifacts are tracked by Git
- Packer templates pin Packer, QEMU plugin, Ansible plugin, and Ubuntu source checksums
- Ansible image playbooks pass syntax and lint checks
- Packer templates pass `packer fmt -check` and `packer validate`
- `ubuntu-base`, `ubuntu-developer`, and `ubuntu-devops` build sequentially
- artifact checksums and manifests are generated
- `ubuntu-devops:1.0.0` imports through CDI
- the disposable KubeVirt VM schedules on `vdi-worker-02`
- virt-launcher requests `devices.kubevirt.io/kvm`
- guest SSH becomes ready through cloud-init key injection
- DevOps tools execute inside the guest
- VM stop, restart, delete, and cleanup pass

Every image must prove:

- it boots
- guest agent or readiness signal works where used
- remote desktop prerequisites are present
- expected tools exist
- no build secrets remain
- package cache is cleaned where appropriate
- version metadata is available
- image can be launched through KubeVirt

Packer completion alone is not image validation. At least one versioned artifact, `ubuntu-devops:1.0.0`, must be validated as a real KubeVirt workload for Phase 6 PASS.

## Remote Desktop Integration Tests

Planned checks:

- Guacamole can connect to a READY desktop
- non-owner cannot connect
- guessed desktop ID or connection ID fails
- remote session can disconnect and reconnect
- clipboard policy behaves as configured
- remote desktop ports are not externally exposed

## End-to-End Test

Core E2E flow:

```text
Authenticate
    |
List authorized images
    |
Request desktop
    |
Observe provisioning
    |
Reach READY
    |
Establish remote session
    |
Disconnect
    |
Stop/restart where supported
    |
Delete desktop
    |
Verify cleanup
```

Evidence should include API responses, audit records, Kubernetes resource state, and selected screenshots or logs.

## Negative and Failure Tests

Required classes:

- invalid OIDC token
- unauthorized image
- cross-user access
- capacity exhaustion
- image unavailable
- Kubernetes API permission denied
- KubeVirt VM startup failure
- provisioning timeout
- Guacamole unavailable
- remote desktop service unavailable
- cleanup failure

## CI/CD Plan

GitHub Actions should eventually run:

```text
Python lint
Python tests
Frontend lint
Frontend tests
Terraform fmt
Terraform validate
Ansible lint
Packer validate
Helm lint
Kubernetes manifest validation
Dependency scanning
Security scanning
Container build validation
```

Phase 1 includes a lightweight repository validation workflow only.

## Traceability

Later phases should add a traceability matrix with columns:

```text
Requirement ID
Implementation reference
Test reference
Evidence
Status
Notes
```

No requirement should be marked complete without an implementation reference and test evidence.
