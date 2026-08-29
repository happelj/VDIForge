# Helm Platform Foundation

This document records the Helm foundation for VDIForge. Phase 4 established repeatable deployment mechanics, resource ownership, platform guardrails, and extension points. Phase 5 extends the same chart with the Keycloak identity foundation. Phase 6 adds the separate Packer/Ansible image pipeline. Phase 7 enables the FastAPI API, asynchronous provisioner, application PostgreSQL, migration job, API ingress, and API-specific NetworkPolicies through `values-phase7-local.yaml`. Phase 8 enables Apache Guacamole, `guacd`, remote desktop TLS, Guacamole NetworkPolicies, and API remote-session RBAC through `values-phase8-local.yaml`. Phase 9 enables the React portal through `values-phase9-local.yaml`. Phase 10 enables API HPA autoscaling through `values-phase10-local.yaml`. Phase 11 enables Prometheus/Grafana observability through `values-phase11-local.yaml` plus a separate upstream `kube-prometheus-stack` release.

## Status

Helm runs from the administrative environment, currently `vdi-control-01`.

| Item | Value |
| --- | --- |
| Helm client | `v4.2.4` |
| Helm Kubernetes client | `v1.36` |
| Kubernetes cluster | `v1.36.4` |
| Chart | `helm/vdiforge` |
| Chart version | `0.11.0` |
| Release | `vdiforge` |
| Release namespace | `vdiforge-system` |
| Foundation values | `helm/vdiforge/values-local.yaml` |
| Identity values | `helm/vdiforge/values-phase5-local.yaml` |
| API/provisioner values | `helm/vdiforge/values-phase7-local.yaml` |
| Remote desktop values | `helm/vdiforge/values-phase8-local.yaml` |
| Portal values | `helm/vdiforge/values-phase9-local.yaml` |
| Autoscaling values | `helm/vdiforge/values-phase10-local.yaml` |
| Observability values | `helm/vdiforge/values-phase11-local.yaml` |
| Monitoring stack values | `monitoring/kube-prometheus-stack-values-local.yaml` |
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
  +-- values-phase8-local.yaml
  +-- values-phase9-local.yaml
  +-- values-phase10-local.yaml
  +-- values-phase11-local.yaml
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
      +-- guacamole.yaml
      +-- guacamole-networkpolicies.yaml
      +-- frontend.yaml
      +-- hpa.yaml
      +-- servicemonitors.yaml
      +-- prometheusrules.yaml
      +-- grafana-dashboard.yaml
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
| Deployment/Service `vdiforge-guacamole` | `guacamole` | Phase 8 Guacamole web application, enabled only by Phase 8 values. |
| Deployment/Service `vdiforge-guacd` | `guacamole` | Phase 8 Guacamole protocol proxy, enabled only by Phase 8 values. |
| Ingress `vdiforge-guacamole` | `guacamole` | HTTPS ingress for `remote.vdiforge.local`, enabled only by Phase 8 values. |
| NetworkPolicies `guacamole-*` | `guacamole` | Phase 8 Guacamole isolation and RDP allow paths. |
| Deployment/Service/Ingress `vdiforge-frontend` | `vdiforge-system` | Phase 9 React portal, enabled only by Phase 9 values. |
| ConfigMap `vdiforge-frontend-runtime-config` | `vdiforge-system` | Public frontend runtime configuration generated by Helm. |
| NetworkPolicy `vdiforge-system-allow-frontend-ingress` | `vdiforge-system` | Traefik-to-frontend ingress path. |
| HorizontalPodAutoscaler `vdiforge-api` | `vdiforge-system` | Phase 10 API pod autoscaling, enabled only by Phase 10 values. |
| ServiceMonitor `vdiforge-api` | `monitoring` | Phase 11 API metrics scraping, enabled only by Phase 11 values. |
| ServiceMonitor `vdiforge-provisioner` | `monitoring` | Phase 11 provisioner metrics scraping, enabled only by Phase 11 values. |
| PrometheusRule `vdiforge-alerts` | `monitoring` | Phase 11 VDIForge alert rules. |
| ConfigMap `vdiforge-overview-dashboard` | `monitoring` | Phase 11 Grafana dashboard-as-code. |

With `values-local.yaml` alone, the chart still renders no application workloads. With `values-phase5-local.yaml`, the chart deploys Keycloak and PostgreSQL. With `values-phase7-local.yaml`, the chart deploys the backend API/provisioner stack. With `values-phase8-local.yaml`, the chart deploys Guacamole remote desktop delivery. With `values-phase9-local.yaml`, the chart deploys the React portal. With `values-phase10-local.yaml`, the chart enables `vdiforge-api` HPA and the local-only authenticated API load-test endpoint. With `values-phase11-local.yaml`, the chart creates VDIForge-specific ServiceMonitors, PrometheusRule alerts, Grafana dashboard ConfigMap, and monitoring scrape NetworkPolicy allowances. It does not deploy image builds, SIEM forwarding, log aggregation, final CI/CD, node autoscaling, or future production hardening. Phase 6 image builds remain outside Helm because they produce VM disk artifacts rather than Kubernetes application releases.

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
| `guacamole` | Phase 3 raw namespace manifest | Helm manages Phase 8 Guacamole resources inside the namespace. |
| `monitoring` | Phase 3 raw namespace manifest | Phase 11 monitoring stack and VDIForge observability resources. |

The chart defaults to:

```yaml
namespaces:
  create: false
```

This avoids competing ownership of namespace objects. Helm owns resources inside the namespaces, not the namespace objects themselves.

## RBAC Foundation

The frontend receives no Kubernetes API privileges. Phase 9 creates `vdiforge-frontend` with token mounting disabled:

```yaml
serviceAccounts:
  frontend:
    automountServiceAccountToken: false
```

The Phase 7 API ServiceAccount disables token mounting by default:

```yaml
serviceAccounts:
  api:
    automountServiceAccountToken: false
```

Phase 8 enables token mounting for the API ServiceAccount so the API can read per-desktop remote credential Secrets and Services after owner/admin authorization succeeds. The read Role is namespace-scoped to `vdiforge-desktops`.

The provisioner uses a namespace-scoped Role in `vdiforge-desktops`. It does not receive `cluster-admin` or a ClusterRoleBinding. Phase 8 adds Secret create/get/update/delete verbs so the provisioner can manage per-desktop remote credential Secrets.

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
| `vdiforge-desktops` | Base values: 20 pods, 10 PVCs, 80 GiB requested storage, 4 VMs, 4 VMIs, 8 DataVolumes. Phase 8 local values raise this to 16 PVCs and 180 GiB declared storage quota for source, scratch, and clone validation objects. |
| `keycloak` | 8 pods, 2 PVCs, 10 GiB requested storage, 1200m requested CPU, 3 GiB requested memory. |
| `guacamole` | 8 pods, 6 Services, 12 Secrets, 800m requested CPU, 1536 MiB requested memory. |
| `monitoring` | Managed by kube-prometheus-stack values. Prometheus, Alertmanager, and Grafana use local-path PVCs and platform-node placement. |

Keycloak requests 250m CPU and 768 MiB memory. Each PostgreSQL instance requests 100m CPU and 256 MiB memory. The API and provisioner each request 100m CPU and 256 MiB memory. Guacamole requests 200m CPU and 512 MiB memory; `guacd` requests 100m CPU and 128 MiB memory.

The local Keycloak deployment uses a configurable Deployment strategy and sets a no-surge rolling update in `values-phase5-local.yaml` with `maxSurge: 0` and `maxUnavailable: 1`. The three-node VirtualBox lab has limited platform-worker capacity, and a default rolling update can require a second Keycloak pod temporarily. That surge can leave a replacement pod Pending during observability and application chart upgrades even though the existing Keycloak pod remains healthy. Production-like environments can choose a higher-availability identity topology with sufficient capacity.

Phase 10 keeps the API CPU request at `100m` and sets `maxReplicas: 3` for the local lab. This gives the HPA a measurable CPU target while avoiding an excessive replica ceiling on the 2 vCPU platform worker. If additional API pods become Pending, treat that as a capacity signal rather than evidence that HPA can add worker nodes.

Phase 11 monitoring values keep Prometheus retention to 3 days / 3 GiB and use small local PVCs: 5 GiB for Prometheus, 1 GiB for Alertmanager, and 2 GiB for Grafana. The monitoring stack targets the platform worker through `vdiforge.io/node-role=platform` where supported by the upstream chart values.

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
    +-- Prometheus -> API/provisioner metrics
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

Remote access namespace model:

```text
guacamole default deny
    |
    +-- DNS egress to CoreDNS
    +-- Traefik -> Guacamole web
    +-- Guacamole web -> guacd
    +-- guacd -> VDI desktop pods on TCP 3389
```

Phase 7 validates that an unauthorized namespace cannot reach the API ClusterIP or application PostgreSQL. Phase 8 validates that the intended Guacamole paths work while unauthorized or unlabeled pods cannot use the remote-access path.

## Configuration and Secrets

Non-sensitive configuration belongs in Helm values and ConfigMaps. Sensitive values are provided as Kubernetes Secrets generated outside Git.

Do not place these values in `values.yaml`, `values-local.yaml`, `values-phase5-local.yaml`, or `values-phase7-local.yaml`:

- passwords
- OIDC client secrets
- TLS private keys
- database credentials
- Guacamole credentials
- Guacamole JSON authentication secret
- per-desktop remote access passwords
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

Runtime Phase 8 Guacamole JSON and remote TLS secrets are generated by:

```bash
bash scripts/phase8-create-local-secrets.sh
```

Generated files live under ignored `.local/phase8/` paths and Kubernetes Secrets in `vdiforge-system` and `guacamole`.

## Node Placement Conventions

Platform workloads, including the API, provisioner, Guacamole, and `guacd`, target:

```yaml
vdiforge.io/node-role: platform
```

Future VDI/KubeVirt workloads target:

```yaml
vdiforge.io/node-role: vdi
```

Templates must avoid hardcoding `vdi-worker-01` or `vdi-worker-02` when role labels express the scheduling intent.

The Phase 10 HPA scales only the API Deployment. API pods inherit the platform placement selector from the Deployment template:

```yaml
vdiforge.io/node-role: platform
```

VDI/KubeVirt desktops continue to target the VDI role label through the provisioner and are not created by the autoscaling load test.

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
remote.vdiforge.local
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

Render with identity, API/provisioner, and remote desktop enabled:

```bash
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --kube-version 1.36.4
```

Render with identity, API/provisioner, remote desktop, portal, and API autoscaling enabled:

```bash
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --values ./helm/vdiforge/values-phase9-local.yaml \
  --values ./helm/vdiforge/values-phase10-local.yaml \
  --kube-version 1.36.4
```

Render with Phase 11 observability resources enabled:

```bash
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --values ./helm/vdiforge/values-phase9-local.yaml \
  --values ./helm/vdiforge/values-phase10-local.yaml \
  --values ./helm/vdiforge/values-phase11-local.yaml \
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

Install or upgrade with remote desktop enabled:

```bash
bash scripts/phase8-create-local-secrets.sh
kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait \
  --wait-for-jobs
kubectl rollout restart deployment/vdiforge-api deployment/vdiforge-provisioner -n vdiforge-system
kubectl rollout restart deployment/vdiforge-guacd -n guacamole
kubectl rollout status deployment/vdiforge-guacd -n guacamole --timeout=600s
kubectl rollout restart deployment/vdiforge-guacamole -n guacamole
kubectl rollout status deployment/vdiforge-guacamole -n guacamole --timeout=600s
```

The migration Job deletion is intentional for Phase 7 and later local upgrades because Kubernetes treats Job pod templates as immutable. The rollout restart is also intentional because the lab reuses local image tags; after a same-tag containerd import, restarting the Deployments ensures pods run the current image content.

Phase 7 provisioner NetworkPolicy egress is configured as a list of Kubernetes API endpoints. The current kubeadm lab allows `10.96.0.1:443` and `192.168.56.10:6443`, covering the in-cluster service address and direct control-plane endpoint.

Phase 8 adds matching API Kubernetes API egress for authorized remote Secret and Service reads.
`values-phase8-local.yaml` and `values-phase9-local.yaml` increase the desktop namespace storage/PVC quota for the local lab because remote-desktop validation can hold historical source images, CDI scratch space, and one cloned desktop volume concurrently.

Install or upgrade with API autoscaling enabled:

```bash
kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --values ./helm/vdiforge/values-phase9-local.yaml \
  --values ./helm/vdiforge/values-phase10-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait \
  --wait-for-jobs
```

When autoscaling is enabled, Helm omits fixed `spec.replicas` from the API Deployment and the HPA owns replica count. Operators should change replica policy through Helm values, not `kubectl scale`, unless they are performing a temporary incident response action that is documented and later reconciled back into Helm.

Install or upgrade the Phase 11 monitoring stack:

```bash
bash scripts/phase11-install-monitoring.sh
```

This command installs the separate `vdiforge-monitoring` kube-prometheus-stack release and then upgrades the VDIForge release with Phase 11 values:

```bash
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --values ./helm/vdiforge/values-phase9-local.yaml \
  --values ./helm/vdiforge/values-phase10-local.yaml \
  --values ./helm/vdiforge/values-phase11-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait \
  --wait-for-jobs
```

Grafana local admin credentials and TLS material are created by `scripts/phase11-create-local-secrets.sh` under ignored `.local/phase11` paths and applied as Kubernetes Secrets in `monitoring`.

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
.\scripts\validate-phase8.ps1
.\scripts\validate-phase9.ps1
.\scripts\validate-phase10.ps1
.\scripts\validate-phase11.ps1
```

Live validation from `vdi-control-01`:

```bash
bash scripts/validate-phase4-live.sh
bash scripts/validate-phase5-live.sh
bash scripts/validate-phase8-live.sh
bash scripts/validate-phase11-live.sh
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

Phase 8 live validation checks Guacamole/`guacd` rollout, trusted remote HTTPS, NetworkPolicy allow/deny behavior, internal RDP reachability, Guacamole JSON-auth token exchange, connection authorization, cleanup, and connection audit events.

Phase 9 live validation checks frontend image loading, portal TLS, frontend rollout, runtime configuration, CORS from `https://vdiforge.local`, OIDC/PKCE token flow, role-specific image visibility, portal-equivalent launch/connect/delete workflow, Guacamole URL handoff, audit events, and KubeVirt/KVM regression health.

Phase 10 live validation checks Metrics Server, Helm render/server dry-run, API image loading, API HPA creation, real CPU metric resolution, automatic scale-up under safe authenticated GET load, new API endpoints becoming Ready, authenticated API consistency under multiple replicas, portal reachability, automatic scale-down, unchanged desktop count, and Phase 1-9 cluster health regression.

Phase 11 live validation checks kube-prometheus-stack install/upgrade, VDIForge ServiceMonitors, PrometheusRule alerts, Grafana dashboard discovery, Prometheus scrape targets, KubeVirt metric discovery, safe Phase 10 load observability, controlled desktop lifecycle metrics, temporary alert firing/cleanup, and Phase 1-10 regression health.

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

If `remote.vdiforge.local` fails:

```bash
kubectl -n guacamole get pods,svc,ingress
kubectl -n guacamole logs deploy/vdiforge-guacamole
kubectl -n guacamole logs deploy/vdiforge-guacd
curl --cacert .local/phase5/tls/vdiforge-local-ca.crt \
  --resolve remote.vdiforge.local:443:192.168.56.11 \
  https://remote.vdiforge.local/
```

If API autoscaling does not occur:

```bash
kubectl describe hpa vdiforge-api -n vdiforge-system
kubectl get hpa vdiforge-api -n vdiforge-system
kubectl top pods -n vdiforge-system -l app.kubernetes.io/component=api
kubectl describe deployment vdiforge-api -n vdiforge-system
kubectl get events -n vdiforge-system --sort-by=.lastTimestamp
```

If HPA metrics show `<unknown>`, verify Metrics Server and API resource requests before changing thresholds. If new API pods are Pending, inspect `vdiforge-system` ResourceQuota and platform-worker capacity.

If Grafana is unavailable:

```bash
kubectl -n monitoring get pods,svc,ingress,pvc
kubectl -n monitoring logs deploy/vdiforge-monitoring-grafana
cat .local/phase11/phase11.env
curl --cacert .local/phase5/tls/vdiforge-local-ca.crt \
  --resolve grafana.vdiforge.local:443:192.168.56.11 \
  https://grafana.vdiforge.local/api/health
```

If Prometheus is not scraping VDIForge:

```bash
kubectl -n monitoring get servicemonitor vdiforge-api vdiforge-provisioner
kubectl -n monitoring get prometheusrule vdiforge-alerts
kubectl -n vdiforge-system get svc vdiforge-api vdiforge-provisioner-metrics --show-labels
kubectl -n monitoring port-forward svc/vdiforge-monitoring-prometheus 19090:9090
curl -fsS http://127.0.0.1:19090/api/v1/targets
```

## Scope Boundary

Phase 8 deploys Guacamole, `guacd`, remote desktop TLS, API remote-session RBAC, and Guacamole NetworkPolicies. Phase 9 deploys the React portal and frontend ingress/NetworkPolicy resources. Phase 10 deploys the API HPA and enables a protected local load-test endpoint only when Phase 10 values are applied. Phase 11 deploys Prometheus/Grafana observability resources and keeps Alertmanager local-only. Phase 12 adds security-header middleware, API rate-limit values, Keycloak hardening values, Grafana security settings, and validation scripts.

Phase 12 does not deploy:

- provisioner HPA
- node autoscaling
- SIEM forwarding
- log aggregation
- Grafana Keycloak OIDC
- final CI/CD
- production VDI desktop image promotion beyond the lab DevOps image

## Phase 12 Helm Security Notes

- `helm/vdiforge/templates/securityheaders.yaml` creates Traefik `Middleware` resources for VDIForge browser-facing services.
- Ingress annotations reference middleware by namespace-qualified name; Services do not carry Ingress-only middleware annotations.
- `values-phase12-local.yaml` enables security headers and API rate limiting without duplicating the chart.
- VDIForge-owned RBAC remains least privilege and does not create `ClusterRoleBinding` or `cluster-admin`.
- Generated TLS keys, passwords, and local env files remain outside Helm values and outside Git.
