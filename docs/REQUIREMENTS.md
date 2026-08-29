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

## Helm Platform Foundation Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| HELM-001 | Phase 4 shall use a pinned Helm client version compatible with the Kubernetes cluster version. | `helm version` and Helm/Kubernetes support matrix review. |
| HELM-002 | The repository shall provide a VDIForge Helm chart under `helm/vdiforge`. | Repository review. |
| HELM-003 | The Helm chart shall provide environment-neutral defaults and a local-lab override file. | `values.yaml` and `values-local.yaml` review. |
| HELM-004 | The Phase 4 chart shall not create fake application Deployments, StatefulSets, DaemonSets, VirtualMachines, Ingresses, or HPAs for services not yet implemented. | Rendered manifest review. |
| HELM-005 | The Helm ownership model shall distinguish Phase 3 namespace/add-on ownership from Phase 4 chart-managed resources. | Documentation and live resource metadata review. |
| HELM-006 | The chart shall create future VDIForge ServiceAccounts and provisioner RBAC without granting `cluster-admin`. | Helm template review and RBAC scan. |
| HELM-007 | The chart shall create lab-safe ResourceQuota and LimitRange resources where useful. | Rendered manifest and live cluster review. |
| HELM-008 | The chart shall create a NetworkPolicy foundation that supports default deny and required DNS/Kubernetes API egress without breaking Phase 3 add-ons. | Rendered manifest review and live cluster regression validation. |
| HELM-009 | The chart shall establish configuration and secret conventions without committing real secrets. | Secret scan and values review. |
| HELM-010 | The chart shall express future platform and VDI placement through role labels rather than hardcoded node names. | Values and rendered manifest review. |
| HELM-011 | The VDIForge Helm release shall pass install, upgrade, repeated upgrade, rollback, and final deployed-state validation. | Phase 4 live validation script. |
| HELM-012 | Phase 4 validation shall produce explicit static and live PASS/FAIL results. | `scripts/validate-phase4.ps1` and `scripts/validate-phase4-live.sh`. |

## Identity Platform Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| IDP-001 | Phase 5 shall deploy a pinned Keycloak release as the VDIForge identity provider. | Helm values review and live deployment image check. |
| IDP-002 | Keycloak shall run on the platform worker placement label and not on the VDI worker or control-plane node. | Pod node assignment check. |
| IDP-003 | Keycloak configuration shall survive ordinary Keycloak pod restart/recreation. | Controlled pod recreation and realm/client/role/user validation. |
| IDP-004 | Keycloak shall use persistent PostgreSQL storage for the local lab rather than an ephemeral development database. | StatefulSet, PVC, and restart validation. |
| IDP-005 | PostgreSQL shall not be exposed outside the cluster. | Service type and NetworkPolicy review. |
| IDP-006 | `auth.vdiforge.local` shall expose Keycloak through HTTPS ingress. | HTTPS discovery request through ingress. |
| IDP-007 | Local TLS material shall be generated outside Git and validated without globally disabling certificate verification. | Secret scan and trusted HTTPS test using the generated local CA. |
| IDP-008 | The `vdiforge` realm shall be reproducibly defined as source-controlled configuration without committed passwords. | Realm JSON review and secret scan. |
| IDP-009 | The `vdiforge-frontend` client shall be a public OIDC client using Authorization Code Flow with PKCE S256. | Realm JSON review and PKCE flow test. |
| IDP-010 | The browser client shall not use implicit flow, direct access grants, wildcard redirects, wildcard web origins, or a client secret. | Static realm validation. |
| IDP-011 | OIDC discovery and JWKS endpoints shall be reachable through trusted HTTPS. | Discovery and JWKS live checks. |
| IDP-012 | A reproducible test shall obtain a signed access token through Authorization Code Flow with PKCE. | `scripts/phase5-oidc-pkce-test.py`. |
| IDP-013 | Access-token validation shall verify signature, issuer, audience, and expiration. | PKCE/JWT validation test. |
| IDP-014 | Realm roles `vdi-user`, `vdi-developer`, `vdi-devops`, and `vdi-admin` shall exist. | Realm import and admin CLI validation. |
| IDP-015 | Demo identities shall receive expected role claims and shall not receive unauthorized roles. | RBAC claim validation for all demo identities. |
| IDP-016 | Negative authentication/security tests shall reject invalid credentials, invalid redirect URI, invalid PKCE verifier, tampered JWT, expired JWT, wrong issuer, and wrong audience. | PKCE/JWT negative validation. |
| IDP-017 | Identity NetworkPolicies shall permit only required Keycloak ingress, Keycloak-to-PostgreSQL, DNS, and future API discovery/JWKS paths. | NetworkPolicy manifest review and live deny/allow test. |
| IDP-018 | Runtime identity credentials, TLS private keys, database passwords, and tokens shall not be committed. | Static secret scan and Git diff review. |
| IDP-019 | Phase 5 validation shall produce explicit static and live PASS/FAIL results. | `scripts/validate-phase5.ps1` and `scripts/validate-phase5-live.sh`. |

## Image Pipeline Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| IMG-001 | Phase 6 shall define Ubuntu golden images named `ubuntu-base`, `ubuntu-developer`, and `ubuntu-devops`. | Repository review and image catalog validation. |
| IMG-002 | Each Phase 6 image definition shall use a pinned Ubuntu 26.04 LTS amd64 source and SHA-256 checksum. | Packer template review and Packer source validation. |
| IMG-003 | Phase 6 Packer templates shall pin the required Packer version range plus QEMU and Ansible plugin versions. | Packer template review and `packer validate`. |
| IMG-004 | Packer shall invoke dedicated image Ansible roles instead of embedding large shell configuration blocks. | Template and Ansible role review. |
| IMG-005 | `ubuntu-base` shall install a lightweight graphical desktop and future remote desktop prerequisites without deploying Guacamole. | In-guest image validation. |
| IMG-006 | `ubuntu-developer` shall include Git, Python 3, build tooling, common CLI tools, and a lightweight graphical editor. | In-guest image validation. |
| IMG-007 | `ubuntu-devops` shall include Terraform, Ansible, kubectl, Helm, Git, and Python 3. | In-guest and KubeVirt guest validation. |
| IMG-008 | Golden images shall remove temporary build credentials, SSH host keys, machine identity, shell history, logs, and temporary files before promotion. | Offline generalization and secret scan review. |
| IMG-009 | Generated image artifacts shall be versioned QCOW2 files with SHA-256 checksums and build manifests. | Artifact manifest and checksum validation. |
| IMG-010 | Large generated image artifacts, caches, ISO files, and temporary build credentials shall not be committed to Git. | `.gitignore`, Git tracked-file scan, and secret scan. |
| IMG-011 | The machine-readable image catalog shall represent all three images, their versions, artifact format, lifecycle state, and allowed-role policy. | `scripts/validate-image-catalog.py`. |
| IMG-012 | The image catalog shall express policy only and shall not implement application authorization. | Repository review and Phase 7 boundary review. |
| IMG-013 | At least `ubuntu-devops:1.0.0` shall import through CDI into a DataVolume/PVC using the `vdiforge-local-path` StorageClass. | `scripts/phase6-cdi-kubevirt-test.sh`. |
| IMG-014 | The `ubuntu-devops:1.0.0` KubeVirt boot test shall schedule through `vdiforge.io/node-role=vdi` and run on `vdi-worker-02`. | VMI and virt-launcher placement checks. |
| IMG-015 | The `ubuntu-devops:1.0.0` KubeVirt boot test shall verify KVM use by checking the virt-launcher pod's `devices.kubevirt.io/kvm` request. | KubeVirt pod resource assertion. |
| IMG-016 | The `ubuntu-devops:1.0.0` KubeVirt boot test shall prove guest boot, guest networking, required DevOps tools, stop, restart, delete, and cleanup. | Guest SSH command validation and KubeVirt lifecycle test. |
| IMG-017 | Phase 6 validation shall produce explicit static and live PASS/FAIL results. | `scripts/validate-phase6.ps1` and `scripts/validate-phase6-live.sh`. |

## Application Control Plane Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| APP-001 | Phase 7 shall pin FastAPI, Pydantic, SQLAlchemy, Alembic, psycopg, PyJWT, and the Kubernetes Python client. | Dependency-file review and static validation. |
| APP-002 | The backend shall expose health, readiness, image, desktop lifecycle, audit, and metrics endpoints under the documented API contract. | Backend tests and live API validation. |
| APP-003 | Protected API endpoints shall reject missing or invalid bearer tokens. | API negative authentication tests. |
| APP-004 | The API shall validate Keycloak-issued JWT signature, issuer, audience, expiration, subject, username, and roles before authorization decisions. | OIDC/API integration tests. |
| APP-005 | The API shall enforce image RBAC server-side and shall not rely on image-catalog filtering alone. | Unit tests and live RBAC validation. |
| APP-006 | Desktop launch shall require an `Idempotency-Key` header and shall replay the original response only when inputs match. | Backend tests and live API validation. |
| APP-007 | Desktop launch shall enforce approved resource profiles and active desktop quotas before recording desired state. | Backend tests and live quota validation. |
| APP-008 | Desktop launch shall return `202 Accepted` after recording desired state and shall not wait for VM boot. | API contract and live E2E validation. |
| APP-009 | Desktop records shall store ownership, desired state, observed state, image version, KubeVirt resource names, source PVC, request ID, and failure details. | Model/migration review and tests. |
| APP-010 | The API shall enforce owner-only access for normal users and admin-only access for all-user listing and audit events. | Backend tests and live API validation. |
| APP-011 | Phase 7 shall persist desktop records, provisioning operations, and audit events in PostgreSQL using Alembic migrations. | Migration job and persistence validation. |
| APP-012 | The provisioner shall reconcile desired desktop state to CDI DataVolumes, KubeVirt VirtualMachines, and per-desktop Services through the Kubernetes Python client. | Reconciler tests and live KubeVirt validation. |
| APP-013 | Provisioned desktop VMs shall target the VDI node role label rather than a hardcoded node name. | Rendered object and VMI placement validation. |
| APP-014 | The provisioner shall use bounded retries, backoff, failure states, and cleanup logic. | Reconciler tests and live lifecycle validation. |
| APP-015 | Desktop delete shall remove the managed VM, VMI, DataVolume/PVC, and Service resources where Kubernetes permits cleanup. | Live E2E cleanup validation. |
| APP-016 | The API shall return stable error codes and request IDs for expected failures. | Backend tests. |
| APP-017 | Phase 7 shall record audit events for desktop requests, lifecycle changes, failures, and admin audit access. | Backend tests and live audit validation. |
| APP-018 | The backend shall expose only minimal Phase 7 metrics and shall not implement the full Phase 11 observability stack. | Metrics endpoint check and scope review. |
| APP-019 | Phase 7 validation shall produce explicit static and live PASS/FAIL results. | `scripts/validate-phase7.ps1` and `scripts/validate-phase7-live.sh`. |

## Remote Desktop Delivery Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| RDP-001 | Phase 8 shall deploy Apache Guacamole and `guacd` from pinned `1.6.0` images. | Helm values, rendered manifest, and live rollout validation. |
| RDP-002 | Guacamole shall be exposed at `remote.vdiforge.local` through HTTPS ingress using local TLS material generated outside Git. | Trusted HTTPS live check and secret scan. |
| RDP-003 | The MVP remote desktop protocol shall be RDP through `xrdp`; VNC shall remain a documented fallback, not the selected Phase 8 path. | Documentation and image validation review. |
| RDP-004 | The provisioner shall create one per-desktop remote access Secret containing cloud-init user data and generated RDP credentials. | KubeVirt resource and Secret lifecycle tests. |
| RDP-005 | The KubeVirt VM shall consume the per-desktop remote access Secret through `cloudInitNoCloud.secretRef`. | Rendered VM object and code review. |
| RDP-006 | The API shall expose `POST /api/v1/desktops/{id}/connect` for remote-session handoff. | API route and integration tests. |
| RDP-007 | The connect endpoint shall require valid Keycloak bearer-token authentication. | Missing-token and OIDC integration tests. |
| RDP-008 | The connect endpoint shall enforce owner/admin authorization before reading remote credentials or returning a Guacamole URL. | Ownership and cross-user negative tests. |
| RDP-009 | The connect endpoint shall reject desktops that are not `READY` or `CONNECTED`. | State-transition API tests. |
| RDP-010 | The API response shall not contain reusable remote desktop usernames or passwords. | API response inspection and negative tests. |
| RDP-011 | FastAPI shall create short-lived encrypted Guacamole JSON-auth tokens using a runtime-only 128-bit secret. | Unit tests, live Guacamole token exchange, and secret scan. |
| RDP-012 | `guacd` shall reach desktop RDP Services only through internal cluster networking and NetworkPolicy-approved paths. | NetworkPolicy and TCP reachability tests. |
| RDP-013 | Desktop RDP Services shall remain `ClusterIP` and shall not be exposed directly outside the cluster. | Kubernetes Service inspection. |
| RDP-014 | Desktop deletion shall clean up the related remote access Secret in addition to VM, DataVolume, PVC, and Service resources. | E2E lifecycle cleanup test. |
| RDP-015 | Connection requests and denials shall be recorded as audit events without passwords, private keys, raw JWTs, or refresh tokens. | Audit API inspection and secret-pattern checks. |
| RDP-016 | Phase 8 validation shall produce explicit static and live PASS/FAIL results. | `scripts/validate-phase8.ps1` and `scripts/validate-phase8-live.sh`. |
| RDP-017 | The provisioner shall not mark a desktop `READY` until the KubeVirt VMI is ready and the internal remote desktop TCP port is reachable. | Reconciler test and live RDP reachability validation. |

## Web Portal Requirements

| ID | Requirement | Verification approach |
| --- | --- | --- |
| WEB-001 | Phase 9 shall implement a React and TypeScript self-service portal deployed at `https://vdiforge.local` through Helm. | Frontend build, Helm render, rollout, and trusted HTTPS validation. |
| WEB-002 | The portal shall authenticate users with Keycloak client `vdiforge-frontend` using Authorization Code Flow with PKCE. | OIDC browser/client configuration review and live PKCE validation. |
| WEB-003 | The browser bundle and runtime configuration shall not contain client secrets, reusable remote desktop credentials, Kubernetes credentials, raw JWTs, refresh tokens, or database credentials. | Static secret scan and runtime-config inspection. |
| WEB-004 | The portal shall call the FastAPI API with bearer tokens, request IDs, and configured runtime API base URL. | API client unit tests and live API validation. |
| WEB-005 | The image catalog view shall render only images returned by `GET /api/v1/images` for the authenticated user. | Component tests and live role-visibility validation. |
| WEB-006 | The launch workflow shall submit only API-supported image ID, resource profile, display name, and idempotency key fields. | API client tests and live desktop launch validation. |
| WEB-007 | The desktop views shall poll lifecycle state and render user-safe labels for API states. | Component tests and live provisioning validation. |
| WEB-008 | The Connect action shall be enabled only for `READY` or `CONNECTED` desktops and shall open the API-returned Guacamole URL exactly as returned. | Component tests and live connection URL validation. |
| WEB-009 | Stop, start, and delete controls shall call the documented API endpoints and rely on API-side authorization/state enforcement. | Component tests and live lifecycle validation. |
| WEB-010 | The portal shall provide loading, empty, and expected-error states without exposing implementation secrets. | Component tests and static review. |
| WEB-011 | The frontend container shall run as a non-root, static nginx workload with no mounted Kubernetes ServiceAccount token. | Helm template review and live pod spec validation. |
| WEB-012 | The frontend workload shall target the platform node role label and shall not hardcode node names. | Helm template/static validation and live pod scheduling check. |
| WEB-013 | The Helm chart shall provide a frontend NetworkPolicy path from Traefik to the frontend Service without giving the frontend pod direct access to platform control services. | Rendered NetworkPolicy review and live validation. |
| WEB-014 | Phase 9 shall promote `ubuntu-devops:1.2.0` as the current launchable DevOps image for new portal-launched desktops. | Image catalog validation and live desktop launch evidence. |
| WEB-015 | Phase 9 shall permanently automate the xrdp/XFCE session fix in the image role and launch-time cloud-init path. | Ansible role review, cloud-init test, and browser/remote desktop validation. |
| WEB-016 | Phase 9 validation shall produce explicit static and live PASS/FAIL results. | `scripts/validate-phase9.ps1` and `scripts/validate-phase9-live.sh`. |
| WEB-017 | Phase 9 shall not implement Prometheus/Grafana, application HPA, final CI/CD, or new VDI golden-image families beyond the required DevOps session fix. | Scope review. |

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

## Phase 4 Traceability

| Requirement | Implementation reference | Test or evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| `NFR-003` | [helm/vdiforge/Chart.yaml](../helm/vdiforge/Chart.yaml), [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml), [docs/HELM-PLATFORM.md](HELM-PLATFORM.md) | Helm version and chart compatibility review. | PASS | Helm v4.2.4 is pinned/documented for Kubernetes 1.36.4. |
| `NFR-006` | [helm/vdiforge](../helm/vdiforge), [scripts/validate-phase4-live.sh](../scripts/validate-phase4-live.sh) | Helm install, upgrade, repeated upgrade, rollback, and final deployed-state validation. | PASS | Phase 4 proves repeatable Helm release lifecycle for foundation resources. |
| `NFR-008` | [helm/vdiforge](../helm/vdiforge), [docs/HELM-PLATFORM.md](HELM-PLATFORM.md) | Chart and documentation review. | PASS | No Kafka, RabbitMQ, service mesh, OpenStack, Ceph, Vault cluster, Argo CD, Crossplane, or Elasticsearch introduced. |
| `NFR-012` | [helm/vdiforge/templates/limitrange.yaml](../helm/vdiforge/templates/limitrange.yaml), [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml) | Rendered manifest and live resource review. | PASS | Phase 4 defines default requests/limits for future platform containers through a LimitRange. |
| `SEC-003` | [helm/vdiforge/templates/rbac.yaml](../helm/vdiforge/templates/rbac.yaml), [scripts/validate-phase4.ps1](../scripts/validate-phase4.ps1) | RBAC scan. | PASS | The chart does not grant `cluster-admin`. |
| `SEC-004` | [helm/vdiforge/templates/rbac.yaml](../helm/vdiforge/templates/rbac.yaml) | Namespace-scoped Role review. | PASS | Provisioner RBAC remains limited to future VDI resources in `vdiforge-desktops`. |
| `SEC-005` | [helm/vdiforge/templates/networkpolicies.yaml](../helm/vdiforge/templates/networkpolicies.yaml), [scripts/validate-phase4-live.sh](../scripts/validate-phase4-live.sh) | Rendered manifest and Phase 3 NetworkPolicy regression. | PASS | Phase 4 establishes platform NetworkPolicies and preserves Calico enforcement. |
| `SEC-008` | [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml), [scripts/validate-phase4.ps1](../scripts/validate-phase4.ps1) | Secret scan and values review. | PASS | No real secrets are committed. |
| `OPS-012` | [scripts/validate-phase4.ps1](../scripts/validate-phase4.ps1), [scripts/validate-phase4-live.sh](../scripts/validate-phase4-live.sh) | Phase validation and Git workflow evidence. | PASS | Static and live validation are automated. |
| `HELM-001` | [docs/HELM-PLATFORM.md](HELM-PLATFORM.md), [scripts/install-helm-client.sh](../scripts/install-helm-client.sh) | `helm version` and official Helm support matrix. | PASS | Helm v4.2.4 supports Kubernetes 1.36.x. |
| `HELM-002` | [helm/vdiforge](../helm/vdiforge) | Repository review. | PASS | Chart directory exists with standard Helm files. |
| `HELM-003` | [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml), [helm/vdiforge/values-local.yaml](../helm/vdiforge/values-local.yaml) | Values review and template rendering. | PASS | Local overrides do not duplicate the chart. |
| `HELM-004` | [helm/vdiforge/templates](../helm/vdiforge/templates), [scripts/validate-phase4.ps1](../scripts/validate-phase4.ps1) | Static workload-kind scan. | PASS | No fake application workload resources are rendered. |
| `HELM-005` | [docs/ADR/0011-helm-platform-ownership.md](ADR/0011-helm-platform-ownership.md), [docs/HELM-PLATFORM.md](HELM-PLATFORM.md) | Documentation and live Helm adoption review. | PASS | Phase 3 owns namespaces/add-ons; Helm owns VDIForge platform resources. |
| `HELM-006` | [helm/vdiforge/templates/serviceaccounts.yaml](../helm/vdiforge/templates/serviceaccounts.yaml), [helm/vdiforge/templates/rbac.yaml](../helm/vdiforge/templates/rbac.yaml) | RBAC scan and rendered manifest review. | PASS | Frontend receives no Kubernetes privileges; provisioner RBAC is namespace-scoped. |
| `HELM-007` | [helm/vdiforge/templates/resourcequota.yaml](../helm/vdiforge/templates/resourcequota.yaml), [helm/vdiforge/templates/limitrange.yaml](../helm/vdiforge/templates/limitrange.yaml) | Live resource review. | PASS | Quotas and platform LimitRange are chart-managed. |
| `HELM-008` | [helm/vdiforge/templates/networkpolicies.yaml](../helm/vdiforge/templates/networkpolicies.yaml) | Server-side dry-run and cluster regression validation. | PASS | Policies allow DNS and future provisioner Kubernetes API egress without breaking Phase 3 components. |
| `HELM-009` | [docs/HELM-PLATFORM.md](HELM-PLATFORM.md), [scripts/validate-phase4.ps1](../scripts/validate-phase4.ps1) | Values review and secret scan. | PASS | Secrets remain a later runtime input, not committed chart data. |
| `HELM-010` | [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml), [docs/HELM-PLATFORM.md](HELM-PLATFORM.md) | Hardcoded-node-name scan. | PASS | Placement uses `vdiforge.io/node-role` labels. |
| `HELM-011` | [scripts/validate-phase4-live.sh](../scripts/validate-phase4-live.sh) | Live Helm lifecycle test. | PASS | Install, upgrade, repeated upgrade, rollback, and final deployed-state checks pass. |
| `HELM-012` | [scripts/validate-phase4.ps1](../scripts/validate-phase4.ps1), [scripts/validate-phase4-live.sh](../scripts/validate-phase4-live.sh) | Validator execution. | PASS | Static and live validators emit explicit PASS/FAIL results. |

## Phase 5 Traceability

| Requirement | Implementation reference | Test or evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| `NFR-003` | [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml), [helm/traefik/values-local.yaml](../helm/traefik/values-local.yaml), [docs/KEYCLOAK-OIDC.md](KEYCLOAK-OIDC.md) | Version pin review and live image checks. | PASS | Keycloak, PostgreSQL, Traefik chart, Helm, and Kubernetes versions are pinned/documented. |
| `NFR-006` | [helm/vdiforge](../helm/vdiforge), [scripts/validate-phase5-live.sh](../scripts/validate-phase5-live.sh) | Helm install/upgrade of identity resources. | PASS | Keycloak identity foundation is repeatably deployed by Helm. |
| `NFR-008` | [docs/KEYCLOAK-OIDC.md](KEYCLOAK-OIDC.md), [docs/ADR/0012-keycloak-oidc-platform.md](ADR/0012-keycloak-oidc-platform.md) | Architecture review. | PASS | No Kafka, RabbitMQ, service mesh, OpenStack, Ceph, Vault cluster, Argo CD, Crossplane, or Elasticsearch introduced. |
| `NFR-012` | [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml), [helm/vdiforge/templates/keycloak.yaml](../helm/vdiforge/templates/keycloak.yaml), [helm/vdiforge/templates/keycloak-postgres.yaml](../helm/vdiforge/templates/keycloak-postgres.yaml) | Rendered manifest and live pod review. | PASS | Keycloak and PostgreSQL define CPU/memory requests and limits. |
| `SEC-005` | [helm/vdiforge/templates/keycloak-networkpolicies.yaml](../helm/vdiforge/templates/keycloak-networkpolicies.yaml), [scripts/phase5-networkpolicy-test.sh](../scripts/phase5-networkpolicy-test.sh) | Identity NetworkPolicy validation. | PASS | Unauthorized pod access to Keycloak and PostgreSQL is denied. |
| `SEC-008` | [.gitignore](../.gitignore), [scripts/phase5-create-local-secrets.sh](../scripts/phase5-create-local-secrets.sh), [scripts/validate-phase5.ps1](../scripts/validate-phase5.ps1) | Secret scan and generated-local-secret review. | PASS | Passwords, TLS private keys, and tokens are excluded from Git. |
| `SEC-015` | [helm/vdiforge/templates/keycloak.yaml](../helm/vdiforge/templates/keycloak.yaml), [docs/ADR/0013-local-ingress-and-tls.md](ADR/0013-local-ingress-and-tls.md) | Trusted HTTPS OIDC discovery validation. | PASS | Keycloak is exposed through HTTPS with a local development CA. |
| `OPS-004` | [docs/RUNBOOK.md](RUNBOOK.md), [docs/KEYCLOAK-OIDC.md](KEYCLOAK-OIDC.md) | Runbook review. | PASS | Keycloak, authentication, and authorization troubleshooting are documented. |
| `OPS-008` | [docs/RUNBOOK.md](RUNBOOK.md), [scripts/phase5-windows-hosts-and-trust.ps1](../scripts/phase5-windows-hosts-and-trust.ps1) | DNS/TLS procedure review and HTTPS validation. | PASS | Local hosts-file and CA trust procedures are documented. |
| `OPS-012` | [scripts/validate-phase5.ps1](../scripts/validate-phase5.ps1), [scripts/validate-phase5-live.sh](../scripts/validate-phase5-live.sh) | Phase validation and Git workflow evidence. | PASS | Static and live validation emit explicit PASS/FAIL results. |
| `IDP-001` | [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml), [helm/vdiforge/templates/keycloak.yaml](../helm/vdiforge/templates/keycloak.yaml) | Helm render and live image check. | PASS | Keycloak `26.7.2` is deployed from the official image. |
| `IDP-002` | [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml) | Pod node assignment check. | PASS | Identity workloads target `vdiforge.io/node-role=platform`. |
| `IDP-003` | [scripts/validate-phase5-live.sh](../scripts/validate-phase5-live.sh) | Controlled Keycloak pod recreation. | PASS | Realm, clients, roles, and demo users remain after pod recreation. |
| `IDP-004` | [helm/vdiforge/templates/keycloak-postgres.yaml](../helm/vdiforge/templates/keycloak-postgres.yaml) | StatefulSet/PVC review and restart validation. | PASS | Keycloak uses persistent PostgreSQL storage. |
| `IDP-005` | [helm/vdiforge/templates/keycloak-postgres.yaml](../helm/vdiforge/templates/keycloak-postgres.yaml), [helm/vdiforge/templates/keycloak-networkpolicies.yaml](../helm/vdiforge/templates/keycloak-networkpolicies.yaml) | Service and NetworkPolicy review. | PASS | PostgreSQL is ClusterIP-only and restricted to Keycloak. |
| `IDP-006` | [helm/vdiforge/templates/keycloak.yaml](../helm/vdiforge/templates/keycloak.yaml), [helm/traefik/values-local.yaml](../helm/traefik/values-local.yaml) | HTTPS discovery through ingress. | PASS | Keycloak is reachable as `https://auth.vdiforge.local`. |
| `IDP-007` | [scripts/phase5-create-local-secrets.sh](../scripts/phase5-create-local-secrets.sh) | Trusted CA HTTPS validation and secret scan. | PASS | Local CA/TLS material is generated under ignored `.local/phase5/`. |
| `IDP-008` | [keycloak/realm/vdiforge-realm.json](../keycloak/realm/vdiforge-realm.json) | Static realm validation. | PASS | Realm JSON contains no committed passwords. |
| `IDP-009` | [keycloak/realm/vdiforge-realm.json](../keycloak/realm/vdiforge-realm.json) | Static realm validation and PKCE flow test. | PASS | `vdiforge-frontend` is public and uses PKCE S256. |
| `IDP-010` | [keycloak/realm/vdiforge-realm.json](../keycloak/realm/vdiforge-realm.json) | Static realm validation. | PASS | Implicit flow, direct grants, wildcard origins, wildcard redirects, and browser client secrets are absent. |
| `IDP-011` | [scripts/validate-phase5-live.sh](../scripts/validate-phase5-live.sh) | Discovery and JWKS HTTPS checks. | PASS | OIDC metadata and signing keys are reachable. |
| `IDP-012` | [scripts/phase5-oidc-pkce-test.py](../scripts/phase5-oidc-pkce-test.py) | Authorization Code + PKCE test. | PASS | The helper obtains access tokens without using Resource Owner Password Credentials as the primary proof. |
| `IDP-013` | [scripts/phase5-oidc-pkce-test.py](../scripts/phase5-oidc-pkce-test.py) | JWT validation tests. | PASS | Signature, issuer, audience, and expiration are validated. |
| `IDP-014` | [keycloak/realm/vdiforge-realm.json](../keycloak/realm/vdiforge-realm.json), [scripts/phase5-configure-keycloak.sh](../scripts/phase5-configure-keycloak.sh) | Realm/admin CLI validation. | PASS | All four realm roles exist. |
| `IDP-015` | [scripts/phase5-oidc-pkce-test.py](../scripts/phase5-oidc-pkce-test.py) | RBAC claim validation. | PASS | Demo identities receive expected roles and lack unauthorized roles. |
| `IDP-016` | [scripts/phase5-oidc-pkce-test.py](../scripts/phase5-oidc-pkce-test.py) | Negative security tests. | PASS | Invalid credentials, redirect URI, PKCE verifier, tampered JWT, expired JWT, wrong issuer, and wrong audience are rejected. |
| `IDP-017` | [helm/vdiforge/templates/keycloak-networkpolicies.yaml](../helm/vdiforge/templates/keycloak-networkpolicies.yaml), [scripts/phase5-networkpolicy-test.sh](../scripts/phase5-networkpolicy-test.sh) | Deny/allow NetworkPolicy test. | PASS | Identity namespace access is restricted to documented paths. |
| `IDP-018` | [.gitignore](../.gitignore), [scripts/validate-phase5.ps1](../scripts/validate-phase5.ps1) | Secret scan and Git diff review. | PASS | No runtime identity credentials are committed. |
| `IDP-019` | [scripts/validate-phase5.ps1](../scripts/validate-phase5.ps1), [scripts/validate-phase5-live.sh](../scripts/validate-phase5-live.sh) | Validator execution. | PASS | Static and live validators produce explicit PASS/FAIL output. |

## Phase 6 Traceability

| Requirement | Implementation reference | Test or evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| `NFR-003` | [packer/ubuntu-base](../packer/ubuntu-base), [packer/ubuntu-developer](../packer/ubuntu-developer), [packer/ubuntu-devops](../packer/ubuntu-devops), [docs/GOLDEN-IMAGES.md](GOLDEN-IMAGES.md) | Packer and version pin review. | PASS | Packer, QEMU plugin, Ansible plugin, Ubuntu source, Terraform, kubectl, and Helm pins are documented. |
| `NFR-008` | [packer](../packer), [ansible/roles/image-common](../ansible/roles/image-common), [docs/GOLDEN-IMAGES.md](GOLDEN-IMAGES.md) | Architecture review. | PASS | Phase 6 adds no Kafka, RabbitMQ, service mesh, OpenStack, Ceph, Vault cluster, Argo CD, Crossplane, or Elasticsearch. |
| `FR-025` | [images/catalog.json](../images/catalog.json) | Catalog validation. | PASS | Catalog includes Ubuntu Base, Ubuntu Developer, and Ubuntu DevOps. |
| `FR-026` | [packer/ubuntu-devops](../packer/ubuntu-devops), [scripts/phase6-cdi-kubevirt-test.sh](../scripts/phase6-cdi-kubevirt-test.sh) | Guest command validation in KubeVirt VM. | PASS | Terraform, Helm, kubectl, Python, Git, and Ansible are validated inside the booted image. |
| `SEC-012` | [packer/ubuntu-base/variables.pkr.hcl](../packer/ubuntu-base/variables.pkr.hcl), [packer/ubuntu-developer/variables.pkr.hcl](../packer/ubuntu-developer/variables.pkr.hcl), [packer/ubuntu-devops/variables.pkr.hcl](../packer/ubuntu-devops/variables.pkr.hcl) | Source checksum review and Packer build. | PASS | Uses official Ubuntu 26.04 LTS amd64 cloud image with pinned SHA-256. |
| `SEC-013` | [images/catalog.json](../images/catalog.json), [docs/GOLDEN-IMAGES.md](GOLDEN-IMAGES.md) | Promotion model and validation gate review. | PASS | Failed builds must not become `available`; rollback affects new launches only. |
| `SEC-008` | [.gitignore](../.gitignore), [scripts/validate-phase6.ps1](../scripts/validate-phase6.ps1) | Secret and tracked artifact scan. | PASS | Generated images, temp keys, credentials, and caches are excluded from Git. |
| `OPS-007` | [docs/RUNBOOK.md](RUNBOOK.md), [docs/GOLDEN-IMAGES.md](GOLDEN-IMAGES.md) | Runbook review. | PASS | Image unavailable, CDI import, and KubeVirt boot failures are documented. |
| `OPS-010` | [scripts/validate-phase6.ps1](../scripts/validate-phase6.ps1), [scripts/validate-phase6-live.sh](../scripts/validate-phase6-live.sh) | Static and live validation. | PASS | Packer, Ansible, catalog, image, and KubeVirt tests are automated. |
| `OPS-012` | [scripts/validate-phase6.ps1](../scripts/validate-phase6.ps1), [scripts/validate-phase6-live.sh](../scripts/validate-phase6-live.sh) | Phase validation and Git workflow evidence. | PASS | Phase 6 validators emit explicit PASS/FAIL output. |
| `IMG-001` | [packer](../packer), [images/catalog.json](../images/catalog.json) | Repository review. | PASS | All three image definitions exist. |
| `IMG-002` | [packer/ubuntu-base/variables.pkr.hcl](../packer/ubuntu-base/variables.pkr.hcl), [packer/ubuntu-developer/variables.pkr.hcl](../packer/ubuntu-developer/variables.pkr.hcl), [packer/ubuntu-devops/variables.pkr.hcl](../packer/ubuntu-devops/variables.pkr.hcl) | Packer template review. | PASS | All templates pin Ubuntu 26.04 source and checksum. |
| `IMG-003` | [packer/ubuntu-base/ubuntu-base.pkr.hcl](../packer/ubuntu-base/ubuntu-base.pkr.hcl), [packer/ubuntu-developer/ubuntu-developer.pkr.hcl](../packer/ubuntu-developer/ubuntu-developer.pkr.hcl), [packer/ubuntu-devops/ubuntu-devops.pkr.hcl](../packer/ubuntu-devops/ubuntu-devops.pkr.hcl) | `packer fmt -check` and `packer validate`. | PASS | Packer, QEMU plugin, and Ansible plugin versions are pinned. |
| `IMG-004` | [ansible/roles/image-common](../ansible/roles/image-common), [ansible/roles/image-desktop](../ansible/roles/image-desktop), [ansible/roles/image-developer](../ansible/roles/image-developer), [ansible/roles/image-devops](../ansible/roles/image-devops) | Template and role review. | PASS | Packer calls Ansible playbooks for OS configuration. |
| `IMG-005` | [ansible/roles/image-desktop](../ansible/roles/image-desktop) | In-guest validation. | PASS | XFCE and xrdp prerequisites are installed without Guacamole deployment. |
| `IMG-006` | [ansible/roles/image-developer](../ansible/roles/image-developer) | In-guest validation. | PASS | Developer tooling is installed and checked. |
| `IMG-007` | [ansible/roles/image-devops](../ansible/roles/image-devops), [packer/shared/scripts/validate-image.sh](../packer/shared/scripts/validate-image.sh) | Guest command validation. | PASS | Terraform, Ansible, kubectl, Helm, Python, and Git checks are required. |
| `IMG-008` | [packer/shared/scripts/generalize-artifact.sh](../packer/shared/scripts/generalize-artifact.sh), [ansible/roles/image-cleanup](../ansible/roles/image-cleanup) | Generalization and secret scan. | PASS | Build credentials and clone-specific identity are removed from the artifact. |
| `IMG-009` | [packer/shared/scripts/write-manifest.sh](../packer/shared/scripts/write-manifest.sh) | Artifact checksum and manifest generation. | PASS | Every build emits a QCOW2, SHA-256 file, and JSON manifest. |
| `IMG-010` | [.gitignore](../.gitignore), [scripts/validate-phase6.ps1](../scripts/validate-phase6.ps1) | Git tracked-file scan. | PASS | Large generated artifacts remain outside Git. |
| `IMG-011` | [images/catalog.json](../images/catalog.json), [scripts/validate-image-catalog.py](../scripts/validate-image-catalog.py) | Catalog validation. | PASS | Image role policies match the SSO/RBAC design. |
| `IMG-012` | [images/README.md](../images/README.md), [docs/GOLDEN-IMAGES.md](GOLDEN-IMAGES.md) | Scope review. | PASS | Catalog policy is data only; application authorization remains Phase 7. |
| `IMG-013` | [scripts/phase6-cdi-kubevirt-test.sh](../scripts/phase6-cdi-kubevirt-test.sh) | CDI DataVolume/PVC validation. | PASS | `ubuntu-devops:1.0.0` imports through CDI using `vdiforge-local-path`. |
| `IMG-014` | [kubernetes/kubevirt/phase6-ubuntu-devops-vm.template.yaml](../kubernetes/kubevirt/phase6-ubuntu-devops-vm.template.yaml), [scripts/phase6-cdi-kubevirt-test.sh](../scripts/phase6-cdi-kubevirt-test.sh) | VMI placement validation. | PASS | The VM schedules by `vdiforge.io/node-role=vdi` onto `vdi-worker-02`. |
| `IMG-015` | [scripts/phase6-cdi-kubevirt-test.sh](../scripts/phase6-cdi-kubevirt-test.sh) | virt-launcher resource assertion. | PASS | KVM is verified by `devices.kubevirt.io/kvm` request. |
| `IMG-016` | [scripts/phase6-cdi-kubevirt-test.sh](../scripts/phase6-cdi-kubevirt-test.sh) | Guest SSH and lifecycle validation. | PASS | Guest boot, networking, DevOps tools, stop, restart, delete, and cleanup are validated. |
| `IMG-017` | [scripts/validate-phase6.ps1](../scripts/validate-phase6.ps1), [scripts/validate-phase6-live.sh](../scripts/validate-phase6-live.sh) | Validator execution. | PASS | Static and live validators produce explicit PASS/FAIL results. |

## Phase 7 Traceability

| Requirement | Implementation reference | Test or evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| `NFR-003` | [backend/requirements-runtime.txt](../backend/requirements-runtime.txt), [backend/pyproject.toml](../backend/pyproject.toml), [docs/API-CONTROL-PLANE.md](API-CONTROL-PLANE.md) | Dependency pin and version review. | PASS | Phase 7 Python dependencies are pinned. |
| `NFR-006` | [helm/vdiforge/values-phase7-local.yaml](../helm/vdiforge/values-phase7-local.yaml), [scripts/validate-phase7-live.sh](../scripts/validate-phase7-live.sh) | Helm install/upgrade and rollout validation. | PASS | API, provisioner, app PostgreSQL, and migrations are deployed by Helm. |
| `NFR-007` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py), [docs/ADR/0017-fastapi-control-plane-and-reconciler.md](ADR/0017-fastapi-control-plane-and-reconciler.md) | Code review and E2E validation. | PASS | Desktop launch uses Kubernetes/KubeVirt APIs, not Terraform. |
| `NFR-008` | [docs/ADR/0017-fastapi-control-plane-and-reconciler.md](ADR/0017-fastapi-control-plane-and-reconciler.md) | Architecture review. | PASS | Phase 7 does not add Kafka, RabbitMQ, a service mesh, OpenStack, Ceph, Vault cluster, Argo CD, Crossplane, or Elasticsearch. |
| `NFR-009` | [backend/app/api/errors.py](../backend/app/api/errors.py), [backend/tests/test_api_authorization.py](../backend/tests/test_api_authorization.py) | API error contract tests. | PASS | Expected failures include stable error codes and request IDs. |
| `NFR-010` | [backend/app/provisioning/reconciler.py](../backend/app/provisioning/reconciler.py), [backend/tests/test_reconciler.py](../backend/tests/test_reconciler.py) | Reconciler tests. | PASS | Provisioning retries are bounded and backoff is configured. |
| `NFR-012` | [helm/vdiforge/templates/api.yaml](../helm/vdiforge/templates/api.yaml), [helm/vdiforge/templates/provisioner.yaml](../helm/vdiforge/templates/provisioner.yaml), [helm/vdiforge/templates/app-postgres.yaml](../helm/vdiforge/templates/app-postgres.yaml) | Rendered manifest review. | PASS | API, provisioner, migration, and app PostgreSQL containers define resources. |
| `FR-002` | [backend/app/api/dependencies.py](../backend/app/api/dependencies.py), [scripts/phase7-api-e2e-test.py](../scripts/phase7-api-e2e-test.py) | Missing-token negative test. | PASS | Protected endpoints reject requests without bearer tokens. |
| `FR-003` | [backend/app/auth/jwt.py](../backend/app/auth/jwt.py), [scripts/phase7-api-e2e-test.py](../scripts/phase7-api-e2e-test.py) | Live Keycloak token validation. | PASS | Signature, issuer, audience, expiration, and required claims are validated. |
| `FR-004` | [backend/app/auth/policy.py](../backend/app/auth/policy.py), [backend/app/services/desktops.py](../backend/app/services/desktops.py) | Authorization tests. | PASS | Roles and owners come from token/backend state, not client input. |
| `FR-005` | [backend/app/services/image_catalog.py](../backend/app/services/image_catalog.py), [backend/tests/test_api_authorization.py](../backend/tests/test_api_authorization.py) | Image catalog RBAC tests. | PASS | Only authorized available images are returned. |
| `FR-006` | [backend/app/api/routes.py](../backend/app/api/routes.py), [backend/app/schemas/api.py](../backend/app/schemas/api.py) | API contract tests. | PASS | Launch accepts image, profile, display name, and idempotency key. |
| `FR-007` | [backend/app/services/desktops.py](../backend/app/services/desktops.py) | Authorization and quota tests. | PASS | Launch validates image authorization, profile, quota, and ownership. |
| `FR-008` | [backend/app/services/desktops.py](../backend/app/services/desktops.py), [scripts/phase7-api-e2e-test.py](../scripts/phase7-api-e2e-test.py) | API response and live VM readiness validation. | PASS | Launch returns `202` before the VM reaches Ready. |
| `FR-009` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py) | Live KubeVirt validation. | PASS | The provisioner creates KubeVirt `VirtualMachine` resources. |
| `FR-010` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py) | Live DataVolume/PVC/Service assertions. | PASS | The provisioner manages related DataVolume/PVC and Service resources. |
| `FR-011` | [backend/app/schemas/api.py](../backend/app/schemas/api.py), [backend/app/models/entities.py](../backend/app/models/entities.py) | Lifecycle tests. | PASS | Phase 7 states include requested, provisioning, booting, ready, stopping, stopped, terminating, terminated, and failed. |
| `FR-012` | [backend/app/models/entities.py](../backend/app/models/entities.py) | Model/migration review. | PASS | Desired and observed state are separate fields. |
| `FR-013` | [backend/app/services/desktops.py](../backend/app/services/desktops.py), [backend/tests/test_api_authorization.py](../backend/tests/test_api_authorization.py) | Ownership tests. | PASS | Normal users cannot read other users' desktops. |
| `FR-014` | [backend/app/services/desktops.py](../backend/app/services/desktops.py), [scripts/phase7-api-e2e-test.py](../scripts/phase7-api-e2e-test.py) | Admin list-all validation. | PASS | Admins can list all desktops. |
| `FR-020` | [backend/app/provisioning/reconciler.py](../backend/app/provisioning/reconciler.py), [scripts/phase7-api-e2e-test.py](../scripts/phase7-api-e2e-test.py) | Live cleanup validation. | PASS | Desktop delete cleans up VM/DataVolume/PVC/Service resources. |
| `FR-021` | [backend/app/api/routes.py](../backend/app/api/routes.py) | Health endpoint test. | PASS | `/api/v1/health` is implemented. |
| `FR-022` | [backend/app/api/routes.py](../backend/app/api/routes.py) | Readiness endpoint test. | PASS | `/api/v1/ready` checks database and image catalog. |
| `FR-023` | [backend/app/api/routes.py](../backend/app/api/routes.py) | Metrics endpoint check. | PASS | `/metrics` emits Prometheus-compatible desktop counters. |
| `FR-024` | [backend/app/audit/service.py](../backend/app/audit/service.py), [backend/app/models/entities.py](../backend/app/models/entities.py) | Audit endpoint and persistence validation. | PASS | Desktop lifecycle and admin audit events are persisted. |
| `SEC-001` | [backend/app/services/desktops.py](../backend/app/services/desktops.py) | Authorization tests. | PASS | Authorization decisions are enforced in the API. |
| `SEC-003` | [helm/vdiforge/templates/rbac.yaml](../helm/vdiforge/templates/rbac.yaml), [scripts/phase7-rbac-test.sh](../scripts/phase7-rbac-test.sh) | RBAC negative test. | PASS | No `cluster-admin` grant exists. |
| `SEC-004` | [helm/vdiforge/templates/rbac.yaml](../helm/vdiforge/templates/rbac.yaml), [scripts/phase7-rbac-test.sh](../scripts/phase7-rbac-test.sh) | Kubernetes `can-i` validation. | PASS | Provisioner is namespace-scoped to VDI resources. |
| `SEC-005` | [helm/vdiforge/templates/networkpolicies.yaml](../helm/vdiforge/templates/networkpolicies.yaml), [scripts/phase7-networkpolicy-test.sh](../scripts/phase7-networkpolicy-test.sh) | NetworkPolicy denial test. | PASS | Unauthorized namespaces cannot reach API ClusterIP or app PostgreSQL. |
| `SEC-008` | [.gitignore](../.gitignore), [scripts/validate-phase7.ps1](../scripts/validate-phase7.ps1) | Secret scan and Git diff review. | PASS | Runtime passwords and TLS private keys stay under ignored `.local/phase7`. |
| `SEC-009` | [backend/app/observability/logging.py](../backend/app/observability/logging.py) | Logging code review. | PASS | Logs are structured and do not include raw JWTs or passwords. |
| `SEC-010` | [backend/app/audit/service.py](../backend/app/audit/service.py), [scripts/phase7-api-e2e-test.py](../scripts/phase7-api-e2e-test.py) | Audit validation. | PASS | Security-relevant lifecycle events are recorded. |
| `SEC-011` | [helm/vdiforge/templates/api.yaml](../helm/vdiforge/templates/api.yaml), [helm/vdiforge/templates/provisioner.yaml](../helm/vdiforge/templates/provisioner.yaml), [helm/vdiforge/templates/app-postgres.yaml](../helm/vdiforge/templates/app-postgres.yaml) | Security-context review. | PASS | Phase 7 containers run non-root where practical. |
| `SEC-014` | [backend/app/schemas/api.py](../backend/app/schemas/api.py) | Request validation tests. | PASS | Pydantic models validate API input. |
| `SEC-015` | [helm/vdiforge/templates/api.yaml](../helm/vdiforge/templates/api.yaml), [scripts/phase7-create-local-secrets.sh](../scripts/phase7-create-local-secrets.sh) | Trusted HTTPS API health check. | PASS | `api.vdiforge.local` uses local TLS through Traefik. |
| `OBS-009` | [backend/app/models/entities.py](../backend/app/models/entities.py), [backend/app/audit/service.py](../backend/app/audit/service.py) | Audit schema review. | PASS | Audit events include request ID, user, action, resource, result, and details. |
| `OBS-010` | [backend/app/main.py](../backend/app/main.py), [backend/app/services/desktops.py](../backend/app/services/desktops.py) | Request-ID tests and audit review. | PASS | Request IDs are attached to responses and persisted on operations/audit events. |
| `OPS-006` | [docs/RUNBOOK.md](RUNBOOK.md) | Runbook review. | PASS | Desktop provisioning and boot troubleshooting reflect Phase 7. |
| `OPS-007` | [docs/RUNBOOK.md](RUNBOOK.md) | Runbook review. | PASS | VM boot, image source, and provisioning timeout troubleshooting are documented. |
| `OPS-012` | [scripts/validate-phase7.ps1](../scripts/validate-phase7.ps1), [scripts/validate-phase7-live.sh](../scripts/validate-phase7-live.sh) | Validator execution. | PASS | Phase 7 validators emit explicit PASS/FAIL results. |
| `APP-001` | [backend/requirements-runtime.txt](../backend/requirements-runtime.txt), [backend/pyproject.toml](../backend/pyproject.toml) | Static validation. | PASS | Dependencies are pinned. |
| `APP-002` | [backend/app/api/routes.py](../backend/app/api/routes.py) | Backend and live API validation. | PASS | Phase 7 endpoints are implemented. |
| `APP-003` | [backend/app/api/dependencies.py](../backend/app/api/dependencies.py) | Negative API validation. | PASS | Missing tokens are rejected. |
| `APP-004` | [backend/app/auth/jwt.py](../backend/app/auth/jwt.py) | Live token validation. | PASS | Keycloak tokens are cryptographically validated. |
| `APP-005` | [backend/app/services/image_catalog.py](../backend/app/services/image_catalog.py), [backend/app/services/desktops.py](../backend/app/services/desktops.py) | RBAC tests. | PASS | Image policy is enforced by the API. |
| `APP-006` | [backend/app/services/desktops.py](../backend/app/services/desktops.py) | Idempotency tests. | PASS | Replays and conflicts are handled. |
| `APP-007` | [backend/app/services/resource_profiles.py](../backend/app/services/resource_profiles.py), [backend/app/services/desktops.py](../backend/app/services/desktops.py) | Quota/profile tests. | PASS | Approved profiles and quotas are enforced. |
| `APP-008` | [backend/app/api/routes.py](../backend/app/api/routes.py) | Live E2E validation. | PASS | Launch is asynchronous. |
| `APP-009` | [backend/app/models/entities.py](../backend/app/models/entities.py), [backend/alembic/versions/0001_phase7_initial.py](../backend/alembic/versions/0001_phase7_initial.py) | Model and migration review. | PASS | Required desktop fields are persisted. |
| `APP-010` | [backend/app/services/desktops.py](../backend/app/services/desktops.py) | Ownership/admin tests. | PASS | Owner and admin boundaries are enforced. |
| `APP-011` | [backend/alembic](../backend/alembic), [helm/vdiforge/templates/migrations.yaml](../helm/vdiforge/templates/migrations.yaml) | Migration job and persistence validation. | PASS | Database schema is managed through Alembic. |
| `APP-012` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py) | Live KubeVirt validation. | PASS | DataVolumes, VirtualMachines, and Services are reconciled through the Kubernetes client. |
| `APP-013` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py), [scripts/phase7-api-e2e-test.py](../scripts/phase7-api-e2e-test.py) | VMI placement validation. | PASS | VMs target `vdiforge.io/node-role=vdi` and run on `vdi-worker-02`. |
| `APP-014` | [backend/app/provisioning/reconciler.py](../backend/app/provisioning/reconciler.py) | Reconciler tests. | PASS | Retry, backoff, failure, and cleanup behavior exists. |
| `APP-015` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py) | Live cleanup validation. | PASS | Delete removes managed Kubernetes resources. |
| `APP-016` | [backend/app/api/errors.py](../backend/app/api/errors.py) | Error contract tests. | PASS | Error responses include stable codes and request IDs. |
| `APP-017` | [backend/app/audit/service.py](../backend/app/audit/service.py) | Audit validation. | PASS | Lifecycle audit events are persisted. |
| `APP-018` | [backend/app/api/routes.py](../backend/app/api/routes.py) | Scope review. | PASS | Minimal metrics exist; full observability is deferred. |
| `APP-019` | [scripts/validate-phase7.ps1](../scripts/validate-phase7.ps1), [scripts/validate-phase7-live.sh](../scripts/validate-phase7-live.sh) | Validator execution. | PASS | Static and live validators are provided. |

## Phase 8 Traceability

| Requirement | Implementation reference | Test or evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| `NFR-003` | [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml), [backend/requirements-runtime.txt](../backend/requirements-runtime.txt), [docs/REMOTE-DESKTOP.md](REMOTE-DESKTOP.md) | Static validation. | PASS | Guacamole, `guacd`, API, and cryptography dependencies are pinned. |
| `NFR-006` | [helm/vdiforge/values-phase8-local.yaml](../helm/vdiforge/values-phase8-local.yaml), [scripts/validate-phase8-live.sh](../scripts/validate-phase8-live.sh) | Helm install/upgrade and rollout validation. | PASS | Phase 8 extends the existing `vdiforge` release instead of creating a separate application stack. |
| `NFR-007` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py), [backend/app/services/remote_access.py](../backend/app/services/remote_access.py) | Code review and live E2E validation. | PASS | Remote-session handoff uses Kubernetes/KubeVirt state, not Terraform. |
| `NFR-008` | [docs/ADR/0018-guacamole-json-session-brokering.md](ADR/0018-guacamole-json-session-brokering.md) | Architecture review. | PASS | Phase 8 does not add Kafka, RabbitMQ, service mesh, OpenStack, Ceph, Vault cluster, Argo CD, Crossplane, or Elasticsearch. |
| `FR-017` | [backend/app/services/desktops.py](../backend/app/services/desktops.py) | Backend tests and live stopped/deleted connection denial. | PASS | Only READY or CONNECTED desktops can receive a connection URL. |
| `FR-018` | [backend/app/services/desktops.py](../backend/app/services/desktops.py), [scripts/phase8-remote-desktop-e2e-test.py](../scripts/phase8-remote-desktop-e2e-test.py) | Cross-user connection denial. | PASS | Owner/admin checks occur before session handoff. |
| `FR-019` | [backend/app/services/remote_access.py](../backend/app/services/remote_access.py), [scripts/phase8-remote-desktop-e2e-test.py](../scripts/phase8-remote-desktop-e2e-test.py) | API response inspection. | PASS | The API response contains an encrypted Guacamole URL, not plaintext RDP credentials. |
| `FR-020` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py) | E2E cleanup validation. | PASS | Delete removes the per-desktop Secret as well as VM/DataVolume/PVC/Service resources. |
| `FR-024` | [backend/app/services/desktops.py](../backend/app/services/desktops.py), [scripts/phase8-remote-desktop-e2e-test.py](../scripts/phase8-remote-desktop-e2e-test.py) | Audit endpoint validation. | PASS | Connection requests and denials are recorded. |
| `RDP-001` | [helm/vdiforge/templates/guacamole.yaml](../helm/vdiforge/templates/guacamole.yaml), [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml) | Helm render and live rollout validation. | PASS | Guacamole and `guacd` use pinned `1.6.0` images. |
| `RDP-002` | [scripts/phase8-create-local-secrets.sh](../scripts/phase8-create-local-secrets.sh), [helm/vdiforge/templates/guacamole.yaml](../helm/vdiforge/templates/guacamole.yaml) | Trusted HTTPS check. | PASS | `remote.vdiforge.local` uses generated local TLS outside Git. |
| `RDP-003` | [docs/REMOTE-DESKTOP.md](REMOTE-DESKTOP.md), [packer/shared/scripts/validate-image.sh](../packer/shared/scripts/validate-image.sh) | Image validation. | PASS | xrdp is required and validated; VNC is only fallback. |
| `RDP-004` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py) | Secret existence check. | PASS | One generated Secret is created per desktop. |
| `RDP-005` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py) | VM spec review. | PASS | VM cloud-init uses `secretRef`. |
| `RDP-006` | [backend/app/api/routes.py](../backend/app/api/routes.py) | API route test. | PASS | Connect endpoint is implemented. |
| `RDP-007` | [backend/app/api/routes.py](../backend/app/api/routes.py), [backend/app/api/dependencies.py](../backend/app/api/dependencies.py) | Missing-token and OIDC test. | PASS | Protected endpoint depends on validated current user. |
| `RDP-008` | [backend/app/services/desktops.py](../backend/app/services/desktops.py) | Cross-user E2E denial. | PASS | Non-owner access is denied and audited. |
| `RDP-009` | [backend/app/services/desktops.py](../backend/app/services/desktops.py), [backend/tests/test_api_authorization.py](../backend/tests/test_api_authorization.py) | Stopped/deleted state checks. | PASS | Non-ready desktops return `DESKTOP_NOT_READY`. |
| `RDP-010` | [backend/app/schemas/api.py](../backend/app/schemas/api.py), [scripts/phase8-remote-desktop-e2e-test.py](../scripts/phase8-remote-desktop-e2e-test.py) | Response and audit scan. | PASS | Plaintext remote passwords are not returned. |
| `RDP-011` | [backend/app/services/remote_access.py](../backend/app/services/remote_access.py), [backend/tests/test_remote_access.py](../backend/tests/test_remote_access.py) | Token encryption unit test and Guacamole token exchange. | PASS | JSON auth payloads are signed, encrypted, and short-lived. |
| `RDP-012` | [helm/vdiforge/templates/guacamole-networkpolicies.yaml](../helm/vdiforge/templates/guacamole-networkpolicies.yaml), [scripts/phase8-networkpolicy-test.sh](../scripts/phase8-networkpolicy-test.sh) | NetworkPolicy allow/deny validation. | PASS | Only intended Guacamole-to-desktop paths are allowed. |
| `RDP-013` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py), [scripts/phase8-remote-desktop-e2e-test.py](../scripts/phase8-remote-desktop-e2e-test.py) | Service inspection. | PASS | Desktop RDP Services remain `ClusterIP`. |
| `RDP-014` | [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py) | E2E cleanup validation. | PASS | Remote access Secret cleanup is part of desktop deletion. |
| `RDP-015` | [backend/app/services/desktops.py](../backend/app/services/desktops.py), [backend/app/audit/service.py](../backend/app/audit/service.py) | Audit API and secret-pattern validation. | PASS | Audit events contain metadata but not credentials. |
| `RDP-016` | [scripts/validate-phase8.ps1](../scripts/validate-phase8.ps1), [scripts/validate-phase8-live.sh](../scripts/validate-phase8-live.sh) | Validator execution. | PASS | Phase 8 validators emit explicit PASS/FAIL output. |
| `RDP-017` | [backend/app/provisioning/reconciler.py](../backend/app/provisioning/reconciler.py), [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py), [helm/vdiforge/templates/networkpolicies.yaml](../helm/vdiforge/templates/networkpolicies.yaml) | Reconciler unit test and live E2E validation. | PASS | `READY` requires both VMI readiness and provisioner access to the configured remote desktop port. |

## Phase 9 Traceability

| Requirement | Implementation reference | Test or evidence | Status | Notes |
| --- | --- | --- | --- | --- |
| `NFR-003` | [frontend/package.json](../frontend/package.json), [frontend/package-lock.json](../frontend/package-lock.json), [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml), [docs/WEB-PORTAL.md](WEB-PORTAL.md) | Dependency pin and chart value review. | PASS | React, Vite, TypeScript, `oidc-client-ts`, Playwright, and portal image tags are pinned. |
| `NFR-006` | [helm/vdiforge/templates/frontend.yaml](../helm/vdiforge/templates/frontend.yaml), [helm/vdiforge/values-phase9-local.yaml](../helm/vdiforge/values-phase9-local.yaml), [scripts/validate-phase9-live.sh](../scripts/validate-phase9-live.sh) | Helm install/render/live rollout validation. | PASS | Phase 9 extends the existing `vdiforge` release with frontend resources. |
| `FR-001` | [frontend/src/auth/oidc.ts](../frontend/src/auth/oidc.ts), [frontend/src/auth/AuthProvider.tsx](../frontend/src/auth/AuthProvider.tsx), [scripts/phase9-portal-e2e-test.py](../scripts/phase9-portal-e2e-test.py) | OIDC PKCE token acquisition. | PASS | The portal uses the existing public Keycloak client and Authorization Code Flow with PKCE. |
| `FR-005` | [frontend/src/components/PortalApp.tsx](../frontend/src/components/PortalApp.tsx), [scripts/phase9-portal-e2e-test.py](../scripts/phase9-portal-e2e-test.py) | Component and live role-visibility validation. | PASS | The portal renders the API-filtered catalog rather than embedding authorization rules. |
| `FR-006` | [frontend/src/api/client.ts](../frontend/src/api/client.ts), [frontend/src/components/PortalApp.tsx](../frontend/src/components/PortalApp.tsx) | API client and component tests. | PASS | Launch requests use the documented API fields and an idempotency key. |
| `FR-017` | [frontend/src/components/PortalApp.tsx](../frontend/src/components/PortalApp.tsx), [frontend/tests/portal.test.tsx](../frontend/tests/portal.test.tsx) | Component tests and live connect validation. | PASS | Connect is only enabled for connectable desktop states. |
| `FR-019` | [frontend/src/api/client.ts](../frontend/src/api/client.ts), [scripts/phase9-portal-e2e-test.py](../scripts/phase9-portal-e2e-test.py) | API response and runtime-config inspection. | PASS | The portal receives an opaque Guacamole URL only, not reusable RDP credentials. |
| `FR-024` | [backend/app/audit/service.py](../backend/app/audit/service.py), [scripts/phase9-portal-e2e-test.py](../scripts/phase9-portal-e2e-test.py) | Audit endpoint validation. | PASS | Portal-driven connection requests are visible as audit events. |
| `SEC-001` | [backend/app/services/desktops.py](../backend/app/services/desktops.py), [frontend/src/components/PortalApp.tsx](../frontend/src/components/PortalApp.tsx) | Backend authorization and portal review. | PASS | The frontend improves usability; authorization stays server-side. |
| `SEC-002` | [frontend/src/components/PortalApp.tsx](../frontend/src/components/PortalApp.tsx), [backend/tests/test_api_authorization.py](../backend/tests/test_api_authorization.py) | Frontend UX test and backend denial tests. | PASS | Hidden or disabled buttons are not treated as security controls. |
| `SEC-008` | [.gitignore](../.gitignore), [scripts/validate-phase9.ps1](../scripts/validate-phase9.ps1), [scripts/phase9-create-local-secrets.sh](../scripts/phase9-create-local-secrets.sh) | Secret scan and runtime secret generation review. | PASS | Portal TLS material and OIDC runtime state stay outside Git. |
| `SEC-011` | [helm/vdiforge/templates/frontend.yaml](../helm/vdiforge/templates/frontend.yaml) | Helm template and live pod spec validation. | PASS | The frontend runs non-root with a read-only root filesystem. |
| `SEC-015` | [scripts/phase9-create-local-secrets.sh](../scripts/phase9-create-local-secrets.sh), [helm/vdiforge/templates/frontend.yaml](../helm/vdiforge/templates/frontend.yaml) | Trusted HTTPS portal check. | PASS | `vdiforge.local` is served through Traefik with local TLS. |
| `WEB-001` | [frontend](../frontend), [helm/vdiforge/templates/frontend.yaml](../helm/vdiforge/templates/frontend.yaml) | Frontend build and Helm rollout. | PASS | The React portal is deployed at `https://vdiforge.local`. |
| `WEB-002` | [frontend/src/auth/oidc.ts](../frontend/src/auth/oidc.ts), [helm/vdiforge/files/keycloak/vdiforge-realm.json](../helm/vdiforge/files/keycloak/vdiforge-realm.json) | OIDC PKCE validation. | PASS | The existing `vdiforge-frontend` public client is used. |
| `WEB-003` | [frontend/public/runtime-config.js](../frontend/public/runtime-config.js), [helm/vdiforge/templates/frontend.yaml](../helm/vdiforge/templates/frontend.yaml), [scripts/validate-phase9.ps1](../scripts/validate-phase9.ps1) | Static and live secret scans. | PASS | Runtime configuration contains public endpoint values only. |
| `WEB-004` | [frontend/src/api/client.ts](../frontend/src/api/client.ts) | Unit tests and live API checks. | PASS | API calls use bearer tokens, request IDs, and runtime base URL. |
| `WEB-005` | [frontend/src/components/PortalApp.tsx](../frontend/src/components/PortalApp.tsx), [frontend/tests/portal.test.tsx](../frontend/tests/portal.test.tsx) | Component and live role-visibility validation. | PASS | Catalog cards are derived from API responses. |
| `WEB-006` | [frontend/src/api/client.ts](../frontend/src/api/client.ts), [frontend/tests/api-client.test.ts](../frontend/tests/api-client.test.ts) | API client tests and live launch. | PASS | Launch request shape matches the Phase 7 API. |
| `WEB-007` | [frontend/src/utils/status.ts](../frontend/src/utils/status.ts), [frontend/src/components/PortalApp.tsx](../frontend/src/components/PortalApp.tsx) | Component tests and live polling. | PASS | API states are rendered as user-safe labels. |
| `WEB-008` | [frontend/src/components/PortalApp.tsx](../frontend/src/components/PortalApp.tsx), [scripts/phase9-portal-e2e-test.py](../scripts/phase9-portal-e2e-test.py) | Component and live connection URL validation. | PASS | The exact API-returned Guacamole URL is opened. |
| `WEB-009` | [frontend/src/components/PortalApp.tsx](../frontend/src/components/PortalApp.tsx) | Component tests and live lifecycle checks. | PASS | Stop, start, and delete use documented endpoints. |
| `WEB-010` | [frontend/tests/portal.test.tsx](../frontend/tests/portal.test.tsx) | Component tests. | PASS | Loading, empty, and expected-error states are covered. |
| `WEB-011` | [frontend/Dockerfile](../frontend/Dockerfile), [helm/vdiforge/templates/frontend.yaml](../helm/vdiforge/templates/frontend.yaml) | Helm and live pod spec validation. | PASS | Static nginx container runs without a Kubernetes API token. |
| `WEB-012` | [helm/vdiforge/templates/frontend.yaml](../helm/vdiforge/templates/frontend.yaml), [helm/vdiforge/values.yaml](../helm/vdiforge/values.yaml) | Static and live scheduling validation. | PASS | Portal placement uses `vdiforge.io/node-role=platform`. |
| `WEB-013` | [helm/vdiforge/templates/networkpolicies.yaml](../helm/vdiforge/templates/networkpolicies.yaml) | Render and live validation. | PASS | Traefik can reach the portal while the frontend has no privileged egress. |
| `WEB-014` | [images/catalog.json](../images/catalog.json), [images/README.md](../images/README.md) | Catalog validation and live launch. | PASS | `ubuntu-devops:1.2.0` is the default launchable DevOps image. |
| `WEB-015` | [ansible/roles/image-desktop/tasks/main.yml](../ansible/roles/image-desktop/tasks/main.yml), [backend/app/provisioning/kubevirt.py](../backend/app/provisioning/kubevirt.py), [backend/tests/test_remote_access.py](../backend/tests/test_remote_access.py) | Role/cloud-init review and test. | PASS | New launches include `.xsession` and Xwrapper configuration for XFCE/xrdp. |
| `WEB-016` | [scripts/validate-phase9.ps1](../scripts/validate-phase9.ps1), [scripts/validate-phase9-live.sh](../scripts/validate-phase9-live.sh) | Validator execution. | PASS | Static and live validators emit explicit PASS/FAIL results. |
| `WEB-017` | [docs/ROADMAP.md](ROADMAP.md), [docs/WEB-PORTAL.md](WEB-PORTAL.md) | Scope review. | PASS | HPA, Prometheus/Grafana, final CI/CD, and further hardening remain later phases. |
