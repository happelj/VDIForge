# VDIForge

VDIForge is a portfolio platform project for a small, open-source, self-service Virtual Desktop Infrastructure control plane. It is designed to demonstrate senior platform, VDI, cloud infrastructure, and infrastructure-as-code engineering practices without depending on paid VDI products or cloud infrastructure for the initial lab.

## Project Status

Phase 1 established the architecture, requirements, roadmap, standards, and documentation structure. Phase 2 added the local VirtualBox infrastructure foundation. Phase 3 established the Kubernetes and KubeVirt foundation. Phase 4 added the Helm deployment foundation. Phase 5 established the Keycloak/OIDC/RBAC identity foundation. Phase 6 established the Ubuntu/Packer golden-image pipeline. Phase 7 established the FastAPI VDI control plane, PostgreSQL application persistence, and asynchronous KubeVirt provisioning. Phase 8 establishes Apache Guacamole remote desktop delivery through server-brokered RDP sessions.

The current local lab is three manually created Ubuntu Server VirtualBox VMs with Terraform infrastructure specifications, Ansible host configuration, kubeadm/containerd, Calico, Metrics Server, KubeVirt, CDI, local-path storage, a Helm v4.2.4 foundation chart, Traefik ingress, Keycloak, PostgreSQL persistence, source-controlled realm configuration, Packer/Ansible golden-image definitions, image catalog policy, FastAPI API/provisioner services, application PostgreSQL persistence, Apache Guacamole, `guacd`, RDP/xrdp session brokering, validation scripts, and verified `/dev/kvm` exposure on the VDI worker. React application code, Prometheus, and Grafana dashboards are not implemented yet.

## Goals

- Provide a self-service browser workflow for launching authorized Ubuntu desktop VMs.
- Use Keycloak for OIDC-based authentication and trusted identity claims.
- Enforce application authorization server-side through a simple RBAC model.
- Provision desktops through Kubernetes and KubeVirt instead of treating containers as VDI VMs.
- Use Apache Guacamole as a browser-based remote desktop gateway.
- Build Ubuntu desktop image variants through Packer and Ansible.
- Keep the initial lab reproducible with free and open-source technologies.
- Design observability, audit logging, CI/CD, and operations from the beginning.

## Architecture Summary

The planned MVP workflow is:

```text
Thin Client / Laptop
        |
      HTTPS
        |
        v
 VDIForge Web Portal
        |
        +------> Keycloak
        |        OIDC / SSO
        |             |
        <-------------+
        |
        v
 VDIForge FastAPI
 Authentication / RBAC
        |
        v
 Provisioning Service
        |
        v
 Kubernetes API
        |
        v
     KubeVirt
        |
        v
 Ubuntu Desktop VM
        |
        v
 Remote Desktop Service
        |
        v
 Apache Guacamole
        |
        v
 Browser-based Desktop
```

The client does not download or boot Ubuntu locally. Applications run on the remote Ubuntu VM. The browser receives a remote graphical session through Guacamole and sends keyboard and mouse input back to the remote desktop.

## Planned Technology Stack

| Area | Technology |
| --- | --- |
| Operating system | Ubuntu Server for Kubernetes nodes; Ubuntu Desktop for VDI images |
| Cluster bootstrap | kubeadm, containerd |
| Networking | Calico CNI with Kubernetes NetworkPolicies |
| VM orchestration | KubeVirt on Kubernetes |
| Infrastructure lifecycle | Terraform specifications for the current VirtualBox lab; future KVM/libvirt or cloud lifecycle where practical |
| Host configuration | Ansible baseline roles and inventory |
| Image build | Packer `1.16.0`, QEMU plugin `1.1.6`, Ansible plugin `1.1.6`, Ansible image roles, QCOW2 artifacts |
| Application backend | Python, FastAPI, Pydantic, PostgreSQL |
| Frontend | React |
| Identity | Keycloak, OIDC, OAuth 2.0, JWT validation |
| Remote desktop | Apache Guacamole, MVP protocol RDP via xrdp, VNC as fallback |
| Deployment | Helm v4.2.4 foundation chart and future application charts |
| Observability | Prometheus, Grafana, structured logs, audit events |
| CI/CD | GitHub Actions |

## Local Development Concept

The initial lab is designed around three Ubuntu Server Kubernetes nodes:

| Node | Role | Host-only IP | CPU | RAM | Disk |
| --- | --- | --- | ---: | ---: | ---: |
| `vdi-control-01` | control-plane node | `192.168.56.10` | 4 vCPU | 6144 MiB | 40 GiB |
| `vdi-worker-01` | future platform worker | `192.168.56.11` | 2 vCPU | 6144 MiB | 50 GiB |
| `vdi-worker-02` | future VDI worker | `192.168.56.12` | 4 vCPU | 8192 MiB | 60 GiB |

Suggested labels:

```text
vdiforge.io/node-role=platform
vdiforge.io/node-role=vdi
```

This local topology demonstrates scheduling, placement, node roles, labels, resource management, node failure behavior, and logical node pools. It is not a production highly available control plane, and three VMs on one physical host are not separate physical failure domains.

Phase 2 uses Oracle VirtualBox 7.2.16 on Windows 10 Pro because the developer cannot install Linux directly on bare metal or add storage. `vdi-worker-02` has nested virtualization enabled and `/dev/kvm` verified inside the Ubuntu guest. See [Local Infrastructure](docs/LOCAL-INFRASTRUCTURE.md).

Phase 4 installs Helm only in the administrative environment and deploys a foundation release named `vdiforge` into `vdiforge-system`. The chart owns VDIForge platform ConfigMap conventions, ServiceAccounts, provisioner RBAC, ResourceQuotas, a LimitRange, and baseline NetworkPolicies. See [Helm Platform Foundation](docs/HELM-PLATFORM.md).

Phase 5 deploys Keycloak `26.7.2`, PostgreSQL `18.0-alpine`, and Traefik chart `41.2.0`. Keycloak is exposed at `https://auth.vdiforge.local`, imports the `vdiforge` realm from source-controlled JSON, and validates Authorization Code Flow with PKCE, JWT signature/issuer/audience/expiration checks, role claims, negative security cases, and persistence after pod recreation. See [Keycloak, OIDC, and RBAC Foundation](docs/KEYCLOAK-OIDC.md).

Phase 6 defines three Ubuntu 26.04 LTS golden images: `ubuntu-base`, `ubuntu-developer`, and `ubuntu-devops`. The current pipeline uses Packer with the QEMU builder, dedicated Ansible image roles, XFCE, QCOW2 artifacts, source checksums, image manifests, a machine-readable image catalog, CDI import, and a KubeVirt boot proof for the DevOps image. Generated image artifacts stay under ignored local `artifacts/images/` paths. See [Golden Images](docs/GOLDEN-IMAGES.md).

Phase 7 deploys the FastAPI API and provisioner backed by PostgreSQL. The API validates Keycloak JWTs, enforces image RBAC, ownership, quotas, idempotency, and audit-event persistence, then returns `202 Accepted` while the provisioner reconciles desktop records into KubeVirt `DataVolume`, `VirtualMachine`, and `Service` resources. See [FastAPI VDI Control Plane](docs/API-CONTROL-PLANE.md).

Phase 8 deploys `localhost/vdiforge-api:0.8.0`, `guacamole/guacamole:1.6.0`, and `guacamole/guacd:1.6.0`. The API adds `POST /api/v1/desktops/{id}/connect`, verifies desktop ownership and READY state, creates a short-lived encrypted Guacamole JSON handoff URL, and records connection audit events without exposing reusable RDP credentials to the frontend. The remote-enabled launchable image is `ubuntu-devops:1.1.0`. See [Remote Desktop Delivery](docs/REMOTE-DESKTOP.md).

## Repository Organization

| Path | Purpose |
| --- | --- |
| [docs/DESIGN.md](docs/DESIGN.md) | Authoritative technical design |
| [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) | Formal testable requirements |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture diagrams and flows |
| [docs/LOCAL-INFRASTRUCTURE.md](docs/LOCAL-INFRASTRUCTURE.md) | Phase 2 host, VirtualBox, network, SSH, and validation details |
| [docs/KUBERNETES-KUBEVIRT.md](docs/KUBERNETES-KUBEVIRT.md) | Phase 3 Kubernetes, KubeVirt, storage, and validation details |
| [docs/HELM-PLATFORM.md](docs/HELM-PLATFORM.md) | Phase 4 Helm chart, ownership, lifecycle, RBAC, quotas, and NetworkPolicies |
| [docs/KEYCLOAK-OIDC.md](docs/KEYCLOAK-OIDC.md) | Phase 5 Keycloak deployment, OIDC, PKCE, JWT validation, local TLS, and identity NetworkPolicies |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model and security controls |
| [docs/IMAGE-PIPELINE.md](docs/IMAGE-PIPELINE.md) | Packer and Ansible image lifecycle |
| [docs/GOLDEN-IMAGES.md](docs/GOLDEN-IMAGES.md) | Phase 6 golden-image pipeline, build, validation, CDI import, and KubeVirt boot proof |
| [docs/API-CONTROL-PLANE.md](docs/API-CONTROL-PLANE.md) | Phase 7 FastAPI API, PostgreSQL persistence, provisioner, KubeVirt lifecycle, and validation |
| [docs/REMOTE-DESKTOP.md](docs/REMOTE-DESKTOP.md) | Phase 8 Guacamole, RDP/xrdp delivery, session brokering, NetworkPolicies, and validation |
| [docs/SSO-RBAC.md](docs/SSO-RBAC.md) | Keycloak, OIDC, roles, and authorization |
| [docs/AUTOSCALING.md](docs/AUTOSCALING.md) | HPA, capacity, and future node autoscaling |
| [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md) | Metrics, logs, dashboards, and audit design |
| [docs/TESTING.md](docs/TESTING.md) | Test strategy and traceability approach |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Operations troubleshooting guide |
| [docs/DEMO.md](docs/DEMO.md) | Final portfolio demonstration plan |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Multi-phase implementation roadmap |
| [docs/ADR](docs/ADR) | Architecture decision records |
| [terraform](terraform/README.md) | Planned infrastructure lifecycle code |
| [ansible](ansible/README.md) | Host baseline and Kubernetes bootstrap roles |
| [packer](packer/README.md) | Planned Ubuntu image build templates |
| [kubernetes](kubernetes/README.md) | Kubernetes foundation manifests, namespace/RBAC skeletons, and KubeVirt test resources |
| [helm/vdiforge](helm/vdiforge/README.md) | VDIForge Helm foundation chart and Phase 5 identity resources |
| [backend](backend/README.md) | FastAPI API and provisioner implementation |
| [frontend](frontend/README.md) | Planned React portal |
| [keycloak](keycloak/README.md) | Reproducible Keycloak realm configuration |
| [monitoring](monitoring/README.md) | Planned Prometheus and Grafana assets |
| [scripts](scripts) | Repository validation and helper scripts |

## Documentation Index

- [Design](docs/DESIGN.md)
- [Requirements](docs/REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Local Infrastructure](docs/LOCAL-INFRASTRUCTURE.md)
- [Kubernetes and KubeVirt](docs/KUBERNETES-KUBEVIRT.md)
- [Helm Platform Foundation](docs/HELM-PLATFORM.md)
- [Keycloak, OIDC, and RBAC](docs/KEYCLOAK-OIDC.md)
- [Security](docs/SECURITY.md)
- [Image Pipeline](docs/IMAGE-PIPELINE.md)
- [Golden Images](docs/GOLDEN-IMAGES.md)
- [FastAPI VDI Control Plane](docs/API-CONTROL-PLANE.md)
- [Remote Desktop Delivery](docs/REMOTE-DESKTOP.md)
- [SSO and RBAC](docs/SSO-RBAC.md)
- [Autoscaling](docs/AUTOSCALING.md)
- [Observability](docs/OBSERVABILITY.md)
- [Testing](docs/TESTING.md)
- [Runbook](docs/RUNBOOK.md)
- [Demo Plan](docs/DEMO.md)
- [Roadmap](docs/ROADMAP.md)

## Limitations

- The current lab includes infrastructure, Kubernetes/KubeVirt, Helm, ingress, identity, the golden-image pipeline, the FastAPI API/provisioner foundation, and Guacamole remote desktop delivery. It does not yet run the React portal or full observability stack.
- Generated QCOW2 image artifacts are local build outputs and are intentionally excluded from Git.
- The Helm chart deploys foundation, identity, API, provisioner, application PostgreSQL, Guacamole, and `guacd` resources when phase values are enabled. Disabled future values remain extension points, not implemented services.
- The local three-node lab is not production HA.
- KubeVirt performance depends on KVM availability. The current Phase 3 acceptance condition requires KubeVirt to expose and consume KVM on `vdi-worker-02`.
- KubeVirt software emulation is a development fallback, not a realistic performance target.
- Local-path storage is suitable for lab validation only and is not physically highly available.
- Local Keycloak persistence uses a single PostgreSQL instance and is not HA.
- Local `.local` TLS requires a generated development CA to be trusted by each browser client.
- `remote.vdiforge.local` requires the same local hosts-file or DNS convention as `auth.vdiforge.local` and `api.vdiforge.local`.
- Phase 8 records connection requests and authorization denials, but detailed browser disconnect/session telemetry remains future work.
- True Kubernetes node autoscaling is future cloud or bare-metal functionality, not part of the fixed local lab.
- Windows desktops are out of scope for the free MVP because they require licensing.

## Roadmap

The next planned task after Phase 8 is Phase 9 - React Self-Service Portal. Later phases add observability, security hardening, CI/CD, and the final end-to-end demo.

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full roadmap.
