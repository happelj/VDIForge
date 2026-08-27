# VDIForge Requirements

This document defines formal Phase 1 requirements for later implementation phases. Each requirement is intended to support traceability:

```text
Requirement -> Implementation -> Test -> Evidence -> PASS / FAIL
```

## Functional Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| FR-001 | The portal shall authenticate users through Keycloak using OIDC Authorization Code Flow with PKCE. | OIDC integration test with redirect and code exchange. |
| FR-002 | The API shall reject protected requests that do not include a valid bearer access token. | API negative authentication test. |
| FR-003 | The API shall validate JWT signature, issuer, expiration, and expected audience before using token claims. | Unit and integration tests using valid and invalid tokens. |
| FR-004 | The API shall derive user identity and roles only from trusted token claims or trusted backend state. | Authorization unit test and request body tampering test. |
| FR-005 | The image catalog endpoint shall return only images authorized for the authenticated user. | RBAC image listing tests for all demo roles. |
| FR-006 | The launch endpoint shall accept an image ID, approved resource profile, and idempotency key. | API contract test. |
| FR-007 | The launch endpoint shall validate image authorization, resource profile authorization, quotas, and ownership before creating desired state. | API authorization and quota tests. |
| FR-008 | Desktop provisioning shall be asynchronous and shall not keep the initial HTTP request open while an Ubuntu VM boots. | Integration test verifies 202 response before VM readiness. |
| FR-009 | The provisioner shall create or update KubeVirt VirtualMachine resources through the Kubernetes API. | Kubernetes integration test. |
| FR-010 | The provisioner shall manage related PersistentVolumeClaim or DataVolume and Service resources needed for desktop startup and access. | Kubernetes resource assertion test. |
| FR-011 | The API shall expose desktop states using REQUESTED, PROVISIONING, BOOTING, READY, CONNECTED, STOPPING, TERMINATED, and FAILED. | Lifecycle unit and integration tests. |
| FR-012 | A desktop shall record desired state and observed KubeVirt state separately. | Database model and reconciler tests. |
| FR-013 | A normal user shall list and retrieve only desktops owned by that user. | Ownership access tests. |
| FR-014 | An admin shall be able to list all desktops. | Admin authorization test. |
| FR-015 | A normal user shall delete only desktops owned by that user. | Ownership delete tests. |
| FR-016 | An admin shall be able to delete another user's desktop. | Admin delete authorization test. |
| FR-017 | The connect action shall be available only for desktops in READY or CONNECTED states. | API state transition tests. |
| FR-018 | The connect action shall require owner or admin authorization before creating any Guacamole session context. | Connection authorization tests. |
| FR-019 | The frontend shall not receive reusable remote desktop credentials. | Browser/API response inspection test. |
| FR-020 | Desktop deletion shall clean up KubeVirt and Kubernetes resources associated with the desktop. | Cleanup integration test. |
| FR-021 | The backend shall expose `/api/v1/health` for basic process health. | Health endpoint test. |
| FR-022 | The backend shall expose `/api/v1/ready` for dependency readiness. | Readiness endpoint test. |
| FR-023 | The backend shall expose `/metrics` in Prometheus-compatible format. | Metrics scrape test. |
| FR-024 | The system shall record audit events for security-relevant user and administrative actions. | Audit persistence tests. |
| FR-025 | The image catalog shall include Ubuntu Base, Ubuntu Developer, and Ubuntu DevOps variants. | Image catalog seed validation. |
| FR-026 | The thin-client demo shall prove that Terraform, Helm, kubectl, Python, and Git execute inside the remote Ubuntu DevOps VM. | Demo checklist evidence. |

## Non-Functional Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| NFR-001 | The MVP lab shall be runnable with free and open-source software, assuming suitable existing hardware. | Bill-of-materials review. |
| NFR-002 | The MVP shall not require paid AWS resources, AWS bare-metal instances, commercial VMware, Windows licensing, PCoIP licensing, paid Okta, or paid Ping Identity. | Architecture review. |
| NFR-003 | Platform components shall use pinned versions or explicit version ranges approved by an ADR. | Manifest and dependency review. |
| NFR-004 | Infrastructure code shall not commit Terraform state, tfvars containing secrets, generated plans, or provider caches. | Git scan and `.gitignore` validation. |
| NFR-005 | Host configuration shall be idempotent so Ansible playbooks can be rerun without unintended changes. | Ansible idempotency test. |
| NFR-006 | Application deployment shall be repeatable through Helm. | Helm install/upgrade test. |
| NFR-007 | User desktop launch shall not invoke Terraform during the request path. | Code review and integration test. |
| NFR-008 | The system shall avoid Kafka, RabbitMQ, service mesh, OpenStack, Ceph, Vault clusters, Argo CD, Crossplane, and Elasticsearch unless a later ADR justifies the addition. | Architecture review. |
| NFR-009 | API errors shall include a stable error code and request ID. | API error contract tests. |
| NFR-010 | Provisioning retries shall use bounded retry counts and backoff. | Reconciler unit tests. |
| NFR-011 | Provisioning operations shall time out desktops that do not reach expected states within configured limits. | Failure integration test. |
| NFR-012 | Resource requests and limits shall be defined for platform pods. | Kubernetes manifest validation. |
| NFR-013 | The local three-node topology shall be documented as non-HA. | Documentation review. |
| NFR-014 | Future production deployment differences shall be documented separately from MVP requirements. | Documentation review. |

## Infrastructure Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| INFRA-001 | The local lab shall define exactly three initial nodes named `vdi-control-01`, `vdi-worker-01`, and `vdi-worker-02`. | Terraform spec review, VirtualBox metadata review, and documentation review. |
| INFRA-002 | `vdi-control-01` shall be sized as the future control-plane node with at least 2 vCPU, 4096 MiB RAM, and 40 GiB disk. | Terraform output and VirtualBox metadata review. |
| INFRA-003 | `vdi-worker-01` shall be sized as the future platform worker with at least 2 vCPU, 6144 MiB RAM, and 50 GiB disk. | Terraform output and VirtualBox metadata review. |
| INFRA-004 | `vdi-worker-02` shall be sized as the future VDI worker with at least 4 vCPU, 8192 MiB RAM, and 60 GiB disk. | Terraform output and VirtualBox metadata review. |
| INFRA-005 | The local lab shall provide host-to-node SSH access for all three nodes over a predictable management network. | Host SSH test to each node. |
| INFRA-006 | The local lab shall provide node-to-node network reachability among all three nodes. | Ping matrix from each node to the other nodes. |
| INFRA-007 | The local lab shall provide node outbound Internet access for package installation. | Guest package metadata or outbound connectivity test. |
| INFRA-008 | The future VDI worker `vdi-worker-02` shall expose hardware virtualization to the guest OS before Phase 3 installs KubeVirt. | `/proc/cpuinfo` virtualization flag check and `/dev/kvm` existence check. |
| INFRA-009 | Phase 2 shall not install Kubernetes, KubeVirt, Keycloak, Guacamole, Prometheus, Grafana, or application workloads. | Repository review and node package/service review. |
| INFRA-010 | Phase 2 infrastructure validation shall produce a useful PASS/FAIL summary and distinguish static checks from live infrastructure checks. | `scripts/validate-phase2.ps1` review and execution. |

## Kubernetes Foundation Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| K8S-001 | Phase 3 shall evaluate Ubuntu, Kubernetes, containerd, Calico, Metrics Server, KubeVirt, CDI, and storage compatibility before installing cluster components. | Compatibility matrix review in `docs/KUBERNETES-KUBEVIRT.md`. |
| K8S-002 | The local lab shall run a three-node kubeadm cluster with `vdi-control-01`, `vdi-worker-01`, and `vdi-worker-02` in `Ready` state. | `kubectl get nodes -o wide`. |
| K8S-003 | Kubernetes node packages shall be pinned to the selected Kubernetes patch version. | Ansible variable and package review. |
| K8S-004 | containerd shall be installed, enabled, active, and configured with a Kubernetes-compatible CRI and systemd cgroup driver. | `containerd --version`, `systemctl is-active containerd`, and config review. |
| K8S-005 | Calico shall provide the pod network and Kubernetes NetworkPolicy enforcement. | Calico status checks and NetworkPolicy deny/allow validation. |
| K8S-006 | CoreDNS shall be healthy after CNI installation. | `kubectl -n kube-system rollout status deployment/coredns`. |
| K8S-007 | `vdi-worker-01` shall be labeled `vdiforge.io/node-role=platform` and `vdi-worker-02` shall be labeled `vdiforge.io/node-role=vdi`. | `kubectl get nodes --show-labels`. |
| K8S-008 | Metrics Server shall be installed and `kubectl top nodes` shall return node metrics. | Metrics Server rollout and `kubectl top` checks. |
| K8S-009 | Phase 3 shall create only the minimal namespace foundation required by the architecture and shall not deploy application workloads. | Manifest review and `kubectl get namespaces`. |
| K8S-010 | Phase 3 live validation shall produce a clear PASS/FAIL result and shall not hide failed checks. | `scripts/validate-phase3-live.sh`. |

## KubeVirt Foundation Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| KV-001 | KubeVirt shall be installed from a pinned release compatible with the selected Kubernetes version. | KubeVirt manifest version review and `kubectl get kubevirt -n kubevirt`. |
| KV-002 | KubeVirt shall expose a KVM device resource on `vdi-worker-02`. | Node allocatable check for `devices.kubevirt.io/kvm`. |
| KV-003 | The Phase 3 hardware-virtualization result shall be classified as `KUBEVIRT_KVM_VERIFIED`, `KUBEVIRT_KVM_NOT_VERIFIED`, or `KUBEVIRT_KVM_UNAVAILABLE`. | Phase 3 live validation report. |
| KV-004 | CDI shall be installed if required for the planned image/DataVolume workflow. | CDI decision review and `kubectl get pods -n cdi`. |
| KV-005 | A disposable KubeVirt test VM shall schedule onto `vdi-worker-02`, reach `Running`, and request KVM acceleration. | `scripts/phase3-kubevirt-test-vm.sh`. |
| KV-006 | The disposable KubeVirt test VM shall stop, restart, delete, and clean up related disposable resources. | KubeVirt lifecycle validation script. |

## Storage Foundation Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| STOR-001 | Phase 3 shall provide a functional StorageClass suitable for the disposable KubeVirt/CDI test VM. | `kubectl get storageclass` and VM disk import test. |
| STOR-002 | The local storage design shall document binding mode, provisioner, limitations, and lack of physical HA. | `docs/KUBERNETES-KUBEVIRT.md` and ADR review. |
| STOR-003 | Phase 3 shall not deploy Ceph or another distributed storage platform unless justified by an ADR. | Repository and cluster resource review. |

## Security Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| SEC-001 | Authorization decisions shall be enforced server-side by FastAPI. | Authorization tests and code review. |
| SEC-002 | Frontend-hidden buttons shall not be treated as security controls. | Authorization bypass tests. |
| SEC-003 | The provisioner ServiceAccount shall not use `cluster-admin`. | Kubernetes RBAC manifest review. |
| SEC-004 | The provisioner ServiceAccount shall be limited to required verbs and resources in VDI namespaces. | RBAC review and negative Kubernetes API test. |
| SEC-005 | Kubernetes NetworkPolicies shall restrict platform and desktop communication to required paths. | NetworkPolicy connectivity tests. |
| SEC-006 | VDI desktops shall not automatically have privileged access to the Kubernetes API. | In-VM network and credential test. |
| SEC-007 | VDI desktops shall not automatically access Keycloak administration, backend database, monitoring administration, or platform control services. | NetworkPolicy negative tests. |
| SEC-008 | Secrets shall be supplied through approved secret mechanisms and shall not be committed. | Secret scan. |
| SEC-009 | Application logs shall not contain passwords, private keys, raw JWTs, refresh tokens, or similar secrets. | Log redaction tests. |
| SEC-010 | Audit events shall record authorization denials and privileged administrative actions. | Audit integration tests. |
| SEC-011 | Containers shall run as non-root where practical. | Kubernetes security context review. |
| SEC-012 | Images shall be built from trusted Ubuntu sources with checksum or signature verification. | Packer pipeline validation. |
| SEC-013 | Image promotion shall require validation and security checks before the image is offered for launches. | Image pipeline test evidence. |
| SEC-014 | API input shall be validated with Pydantic models before business logic executes. | API validation tests. |
| SEC-015 | TLS shall protect browser-facing endpoints. | Ingress/TLS validation. |
| SEC-016 | Guacamole connection identifiers or URLs shall not allow cross-user desktop access. | Connection guessing negative tests. |

## Observability Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| OBS-001 | The API shall emit Prometheus metrics for request rate, error rate, and latency. | Metrics test and scrape validation. |
| OBS-002 | The API shall emit desktop lifecycle metrics including active, provisioning, and failed desktops. | Metrics integration test. |
| OBS-003 | The provisioner shall emit metrics for provisioning success rate and provisioning latency. | Metrics integration test. |
| OBS-004 | Grafana dashboards shall include P50/P95 provisioning latency. | Dashboard JSON review. |
| OBS-005 | Grafana dashboards shall include API replica count and HPA desired/current replicas. | Dashboard JSON review. |
| OBS-006 | Grafana dashboards shall include pod CPU/memory and worker-node CPU/memory. | Dashboard JSON review. |
| OBS-007 | Grafana dashboards shall include Kubernetes node health and active remote sessions. | Dashboard JSON review. |
| OBS-008 | Application logs shall include timestamp, level, service, request ID, user ID where known, operation, resource ID where relevant, and message. | Log schema test. |
| OBS-009 | Audit events shall include timestamp, event ID, request ID, user ID, action, resource type, resource ID, source IP, result, and details. | Audit schema test. |
| OBS-010 | Request IDs shall propagate from browser/API requests through provisioning and audit records. | Correlation integration test. |

## Operations Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| OPS-001 | A runbook shall document Kubernetes node NotReady troubleshooting. | Runbook review. |
| OPS-002 | A runbook shall document pod Pending and CrashLoopBackOff troubleshooting. | Runbook review. |
| OPS-003 | A runbook shall document insufficient CPU, memory, and storage troubleshooting. | Runbook review. |
| OPS-004 | A runbook shall document Keycloak unavailable, authentication failure, and authorization failure troubleshooting. | Runbook review. |
| OPS-005 | A runbook shall document Guacamole unavailable and VDI connection failure troubleshooting. | Runbook review. |
| OPS-006 | A runbook shall document desktop stuck PROVISIONING and BOOTING troubleshooting. | Runbook review. |
| OPS-007 | A runbook shall document VM boot failure, image unavailable, and provisioning timeout troubleshooting. | Runbook review. |
| OPS-008 | A runbook shall document DNS and TLS troubleshooting. | Runbook review. |
| OPS-009 | CI shall run Phase 1 repository validation on push and pull request. | GitHub Actions workflow review. |
| OPS-010 | Later CI shall include Python lint/tests, frontend lint/tests, Terraform fmt/validate, Ansible lint, Packer validate, Helm lint, manifest validation, dependency scanning, security scanning, and container build validation. | CI design review. |
| OPS-011 | The final demo shall include a pre-flight checklist. | Demo document review. |
| OPS-012 | Phase completion shall include repository validation before merge to `main`. | Git workflow evidence. |

## Requirement Quality Rules

- Every requirement ID must be unique.
- Requirements should describe observable behavior or verifiable design constraints.
- Later phases should create a traceability matrix mapping these IDs to implementation, tests, evidence, and status.
- If a requirement changes, the same ID should be updated intentionally rather than duplicated under a new meaning.

## Phase 2 Traceability

| Requirement | Implementation reference | Test or evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| `NFR-001` | [docs/LOCAL-INFRASTRUCTURE.md](LOCAL-INFRASTRUCTURE.md) | Bill-of-materials review: VirtualBox, Ubuntu Server, Terraform, Ansible plans are free for the lab. | PASS | Assumes existing host hardware. |
| `NFR-002` | [docs/LOCAL-INFRASTRUCTURE.md](LOCAL-INFRASTRUCTURE.md) | Architecture review. | PASS | No paid AWS, VMware, PCoIP, Windows desktop, Okta, or Ping dependency. |
| `NFR-003` | [terraform/environments/local/main.tf](../terraform/environments/local/main.tf), [docs/LOCAL-INFRASTRUCTURE.md](LOCAL-INFRASTRUCTURE.md) | Version and resource review. | PASS | Phase 2 pins the local OS and VirtualBox result; Phase 3 must re-check Kubernetes/KubeVirt pins before installing cluster components. |
| `NFR-004` | [.gitignore](../.gitignore), [scripts/validate-phase2.ps1](../scripts/validate-phase2.ps1) | `.gitignore` and secret-scan validation. | PASS | Terraform state, VM disks, ISOs, credentials, and generated artifacts are excluded. |
| `NFR-005` | [ansible/playbooks/baseline.yml](../ansible/playbooks/baseline.yml) | Ansible syntax check, `ansible-lint`, and second playbook run with `changed=0` on all nodes. | PASS | Validation used `vdi-control-01` as the temporary Ansible controller. |
| `NFR-013` | [docs/LOCAL-INFRASTRUCTURE.md](LOCAL-INFRASTRUCTURE.md), [docs/ARCHITECTURE.md](ARCHITECTURE.md) | Documentation review. | PASS | Single physical host is explicitly not HA. |
| `NFR-014` | [docs/DESIGN.md](DESIGN.md), [docs/ROADMAP.md](ROADMAP.md) | Documentation review. | PASS | Future bare-metal/cloud evolution is separated from the local lab. |
| `SEC-008` | [.gitignore](../.gitignore), [scripts/validate-phase2.ps1](../scripts/validate-phase2.ps1) | Secret scan and Git review. | PASS | Private SSH keys and passwords are not committed. |
| `OPS-012` | [scripts/validate-phase2.ps1](../scripts/validate-phase2.ps1) | Phase validation and Git workflow evidence. | PASS | Static validation is automated; live checks are manual or key-based SSH. |
| `INFRA-001` | [terraform/environments/local/main.tf](../terraform/environments/local/main.tf), VirtualBox VMs | VirtualBox metadata and Terraform spec review. | PASS | Three expected node definitions exist. |
| `INFRA-002` | [terraform/environments/local/main.tf](../terraform/environments/local/main.tf), VirtualBox metadata | CPU/RAM/disk review. | PASS | `vdi-control-01` is 4 vCPU, 6144 MiB RAM, 40 GiB disk after the Phase 3 stability resize. |
| `INFRA-003` | [terraform/environments/local/main.tf](../terraform/environments/local/main.tf), VirtualBox metadata | CPU/RAM/disk review. | PASS | `vdi-worker-01` is 2 vCPU, 6144 MiB RAM, 50 GiB disk. |
| `INFRA-004` | [terraform/environments/local/main.tf](../terraform/environments/local/main.tf), VirtualBox metadata | CPU/RAM/disk review. | PASS | `vdi-worker-02` is 4 vCPU, 8192 MiB RAM, 60 GiB disk. |
| `INFRA-005` | [docs/LOCAL-INFRASTRUCTURE.md](LOCAL-INFRASTRUCTURE.md) | User-confirmed SSH from host to all three nodes. | PASS | Password bootstrap worked; key-based SSH remains recommended. |
| `INFRA-006` | [docs/LOCAL-INFRASTRUCTURE.md](LOCAL-INFRASTRUCTURE.md) | User-confirmed node-to-node ping matrix. | PASS | Host-only network is `192.168.56.0/24`. |
| `INFRA-007` | [docs/LOCAL-INFRASTRUCTURE.md](LOCAL-INFRASTRUCTURE.md) | User-confirmed outbound checks passed on all three nodes. | PASS | NAT is configured on Adapter 1 for each VM. |
| `INFRA-008` | [docs/LOCAL-INFRASTRUCTURE.md](LOCAL-INFRASTRUCTURE.md) | User-confirmed `svm` flags and `/dev/kvm` on `vdi-worker-02`. | PASS | KubeVirt hardware acceleration readiness is VERIFIED for Phase 2. |
| `INFRA-009` | Repository review | No Kubernetes/KubeVirt manifests or install automation added in Phase 2. | PASS | Phase 2 correctly stopped before Kubernetes/KubeVirt implementation. |
| `INFRA-010` | [scripts/validate-phase2.ps1](../scripts/validate-phase2.ps1) | Static validator execution. | PASS | Live SSH mode requires key-based SSH for non-interactive checks. |

## Phase 3 Traceability

| Requirement | Implementation reference | Test or evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| `NFR-003` | [ansible/inventory/local/group_vars/all.yml](../ansible/inventory/local/group_vars/all.yml), [docs/KUBERNETES-KUBEVIRT.md](KUBERNETES-KUBEVIRT.md) | Compatibility matrix and static validation. | PASS | Version set is pinned and live validation passed. |
| `NFR-005` | [ansible/playbooks/phase3.yml](../ansible/playbooks/phase3.yml) | Syntax, lint, and repeat playbook execution. | PASS | Final rerun reported `changed=0`, `failed=0`, `unreachable=0` on all nodes. |
| `SEC-003` | [kubernetes/rbac/vdiforge-provisioner-foundation.yaml](../kubernetes/rbac/vdiforge-provisioner-foundation.yaml) | RBAC manifest review and static secret/RBAC scan. | PASS | No VDIForge application component receives `cluster-admin`. |
| `SEC-004` | [kubernetes/rbac/vdiforge-provisioner-foundation.yaml](../kubernetes/rbac/vdiforge-provisioner-foundation.yaml) | Namespace-scoped Role review. | PASS | Provisioner role is limited to future VDI namespace resource management. |
| `SEC-005` | [scripts/phase3-networkpolicy-test.sh](../scripts/phase3-networkpolicy-test.sh) | Deny/allow NetworkPolicy validation. | PASS | Disposable validation resources are cleaned up. |
| `SEC-008` | [.gitignore](../.gitignore), [scripts/validate-phase3.ps1](../scripts/validate-phase3.ps1) | Secret scan and Git review. | PASS | Kubeconfigs, join tokens, certificates, and keys are not committed. |
| `OPS-001` | [docs/RUNBOOK.md](RUNBOOK.md) | Runbook review for node NotReady. | PASS | Phase 3 adds Kubernetes-specific diagnostics. |
| `OPS-002` | [docs/RUNBOOK.md](RUNBOOK.md) | Runbook review for pod Pending and CrashLoopBackOff. | PASS | Phase 3 adds cluster add-on examples. |
| `OPS-003` | [docs/RUNBOOK.md](RUNBOOK.md), [docs/KUBERNETES-KUBEVIRT.md](KUBERNETES-KUBEVIRT.md) | Storage and capacity runbook review. | PASS | Local-path and control-plane memory limitations are documented. |
| `OPS-012` | [scripts/validate-phase3.ps1](../scripts/validate-phase3.ps1), [scripts/validate-phase3-live.sh](../scripts/validate-phase3-live.sh) | Phase validation and Git workflow evidence. | PASS | Validation passed before merge to `main`. |
| `K8S-001` | [docs/KUBERNETES-KUBEVIRT.md](KUBERNETES-KUBEVIRT.md) | Compatibility matrix review. | PASS | Ubuntu 26.04, Kubernetes 1.36.4, Calico 3.32.1, KubeVirt 1.9.0, CDI 1.66.0. |
| `K8S-002` | [ansible/playbooks/kubernetes.yml](../ansible/playbooks/kubernetes.yml) | `kubectl get nodes -o wide`. | PASS | All three nodes are Ready. |
| `K8S-003` | [ansible/roles/kubernetes-common/tasks/main.yml](../ansible/roles/kubernetes-common/tasks/main.yml) | Package version and apt hold review. | PASS | kubelet, kubeadm, and kubectl are pinned at `1.36.4-1.1`. |
| `K8S-004` | [ansible/roles/containerd](../ansible/roles/containerd) | `containerd --version` and service health checks. | PASS | Uses containerd `2.2.2` with systemd cgroups. |
| `K8S-005` | [kubernetes/calico/custom-resources.yaml](../kubernetes/calico/custom-resources.yaml), [scripts/phase3-networkpolicy-test.sh](../scripts/phase3-networkpolicy-test.sh) | Calico status and NetworkPolicy validation. | PASS | Uses Calico VXLAN and NetworkPolicy enforcement passed. |
| `K8S-006` | [scripts/validate-phase3-live.sh](../scripts/validate-phase3-live.sh) | CoreDNS rollout status. | PASS | CoreDNS rollout passed after CNI installation. |
| `K8S-007` | [ansible/playbooks/kubernetes.yml](../ansible/playbooks/kubernetes.yml) | `kubectl get nodes --show-labels`. | PASS | Platform and VDI labels applied. |
| `K8S-008` | [ansible/playbooks/cluster-addons.yml](../ansible/playbooks/cluster-addons.yml) | Metrics Server rollout and `kubectl top nodes`. | PASS | Local TLS exception documented; node and pod metrics passed. |
| `K8S-009` | [kubernetes/namespaces/vdiforge-namespaces.yaml](../kubernetes/namespaces/vdiforge-namespaces.yaml) | Namespace manifest and cluster review. | PASS | No application workloads deployed. |
| `K8S-010` | [scripts/validate-phase3-live.sh](../scripts/validate-phase3-live.sh) | Live PASS/FAIL summary. | PASS | Live validation ended with `Phase 3 live validation: PASS`. |
| `KV-001` | [ansible/playbooks/cluster-addons.yml](../ansible/playbooks/cluster-addons.yml) | `kubectl get kubevirt -n kubevirt`. | PASS | KubeVirt v1.9.0 pinned and Available. |
| `KV-002` | [scripts/validate-phase3-live.sh](../scripts/validate-phase3-live.sh) | KVM allocatable resource check. | PASS | `devices.kubevirt.io/kvm` is exposed on `vdi-worker-02`. |
| `KV-003` | [docs/KUBERNETES-KUBEVIRT.md](KUBERNETES-KUBEVIRT.md) | Final KVM classification. | PASS | Result is `KUBEVIRT_KVM_VERIFIED`. |
| `KV-004` | [ansible/playbooks/cluster-addons.yml](../ansible/playbooks/cluster-addons.yml) | `kubectl get pods -n cdi`. | PASS | CDI v1.66.0 pinned and Available. |
| `KV-005` | [kubernetes/kubevirt/phase3-test-vm.yaml](../kubernetes/kubevirt/phase3-test-vm.yaml), [scripts/phase3-kubevirt-test-vm.sh](../scripts/phase3-kubevirt-test-vm.sh) | Disposable VM lifecycle test. | PASS | VM ran on `vdi-worker-02` and requested KVM. |
| `KV-006` | [scripts/phase3-kubevirt-test-vm.sh](../scripts/phase3-kubevirt-test-vm.sh) | Stop, restart, delete, cleanup checks. | PASS | Disposable VM was cleaned up. |
| `STOR-001` | [kubernetes/storage/local-path-provisioner.yaml](../kubernetes/storage/local-path-provisioner.yaml) | StorageClass and test VM disk import. | PASS | StorageClass is `vdiforge-local-path`. |
| `STOR-002` | [docs/KUBERNETES-KUBEVIRT.md](KUBERNETES-KUBEVIRT.md), [docs/ADR/0010-local-path-storage-for-phase3.md](ADR/0010-local-path-storage-for-phase3.md) | Documentation review. | PASS | Local-path limitations documented. |
| `STOR-003` | Repository review | No Ceph or distributed storage manifests. | PASS | Distributed storage remains future work. |
