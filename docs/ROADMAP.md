# Roadmap

This roadmap defines planned implementation phases. Do not begin a future phase until the preceding phase has met its acceptance criteria or an ADR explicitly changes the sequence.

## Phases

| Phase | Name | Primary outcome |
| ---: | --- | --- |
| 1 | Architecture and requirements | Documentation, repository foundation, ADRs, validation. |
| 2 | Local infrastructure | Local host/hypervisor plan, three Ubuntu Server nodes, Terraform/Ansible local foundation where practical. |
| 3 | Kubernetes/KubeVirt foundation | kubeadm cluster, containerd, Calico, Metrics Server, KubeVirt validated. |
| 4 | Helm/platform foundation | Namespaces, base Helm chart, platform deployment skeleton, PostgreSQL dependency path. |
| 5 | Keycloak/OIDC/RBAC | Realm, clients, demo users, token validation, RBAC policy tests. |
| 6 | Ubuntu/Packer image pipeline | Three versioned Ubuntu desktop images built with Packer and Ansible. |
| 7 | FastAPI VDI control plane | API, database models, desktop lifecycle, asynchronous provisioner. |
| 8 | Guacamole remote desktop | Guacamole deployment, secure dynamic connection handling, RDP/VNC validation. |
| 9 | React self-service portal | Authenticated portal, image catalog, desktop launch, lifecycle, connect/delete UI. |
| 10 | HPA/autoscaling | API/provisioner HPA, controlled load demo, capacity failure handling. |
| 11 | Prometheus/Grafana | Metrics, dashboards, alerts, logging correlation. |
| 12 | Security/audit hardening | Threat-model controls, audit persistence, secret handling, RBAC hardening, network tests. |
| 13 | CI/CD | GitHub Actions workflows for code, IaC, images, charts, security scans. |
| 14 | End-to-end validation/demo | Final E2E test, demo script, cleanup, portfolio readiness. |

## Phase 2 - Local Infrastructure

Planned outcomes:

- choose and document the local hypervisor path
- validate hardware virtualization support
- validate nested virtualization if nodes are VMs
- create or document creation of:
  - `vdi-control-01`
  - `vdi-worker-01`
  - `vdi-worker-02`
- establish Terraform boundary for local VM/network lifecycle where practical
- establish Ansible inventory and host bootstrap roles
- document fallback if nested virtualization is not reliable

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

- exact local hypervisor for the user's hardware
- storage class for KubeVirt desktop disks
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
