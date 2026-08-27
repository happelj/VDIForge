# Roadmap

This roadmap defines planned implementation phases. Do not begin a future phase until the preceding phase has met its acceptance criteria or an ADR explicitly changes the sequence.

## Phases

| Phase | Name | Status | Primary outcome |
| ---: | --- | --- | --- |
| 1 | Architecture and requirements | Complete | Documentation, repository foundation, ADRs, validation. |
| 2 | Local infrastructure | Complete | VirtualBox local lab, three Ubuntu Server nodes, Terraform/Ansible local foundation, `/dev/kvm` verified on VDI worker. |
| 3 | Kubernetes/KubeVirt foundation | Complete | kubeadm cluster, containerd, Calico, Metrics Server, KubeVirt, CDI, storage, NetworkPolicy, and test VM validation. |
| 4 | Helm/platform foundation | Complete | Helm v4.2.4 client, VDIForge foundation chart, release lifecycle, RBAC, quotas, LimitRange, NetworkPolicies, and validation. |
| 5 | Keycloak/OIDC/RBAC | Planned | Realm, clients, demo users, token validation, RBAC policy tests. |
| 6 | Ubuntu/Packer image pipeline | Planned | Three versioned Ubuntu desktop images built with Packer and Ansible. |
| 7 | FastAPI VDI control plane | Planned | API, database models, desktop lifecycle, asynchronous provisioner. |
| 8 | Guacamole remote desktop | Planned | Guacamole deployment, secure dynamic connection handling, RDP/VNC validation. |
| 9 | React self-service portal | Planned | Authenticated portal, image catalog, desktop launch, lifecycle, connect/delete UI. |
| 10 | HPA/autoscaling | Planned | API/provisioner HPA, controlled load demo, capacity failure handling. |
| 11 | Prometheus/Grafana | Planned | Metrics, dashboards, alerts, logging correlation. |
| 12 | Security/audit hardening | Planned | Threat-model controls, audit persistence, secret handling, RBAC hardening, network tests. |
| 13 | CI/CD | Planned | GitHub Actions workflows for code, IaC, images, charts, security scans. |
| 14 | End-to-end validation/demo | Planned | Final E2E test, demo script, cleanup, portfolio readiness. |

## Phase 2 - Local Infrastructure

Completed outcomes:

- selected and documented Oracle VirtualBox 7.2.16 on Windows 10 Pro for the current host
- created and documented:
  - `vdi-control-01`
  - `vdi-worker-01`
  - `vdi-worker-02`
- validated host-to-node SSH
- validated node-to-node ping
- verified `/dev/kvm` on `vdi-worker-02`
- established Terraform specification boundary for the VirtualBox lab
- established Ansible inventory and baseline roles
- documented limits and troubleshooting in [Local Infrastructure](LOCAL-INFRASTRUCTURE.md)

Phase 2 validation notes:

- Ansible syntax, lint, and idempotency passed from `vdi-control-01`.
- Outbound connectivity passed on all three nodes.
- Temporary validation-only passwordless sudo was removed after the idempotency check.

## Phase 3 - Kubernetes/KubeVirt Foundation

Completed outcomes:

- install pinned Kubernetes 1.36.4 with kubeadm and containerd
- install Calico v3.32.1 for pod networking and NetworkPolicy support
- label `vdi-worker-01` as the platform worker and `vdi-worker-02` as the VDI worker
- install Metrics Server v0.8.1 for future HPA metrics
- install KubeVirt v1.9.0 and CDI v1.66.0
- install local-path provisioner v0.0.32 with StorageClass `vdiforge-local-path`
- create namespace and least-privilege RBAC foundations without deploying applications
- prove NetworkPolicy deny/allow behavior
- prove a disposable CirrOS VM can run on `vdi-worker-02` with KVM

Phase 3 validation passed with `KUBEVIRT_KVM_VERIFIED` on `vdi-worker-02`, clean Ansible idempotency, and successful disposable KubeVirt VM lifecycle cleanup.

## Phase 4 - Helm / Platform Foundation

Completed outcomes:

- selected and documented Helm v4.2.4 for the Kubernetes 1.36.4 lab
- created the `helm/vdiforge` chart with environment-neutral defaults and local overrides
- deployed release `vdiforge` in `vdiforge-system`
- documented namespace ownership: Phase 3 owns foundational namespaces, Helm owns VDIForge platform resources
- adopted the Phase 3 provisioner ServiceAccount, Role, and RoleBinding into Helm ownership
- created Helm-managed ServiceAccounts, provisioner RBAC, ResourceQuotas, a platform LimitRange, ConfigMap conventions, and baseline NetworkPolicies
- validated install, upgrade, repeated upgrade, rollback, and final deployed release state
- confirmed Phase 4 does not deploy Keycloak, Guacamole, FastAPI, React, Prometheus/Grafana, Packer images, or VDI desktops

Phase 4 validation confirms Helm lifecycle behavior while preserving the Phase 3 Kubernetes, KubeVirt, CDI, Metrics Server, Calico, storage, and KVM foundation.

## Future Enhancements

Potential future work after the MVP:

- physical bare-metal Kubernetes
- cloud deployment
- true Kubernetes node autoscaling
- HA control plane
- GPU-backed desktops
- persistent user profiles
- distributed storage
- snapshots
- backup/restore
- SIEM integration
- policy engines
- staged/canary image releases
- automated image rollback
- cost accounting/showback
- stronger multi-tenancy
- Windows support only as an optional future licensed capability

## Deferred Decisions

The following are intentionally deferred:

- exact Ansible controller path for routine operations after Phase 3
- exact Keycloak configuration-as-code mechanism and Helm chart choice
- Keycloak persistence mode and resource allocation on the platform worker
- local ingress controller, DNS, and TLS approach for browser-facing services
- Guacamole dynamic connection implementation strategy
- exact Ubuntu desktop flavor
- remote desktop clipboard/file-transfer policy
- exact PostgreSQL deployment mode
- exact security and dependency scanning tools

## Roadmap Rules

- Do not add complex infrastructure to satisfy keywords.
- Every phase must update documentation when reality differs from design.
- Every major architectural change requires an ADR.
- Demonstrability and reliability take priority over unnecessary complexity.
