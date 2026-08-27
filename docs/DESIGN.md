# VDIForge Technical Design

This document is the authoritative technical design for VDIForge. Later implementation phases must update this document or create an ADR before deviating from these decisions.

## Status

Phase 2 local infrastructure foundation is documented and host-validated. The full VDI platform remains planned: Kubernetes, KubeVirt, Keycloak, Guacamole, FastAPI, React, Helm application deployment, Packer image automation, and Prometheus/Grafana are not implemented yet.

## Goals

- Provide a small self-service VDI platform suitable for a senior platform engineering portfolio.
- Keep the MVP reproducible on local hardware with approximately zero infrastructure and software licensing cost.
- Use real VM lifecycle management through KubeVirt, not desktop-like containers.
- Use OIDC and server-side authorization for access decisions.
- Keep the design simple enough to demonstrate reliably in an interview setting.
- Make infrastructure, host configuration, application deployment, and image build responsibilities explicit.
- Design observability, audit logging, security controls, operations, and tests before implementation.

## Non-Goals

- Production high availability for the first local lab.
- Paid AWS resources, AWS bare-metal instances, commercial VMware, commercial VDI products, Windows desktops, PCoIP licensing, paid Okta, or paid Ping Identity.
- Reproducing any proprietary cloud provider architecture.
- Adding Kafka, service meshes, OpenStack, Ceph, Vault clusters, Argo CD, Crossplane, or Elasticsearch without a specific later requirement.
- Synchronous VM provisioning inside a single HTTP request.
- Treating frontend visibility controls as security.

## Design Principles

- Reproducibility: later phases should be rebuildable from source-controlled definitions and documented commands.
- Idempotency: provisioning and configuration should tolerate retries.
- Least privilege: application services and Kubernetes ServiceAccounts receive only the permissions they need.
- Separation of concerns: Terraform, Ansible, Helm, Packer, Kubernetes, and application code have distinct ownership.
- Declarative configuration: desired state should be expressed in code where practical.
- Immutable images: patched desktops are produced by rebuilding versioned images.
- Observability by design: metrics, logs, dashboards, and audit records are first-class requirements.
- Security by design: authentication, authorization, secret handling, and network isolation are part of the baseline.
- Testability: requirements are written so later phases can map implementation and test evidence.
- Portability: local lab choices should not block future bare-metal or cloud deployment.
- Simple failure recovery: operations should be diagnosable with standard Linux, Kubernetes, and application tools.

## Research Baseline

Sources reviewed during Phase 1:

- KubeVirt installation requirements and runtime support: [KubeVirt installation guide](https://kubevirt.io/user-guide/cluster_admin/installation/)
- KubeVirt Kubernetes compatibility policy: [KubeVirt Kubernetes compatibility](https://github.com/kubevirt/kubevirt/blob/main/docs/kubernetes-compatibility.md)
- KubeVirt software emulation fallback: [KubeVirt software emulation](https://github.com/kubevirt/kubevirt/blob/main/docs/software-emulation.md)
- KubeVirt architecture: [KubeVirt architecture](https://github.com/kubevirt/user-guide/blob/main/docs/architecture.md)
- Kubernetes active release support: [Kubernetes releases](https://kubernetes.io/releases/)
- Calico Kubernetes support and NetworkPolicy behavior: [Calico system requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements)
- Calico and KubeVirt networking notes: [Calico KubeVirt networking](https://docs.tigera.io/calico/latest/networking/kubevirt/kubevirt-networking)
- KubeVirt NetworkPolicy behavior: [KubeVirt NetworkPolicy](https://kubevirt.io/user-guide/network/networkpolicy/)
- Apache Guacamole architecture and protocol support: [Guacamole architecture](https://guacamole.apache.org/doc/gug/guacamole-architecture.html) and [Guacamole configuration](https://guacamole.apache.org/doc/gug/configuring-guacamole.html)
- Keycloak OIDC flows and role claims: [Keycloak server administration guide](https://www.keycloak.org/docs/latest/server_admin/)
- Terraform libvirt provider status: [dmacvicar/libvirt Terraform provider](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs)
- Phase 2 local host implementation: [Local Infrastructure](LOCAL-INFRASTRUCTURE.md)

## Candidate Version Pins

These pins are design inputs as of 2026-08-26. Implementation phases must re-check patch releases before installing and must record any change in an ADR.

| Component | Candidate pin | Rationale |
| --- | --- | --- |
| Ubuntu Server | 26.04 LTS | Actual Phase 2 node baseline installed from `ubuntu-26.04-live-server-amd64.iso`; Phase 3 must validate Kubernetes/KubeVirt on this OS and kernel. |
| Kubernetes | 1.36.2 | Active Kubernetes release line per Kubernetes release documentation. |
| KubeVirt | 1.9.0 | Release notes state it targets Kubernetes 1.36 and supports the previous two minor releases. |
| Calico | 3.32.1 | Calico 3.32 documentation lists Kubernetes 1.34, 1.35, and 1.36 as tested versions. |
| Terraform local lab | Terraform 1.15.8 with built-in `terraform_data` | Actual Phase 2 host uses VirtualBox; Terraform validates the lab specification without depending on an alpha VirtualBox provider. |
| Apache Guacamole | 1.6.0 | Current documented Guacamole release with RDP, VNC, SSH, WebSocket, and container deployment support. |

No implementation phase should use floating `latest` tags for platform components, images, or charts.

## Infrastructure Design

The initial lab uses three Ubuntu Server Kubernetes nodes:

| Node | Kubernetes role | Intended workload class |
| --- | --- | --- |
| `vdi-control-01` | control-plane node | Kubernetes control plane |
| `vdi-worker-01` | worker node | Platform services such as API, Keycloak, Guacamole, PostgreSQL, monitoring |
| `vdi-worker-02` | worker node | VDI-oriented workloads, KubeVirt VirtualMachineInstances |

The nodes may initially be VMs running on a free local hypervisor. The preferred no-cost path remains a Linux host with KVM/libvirt because it aligns directly with KubeVirt's KVM dependency and has a stronger Terraform provider story. The actual Phase 2 host cannot use that path, so [ADR 0009](ADR/0009-virtualbox-local-lab-on-windows.md) accepts Oracle VirtualBox 7.2.16 on Windows 10 Pro for this local lab.

Phase 2 actual node resources:

| Node | CPU | RAM | Disk | Host-only IP | Status |
| --- | ---: | ---: | ---: | --- | --- |
| `vdi-control-01` | 2 vCPU | 4096 MiB | 40 GiB | `192.168.56.10` | SSH verified |
| `vdi-worker-01` | 2 vCPU | 6144 MiB | 50 GiB | `192.168.56.11` | SSH verified |
| `vdi-worker-02` | 4 vCPU | 8192 MiB | 60 GiB | `192.168.56.12` | SSH and `/dev/kvm` verified |

Each VM uses NAT for outbound package access and a VirtualBox host-only adapter on `192.168.56.0/24` for host administration and node-to-node traffic.

If all three nodes run on one physical computer, they are only logical failure domains. The lab still demonstrates real Kubernetes concepts:

- control-plane and worker roles
- scheduling
- workload placement
- labels
- taints and tolerations where justified
- affinity
- node failures
- resource requests and limits
- logical node pools

Suggested labels:

```text
vdiforge.io/node-role=platform
vdiforge.io/node-role=vdi
```

Initial scheduling behavior:

- Platform services prefer `vdi-worker-01`.
- KubeVirt VM workloads prefer `vdi-worker-02`.
- Hard scheduling constraints should be used only when a workload truly cannot run elsewhere.
- Soft affinity is preferred for demonstrability unless isolation, hardware, or capacity requires hard placement.

## Kubernetes Design

The local cluster will be built with:

- kubeadm for bootstrap where practical
- containerd as the container runtime
- Calico as the CNI
- Metrics Server for resource metrics
- namespaces for logical separation
- Kubernetes RBAC
- dedicated ServiceAccounts
- resource requests and limits
- NetworkPolicies
- HorizontalPodAutoscaler for eligible stateless platform workloads

Planned namespaces:

| Namespace | Purpose |
| --- | --- |
| `vdiforge-system` | FastAPI, provisioner, frontend, shared app resources |
| `vdiforge-desktops` | KubeVirt desktop resources |
| `keycloak` | Keycloak and its supporting resources |
| `guacamole` | Guacamole web application and guacd |
| `monitoring` | Prometheus, Grafana, exporters |
| `kubevirt` | KubeVirt operator and core components |

Calico is selected because it supports Kubernetes NetworkPolicy, has a current release line tested with Kubernetes 1.34 through 1.36, and has specific KubeVirt networking documentation. The MVP should use standard Kubernetes NetworkPolicy first. Calico-specific policy features may be added later only when standard NetworkPolicy is insufficient.

## KubeVirt Design

KubeVirt is the target VM lifecycle layer. VDIForge creates and reconciles KubeVirt resources through the Kubernetes API.

Planned resource relationship:

```text
VDIForge Desktop
       |
       v
KubeVirt VirtualMachine
       |
       v
VirtualMachineInstance
       |
       +---- PersistentVolumeClaim or DataVolume
       |
       +---- Service
       |
       +---- Remote desktop service inside guest
```

Relevant resource types:

- `VirtualMachine`
- `VirtualMachineInstance`
- `DataVolume` where image import or cloning uses Containerized Data Importer
- `PersistentVolumeClaim`
- `Service`
- `NetworkPolicy`
- `Secret` only for runtime credentials that cannot be avoided

KubeVirt runs VMs in Kubernetes-managed pods and delegates scheduling, networking, and storage integration to Kubernetes while using QEMU/KVM for virtualization.

## Nested Virtualization Feasibility

KubeVirt normally expects hardware virtualization through `/dev/kvm`. For a local cluster where Kubernetes nodes are themselves VMs, the physical CPU must support Intel VT-x or AMD-V and the outer hypervisor must expose nested virtualization into the node VMs.

Feasibility conclusion:

- Best local target: Linux host with KVM/libvirt and nested virtualization enabled for the Kubernetes node VMs.
- Required validation: each Kubernetes worker that may host KubeVirt VMs must expose `/dev/kvm`, load KVM kernel modules, and pass KubeVirt node checks.
- Important limitation: if `/dev/kvm` is unavailable, KubeVirt VM startup may fail unless software emulation is enabled.
- Fallback: KubeVirt `useEmulation: true` can support development-only validation but will be slower and should not be used for a performance-oriented demo.
- Actual Phase 2 result: VirtualBox nested virtualization is verified on `vdi-worker-02` because `svm` flags are visible in `/proc/cpuinfo` and `/dev/kvm` exists inside the guest.

Phase 2 validation commands:

```bash
lscpu | grep -E 'Virtualization|vmx|svm'
lsmod | grep kvm
test -e /dev/kvm
sudo kvm-ok
```

Phase 3 Kubernetes/KubeVirt validation will add:

```bash
kubectl get nodes -o wide
kubectl -n kubevirt get pods
```

This risk is tracked in [ADR 0002](ADR/0002-kubevirt-for-vm-workloads.md) and [ADR 0008](ADR/0008-local-three-node-development-cluster.md).

## Terraform Boundary

Terraform manages infrastructure lifecycle, not per-user desktop launches.

Terraform responsibilities:

- validated local VirtualBox lab specification for this Windows host
- node CPU, memory, disk, role, IP, and SSH-target metadata
- local virtual networks and storage pools where a maintained provider is practical
- reusable infrastructure modules
- future cloud infrastructure
- environment-level variables and outputs

Terraform must not be invoked by the VDIForge application for every Launch click. User desktop lifecycle is handled by the backend calling Kubernetes/KubeVirt APIs.

The maintained `dmacvicar/libvirt` provider remains the preferred candidate for a future Linux KVM/libvirt environment. For the actual Windows/VirtualBox host, Phase 2 intentionally avoids making an alpha or weakly maintained VirtualBox provider authoritative. Terraform uses the built-in `terraform_data` resource to validate and output the lab specification while VM lifecycle remains VirtualBox GUI or `VBoxManage`.

Terraform state, tfvars, credentials, and generated plans must not be committed.

## Ansible Boundary

Ansible configures operating systems and hosts. Phase 2 introduces:

```text
common
security-baseline
```

Later phases add:

```text
containerd
kubernetes-common
kubernetes-control-plane
kubernetes-worker
```

The current Windows host does not provide a native Ansible control environment. Phase 2 ran syntax, lint, connectivity, and idempotency checks from `vdi-control-01` as a temporary Ubuntu VM controller. Ansible does not install Kubernetes in Phase 2.

Ansible also participates in golden image configuration by installing packages, hardening defaults, configuring the remote desktop service, and running validation tasks inside images.

## Helm Boundary

Helm deploys VDIForge application resources into Kubernetes. The eventual local deployment command should approximate:

```bash
helm upgrade --install vdiforge ./helm/vdiforge
```

Planned chart resources:

- frontend Deployment, Service, Ingress
- FastAPI Deployment, Service, Ingress
- provisioning worker Deployment
- ConfigMaps
- ServiceAccounts
- Kubernetes Roles and RoleBindings
- NetworkPolicies
- HPA definitions

Third-party systems such as Keycloak, PostgreSQL, Prometheus, Grafana, and Guacamole should use established upstream charts or images when that is simpler and safer than maintaining custom manifests.

## Ubuntu Image Architecture

Initial image catalog:

| Image | Purpose |
| --- | --- |
| `ubuntu-base:v1.0.0` | Minimal graphical Ubuntu desktop suitable for remote access. |
| `ubuntu-developer:v1.0.0` | Developer desktop with Git, Python, build tools, CLI utilities, and a graphical editor or IDE. |
| `ubuntu-devops:v1.0.0` | Infrastructure desktop with Terraform, Ansible, kubectl, Helm, Git, Python, and useful infrastructure CLIs. |

Image lifecycle:

```text
Trusted Ubuntu Source
        |
        v
      Packer
        |
        v
      Ansible
        |
        v
   Configuration
        |
        v
    Validation
        |
        v
 Security Checks
        |
        v
 Versioned Artifact
        |
        v
      Testing
        |
        v
     Promotion
```

Patching should rebuild and promote new versioned images. Rollback changes which image version is offered for new launches. Rollback does not automatically modify already-running VMs.

## VDI Control Plane Design

The backend is planned as Python with FastAPI, Pydantic models, and PostgreSQL for MVP persistence. Do not introduce multiple databases for the MVP.

Primary entities:

- `Desktop`
- `Image`
- `ProvisioningOperation`
- `AuditEvent`

Planned API surface:

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

Desktop lifecycle:

```text
REQUESTED -> PROVISIONING -> BOOTING -> READY -> CONNECTED -> STOPPING -> TERMINATED
```

Any appropriate stage may transition to `FAILED`.

Provisioning is asynchronous. The API records desired state and returns quickly. A provisioner reconciles desired state against Kubernetes/KubeVirt observed state using idempotent operations, request IDs, bounded retries, backoff, timeouts, and cleanup logic.

Authoritative sources of truth:

| Domain | Source of truth |
| --- | --- |
| Identity | Keycloak |
| Desktop ownership | VDIForge database |
| Desired desktop state | VDIForge database |
| Actual VM state | Kubernetes/KubeVirt |
| Infrastructure | Terraform |
| Host configuration | Ansible |
| Application deployment | Helm and Kubernetes |

## Identity and Authorization

Keycloak realm:

```text
vdiforge
```

Planned roles:

```text
vdi-user
vdi-developer
vdi-devops
vdi-admin
```

The frontend should use Authorization Code Flow with PKCE. The backend must validate tokens server-side:

- JWT signature through Keycloak JWKS
- issuer
- audience where applicable
- expiration and not-before semantics where available
- expected role and identity claims

The backend must not merely Base64-decode JWT payloads.

Authorization is application-level and happens in FastAPI. Kubernetes RBAC is separate and limits what the provisioner can do to Kubernetes resources. Hidden buttons in the React UI are only user experience controls and must not be treated as authorization.

## RBAC Summary

| Capability | User | Developer | DevOps | Admin |
| --- | ---: | ---: | ---: | ---: |
| Launch Ubuntu Base | Yes | Yes | Yes | Yes |
| Launch Ubuntu Developer | No | Yes | Yes | Yes |
| Launch Ubuntu DevOps | No | No | Yes | Yes |
| View own desktops | Yes | Yes | Yes | Yes |
| Delete own desktop | Yes | Yes | Yes | Yes |
| View all desktops | No | No | No | Yes |
| Delete another user's desktop | No | No | No | Yes |
| Administrative audit access | No | No | No | Yes |

Demo identities:

```text
demo-user
demo-developer
demo-devops
demo-admin
```

No real passwords may be committed.

## Networking Design

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

- VDI desktops to Kubernetes API
- VDI desktops to Keycloak administration
- VDI desktops to backend database
- VDI desktops to monitoring administration
- arbitrary cross-namespace communication
- direct external access to remote desktop ports

NetworkPolicies should default to least privilege. Remote desktop services should be reachable only by Guacamole or the controlled gateway path.

## Storage Design

MVP storage should be simple local storage suitable for a lab. The design must distinguish image artifacts, PVCs used by KubeVirt desktops, PostgreSQL storage, and monitoring storage.

Initial storage goals:

- keep image artifacts versioned
- isolate desktop disks by owner and desktop ID
- support deletion cleanup
- document storage exhaustion behavior
- avoid adding distributed storage until a real need exists

Future options include distributed storage, snapshots, persistent user profiles, backup/restore, and staged image promotion.

## Remote Desktop Design

Target path:

```text
Ubuntu VM
    |
RDP/VNC
    |
Apache Guacamole
    |
HTTPS / WebSocket
    |
Browser
```

MVP protocol decision: use RDP through `xrdp` inside Ubuntu desktops, with VNC as fallback.

Rationale:

- Guacamole supports both RDP and VNC.
- Guacamole documentation notes RDP is generally faster than VNC because of caching.
- `xrdp` is widely used for Linux graphical desktop access.
- VNC remains useful when RDP compatibility or session behavior blocks a lab demo.

Security requirements:

- Do not expose reusable remote desktop credentials to frontend JavaScript.
- Do not let users access desktops by guessing IDs, VM names, Guacamole connection IDs, IP addresses, or URLs.
- Connection creation must be scoped to the authenticated user and desktop ownership.
- Remote desktop ports should not be exposed directly outside the cluster.

## Thin Client Design

The thin-client demo device is intentionally minimal:

- lightweight OS
- networking
- browser

It should not contain Terraform, Helm, kubectl, development Python tooling, or VDIForge backend tools. The final demo should prove that these tools execute inside the remote Ubuntu DevOps VM by running:

```bash
hostname
terraform version
helm version
kubectl version --client
python --version
git --version
```

## Autoscaling Design

Platform autoscaling uses Kubernetes HPA for stateless components such as:

- FastAPI API replicas
- provisioning workers

Initial metrics may be CPU and memory. Future custom metrics may include queue depth or reconciliation lag.

Cluster or node autoscaling is separate. The local lab has fixed worker-node capacity. HPA changes pod replica counts; it does not add physical or virtual Kubernetes worker nodes. True node autoscaling is a future cloud or bare-metal enhancement.

Capacity failures must be handled gracefully with clear API errors, audit events where relevant, and metrics.

## Observability Design

Prometheus metrics should include:

- active desktops
- provisioning desktops
- failed desktops
- provisioning success rate
- P50/P95 provisioning latency
- API request rate
- API error rate
- API latency
- API replica count
- HPA desired/current replicas
- pod CPU/memory
- worker-node CPU/memory
- Kubernetes node health
- active remote sessions

Structured application logs:

```text
timestamp
level
service
request_id
user_id
operation
resource_id
message
```

Audit events:

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

Never log passwords, private keys, raw JWTs, refresh tokens, or other secrets.

## Security Design

Baseline controls:

- OIDC authentication
- server-side authorization
- JWT signature, issuer, audience, and expiration validation
- application RBAC
- Kubernetes RBAC
- dedicated ServiceAccounts
- least privilege Kubernetes Roles
- NetworkPolicies
- TLS
- secure secret handling
- resource quotas
- resource requests and limits
- input validation
- non-root containers where practical
- dependency scanning
- image scanning
- structured audit logging

The provisioning service is sensitive because it creates and deletes KubeVirt resources. It must not receive `cluster-admin`. Its Kubernetes access should be scoped to the VDI namespaces and the minimal resource verbs required.

## Failure Handling

Expected failure classes:

- node NotReady
- pod Pending
- CrashLoopBackOff
- insufficient CPU, memory, or storage
- Keycloak unavailable
- authentication or authorization failure
- Guacamole unavailable
- VDI connection failure
- desktop stuck in provisioning or booting
- VM boot failure
- image unavailable
- DNS or TLS problems

The API should return consistent errors with request IDs. The provisioner should record failed operations, reason codes, retries attempted, and cleanup status.

## Testing Design

Later phases should add:

- Python unit tests
- frontend unit tests
- API integration tests
- OIDC tests
- authorization and ownership tests
- Kubernetes integration tests
- KubeVirt tests
- Terraform validation
- Ansible linting
- Packer validation
- Helm linting
- image validation
- remote desktop integration tests
- end-to-end tests
- negative and failure tests

The core E2E path is:

```text
Authenticate -> List authorized images -> Request desktop -> Observe provisioning
-> Reach READY -> Establish remote session -> Disconnect -> Stop/restart
-> Delete desktop -> Verify cleanup
```

## Local Deployment Plan

Phase 2 produced local infrastructure that can host the planned three-node cluster:

1. Oracle VirtualBox 7.2.16 on Windows 10 Pro.
2. Ubuntu Server 26.04 LTS node VMs named `vdi-control-01`, `vdi-worker-01`, and `vdi-worker-02`.
3. NAT plus host-only networking on `192.168.56.0/24`.
4. SSH access from the host to all nodes.
5. Node-to-node ping validation.
6. `/dev/kvm` validation on `vdi-worker-02`.
7. Terraform specification and outputs under `terraform/environments/local`.
8. Ansible baseline inventory and roles under `ansible`.

Phase 3 begins with Kubernetes prerequisites, kubeadm/containerd installation, CNI installation, Metrics Server, and KubeVirt validation. Phase 2 intentionally does not install these components.

## Future Cloud or Bare-Metal Deployment

Future evolution may include:

- physical bare-metal Kubernetes
- cloud deployment
- HA control plane
- true node autoscaling
- GPU-backed desktops
- distributed storage
- snapshots
- backup/restore
- SIEM integration
- policy engines
- stronger multi-tenancy
- cost accounting or showback

These are not required for the MVP.

## Known Limitations

- The local cluster is not production HA.
- One physical host running all node VMs is a single physical failure domain.
- The current Phase 2 hypervisor is VirtualBox on Windows because bare-metal Linux KVM/libvirt is unavailable to the user.
- VirtualBox VM lifecycle is not fully Terraform-managed in this lab.
- Ansible execution requires a Linux/WSL/Ubuntu controller; Phase 2 validation used `vdi-control-01`.
- KubeVirt software emulation is slow and only acceptable for development fallback.
- Local storage can limit migration and recovery behavior.
- Remote desktop performance will not match commercial proprietary protocols.
- Windows desktops are excluded from the free MVP.
- Version pins must be revalidated during implementation.

## Open Questions

- Which controller should be used for routine Ansible operations after Phase 2: WSL, `vdi-control-01`, or another Linux VM?
- Does Kubernetes 1.36 and the selected KubeVirt release pass validation on Ubuntu Server 26.04 LTS with the current kernel?
- Which storage class will be used for KubeVirt desktop disks in the lab?
- Should Guacamole connection handling use its REST/API integration, a custom extension, or short-lived generated connection records for the MVP?
- What exact resource profiles should be exposed first?
- Which Keycloak configuration-as-code method will be most reproducible for the lab: realm import, Keycloak Operator, Terraform provider, or admin API script?
