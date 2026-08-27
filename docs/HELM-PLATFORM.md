# Helm Platform Foundation

This document records the Phase 4 Helm foundation for VDIForge. Phase 4 establishes repeatable deployment mechanics, resource ownership, platform guardrails, and extension points for later application phases. It does not deploy Keycloak, Guacamole, FastAPI, React, Prometheus/Grafana, image pipelines, or VDI desktops.

## Status

Phase 4 uses Helm as a deployment client from the administrative environment, currently `vdi-control-01`.

| Item | Value |
| --- | --- |
| Helm client | `v4.2.4` |
| Helm Kubernetes client | `v1.36` |
| Kubernetes cluster | `v1.36.4` |
| Chart | `helm/vdiforge` |
| Chart version | `0.4.0` |
| Release | `vdiforge` |
| Release namespace | `vdiforge-system` |
| Values file | `helm/vdiforge/values-local.yaml` |
| Final live validation state | Deployed; revision advances when lifecycle validation is rerun |

Helm v4 is the current stable Helm major release. Helm v4.2.x supports Kubernetes 1.36.x through 1.33.x, so v4.2.4 is compatible with the Phase 3 Kubernetes 1.36.4 cluster.

References:

- [Helm v4 version support policy](https://blog.helm.sh/docs/topics/version_skew/)
- [Helm install documentation](https://docs.helm.sh/helm/)
- [Helm commands](https://helm.sh/docs/helm/)

## Chart Architecture

The VDIForge chart is intentionally a foundation chart in Phase 4.

```text
helm/vdiforge
  |
  +-- Chart.yaml
  +-- values.yaml
  +-- values-local.yaml
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
      +-- NOTES.txt
```

Chart-managed resources:

| Resource | Namespace | Purpose |
| --- | --- | --- |
| ConfigMap `vdiforge-platform-config` | `vdiforge-system` | Non-sensitive platform conventions and validation marker. |
| ServiceAccount `vdiforge-api` | `vdiforge-system` | Future API identity with token automount disabled. |
| ServiceAccount `vdiforge-provisioner` | `vdiforge-system` | Future provisioner identity with token automount enabled. |
| Role `vdiforge-provisioner-vdi-manager` | `vdiforge-desktops` | Narrow KubeVirt/CDI/PVC/Service/Event permissions. |
| RoleBinding `vdiforge-provisioner-vdi-manager` | `vdiforge-desktops` | Binds provisioner ServiceAccount to the VDI Role. |
| ResourceQuota `vdiforge-system-quota` | `vdiforge-system` | Lab-safe cap for future platform services. |
| ResourceQuota `vdiforge-desktops-quota` | `vdiforge-desktops` | Lab-safe cap for future VM resources and storage. |
| LimitRange `vdiforge-system-defaults` | `vdiforge-system` | Default requests/limits for future small platform containers. |
| NetworkPolicy `vdiforge-system-default-deny` | `vdiforge-system` | Default-deny baseline for future platform pods. |
| NetworkPolicy `vdiforge-system-allow-dns` | `vdiforge-system` | DNS egress exception for future platform pods. |
| NetworkPolicy `vdiforge-system-provisioner-kubernetes-api` | `vdiforge-system` | Future provisioner egress path to Kubernetes API. |

No `Deployment`, `StatefulSet`, `DaemonSet`, `VirtualMachine`, application `Service`, `Ingress`, HPA, Keycloak, Guacamole, Prometheus, Grafana, or desktop workload is created in Phase 4.

## Helm Toolchain

Helm runs from `vdi-control-01` because that node already has cluster-admin kubeconfig for the local lab and acts as the current administrative controller. Helm is not installed on every Kubernetes node because Helm is a client-side deployment tool, not a node service.

Install or refresh the pinned user-local client:

```bash
cd ~/vdiforge-phase4-validation
HELM_VERSION=v4.2.4 bash scripts/install-helm-client.sh
```

The installer downloads from `https://get.helm.sh`, verifies the published SHA256 sum, and installs `helm` to:

```text
~/.local/bin/helm
```

## Namespace Ownership

Phase 3 created the foundational namespaces:

| Namespace | Owner | Phase 4 behavior |
| --- | --- | --- |
| `vdiforge-system` | Phase 3 raw namespace manifest | Helm release namespace and chart-managed resources live here. |
| `vdiforge-desktops` | Phase 3 raw namespace manifest | Helm manages VDI quotas and provisioner Role/RoleBinding here. |
| `keycloak` | Phase 3 raw namespace manifest | Reserved for Phase 5. |
| `guacamole` | Phase 3 raw namespace manifest | Reserved for Phase 8. |
| `monitoring` | Phase 3 raw namespace manifest | Reserved for Phase 11. |

The chart defaults to:

```yaml
namespaces:
  create: false
```

This avoids competing namespace ownership between Phase 3 raw manifests and the Phase 4 Helm release. Optional namespace templates exist for future environments, but they are disabled in the local lab.

## RBAC Foundation

The frontend receives no Kubernetes API privileges. The future API ServiceAccount disables automatic service account token mounting:

```yaml
serviceAccounts:
  api:
    automountServiceAccountToken: false
```

The future provisioner uses a namespace-scoped Role in `vdiforge-desktops`. It can manage the resource types needed for VM reconciliation:

- KubeVirt `virtualmachines`
- KubeVirt `virtualmachineinstances`
- CDI `datavolumes`
- PVCs
- Services
- Events
- read-only Pods

It does not receive `cluster-admin`, a ClusterRoleBinding, or broad Secret access.

## Phase 3 RBAC Adoption

Phase 3 created the initial `vdiforge-provisioner` ServiceAccount, Role, and RoleBinding with raw manifests. Phase 4 adopts those existing objects into Helm ownership during the first install:

```bash
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait
```

`--take-ownership` transfers Helm metadata ownership. Helm v4 uses server-side apply, so `--force-conflicts` is also required to take field ownership from the previous `kubectl apply` manager. This is not `--force-replace`; it does not delete and recreate the RBAC objects.

After adoption, changes to these resources should flow through Helm values and chart templates.

## Resource Governance

The local lab has limited resources:

| Node | CPU | RAM |
| --- | ---: | ---: |
| `vdi-control-01` | 4 vCPU | 6 GiB |
| `vdi-worker-01` | 2 vCPU | 6 GiB |
| `vdi-worker-02` | 4 vCPU | 8 GiB |

Phase 4 adds conservative ResourceQuotas:

| Namespace | Important caps |
| --- | --- |
| `vdiforge-system` | 20 pods, 1500m requested CPU, 3 GiB requested memory, 3 CPU limit, 5 GiB memory limit. |
| `vdiforge-desktops` | 20 pods, 10 PVCs, 80 GiB requested storage, 4 VMs, 4 VMIs, 8 DataVolumes. |

Only `vdiforge-system` receives a LimitRange in Phase 4. The desktop namespace does not receive a default container LimitRange because KubeVirt VM launcher pods need resource behavior driven by VM definitions, not small platform-container defaults.

## NetworkPolicy Foundation

Phase 3 proved NetworkPolicy enforcement with disposable resources. Phase 4 adds a Helm-managed foundation for future platform pods in `vdiforge-system`:

```text
default deny
    |
    +-- allow DNS egress to CoreDNS
    |
    +-- allow future provisioner-labeled pods to reach Kubernetes API
```

The chart does not yet impose default-deny policies on the VDI desktop namespace because later Guacamole and VM access policies need more concrete labels and ports. This avoids breaking KubeVirt/CDI validation before the VDI application exists.

Future expected policies:

- frontend to API
- API to Keycloak
- API to PostgreSQL
- provisioner to Kubernetes API
- Guacamole to VDI VM remote desktop port
- Prometheus to metrics endpoints
- deny VDI desktops from platform administration services

## Configuration and Secrets

Non-sensitive platform configuration belongs in Helm values and ConfigMaps. Sensitive values must be supplied later through Kubernetes Secrets or another approved mechanism and must not be committed to Git.

Phase 4 commits no real secrets and creates no Secret manifests.

Do not place these values in `values.yaml` or `values-local.yaml`:

- passwords
- OIDC client secrets
- TLS private keys
- database credentials
- Guacamole credentials
- kubeconfigs
- tokens

## Node Placement Conventions

The chart records future placement conventions in values:

```yaml
placement:
  platform:
    nodeSelector:
      vdiforge.io/node-role: platform
  vdi:
    nodeSelector:
      vdiforge.io/node-role: vdi
```

Future platform workloads should target the platform worker label. Future VDI/KubeVirt workloads should target the VDI worker label. Templates must avoid hardcoding `vdi-worker-01` or `vdi-worker-02` when role labels express the scheduling intent.

## Ingress Decision

Phase 4 does not install an Ingress Controller because there are no HTTP applications yet. Installing one now would add moving parts without a resource that needs ingress.

Planned local hostnames remain:

```text
vdiforge.local
auth.vdiforge.local
grafana.vdiforge.local
```

Phase 5 or a later HTTP-facing phase should choose the Ingress Controller and local DNS/TLS approach when a real service exists.

## Helm Lifecycle

Render and lint:

```bash
helm lint ./helm/vdiforge
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --kube-version 1.36.4
```

Install or upgrade:

```bash
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait
```

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

Uninstall should be used carefully because it removes the Helm-managed foundation resources:

```bash
helm uninstall vdiforge --namespace vdiforge-system
```

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

GitOps tooling is intentionally deferred. Helm remains the deployment mechanism for Phase 4.

## Validation

Static validation:

```powershell
.\scripts\validate-phase4.ps1
```

Live validation from `vdi-control-01`:

```bash
cd ~/vdiforge-phase4-validation
bash scripts/validate-phase4-live.sh
```

Live validation checks:

- Helm client version
- `helm lint`
- `helm template`
- rendered label conventions
- no `cluster-admin`
- Helm server dry-run schema validation
- node readiness
- Calico health
- CoreDNS health
- Metrics Server health
- KubeVirt health
- CDI health
- install baseline
- upgrade
- repeated upgrade
- rollback
- expected resources
- KubeVirt KVM resource remains available on `vdi-worker-02`

Representative Phase 4 live result:

```text
Helm version: v4.2.4
helm lint: PASS
helm template: PASS
Helm server dry-run: PASS
install: PASS
upgrade: PASS
repeated upgrade: PASS
rollback: PASS
final Helm revision: recorded by validation output
Phase 4 live validation: PASS
```

## Troubleshooting

If Helm reports ownership conflicts during the first Phase 4 install, confirm that the command includes both:

```text
--take-ownership
--force-conflicts
```

If Helm reports a failed release:

```bash
helm status vdiforge --namespace vdiforge-system
helm history vdiforge --namespace vdiforge-system
helm get manifest vdiforge --namespace vdiforge-system
```

If ResourceQuota blocks a future phase, adjust the chart values and upgrade. Do not manually edit the live quota.

If a future pod cannot reach DNS or the Kubernetes API, inspect the Helm-managed NetworkPolicies and add explicit allow policies in the appropriate future phase.

## Scope Boundary

Phase 4 does not deploy:

- Keycloak
- OIDC clients or demo identities
- PostgreSQL
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
