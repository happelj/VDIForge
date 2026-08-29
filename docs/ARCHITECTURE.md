# VDIForge Architecture

This document contains architecture views for VDIForge. The local VirtualBox infrastructure, Kubernetes/KubeVirt foundation, Helm platform foundation, Keycloak identity foundation, golden-image pipeline, FastAPI control plane, Guacamole remote desktop flow, React portal, API HPA autoscaling, and Prometheus/Grafana observability reflect Phases 2 through 11.

## System Context

```mermaid
flowchart LR
  User[Thin client or laptop browser]
  Portal[VDIForge React portal]
  API[VDIForge FastAPI]
  Keycloak[Keycloak realm: vdiforge]
  DB[(PostgreSQL)]
  Provisioner[Provisioning reconciler]
  K8s[Kubernetes API]
  KubeVirt[KubeVirt]
  VM[Ubuntu desktop VM]
  XRDP[xrdp or VNC service]
  Guac[Apache Guacamole]
  Prom[Prometheus]
  Grafana[Grafana]

  User -->|HTTPS| Portal
  Portal -->|OIDC redirect| Keycloak
  Keycloak -->|tokens| Portal
  Portal -->|HTTPS API calls| API
  API -->|JWKS / issuer metadata| Keycloak
  API -->|state| DB
  API -->|desired state| Provisioner
  Provisioner -->|Kubernetes client| K8s
  K8s --> KubeVirt
  KubeVirt --> VM
  VM --> XRDP
  Guac -->|RDP or VNC| XRDP
  User -->|HTTPS / WebSocket| Guac
  Prom -->|scrape /metrics| API
  Prom -->|scrape /metrics| Provisioner
  Prom -->|scrape Kubernetes metrics| K8s
  Prom -->|scrape KubeVirt metrics| KubeVirt
  Grafana --> Prom
```

The Ubuntu desktop runs remotely inside the VM. The browser receives graphical session updates through Guacamole and sends keyboard and mouse input.

## Kubernetes Nodes

```mermaid
flowchart TB
  subgraph Cluster[Kubernetes cluster]
    CP[vdi-control-01<br/>control-plane node]
    W1[vdi-worker-01<br/>platform worker<br/>vdiforge.io/node-role=platform]
    W2[vdi-worker-02<br/>VDI worker<br/>vdiforge.io/node-role=vdi]
  end

  CP --> W1
  CP --> W2

  subgraph Platform[Platform workloads]
    FE[React frontend]
    API[FastAPI]
    KC[Keycloak]
    DB[(PostgreSQL)]
    GUAC[Guacamole]
    MON[Prometheus / Grafana<br/>Alertmanager]
  end

  subgraph VDI[VDI workloads]
    KV[KubeVirt handlers]
    VM1[Ubuntu desktop VMs]
  end

  W1 -. preferred placement .-> Platform
  W2 -. preferred placement .-> VDI
```

This is a non-HA local topology. When all three nodes are VMs on one host, the physical host remains a single failure domain.

## Local Infrastructure Layers

```mermaid
flowchart TB
  HW[Windows 10 Pro workstation<br/>Ryzen 7 1700 / 32 GB RAM]
  VBox[Oracle VirtualBox 7.2.16]
  NAT[NAT network<br/>outbound Internet]
  HostOnly[Host-only network<br/>192.168.56.0/24]
  CP[vdi-control-01<br/>192.168.56.10<br/>4 vCPU / 6 GiB / 40 GiB]
  W1[vdi-worker-01<br/>192.168.56.11<br/>2 vCPU / 6 GiB / 50 GiB]
  W2[vdi-worker-02<br/>192.168.56.12<br/>4 vCPU / 8 GiB / 60 GiB<br/>/dev/kvm verified]
  Cluster[Phase 3 foundation<br/>kubeadm, containerd, Calico, Metrics Server, KubeVirt, CDI]
  Observability[Phase 11 observability<br/>Prometheus, Grafana, Alertmanager]

  HW --> VBox
  VBox --> NAT
  VBox --> HostOnly
  NAT --> CP
  NAT --> W1
  NAT --> W2
  HostOnly --> CP
  HostOnly --> W1
  HostOnly --> W2
  CP --> Cluster
  W1 --> Cluster
  W2 --> Cluster
  Cluster --> Observability
```

`vdi-worker-02` is the only node that requires nested virtualization for Phase 3. Phase 2 verified `svm` CPU flags and `/dev/kvm` inside the guest; Phase 3 verified KubeVirt exposes and consumes `devices.kubevirt.io/kvm`.

Actual Phase 2 network:

| Node | NAT | Host-only IP | Purpose |
| --- | --- | --- | --- |
| `vdi-control-01` | DHCP | `192.168.56.10` | Kubernetes control-plane node |
| `vdi-worker-01` | DHCP | `192.168.56.11` | platform worker |
| `vdi-worker-02` | DHCP | `192.168.56.12` | KubeVirt/VDI worker |

The host-only adapter address is `192.168.56.1`. DHCP is disabled on the host-only network; static addresses are assigned inside each Ubuntu guest. NAT supplies outbound Internet access.

## Kubernetes/KubeVirt Foundation

```mermaid
flowchart TB
  subgraph Host[Windows 10 Pro host]
    VBox[VirtualBox 7.2.16]
  end

  subgraph Cluster[Kubernetes 1.36.4]
    CP[vdi-control-01<br/>control plane<br/>192.168.56.10]
    W1[vdi-worker-01<br/>platform worker<br/>192.168.56.11<br/>vdiforge.io/node-role=platform]
    W2[vdi-worker-02<br/>VDI worker<br/>192.168.56.12<br/>vdiforge.io/node-role=vdi]
    Calico[Calico v3.32.1<br/>VXLAN pod network<br/>NetworkPolicy]
    Metrics[Metrics Server v0.8.1]
    Storage[vdiforge-local-path<br/>local-path provisioner v0.0.32]
    KV[KubeVirt v1.9.0]
    CDI[CDI v1.66.0]
    TestVM[Disposable CirrOS VM<br/>phase3-cirros]
  end

  VBox --> CP
  VBox --> W1
  VBox --> W2
  CP --> Calico
  CP --> Metrics
  CP --> KV
  KV --> CDI
  CDI --> Storage
  Storage --> TestVM
  KV --> TestVM
  TestVM --> W2
  W2 --> KVM[/dev/kvm<br/>devices.kubevirt.io/kvm]
```

The disposable test VM validates the KubeVirt foundation only. It is not one of the final Ubuntu desktop images and must be deleted after validation.

## Helm Platform Foundation

```mermaid
flowchart TB
  Git[Git repository<br/>Helm chart and values]
  Helm[Helm v4.2.4 client<br/>vdi-control-01]
  Release[Release: vdiforge<br/>namespace: vdiforge-system]
  CM[ConfigMap<br/>platform conventions]
  SA[ServiceAccounts<br/>vdiforge-api / vdiforge-provisioner]
  RBAC[Role and RoleBinding<br/>vdiforge-desktops]
  Quota[ResourceQuotas<br/>system and desktops]
  Limit[LimitRange<br/>system namespace]
  NP[NetworkPolicies<br/>default deny, DNS, Kubernetes API egress]
  Identity[Phase 5 identity resources<br/>Keycloak, PostgreSQL, identity policies]
  Remote[Phase 8 remote desktop<br/>Guacamole and guacd]
  Portal[Phase 9 portal<br/>React and nginx]
  HPA[Phase 10 API HPA<br/>vdiforge-api]
  Observability[Phase 11 observability resources<br/>ServiceMonitors, alerts, dashboard]
  Monitoring[Release: vdiforge-monitoring<br/>kube-prometheus-stack]

  Git --> Helm
  Helm --> Release
  Release --> CM
  Release --> SA
  Release --> RBAC
  Release --> Quota
  Release --> Limit
  Release --> NP
  Release --> Identity
  Release --> Remote
  Release --> Portal
  Release --> HPA
  Release --> Observability
  Monitoring -. scrapes .-> Observability
```

Phase 4 establishes Helm ownership, values conventions, RBAC boundaries, resource governance, NetworkPolicy foundations, and lifecycle validation for install, upgrade, repeated upgrade, and rollback. Later phase values enable the identity, API/provisioner, Guacamole, portal, HPA, and VDIForge observability resources. Phase 11 uses a separate upstream `kube-prometheus-stack` release for the core monitoring stack and the VDIForge chart for app-specific monitoring resources.

## Identity Foundation

```mermaid
flowchart TB
  Client[Browser or OIDC test client]
  Hosts[Local hosts entry or explicit resolver<br/>auth.vdiforge.local -> 192.168.56.11]
  CA[Generated local development CA<br/>not committed]
  subgraph Cluster[Kubernetes cluster]
    W1[vdi-worker-01<br/>platform worker]
    subgraph Ingress[Namespace: ingress-traefik]
      Traefik[Traefik chart 41.2.0<br/>hostPort 443]
    end
    subgraph Identity[Namespace: keycloak]
      Keycloak[Keycloak 26.7.2<br/>realm: vdiforge]
      PG[(PostgreSQL 18.0<br/>PVC: vdiforge-local-path)]
      Policies[NetworkPolicies<br/>default deny + explicit allows]
    end
  end

  Client -->|HTTPS with trusted local CA| Hosts
  CA -. trusts .-> Client
  Hosts --> Traefik
  Traefik -->|HTTP 8080 inside cluster| Keycloak
  Keycloak -->|JDBC 5432| PG
  Policies -. restrict .-> Keycloak
  Policies -. restrict .-> PG
  W1 --> Traefik
  W1 --> Keycloak
  W1 --> PG
```

The identity foundation proves OIDC discovery, JWKS, Authorization Code Flow with PKCE, signed JWT validation, expected role claims, unauthorized role absence, negative security cases, and persistence after Keycloak pod recreation. Phase 7 and Phase 8 consume those Keycloak access tokens from the FastAPI API, and Phase 9 uses the public `vdiforge-frontend` client from the React portal.

## API Control Plane

```mermaid
flowchart LR
  Browser[Browser or validation client]
  Ingress[Traefik ingress<br/>api.vdiforge.local]
  API[vdiforge-api<br/>FastAPI]
  Keycloak[Keycloak JWKS<br/>internal Service]
  DB[(vdiforge-app-postgres)]
  Provisioner[vdiforge-provisioner]
  K8s[Kubernetes API]
  CDI[CDI DataVolume]
  VM[KubeVirt VirtualMachine]
  Secret[Per-desktop remote Secret]

  Browser -->|HTTPS + bearer token| Ingress
  Ingress --> API
  API -->|JWKS fetch| Keycloak
  API -->|desktop/audit state| DB
  API -->|authorized connect read| Secret
  Provisioner -->|desired state| DB
  Provisioner -->|Kubernetes Python client| K8s
  K8s --> CDI
  K8s --> VM
  K8s --> Secret
```

The API validates the external issuer claim `https://auth.vdiforge.local/realms/vdiforge` while using an internal Keycloak Service URL for JWKS retrieval from inside the cluster. This avoids relying on workstation hosts-file DNS from pods.

## API Autoscaling

```mermaid
flowchart TB
  Load[Safe authenticated API load<br/>GET /api/v1/health/load-test]
  Ingress[Traefik ingress<br/>api.vdiforge.local]
  SVC[Service<br/>vdiforge-api]
  HPA[HorizontalPodAutoscaler<br/>autoscaling/v2]
  Metrics[Metrics Server<br/>resource metrics API]
  Deploy[Deployment<br/>vdiforge-api]
  API1[API pod 1]
  API2[API pod 2]
  API3[API pod 3]
  DB[(Application PostgreSQL)]
  Keycloak[Keycloak JWKS]

  Load --> Ingress
  Ingress --> SVC
  SVC --> API1
  SVC --> API2
  SVC --> API3
  Metrics --> HPA
  HPA --> Deploy
  Deploy --> API1
  Deploy --> API2
  Deploy --> API3
  API1 --> DB
  API2 --> DB
  API3 --> DB
  API1 --> Keycloak
  API2 --> Keycloak
  API3 --> Keycloak
```

Phase 10 uses Kubernetes `autoscaling/v2` to scale only the stateless FastAPI Deployment. The HPA changes API pod replicas; it does not create KubeVirt desktops, scale the provisioner, or add Kubernetes worker nodes. Provisioner horizontal scaling remains deferred until reconciliation has explicit work coordination such as leader election or database-backed row claiming.

## Authentication Flow

```mermaid
sequenceDiagram
  autonumber
  participant B as Browser
  participant P as React portal
  participant K as Keycloak
  participant A as FastAPI

  B->>P: Open https://vdiforge.local
  P->>K: Redirect using OIDC Authorization Code Flow with PKCE
  K->>B: Authenticate user
  K->>P: Return authorization code
  P->>K: Exchange code with PKCE verifier
  K->>P: Return ID/access tokens
  P->>A: Call API with bearer access token
  A->>K: Retrieve JWKS as needed
  A->>A: Validate signature, issuer, audience, expiration, claims
  A->>A: Enforce application RBAC
  A-->>P: Authorized API response
```

The frontend may hide unauthorized actions for usability, but authorization is enforced by FastAPI.

## Provisioning Flow

```mermaid
sequenceDiagram
  autonumber
  participant U as User
  participant P as Portal
  participant A as FastAPI
  participant DB as PostgreSQL
  participant R as Provisioner
  participant K as Kubernetes API
  participant V as KubeVirt

  U->>P: Select image and resource profile
  P->>A: POST /api/v1/desktops
  A->>A: Validate JWT and RBAC
  A->>A: Validate quota, image authorization, idempotency key
  A->>DB: Create Desktop and ProvisioningOperation
  A-->>P: 202 Accepted with desktop ID
  R->>DB: Read requested operations
  R->>K: Create or patch VirtualMachine, PVC/DataVolume, Service
  K->>V: Reconcile VM resources
  V->>K: Report VMI phase and conditions
  R->>K: Observe VM state
  R->>DB: Update observed state and audit events
  P->>A: Poll or subscribe to desktop status
  A-->>P: READY when KubeVirt VM is running and RDP is reachable
```

Provisioning is asynchronous. The HTTP request is not held open while a VM boots.

## VDI Lifecycle

```mermaid
stateDiagram-v2
  [*] --> REQUESTED
  REQUESTED --> PROVISIONING
  PROVISIONING --> BOOTING
  BOOTING --> READY
  READY --> CONNECTED
  CONNECTED --> READY: disconnect
  READY --> STOPPING
  CONNECTED --> STOPPING
  STOPPING --> TERMINATED
  READY --> TERMINATED: delete
  PROVISIONING --> FAILED
  BOOTING --> FAILED
  STOPPING --> FAILED
  FAILED --> TERMINATED: cleanup
```

`FAILED` states must include a reason and enough context for troubleshooting without exposing secrets.

## Remote Connection

```mermaid
sequenceDiagram
  autonumber
  participant B as React portal / browser
  participant A as FastAPI
  participant D as PostgreSQL
  participant K as Kubernetes API
  participant G as Guacamole web
  participant GD as guacd
  participant S as Desktop Service
  participant VM as Ubuntu VM xrdp

  B->>A: POST /api/v1/desktops/{id}/connect with bearer token
  A->>A: Validate JWT, owner/admin access, READY state
  A->>K: Read per-desktop remote Secret
  A->>D: Record connection request audit event
  A-->>B: Short-lived encrypted Guacamole JSON URL
  B->>G: Open https://remote.vdiforge.local/?data=...
  G->>G: Validate and decrypt JSON token
  G->>GD: Create one RDP connection
  GD->>S: RDP 3389 inside cluster
  S->>VM: Forward to xrdp
```

Remote desktop credentials are not returned by the API response. The browser receives only an encrypted Guacamole JSON-auth token with a 300-second TTL. Direct RDP is not exposed outside the cluster.

## Image Pipeline

```mermaid
flowchart TB
  Source[Official Ubuntu 26.04 cloud image<br/>pinned SHA-256]
  Packer[Packer 1.16.0<br/>QEMU + Ansible plugins 1.1.6]
  Ansible[Image Ansible roles<br/>common, desktop, developer, devops]
  Validate[In-guest validation<br/>desktop and tool checks]
  Generalize[Offline generalization<br/>virt-sysprep]
  Artifact[Versioned QCOW2 artifact<br/>artifacts/images]
  Catalog[images/catalog.json<br/>role policy and version metadata]
  HTTP[Temporary host-only HTTP source<br/>vdi-worker-02]
  CDI[CDI DataVolume import<br/>checksum validated]
  PVC[PVC<br/>vdiforge-local-path]
  VM[KubeVirt VM<br/>phase6-ubuntu-devops]
  KVM[KVM request<br/>devices.kubevirt.io/kvm]

  Source --> Packer
  Packer --> Ansible
  Ansible --> Validate
  Validate --> Generalize
  Generalize --> Artifact
  Artifact --> Catalog
  Artifact --> HTTP
  HTTP --> CDI
  CDI --> PVC
  PVC --> VM
  VM --> KVM
```

Phase 6 builds `ubuntu-base`, `ubuntu-developer`, and `ubuntu-devops` image definitions. The required integration proof imports the generated `ubuntu-devops:1.0.0` QCOW2 through CDI, schedules a disposable VM by `vdiforge.io/node-role=vdi`, verifies it runs on `vdi-worker-02`, verifies the KVM request, validates DevOps tooling inside the guest, and cleans up the disposable VM resources. Phase 8 builds/imports `ubuntu-devops:1.1.0` for remote desktop validation. Phase 9 promotes `ubuntu-devops:1.2.0` as the current launchable DevOps image with the permanent XFCE/xrdp session fix.

Image rollback changes the promoted version for new launches only. Running desktops are not silently modified by rollback.

## Observability

```mermaid
flowchart TB
  Browser[Browser request ID]
  API[FastAPI logs and metrics]
  Provisioner[Provisioner logs and metrics]
  Kube[Kubernetes events]
  KubeVirt[KubeVirt VM conditions]
  Audit[(Audit events)]
  Guac[Guacamole logs]
  Guacd[guacd logs]
  Prom[Prometheus]
  Grafana[Grafana dashboards]

  Browser --> API
  API --> Provisioner
  Provisioner --> Kube
  Kube --> KubeVirt
  API --> Audit
  Provisioner --> Audit
  Browser --> Guac
  Guac --> Guacd
  API --> Prom
  Provisioner --> Prom
  Kube --> Prom
  KubeVirt --> Prom
  Prom --> Grafana
```

Correlation/request IDs allow a launch operation to be traced across browser, API, provisioner, Kubernetes/KubeVirt, and audit events.
