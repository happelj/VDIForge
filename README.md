# VDIForge

VDIForge is a portfolio platform project for a small, open-source, self-service Virtual Desktop Infrastructure control plane. It is designed to demonstrate senior platform, VDI, cloud infrastructure, and infrastructure-as-code engineering practices without depending on paid VDI products or cloud infrastructure for the initial lab.

## Project Status

Phase 1 established the architecture, requirements, roadmap, standards, and documentation structure. Phase 2 added the local VirtualBox infrastructure foundation. Phase 3 established the Kubernetes and KubeVirt foundation. Phase 4 added the Helm deployment foundation. Phase 5 established the Keycloak/OIDC/RBAC identity foundation. Phase 6 established the Ubuntu/Packer golden-image pipeline. Phase 7 established the FastAPI VDI control plane, PostgreSQL application persistence, and asynchronous KubeVirt provisioning. Phase 8 established Apache Guacamole remote desktop delivery through server-brokered RDP sessions. Phase 9 added the React self-service portal. Phase 10 added Kubernetes HPA autoscaling for the API. Phase 11 added Prometheus and Grafana observability. Phase 12 added security and audit hardening. Phase 13 adds GitHub Actions CI/CD.

The current local lab is three manually created Ubuntu Server VirtualBox VMs with Terraform infrastructure specifications, Ansible host configuration, kubeadm/containerd, Calico, Metrics Server, KubeVirt, CDI, local-path storage, a Helm v4.2.4 foundation chart, Traefik ingress, Keycloak, PostgreSQL persistence, source-controlled realm configuration, Packer/Ansible golden-image definitions, image catalog policy, FastAPI API/provisioner services, application PostgreSQL persistence, Apache Guacamole, `guacd`, RDP/xrdp session brokering, a React/TypeScript browser portal, API HPA autoscaling, kube-prometheus-stack, Prometheus, Grafana, Alertmanager, VDIForge ServiceMonitors, alert rules, dashboard-as-code, security headers, restricted CORS, RBAC/NetworkPolicy validation, audit hash chaining/export, dependency/container scan automation, GitHub Actions workflows, Dependabot configuration, CI-safe validation scripts, and verified `/dev/kvm` exposure on the VDI worker.

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
| Application backend | Python, FastAPI, Pydantic, PostgreSQL, prometheus-client |
| Frontend | React `19.2.8`, TypeScript `6.0.3`, Vite `8.2.2`, `oidc-client-ts` `3.5.0` |
| Identity | Keycloak, OIDC, OAuth 2.0, JWT validation |
| Remote desktop | Apache Guacamole, MVP protocol RDP via xrdp, VNC as fallback |
| Deployment | Helm v4.2.4 foundation chart and future application charts |
| Autoscaling | Kubernetes HPA for `vdiforge-api`; node autoscaling deferred |
| Observability | Metrics Server for HPA, kube-prometheus-stack `88.6.1`, Prometheus Operator `v0.93.1`, Prometheus, Grafana, Alertmanager, ServiceMonitors, PrometheusRule alerts, structured logs, audit events |
| Security validation | Keycloak hardening, Traefik/FastAPI security headers, restricted CORS, `kubectl auth can-i`, NetworkPolicy probes, pip-audit, npm audit, Trivy |
| CI/CD | GitHub Actions, Dependabot, Gitleaks, pip-audit, npm audit, Trivy, Docker Buildx, kubeconform, actionlint |

## Local Development Concept

The initial lab is designed around three Ubuntu Server Kubernetes nodes:

| Node | Role | Host-only IP | CPU | RAM | Disk |
| --- | --- | --- | ---: | ---: | ---: |
| `vdi-control-01` | control-plane node | `192.168.56.10` | 4 vCPU | 6144 MiB | 40 GiB |
| `vdi-worker-01` | platform worker | `192.168.56.11` | 2 vCPU | 6144 MiB | 50 GiB |
| `vdi-worker-02` | VDI/KubeVirt worker | `192.168.56.12` | 4 vCPU | 8192 MiB | 60 GiB |

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

Phase 8 deploys Apache Guacamole `1.6.0` and `guacd` `1.6.0`. The API adds `POST /api/v1/desktops/{id}/connect`, verifies desktop ownership and READY state, creates a short-lived encrypted Guacamole JSON handoff URL, and records connection audit events without exposing reusable RDP credentials to the frontend. See [Remote Desktop Delivery](docs/REMOTE-DESKTOP.md).

Phase 9 deploys `localhost/vdiforge-frontend:0.9.0` at `https://vdiforge.local` and upgrades the API/provisioner image to `localhost/vdiforge-api:0.9.0`. The portal uses the existing Keycloak public client with Authorization Code Flow and PKCE, renders API-authorized images/desktops, launches the current `ubuntu-devops:1.2.0` image, polls lifecycle state, opens the exact brokered Guacamole URL, and never receives reusable remote desktop credentials. See [React Self-Service Portal](docs/WEB-PORTAL.md).

Phase 10 upgrades the API/provisioner image tag to `localhost/vdiforge-api:0.10.0` and adds a Helm-managed `autoscaling/v2` HPA for `vdiforge-api`. The autoscaling demo uses a protected, local/test-gated `GET /api/v1/health/load-test` endpoint and does not create desktop VMs. Provisioner HPA remains deferred until reconciliation has explicit work coordination. See [Autoscaling](docs/AUTOSCALING.md).

Phase 11 upgrades the API/provisioner image tag to `localhost/vdiforge-api:0.11.0` and deploys `kube-prometheus-stack` into the existing `monitoring` namespace. Prometheus scrapes VDIForge API/provisioner metrics through ServiceMonitors, KubeVirt metrics through the supported Prometheus Operator integration, Kubernetes/node/HPA metrics, and renders the `VDIForge Overview` Grafana dashboard at `https://grafana.vdiforge.local`. See [Prometheus and Grafana](docs/PROMETHEUS-GRAFANA.md).

Phase 12 upgrades the API/provisioner image tag to `localhost/vdiforge-api:0.12.0` and hardens the existing platform. It adds API security headers, Traefik header middleware, restricted CORS validation, high-impact operation rate limits, stricter input validation, centralized redaction, audit hash chaining, admin-only JSON Lines audit export, Keycloak brute-force protection, RBAC/NetworkPolicy security tests, dependency/container scanning, and a documented secret inventory. See [Security Hardening](docs/SECURITY-HARDENING.md).

Phase 13 adds GitHub Actions CI/CD for pull requests, feature-branch validation pushes, pushes to `main`, releases, and manual validation. CI runs backend lint/tests/migration checks, frontend lint/tests/build checks, Terraform/Ansible/Packer/Helm/Kubernetes manifest validation, secret and dependency scans, custom container builds, Trivy image scans, SBOM generation, and workflow validation. Full KubeVirt, Guacamole, xrdp, and QCOW2 image-build tests remain local/manual because they require the live VirtualBox/KVM lab. See [CI/CD Pipeline](docs/CI-CD.md).

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
| [docs/WEB-PORTAL.md](docs/WEB-PORTAL.md) | Phase 9 React portal, OIDC/PKCE login, desktop workflows, Helm deployment, and validation |
| [docs/PROMETHEUS-GRAFANA.md](docs/PROMETHEUS-GRAFANA.md) | Phase 11 Prometheus, Grafana, Alertmanager, dashboards, alerts, and validation |
| [docs/SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md) | Phase 12 security controls, audit integrity, secret inventory, scanning, and validation |
| [docs/CI-CD.md](docs/CI-CD.md) | Phase 13 GitHub Actions, validation checks, security scans, container builds, SBOMs, releases, and branch protection |
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
| [frontend](frontend/README.md) | React self-service portal |
| [keycloak](keycloak/README.md) | Reproducible Keycloak realm configuration |
| [monitoring](monitoring/README.md) | Prometheus/Grafana values and dashboard source |
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
- [React Self-Service Portal](docs/WEB-PORTAL.md)
- [Prometheus and Grafana](docs/PROMETHEUS-GRAFANA.md)
- [Security Hardening](docs/SECURITY-HARDENING.md)
- [CI/CD Pipeline](docs/CI-CD.md)
- [SSO and RBAC](docs/SSO-RBAC.md)
- [Autoscaling](docs/AUTOSCALING.md)
- [Observability](docs/OBSERVABILITY.md)
- [Testing](docs/TESTING.md)
- [Runbook](docs/RUNBOOK.md)
- [Demo Plan](docs/DEMO.md)
- [Roadmap](docs/ROADMAP.md)

## Limitations

- The current lab includes infrastructure, Kubernetes/KubeVirt, Helm, ingress, identity, the golden-image pipeline, the FastAPI API/provisioner foundation, Guacamole remote desktop delivery, the React self-service portal, API HPA autoscaling, Prometheus/Grafana observability, Phase 12 security/audit hardening, and Phase 13 CI/CD.
- Generated QCOW2 image artifacts are local build outputs and are intentionally excluded from Git.
- The Helm chart deploys foundation, identity, API, provisioner, application PostgreSQL, Guacamole, `guacd`, and frontend resources when phase values are enabled. Disabled future values remain extension points, not implemented services.
- The local three-node lab is not production HA.
- KubeVirt performance depends on KVM availability. The current Phase 3 acceptance condition requires KubeVirt to expose and consume KVM on `vdi-worker-02`.
- KubeVirt software emulation is a development fallback, not a realistic performance target.
- Local-path storage is suitable for lab validation only and is not physically highly available.
- Local Keycloak persistence uses a single PostgreSQL instance and is not HA.
- Local `.local` TLS requires a generated development CA to be trusted by each browser client.
- `vdiforge.local` and `remote.vdiforge.local` require the same local hosts-file or DNS convention as `auth.vdiforge.local` and `api.vdiforge.local`.
- Phase 9 records portal-driven connection requests and authorization denials through the API, but detailed browser disconnect/session telemetry remains future work.
- Phase 10 autoscaling applies only to API pods. It does not autoscale KubeVirt desktops, the provisioner, or Kubernetes worker nodes.
- Phase 11 Grafana uses generated local admin credentials instead of Keycloak OIDC. Grafana OIDC role mapping is deferred.
- Alertmanager has no external notification receiver in the local lab.
- Phase 12 rate limiting is in-process and therefore per API pod under HPA; production would need a shared limiter or gateway policy.
- Phase 12 audit hash chaining is tamper-evident inside the application database, not an immutable external audit sink.
- Phase 13 GitHub Actions does not connect to the home lab, run live KubeVirt/Guacamole/browser VDI tests, or build full QCOW2 golden images on normal pull requests.
- Phase 13 release publishing targets GHCR only from semantic version tag or manual workflows; pull-request container jobs build and scan but do not push images.
- True Kubernetes node autoscaling is future cloud or bare-metal functionality, not part of the fixed local lab.
- Windows desktops are out of scope for the free MVP because they require licensing.

## Roadmap

The next planned task after Phase 13 is Phase 14 - Final End-to-End Validation & Portfolio Demo.

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full roadmap.
