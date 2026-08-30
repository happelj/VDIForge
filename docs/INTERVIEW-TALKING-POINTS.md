# VDIForge Interview Talking Points

Use this document as a technical prompt sheet for explaining VDIForge in interviews. Keep answers grounded in the implemented local lab and avoid implying that VDIForge reproduces any proprietary platform.

## Opening

VDIForge is a self-service VDI platform built as a local Kubernetes/KubeVirt lab. The interesting engineering work is the control-plane boundary: users authenticate with Keycloak, the API authorizes image and desktop actions, PostgreSQL stores desired state, the provisioner reconciles that state to KubeVirt, and Guacamole brokers browser access without exposing reusable desktop credentials.

## Architecture Decisions

| Decision | Talking Point |
| --- | --- |
| Kubernetes + KubeVirt | Kubernetes manages platform workloads and KubeVirt manages real VM lifecycle. Containers are not treated as VDI desktops. |
| VirtualBox local lab | The user constraint was no new hardware and no paid cloud. VirtualBox on Windows 10 Pro was acceptable after `/dev/kvm` and KubeVirt KVM resources were verified on `vdi-worker-02`. |
| Calico | NetworkPolicy support is required for cross-service isolation and negative security tests. |
| Keycloak | Provides reproducible local OIDC, PKCE, roles, and demo identities without paid IdP services. |
| FastAPI + PostgreSQL | Simple, inspectable control plane with durable desired state and audit persistence. |
| Guacamole + RDP/xrdp | Free browser remote desktop path with server-brokered handoff. It is not PCoIP and is not claimed as equivalent. |
| Helm | Manages repeatable platform/app deployment without introducing GitOps before it is needed. |
| Local-path storage | Sufficient for a single-host lab and simple to reason about; not HA and documented as such. |

## Demo Flow

1. Show the three-node cluster and node labels.
2. Show the VDIForge portal and Keycloak login.
3. Login as different demo users to show role-based image visibility.
4. Login as `demo-devops`, launch Ubuntu DevOps, and watch the desktop reach `READY`.
5. Show KubeVirt VM/VMI/DataVolume/Service resources and `vdi-worker-02` placement.
6. Click Connect and open the Guacamole browser desktop.
7. Run `hostname`, `terraform version`, `helm version`, `kubectl version --client`, `python --version`, and `git --version` inside the remote desktop.
8. Show Grafana and API/HPA metrics.
9. Show audit events and export.
10. Delete the desktop and show Kubernetes cleanup.

## Questions To Expect

### Why not just run Linux desktops in containers?

VDIForge intentionally uses KubeVirt because the target is VM lifecycle management. Containers are useful for platform services, but they are not a substitute for full desktop VMs when the goal is VDI behavior, guest OS isolation, and VM scheduling.

### Why VirtualBox instead of KVM/libvirt?

Linux KVM/libvirt remains the preferred architecture, but the available host was Windows 10 Pro with no spare SSD and no budget for cloud or new hardware. The project documented that constraint and verified VirtualBox nested virtualization by checking `/dev/kvm`, CPU flags, and KubeVirt KVM device allocation.

### What prevents one user from accessing another user's desktop?

The frontend hides buttons only for usability. Enforcement happens server-side. The API validates JWTs, derives identity and roles from trusted claims, checks desktop ownership, rejects guessed IDs, and issues Guacamole handoff URLs only after authorization succeeds.

### How are credentials handled?

Local secrets are generated outside Git, stored in Kubernetes Secrets or ignored local files, and redacted from logs and audit exports. Per-desktop xrdp credentials are disposable and deleted with the desktop. The frontend never receives reusable RDP credentials.

### What is the control plane's source of truth?

Keycloak owns identity. VDIForge owns desktop ownership, desired state, and audit events. Kubernetes/KubeVirt expose actual VM state. Terraform describes infrastructure, Ansible configures hosts and images, and Helm deploys platform resources.

### What are the main production gaps?

The local lab is not HA, local-path storage is not production storage, Keycloak/PostgreSQL/Grafana are single-instance local deployments, certificates are local CA material, and rate limiting is per API pod. Production would need HA control plane, production storage, external secret management, managed DNS/TLS, shared rate limiting, backup/restore, and hardened network boundaries.

## Strong Signals To Emphasize

- Clear separation between authentication, application authorization, and Kubernetes RBAC.
- Asynchronous provisioning instead of holding HTTP requests open while VMs boot.
- Desired-vs-observed state reconciliation.
- Role-based image catalog and server-side launch authorization.
- KubeVirt KVM verification, not just `/dev/kvm` existence.
- Audit logs are separate from application logs and include tamper-evident hash metadata.
- HPA is demonstrated for the API only and is not misrepresented as node autoscaling.
- CI avoids live-lab secrets and does not pretend GitHub-hosted runners can run the KVM/Guacamole path.
