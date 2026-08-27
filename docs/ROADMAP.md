# Roadmap

This roadmap defines planned implementation phases. Do not begin a future phase until the preceding phase has met its acceptance criteria or an ADR explicitly changes the sequence.

## Phases

| Phase | Name | Status | Primary outcome |
| ---: | --- | --- | --- |
| 1 | Architecture and requirements | Complete | Documentation, repository foundation, ADRs, validation. |
| 2 | Local infrastructure | Complete | VirtualBox local lab, three Ubuntu Server nodes, Terraform/Ansible local foundation, `/dev/kvm` verified on VDI worker. |
| 3 | Kubernetes/KubeVirt foundation | Next | kubeadm cluster, containerd, Calico, Metrics Server, KubeVirt validated. |
| 4 | Helm/platform foundation | Planned | Namespaces, base Helm chart, platform deployment skeleton, PostgreSQL dependency path. |
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

- storage class for KubeVirt desktop disks
- exact Ansible controller path for routine operations after Phase 2
- exact Keycloak configuration-as-code mechanism
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
