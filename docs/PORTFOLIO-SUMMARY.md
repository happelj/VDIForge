# VDIForge Portfolio Summary

VDIForge is a local, open-source Virtual Desktop Infrastructure portfolio platform. It demonstrates how a self-service browser portal can authenticate users, authorize image access, provision KubeVirt-backed Ubuntu desktops, broker remote access through Apache Guacamole, observe the platform with Prometheus/Grafana, and validate the repository with CI/CD.

This project was created with AI-assisted engineering tools under human direction, review, and validation. The repository keeps architecture decisions, implementation details, and validation scripts in source control so reviewers can inspect the design and reproduce the evidence.

## 30-Second Summary

VDIForge is a three-node local Kubernetes/KubeVirt VDI lab running on VirtualBox. It uses Keycloak OIDC with PKCE, a FastAPI control plane, PostgreSQL state, KubeVirt virtual machines, Apache Guacamole RDP brokering, a React portal, Prometheus/Grafana observability, HPA autoscaling, security hardening, audit hash chaining, and GitHub Actions CI/CD. It is intentionally local and free to run on existing hardware rather than dependent on paid cloud or commercial VDI products.

## 2-Minute Summary

VDIForge starts with a Windows 10 Pro host running three Ubuntu Server VirtualBox nodes. The cluster uses kubeadm, containerd, Calico NetworkPolicy, Metrics Server, KubeVirt, CDI, and local-path storage. `vdi-worker-02` exposes KVM to KubeVirt and runs VDI workloads.

Users authenticate through Keycloak at `auth.vdiforge.local`. The React portal at `vdiforge.local` uses Authorization Code Flow with PKCE and sends bearer tokens to the FastAPI API at `api.vdiforge.local`. The API validates JWT signature, issuer, audience, expiration, and role claims before returning authorized images or accepting desktop lifecycle actions.

The API records desired desktop state in PostgreSQL. The provisioner reconciles that state into KubeVirt `DataVolume`, `VirtualMachine`, and Service resources. When a desktop reaches `READY`, the API returns a short-lived Apache Guacamole handoff URL for `remote.vdiforge.local` without exposing reusable RDP credentials to browser JavaScript.

The final demo catalog contains:

| Role | Visible Images |
| --- | --- |
| `demo-user` | Ubuntu Base |
| `demo-developer` | Ubuntu Base, Ubuntu Developer |
| `demo-devops` | Ubuntu Base, Ubuntu Developer, Ubuntu DevOps |
| `demo-admin` | Ubuntu Base, Ubuntu Developer, Ubuntu DevOps |

The main browser VDI proof launches Ubuntu DevOps `1.2.0` because it contains the validated XFCE/xrdp remote desktop path and DevOps tools.

## Resume Bullets

- Built VDIForge, a local Kubernetes/KubeVirt VDI platform using Ubuntu, kubeadm, containerd, Calico, Metrics Server, KubeVirt, CDI, Helm, Keycloak, FastAPI, PostgreSQL, React, Apache Guacamole, Prometheus, Grafana, Terraform specs, Ansible, Packer, and GitHub Actions.
- Implemented server-side OIDC/JWT validation and RBAC so users only see authorized images and can only manage their own desktops unless they hold the admin role.
- Implemented asynchronous desktop provisioning with FastAPI, PostgreSQL, KubeVirt `VirtualMachine`/`DataVolume` resources, desired-vs-observed state, idempotency, lifecycle transitions, and cleanup.
- Delivered browser-based Ubuntu desktop access through Guacamole and xrdp using short-lived connection handoff URLs and per-desktop credentials kept out of frontend JavaScript.
- Added Prometheus/Grafana observability, API HPA autoscaling, structured logs, audit persistence, tamper-evident audit hashes, security headers, CORS restrictions, RBAC tests, NetworkPolicy tests, and vulnerability/dependency scans.
- Established CI/CD with GitHub Actions for backend, frontend, Terraform, Ansible, Packer, Helm, Kubernetes manifests, secret scanning, dependency scanning, container builds, Trivy scanning, SBOMs, Dependabot, and branch-protection-ready checks.

## Demonstrated Skills

- Linux and Ubuntu server administration
- Kubernetes cluster bootstrap and operations
- KubeVirt VM orchestration
- Terraform infrastructure specification boundaries
- Ansible host/image automation
- Helm chart design and release lifecycle
- Packer/QEMU golden-image build pipeline
- Python/FastAPI backend engineering
- React/TypeScript frontend engineering
- Keycloak, OIDC, OAuth 2.0, JWT, PKCE, and RBAC
- Apache Guacamole and browser-based remote desktop delivery
- Prometheus, Grafana, metrics, alerts, and dashboards
- HPA autoscaling and capacity boundaries
- Audit logging, tamper evidence, and SIEM-ready export
- CI/CD, secret scanning, dependency scanning, container scanning, and SBOM generation

## Honest Boundaries

VDIForge is not a production commercial VDI platform. It does not reproduce any proprietary cloud or VDI architecture. The local lab is not highly available, uses local-path storage, and depends on a single physical host. It is a portfolio-grade platform designed to be technically defensible, reproducible, and demonstrable without paid infrastructure.
