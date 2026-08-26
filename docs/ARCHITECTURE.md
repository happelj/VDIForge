# VDIForge Architecture

This document contains the Phase 1 architecture views for VDIForge. The diagrams show planned architecture, not an implemented system.

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
  Prom -->|scrape| API
  Prom -->|scrape| Provisioner
  Prom -->|scrape| K8s
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
    MON[Prometheus / Grafana]
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
  HW[Physical developer hardware<br/>CPU with VT-x or AMD-V]
  Hypervisor[Free local hypervisor<br/>preferred: KVM/libvirt]
  Nodes[Three Ubuntu Server node VMs]
  K8s[kubeadm Kubernetes with containerd]
  Calico[Calico CNI and NetworkPolicies]
  KubeVirt[KubeVirt on Kubernetes]
  Workloads[VDIForge platform and desktop VMs]

  HW --> Hypervisor
  Hypervisor --> Nodes
  Nodes --> K8s
  K8s --> Calico
  K8s --> KubeVirt
  KubeVirt --> Workloads
```

Nested virtualization must be validated before using a VM-based worker node for KubeVirt workloads.

## Authentication Flow

```mermaid
sequenceDiagram
  autonumber
  participant B as Browser
  participant P as React portal
  participant K as Keycloak
  participant A as FastAPI

  B->>P: Open VDIForge
  P->>K: Redirect using OIDC Authorization Code Flow with PKCE
  K->>B: Authenticate user
  K->>P: Return authorization code
  P->>K: Exchange code with PKCE verifier
  K->>P: Return ID/access tokens
  P->>A: Call API with bearer access token
  A->>K: Retrieve JWKS and issuer metadata as needed
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
  A-->>P: READY when remote session is available
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
flowchart LR
  Browser[Browser]
  Portal[VDIForge portal]
  API[FastAPI connect endpoint]
  AuthZ[Ownership and RBAC check]
  Guac[Apache Guacamole]
  Guacd[guacd]
  Service[Kubernetes Service for desktop]
  VM[Ubuntu desktop VM]
  XRDP[xrdp MVP protocol]

  Browser -->|HTTPS| Portal
  Portal -->|request connect| API
  API --> AuthZ
  AuthZ -->|short-lived connection context| Guac
  Browser -->|HTTPS / WebSocket| Guac
  Guac --> Guacd
  Guacd -->|RDP or VNC| Service
  Service --> VM
  VM --> XRDP
```

Remote desktop credentials and backend connection details are not exposed to frontend JavaScript.

## Image Pipeline

```mermaid
flowchart LR
  Source[Trusted Ubuntu source]
  Verify[Checksum and signature verification]
  Packer[Packer build]
  Ansible[Ansible configuration]
  Validate[Image validation]
  Scan[Security checks]
  Artifact[Versioned artifact]
  Test[Test launch]
  Promote[Promotion to image catalog]

  Source --> Verify
  Verify --> Packer
  Packer --> Ansible
  Ansible --> Validate
  Validate --> Scan
  Scan --> Artifact
  Artifact --> Test
  Test --> Promote
```

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
  Prom[Prometheus]
  Grafana[Grafana dashboards]

  Browser --> API
  API --> Provisioner
  Provisioner --> Kube
  Kube --> KubeVirt
  API --> Audit
  Provisioner --> Audit
  API --> Prom
  Provisioner --> Prom
  Kube --> Prom
  KubeVirt --> Prom
  Prom --> Grafana
```

Correlation/request IDs allow a launch operation to be traced across browser, API, provisioner, Kubernetes/KubeVirt, and audit events.
