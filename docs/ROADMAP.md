# Roadmap

This roadmap defines planned implementation phases. Do not begin a future phase until the preceding phase has met its acceptance criteria or an ADR explicitly changes the sequence.

## Phases

| Phase | Name | Status | Primary outcome |
| ---: | --- | --- | --- |
| 1 | Architecture and requirements | Complete | Documentation, repository foundation, ADRs, validation. |
| 2 | Local infrastructure | Complete | VirtualBox local lab, three Ubuntu Server nodes, Terraform/Ansible local foundation, `/dev/kvm` verified on VDI worker. |
| 3 | Kubernetes/KubeVirt foundation | Complete | kubeadm cluster, containerd, Calico, Metrics Server, KubeVirt, CDI, storage, NetworkPolicy, and test VM validation. |
| 4 | Helm/platform foundation | Complete | Helm v4.2.4 client, VDIForge foundation chart, release lifecycle, RBAC, quotas, LimitRange, NetworkPolicies, and validation. |
| 5 | Keycloak/OIDC/RBAC | Complete | Keycloak, PostgreSQL persistence, Traefik ingress, local TLS, realm import, demo users, PKCE/JWT/RBAC validation. |
| 6 | Ubuntu/Packer image pipeline | Complete | Packer/QEMU image templates, Ansible image roles, image catalog, QCOW2 artifacts, CDI import, and KubeVirt boot validation. |
| 7 | FastAPI VDI control plane | Complete | API, database models, desktop lifecycle, asynchronous provisioner, audit persistence, KubeVirt reconciliation. |
| 8 | Guacamole remote desktop | Complete | Guacamole deployment, secure dynamic connection handling, RDP validation. |
| 9 | React self-service portal | Complete | Authenticated portal, image catalog, desktop launch, lifecycle, connect/delete UI. |
| 10 | HPA/autoscaling | Complete | API HPA, safe authenticated load test, capacity evidence, and provisioner scaling decision. |
| 11 | Prometheus/Grafana | Complete | Prometheus, Grafana, Alertmanager, application metrics, dashboards, alerts, and validation. |
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
- install Metrics Server v0.8.1 for Kubernetes resource metrics later used by the Phase 10 API HPA
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

## Phase 5 - Keycloak / OIDC / RBAC

Completed outcomes:

- selected Keycloak `26.7.2` with the official container image
- deployed Keycloak through the VDIForge Helm chart with Phase 5 local values
- deployed single-instance PostgreSQL `18.0-alpine` with persistent local-path storage for Keycloak
- installed Traefik chart `41.2.0` as the local ingress controller in `ingress-traefik`
- exposed Keycloak at `https://auth.vdiforge.local` using a generated local development CA
- defined the `vdiforge` realm as source-controlled JSON
- created public OIDC client `vdiforge-frontend` using Authorization Code Flow with PKCE S256
- created API audience client `vdiforge-api`
- created realm roles `vdi-user`, `vdi-developer`, `vdi-devops`, and `vdi-admin`
- created demo identities without committing passwords
- validated discovery, JWKS, signed access tokens, issuer, audience, expiration, and role claims
- validated negative cases including invalid credentials, invalid redirect URI, invalid PKCE verifier, tampered JWT, expired JWT, wrong issuer, wrong audience, and unauthorized admin role absence
- verified Keycloak state survives ordinary Keycloak pod recreation
- validated identity NetworkPolicies and previous phase regression health

## Phase 6 - Ubuntu / Packer Golden Image Pipeline

Completed outcomes:

- selected Packer `1.16.0` with the HashiCorp QEMU and Ansible plugins `1.1.6`
- selected the official Ubuntu 26.04 LTS amd64 cloud image as the trusted source
- pinned the Ubuntu source SHA-256 checksum in every Packer template
- created Packer definitions for `ubuntu-base`, `ubuntu-developer`, and `ubuntu-devops`
- created dedicated Ansible image roles separate from host/Kubernetes roles
- selected XFCE as the lightweight desktop foundation
- installed future remote desktop prerequisites without deploying Guacamole
- selected QCOW2 as the local image artifact format
- created the machine-readable image catalog at `images/catalog.json`
- implemented build, catalog, image, CDI import, and KubeVirt validation scripts
- documented promotion, rollback, patching, security cleanup, and artifact handling
- kept generated QCOW2 artifacts out of Git

Phase 6 validation requires the final `ubuntu-devops:1.0.0` artifact to import through CDI, boot as a KubeVirt VM on `vdi-worker-02`, request KVM, validate DevOps tools inside the guest, stop, restart, delete, and clean up.

## Phase 7 - FastAPI VDI Control Plane

Completed outcomes:

- selected and pinned FastAPI, Pydantic, SQLAlchemy, Alembic, psycopg, PyJWT, and the Kubernetes Python client
- implemented the `backend/app` FastAPI API with health, readiness, image catalog, desktop lifecycle, audit, and metrics endpoints
- implemented JWT validation against Keycloak-issued RS256 tokens with issuer, audience, expiration, and role-claim checks
- implemented server-side RBAC, ownership enforcement, quotas, resource profiles, idempotent launches, consistent error responses, and request IDs
- implemented PostgreSQL persistence for desktops, provisioning operations, and audit events
- implemented Alembic database migration `0001_phase7_initial`
- implemented an asynchronous provisioner that reconciles VDIForge desktop records into CDI DataVolumes, KubeVirt VirtualMachines, and per-desktop Services through the Kubernetes Python client
- updated the Helm chart to deploy the API, provisioner, app PostgreSQL, migration job, API ingress, runtime Secret references, and NetworkPolicies through `values-phase7-local.yaml`
- promoted only `ubuntu-devops:1.0.0` to launchable catalog state with a CDI source PVC reference
- validated unauthorized image access, idempotency, quota enforcement, ownership checks, admin audit access, KubeVirt placement on `vdi-worker-02`, KVM requests, stop/start/delete lifecycle, cleanup, and audit persistence
- confirmed Phase 7 does not deploy Guacamole, React, Prometheus/Grafana, HPA, or browser remote desktop sessions

Phase 7 validation required the API/provisioner deployment to preserve Phase 3-6 health while proving a backend-requested `ubuntu-devops:1.0.0` desktop reaches KubeVirt `READY` on `vdi-worker-02` with KVM and cleans up after deletion.

## Phase 8 - Guacamole Remote Desktop

Completed outcomes:

- selected Apache Guacamole `1.6.0` and `guacd` `1.6.0`
- selected RDP through `xrdp` as the MVP remote desktop protocol
- documented VNC as a fallback rather than an equivalent commercial VDI protocol
- deployed Guacamole and `guacd` through the VDIForge Helm chart using `values-phase8-local.yaml`
- exposed Guacamole at `https://remote.vdiforge.local` with generated local TLS
- added `POST /api/v1/desktops/{id}/connect`
- implemented short-lived encrypted Guacamole JSON-auth session brokering
- created per-desktop generated remote credentials through Kubernetes Secrets consumed by KubeVirt cloud-init
- promoted `ubuntu-devops:1.1.0` as the Phase 8 remote-enabled launchable DevOps image version
- validated internal RDP reachability from the `guacd` network position
- validated cross-user and guessed-ID connection denial
- validated stop, restart, reconnect, delete, and Secret cleanup behavior
- recorded connection request and denial audit events without exposing passwords
- confirmed Phase 8 does not implement React, Prometheus/Grafana, HPA, Guacamole user self-service connection management, or final CI/CD

## Phase 9 - React Self-Service Portal

Completed outcomes:

- implemented the React/TypeScript portal under `frontend`
- selected React `19.2.8`, TypeScript `6.0.3`, Vite `8.2.2`, and `oidc-client-ts` `3.5.0`
- deployed the static frontend image `localhost/vdiforge-frontend:0.9.0` through the existing VDIForge Helm chart
- exposed the portal at `https://vdiforge.local` through Traefik and generated local TLS
- used the existing Keycloak public client `vdiforge-frontend` with Authorization Code Flow and PKCE
- added runtime configuration through a Helm-managed ConfigMap instead of baking local URLs into the frontend image
- added API CORS support for `https://vdiforge.local`
- rendered API-authorized image catalog data and desktop lifecycle state in the portal
- implemented desktop launch with idempotency, lifecycle polling, connect, stop, start, and delete workflows
- opened the exact API-returned Guacamole handoff URL without exposing reusable remote desktop credentials
- promoted `ubuntu-devops:1.2.0` as the current launchable DevOps image with the permanent XFCE/xrdp session fix
- automated the XFCE/xrdp fix in both the image role and per-desktop cloud-init path
- added frontend unit/component/API-client tests and Phase 9 static/live validation scripts
- confirmed Phase 9 does not implement HPA, Prometheus/Grafana, final CI/CD, or additional production hardening

## Phase 10 - Kubernetes HPA / Autoscaling

Completed outcomes:

- upgraded the VDIForge chart and backend package to `0.10.0`
- implemented a Helm-managed `autoscaling/v2` HPA for `vdiforge-api`
- selected local-lab API autoscaling defaults of `minReplicas: 1`, `maxReplicas: 3`, and CPU target `50%`
- kept API CPU/memory requests and limits in place so HPA metrics can resolve through Metrics Server
- added a protected `GET /api/v1/health/load-test` endpoint that is disabled by default and enabled only through Phase 10 local values
- added `scripts/load-test-api.py` for safe authenticated GET load without desktop creation
- validated authenticated image and desktop reads while multiple API replicas are Ready
- validated automatic scale-up and scale-down behavior through `scripts/validate-phase10-live.sh`
- documented that HPA changes API pods only and does not create Kubernetes worker nodes or VDI desktops
- deferred provisioner HPA because the current reconciler does not yet include leader election, database row claiming, or another safe multi-worker coordination mechanism
- confirmed Phase 10 does not deploy Prometheus/Grafana, node autoscaling, final CI/CD, or Phase 12 hardening

## Phase 11 - Prometheus / Grafana Observability

Completed outcomes:

- deployed `prometheus-community/kube-prometheus-stack` `88.6.1` into the existing `monitoring` namespace
- retained Metrics Server as the Kubernetes HPA resource-metrics provider
- added `prometheus-client` instrumentation to the FastAPI API and provisioner
- exposed API request count, API latency, desktop state, provisioning request/failure/duration, remote-session, reconciler, and pending-operation metrics
- added VDIForge ServiceMonitors, PrometheusRule alerts, and Grafana dashboard ConfigMap resources to the Helm chart
- integrated KubeVirt metrics through the supported Prometheus Operator monitoring fields on the KubeVirt CR
- created `VDIForge Overview` dashboard-as-code under `monitoring/grafana`
- exposed Grafana at `https://grafana.vdiforge.local` with generated local TLS and generated local admin credentials
- validated a temporary alert, safe Phase 10 load visibility, and controlled desktop lifecycle metrics
- confirmed Phase 11 does not implement SIEM forwarding, log aggregation, Grafana Keycloak OIDC, final CI/CD, or additional security hardening

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
- whether future image builds should move from `vdi-worker-02` to a dedicated Linux/KVM build host
- remote desktop clipboard/file-transfer policy
- detailed Guacamole connect/disconnect telemetry beyond API-side connection request audit events
- exact security and dependency scanning tools
- stronger browser token-session hardening beyond the Phase 9 sessionStorage and PKCE baseline
- whether the future API needs a separate confidential admin/service client
- whether the local API image import workflow should move to a registry before CI/CD
- provisioner horizontal scaling design: leader election, row claiming, or queue-backed reconciliation

## Roadmap Rules

- Do not add complex infrastructure to satisfy keywords.
- Every phase must update documentation when reality differs from design.
- Every major architectural change requires an ADR.
- Demonstrability and reliability take priority over unnecessary complexity.
