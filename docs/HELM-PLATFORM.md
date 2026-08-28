# Helm Platform Foundation

This document records the Helm foundation for VDIForge. Phase 4 established repeatable deployment mechanics, resource ownership, platform guardrails, and extension points. Phase 5 extends the same chart with the Keycloak identity foundation. Phase 6 adds the separate Packer/Ansible image pipeline. Phase 7 enables the FastAPI API, asynchronous provisioner, application PostgreSQL, migration job, API ingress, and API-specific NetworkPolicies through `values-phase7-local.yaml`. Guacamole, React, Prometheus/Grafana, and browser remote desktop sessions remain future work.

## Status

Helm runs from the administrative environment, currently `vdi-control-01`.

| Item | Value |
| --- | --- |
| Helm client | `v4.2.4` |
| Helm Kubernetes client | `v1.36` |
| Kubernetes cluster | `v1.36.4` |
| Chart | `helm/vdiforge` |
| Chart version | `0.7.0` |
| Release | `vdiforge` |
| Release namespace | `vdiforge-system` |
| Foundation values | `helm/vdiforge/values-local.yaml` |
| Identity values | `helm/vdiforge/values-phase5-local.yaml` |
| API/provisioner values | `helm/vdiforge/values-phase7-local.yaml` |
| Final live validation state | Deployed; revision advances when validation is rerun |

Helm v4.2.x is pinned for the Kubernetes 1.36.4 local lab.

References:

- [Helm v4 version support policy](https://blog.helm.sh/docs/topics/version_skew/)
- [Helm install documentation](https://docs.helm.sh/helm/)
- [Helm commands](https://helm.sh/docs/helm/)

## Chart Architecture

```text
helm/vdiforge
  |
  +-- Chart.yaml
  +-- values.yaml
  +-- values-local.yaml
  +-- values-phase5-local.yaml
  +-- values-phase7-local.yaml
  +-- files/keycloak/vdiforge-realm.json
  +-- templates/
      |
      +-- _helpers.tpl
      +-- configmap.yaml
      +-- namespaces.yaml
      +-- serviceaccounts.yaml
      +-- rbac.yaml
      +-- resourcequota.yaml
      +-- limitrange.yaml
      +-- networkpolicies.yaml
      +-- keycloak.yaml
      +-- keycloak-postgres.yaml
      +-- keycloak-networkpolicies.yaml
      +-- app-postgres.yaml
      +-- api.yaml
      +-- provisioner.yaml
      +-- migrations.yaml
      +-- NOTES.txt
```

Chart-managed resources:

| Resource | Namespace | Purpose |
| --- | --- | --- |
| ConfigMap `vdiforge-platform-config` | `vdiforge-system` | Non-sensitive platform conventions and validation marker. |
| ServiceAccount `vdiforge-api` | `vdiforge-system` | API identity with token automount disabled. |
| ServiceAccount `vdiforge-provisioner` | `vdiforge-system` | Provisioner identity with token automount enabled. |
| ServiceAccount `vdiforge-app-postgres` | `vdiforge-system` | Application database identity with token automount disabled. |
| Role and RoleBinding `vdiforge-provisioner-vdi-manager` | `vdiforge-desktops` | Narrow KubeVirt/CDI/PVC/Service/Event permissions. |
| ResourceQuota `vdiforge-system-quota` | `vdiforge-system` | Lab-safe cap for future platform services. |
| ResourceQuota `vdiforge-desktops-quota` | `vdiforge-desktops` | Lab-safe cap for future VM resources and storage. |
| LimitRange `vdiforge-system-defaults` | `vdiforge-system` | Default requests/limits for future small platform containers. |
| NetworkPolicies `vdiforge-system-*` | `vdiforge-system` | Platform default deny, DNS egress, and future Kubernetes API egress. |
| Deployment `vdiforge-keycloak` | `keycloak` | Phase 5 identity provider, enabled only by Phase 5 values. |
| StatefulSet `vdiforge-keycloak-postgres` | `keycloak` | Persistent local Keycloak database, enabled only by Phase 5 values. |
| Ingress `vdiforge-keycloak` | `keycloak` | HTTPS ingress for `auth.vdiforge.local`, enabled only by Phase 5 values. |
| NetworkPolicies `keycloak-*` | `keycloak` | Identity namespace isolation and required allow paths. |
| Deployment/Service/Ingress `vdiforge-api` | `vdiforge-system` | Phase 7 FastAPI control-plane API, enabled only by Phase 7 values. |
| Deployment `vdiforge-provisioner` | `vdiforge-system` | Phase 7 asynchronous KubeVirt reconciler, enabled only by Phase 7 values. |
| StatefulSet/Service `vdiforge-app-postgres` | `vdiforge-system` | Phase 7 application database, enabled only by Phase 7 values. |
| Job `vdiforge-api-migrations` | `vdiforge-system` | Phase 7 Alembic migration job, enabled only by Phase 7 values. |

With `values-local.yaml` alone, the chart still renders no application workloads. With `values-phase5-local.yaml`, the chart deploys Keycloak and PostgreSQL only. With `values-phase7-local.yaml`, the chart deploys the backend API/provisioner stack. It does not deploy Guacamole, React, Prometheus, Grafana, HPA objects, image builds, or browser remote desktop sessions. Phase 6 image builds remain outside Helm because they produce VM disk artifacts rather than Kubernetes application releases.

## Helm Toolchain

Helm is a client-side deployment tool. It is installed only in the administrative environment, not on every Kubernetes node.

Install or refresh the pinned user-local client:

```bash
HELM_VERSION=v4.2.4 bash scripts/install-helm-client.sh
```

The installer downloads from `https://get.helm.sh`, verifies the published SHA256 sum, and installs `helm` to:

```text
~/.local/bin/helm
```

## Namespace Ownership

Phase 3 created foundational namespaces:

| Namespace | Owner | Current behavior |
| --- | --- | --- |
| `vdiforge-system` | Phase 3 raw namespace manifest | Helm release namespace and platform resources. |
| `vdiforge-desktops` | Phase 3 raw namespace manifest | Helm manages VDI quotas and provisioner Role/RoleBinding. |
| `keycloak` | Phase 3 raw namespace manifest | Helm manages Phase 5 identity resources inside the namespace. |
| `guacamole` | Phase 3 raw namespace manifest | Reserved for Phase 8. |
| `monitoring` | Phase 3 raw namespace manifest | Reserved for Phase 11. |

The chart defaults to:

```yaml
namespaces:
  create: false
```

This avoids competing ownership of namespace objects. Helm owns resources inside the namespaces, not the namespace objects themselves.

## RBAC Foundation

The frontend receives no Kubernetes API privileges. The Phase 7 API ServiceAccount disables token mounting:

```yaml
serviceAccounts:
  api:
    automountServiceAccountToken: false
```

The future provisioner uses a namespace-scoped Role in `vdiforge-desktops`. It does not receive `cluster-admin`, a ClusterRoleBinding, or broad Secret access.

Keycloak and PostgreSQL ServiceAccounts set `automountServiceAccountToken: false` because they do not need to call the Kubernetes API.

## Resource Governance

The local lab has limited resources:

| Node | CPU | RAM |
| --- | ---: | ---: |
| `vdi-control-01` | 4 vCPU | 6 GiB |
| `vdi-worker-01` | 2 vCPU | 6 GiB |
| `vdi-worker-02` | 4 vCPU | 8 GiB |

Helm-managed quotas:

| Namespace | Important caps |
| --- | --- |
| `vdiforge-system` | 20 pods, 1500m requested CPU, 3 GiB requested memory, 3 CPU limit, 5 GiB memory limit. |
| `vdiforge-desktops` | 20 pods, 10 PVCs, 80 GiB requested storage, 4 VMs, 4 VMIs, 8 DataVolumes. |
| `keycloak` | 8 pods, 2 PVCs, 10 GiB requested storage, 1200m requested CPU, 3 GiB requested memory. |

Keycloak requests 250m CPU and 768 MiB memory. Each PostgreSQL instance requests 100m CPU and 256 MiB memory. The Phase 7 API and provisioner each request 100m CPU and 256 MiB memory.

## NetworkPolicy Foundation

Platform namespace model:

```text
vdiforge-system default deny
    |
    +-- DNS egress to CoreDNS
    +-- Traefik -> FastAPI ingress
    +-- FastAPI -> Keycloak JWKS
    +-- FastAPI/provisioner/migration -> app PostgreSQL
    +-- provisioner egress to Kubernetes API
```

Identity namespace model:

```text
keycloak default deny
    |
    +-- DNS egress to CoreDNS
    +-- Traefik -> Keycloak
    +-- Keycloak -> PostgreSQL
    +-- API -> Keycloak discovery/JWKS
```

The chart does not yet impose the full VDI desktop namespace policy because Guacamole connection routing and final desktop port policies are Phase 8 concerns. Phase 7 validates that an unauthorized namespace cannot reach the API ClusterIP or application PostgreSQL.

## Configuration and Secrets

Non-sensitive configuration belongs in Helm values and ConfigMaps. Sensitive values are provided as Kubernetes Secrets generated outside Git.

Do not place these values in `values.yaml`, `values-local.yaml`, `values-phase5-local.yaml`, or `values-phase7-local.yaml`:

- passwords
- OIDC client secrets
- TLS private keys
- database credentials
- Guacamole credentials
- kubeconfigs
- tokens

Runtime Phase 5 secrets are generated by:

```bash
bash scripts/phase5-create-local-secrets.sh
```

Generated files live under ignored `.local/phase5/` paths.

Runtime Phase 7 app/database/API TLS secrets are generated by:

```bash
bash scripts/phase7-create-local-secrets.sh
```

Generated files live under ignored `.local/phase7/` paths.

## Node Placement Conventions

Platform workloads, including the Phase 7 API/provisioner stack, target:

```yaml
vdiforge.io/node-role: platform
```

Future VDI/KubeVirt workloads target:

```yaml
vdiforge.io/node-role: vdi
```

Templates must avoid hardcoding `vdi-worker-01` or `vdi-worker-02` when role labels express the scheduling intent.

## Ingress

Phase 5 installs Traefik as a separate Helm release:

```text
Release: traefik
Namespace: ingress-traefik
Chart: traefik/traefik
Version: 41.2.0
```

The identity endpoint is:

```text
https://auth.vdiforge.local
```

Local hostnames:

```text
auth.vdiforge.local
vdiforge.local
api.vdiforge.local
grafana.vdiforge.local
```

See [Keycloak, OIDC, and RBAC Foundation](KEYCLOAK-OIDC.md) and [ADR 0013](ADR/0013-local-ingress-and-tls.md).

## Helm Lifecycle

Render and lint foundation only:

```bash
helm lint ./helm/vdiforge
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --kube-version 1.36.4
```

Render with identity enabled:

```bash
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --kube-version 1.36.4
```

Render with identity and API/provisioner enabled:

```bash
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --kube-version 1.36.4
```

Install or upgrade with identity enabled:

```bash
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait
```

Install or upgrade with identity and API/provisioner enabled:

```bash
kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait \
  --wait-for-jobs
kubectl rollout restart deployment/vdiforge-api deployment/vdiforge-provisioner -n vdiforge-system
```

The migration Job deletion is intentional for Phase 7 local upgrades because Kubernetes treats Job pod templates as immutable. The rollout restart is also intentional because the lab reuses the local image tag `localhost/vdiforge-api:0.7.0`; after a same-tag containerd import, restarting the Deployments ensures pods run the current image content.

Phase 7 provisioner NetworkPolicy egress is configured as a list of Kubernetes API endpoints. The current kubeadm lab allows `10.96.0.1:443` and `192.168.56.10:6443`, covering the in-cluster service address and direct control-plane endpoint.

Inspect:

```bash
helm list -A
helm status vdiforge --namespace vdiforge-system
helm history vdiforge --namespace vdiforge-system
```

Rollback:

```bash
helm rollback vdiforge <revision> \
  --namespace vdiforge-system \
  --force-conflicts \
  --wait
```

Uninstall should be used carefully because it removes Helm-managed VDIForge foundation and identity resources. It does not remove ignored local secrets or local-path PV data unless those objects are separately deleted.

## Drift Management

Operational rule:

```text
Git / Helm values
      |
      v
Helm release
      |
      v
Kubernetes desired resources
```

Do not casually run `kubectl edit` against Helm-managed objects. Manual changes create drift and may be overwritten during the next Helm upgrade or rollback.

Use:

```bash
helm get values vdiforge --namespace vdiforge-system
helm get manifest vdiforge --namespace vdiforge-system
helm status vdiforge --namespace vdiforge-system
kubectl describe <resource>
```

GitOps tooling remains deferred.

## Validation

Static validation:

```powershell
.\scripts\validate-phase4.ps1
.\scripts\validate-phase5.ps1
```

Live validation from `vdi-control-01`:

```bash
bash scripts/validate-phase4-live.sh
bash scripts/validate-phase5-live.sh
```

Phase 5 live validation checks:

- Traefik install and placement
- runtime-only secret generation
- Keycloak/PostgreSQL deployment
- trusted HTTPS discovery and JWKS
- Authorization Code Flow with PKCE
- JWT signature, issuer, audience, and expiration validation
- role claims and unauthorized role absence
- persistence after Keycloak pod recreation
- NetworkPolicy enforcement
- previous phase regression health

## Troubleshooting

If Helm reports ownership conflicts, confirm the command includes:

```text
--take-ownership
--force-conflicts
```

If Keycloak is not Ready:

```bash
kubectl -n keycloak get pods
kubectl -n keycloak describe pod -l app.kubernetes.io/name=vdiforge-keycloak
kubectl -n keycloak logs deployment/vdiforge-keycloak
```

If PostgreSQL is not Ready:

```bash
kubectl -n keycloak get pvc,pods
kubectl -n keycloak logs statefulset/vdiforge-keycloak-postgres
```

If `auth.vdiforge.local` fails:

```bash
kubectl -n ingress-traefik get pods,svc
kubectl -n keycloak get ingress vdiforge-keycloak
curl --cacert .local/phase5/tls/vdiforge-local-ca.crt \
  --resolve auth.vdiforge.local:443:192.168.56.11 \
  https://auth.vdiforge.local/realms/vdiforge/.well-known/openid-configuration
```

## Scope Boundary

Phase 5 deploys Keycloak, PostgreSQL, Traefik ingress, the `vdiforge` realm, OIDC clients, and demo identities.

Phase 5 does not deploy:

- FastAPI
- provisioner application code
- React
- Guacamole
- Prometheus
- Grafana
- HPA objects
- Packer image builds
- Ubuntu desktop images
- production VDI desktops
