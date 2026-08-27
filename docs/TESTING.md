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

Planned Python tests:

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

- missing token denied
- expired token denied
- wrong issuer denied
- wrong audience denied
- invalid signature denied
- valid token accepted
- user cannot request unauthorized image
- user cannot retrieve another user's desktop
- admin can view all desktops
- frontend-supplied user ID or role is ignored

## Kubernetes and KubeVirt Tests

Planned tests:

- provisioner can create required KubeVirt resources
- provisioner cannot perform disallowed Kubernetes API operations
- VirtualMachine reaches expected phases
- PVC or DataVolume is created and cleaned up
- Service is created only for the owning desktop
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

Packer:

```bash
packer fmt -check
packer validate
```

Helm:

```bash
helm lint ./helm/vdiforge
helm template vdiforge ./helm/vdiforge
```

Kubernetes manifests:

```bash
kubectl apply --dry-run=server -f <manifest>
```

These commands become active as each area gains implementation files.

## Image Validation

Every image should prove:

- it boots
- guest agent or readiness signal works where used
- remote desktop service starts
- expected tools exist
- no build secrets remain
- package cache is cleaned where appropriate
- version metadata is available
- image can be launched through KubeVirt

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
