# VDIForge

VDIForge is a portfolio platform project for a small, open-source, self-service Virtual Desktop Infrastructure control plane. It is designed to demonstrate senior platform, VDI, cloud infrastructure, and infrastructure-as-code engineering practices without depending on paid VDI products or cloud infrastructure for the initial lab.

## Project Status

Phase 1 is an architecture and requirements phase. The repository currently contains the authoritative design, requirements, roadmap, standards, and documentation structure for later implementation phases.

No VDI platform is implemented yet. The FastAPI backend, React portal, Helm chart, Terraform modules, Ansible roles, Packer templates, KubeVirt manifests, and monitoring dashboards are planned deliverables for later phases.

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

| Area | Planned technology |
| --- | --- |
| Operating system | Ubuntu Server for Kubernetes nodes; Ubuntu Desktop for VDI images |
| Cluster bootstrap | kubeadm, containerd |
| Networking | Calico CNI with Kubernetes NetworkPolicies |
| VM orchestration | KubeVirt on Kubernetes |
| Infrastructure lifecycle | Terraform, with local KVM/libvirt as the preferred no-cost lab target where practical |
| Host configuration | Ansible |
| Image build | Packer plus Ansible |
| Application backend | Python, FastAPI, Pydantic, PostgreSQL |
| Frontend | React |
| Identity | Keycloak, OIDC, OAuth 2.0, JWT validation |
| Remote desktop | Apache Guacamole, MVP protocol RDP via xrdp, VNC as fallback |
| Deployment | Helm |
| Observability | Prometheus, Grafana, structured logs, audit events |
| CI/CD | GitHub Actions |

## Local Development Concept

The initial lab is designed around three Ubuntu Server Kubernetes nodes:

| Node | Role | Intended placement |
| --- | --- | --- |
| `vdi-control-01` | control-plane node | Kubernetes API and control-plane components |
| `vdi-worker-01` | platform worker | API, identity, monitoring, Guacamole |
| `vdi-worker-02` | VDI worker | KubeVirt VM workloads and VDI-oriented resources |

Suggested labels:

```text
vdiforge.io/node-role=platform
vdiforge.io/node-role=vdi
```

This local topology demonstrates scheduling, placement, node roles, labels, resource management, node failure behavior, and logical node pools. It is not a production highly available control plane, and three VMs on one physical host are not separate physical failure domains.

## Repository Organization

| Path | Purpose |
| --- | --- |
| [docs/DESIGN.md](docs/DESIGN.md) | Authoritative technical design |
| [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) | Formal testable requirements |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture diagrams and flows |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model and security controls |
| [docs/IMAGE-PIPELINE.md](docs/IMAGE-PIPELINE.md) | Packer and Ansible image lifecycle |
| [docs/SSO-RBAC.md](docs/SSO-RBAC.md) | Keycloak, OIDC, roles, and authorization |
| [docs/AUTOSCALING.md](docs/AUTOSCALING.md) | HPA, capacity, and future node autoscaling |
| [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md) | Metrics, logs, dashboards, and audit design |
| [docs/TESTING.md](docs/TESTING.md) | Test strategy and traceability approach |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Operations troubleshooting guide |
| [docs/DEMO.md](docs/DEMO.md) | Final portfolio demonstration plan |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Multi-phase implementation roadmap |
| [docs/ADR](docs/ADR) | Architecture decision records |
| [terraform](terraform/README.md) | Planned infrastructure lifecycle code |
| [ansible](ansible/README.md) | Planned host and image configuration roles |
| [packer](packer/README.md) | Planned Ubuntu image build templates |
| [kubernetes](kubernetes/README.md) | Planned namespaces, policies, and KubeVirt resources |
| [helm/vdiforge](helm/vdiforge/README.md) | Planned VDIForge Helm chart |
| [backend](backend/README.md) | Planned FastAPI service |
| [frontend](frontend/README.md) | Planned React portal |
| [keycloak](keycloak/README.md) | Planned reproducible realm configuration |
| [monitoring](monitoring/README.md) | Planned Prometheus and Grafana assets |
| [scripts](scripts) | Repository validation and helper scripts |

## Documentation Index

- [Design](docs/DESIGN.md)
- [Requirements](docs/REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Security](docs/SECURITY.md)
- [Image Pipeline](docs/IMAGE-PIPELINE.md)
- [SSO and RBAC](docs/SSO-RBAC.md)
- [Autoscaling](docs/AUTOSCALING.md)
- [Observability](docs/OBSERVABILITY.md)
- [Testing](docs/TESTING.md)
- [Runbook](docs/RUNBOOK.md)
- [Demo Plan](docs/DEMO.md)
- [Roadmap](docs/ROADMAP.md)

## Limitations

- The current phase is documentation-only.
- The local three-node lab is not production HA.
- KubeVirt performance depends on KVM availability. Nested virtualization must be validated on the chosen host and hypervisor before relying on the local VM-based node layout.
- KubeVirt software emulation is a development fallback, not a realistic performance target.
- True Kubernetes node autoscaling is future cloud or bare-metal functionality, not part of the fixed local lab.
- Windows desktops are out of scope for the free MVP because they require licensing.

## Roadmap

The next planned task is Phase 2 - Local Infrastructure. Later phases add Kubernetes, KubeVirt, Helm, Keycloak, image automation, backend, frontend, Guacamole, observability, security hardening, CI/CD, and the final end-to-end demo.

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full roadmap.
