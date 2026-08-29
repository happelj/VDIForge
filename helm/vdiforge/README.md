# VDIForge Helm Chart

This chart establishes the Helm-managed VDIForge platform foundation. Phase 4 rendered only shared foundation resources. Phase 5 enables the Keycloak identity foundation through `values-phase5-local.yaml`. Phase 6 adds the separate Packer/Ansible golden-image pipeline outside Helm because it produces VM disk artifacts. Phase 7 enables the FastAPI API, asynchronous provisioner, application PostgreSQL, migrations, API ingress, and API-specific NetworkPolicies through `values-phase7-local.yaml`. Phase 8 enables Apache Guacamole, `guacd`, remote desktop ingress/TLS, API remote-session RBAC, and Guacamole NetworkPolicies through `values-phase8-local.yaml`. Phase 9 enables the React portal through `values-phase9-local.yaml`. Phase 10 enables API HPA autoscaling through `values-phase10-local.yaml`. Phase 11 enables VDIForge-specific Prometheus/Grafana observability resources through `values-phase11-local.yaml`. Node autoscaling and final production hardening remain unimplemented.

## Scope

Chart-managed resources:

- VDIForge platform ConfigMap conventions
- `vdiforge-api` ServiceAccount without automatic Kubernetes API token mounting
- `vdiforge-provisioner` ServiceAccount with a narrow namespace-scoped Role
- provisioner Role and RoleBinding in the desktop namespace
- lab-safe ResourceQuotas
- a platform namespace LimitRange
- baseline NetworkPolicies for future platform isolation
- optional Phase 5 Keycloak, PostgreSQL, identity ingress, identity ResourceQuota, and identity NetworkPolicies
- optional Phase 7 FastAPI API, provisioner, app PostgreSQL, migration Job, API ingress, and API NetworkPolicies
- optional Phase 8 Guacamole, `guacd`, remote desktop ingress, API remote-session RBAC, Guacamole ResourceQuota/LimitRange, and Guacamole NetworkPolicies
- optional Phase 9 React frontend Deployment, Service, Ingress, runtime ConfigMap, ServiceAccount, and frontend NetworkPolicy
- optional Phase 10 API HorizontalPodAutoscaler and protected local load-test endpoint settings
- optional Phase 11 API/provisioner ServiceMonitors, PrometheusRule alerts, Grafana dashboard ConfigMap, and monitoring scrape NetworkPolicy

Cluster add-ons from Phase 3 remain outside this chart:

- Calico
- Metrics Server
- KubeVirt
- CDI
- local-path provisioner
- namespace bootstrap manifests
- kube-prometheus-stack core monitoring components

Phase 11 installs Prometheus, Grafana, Alertmanager, and kube-state-metrics through the separate upstream `prometheus-community/kube-prometheus-stack` release `vdiforge-monitoring` in `monitoring`. The local baseline disables node-exporter so the monitoring namespace can keep baseline Pod Security enforcement.

## Install Foundation Only

Run Helm from the administrative environment, currently `vdi-control-01`.

```bash
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait
```

`--take-ownership` and `--force-conflicts` are required for the first Phase 4 install on the current lab because Phase 3 created the initial `vdiforge-provisioner` ServiceAccount, Role, and RoleBinding as raw Kubernetes manifests. Helm v4 uses server-side apply, so `--force-conflicts` transfers field ownership without deleting or replacing those objects. After Phase 4 adoption, Helm owns those objects.

## Install Phase 5 Identity Foundation

Create runtime-only secrets before enabling Keycloak:

```bash
bash scripts/phase5-create-local-secrets.sh
```

Install or upgrade with the local Phase 5 values file:

```bash
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait
```

Phase 5 deploys Keycloak and PostgreSQL into the existing `keycloak` namespace. Traefik is installed as a separate shared ingress release in `ingress-traefik`.

## Install Phase 7 API Foundation

Create runtime-only secrets and the source golden-image PVC before enabling the API/provisioner:

```bash
bash scripts/phase7-create-local-secrets.sh
bash scripts/phase7-prepare-golden-source.sh
bash scripts/phase7-build-load-image.sh
```

`phase7-build-load-image.sh` uses Podman or Buildah on `vdi-worker-01` when available. If neither exists, it falls back to temporary BuildKit/importer validation pods so the lab does not require a permanent container builder installation.

Install or upgrade with the Phase 5 and Phase 7 values files:

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

Phase 7 deploys only the backend control plane and a disposable-capable KubeVirt provisioning path.

## Install Phase 8 Remote Desktop

Create runtime-only Guacamole JSON-auth and TLS secrets:

```bash
bash scripts/phase8-create-local-secrets.sh
```

Prepare the remote-enabled DevOps source PVC and load the API image:

```bash
bash scripts/phase8-prepare-remote-source.sh
PHASE7_IMAGE=localhost/vdiforge-api:0.8.0 \
  PHASE7_IMAGE_TAR=/tmp/vdiforge-api-0.8.0.tar \
  bash scripts/phase7-build-load-image.sh
```

Install or upgrade with Phase 5, Phase 7, and Phase 8 values:

```bash
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
```

Phase 8 exposes Guacamole at:

```text
https://remote.vdiforge.local
```

The Windows hosts-file helper includes this hostname:

```powershell
.\scripts\phase5-windows-hosts-and-trust.ps1
```

## Install Phase 9 React Portal

Create runtime-only portal TLS material, build/load the frontend image, and prepare the current remote-enabled DevOps source PVC:

```bash
bash scripts/phase9-create-local-secrets.sh
bash scripts/phase9-build-load-frontend-image.sh
PHASE7_IMAGE=localhost/vdiforge-api:0.9.0 \
  PHASE7_IMAGE_TAR=/tmp/vdiforge-api-0.9.0.tar \
  bash scripts/phase7-build-load-image.sh
VDIFORGE_IMAGE_VERSION=1.2.0 bash scripts/phase8-build-remote-image.sh
VDIFORGE_IMAGE_VERSION=1.2.0 bash scripts/phase8-prepare-remote-source.sh
```

Install or upgrade with Phase 5, Phase 7, Phase 8, and Phase 9 values:

```bash
kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --values ./helm/vdiforge/values-phase9-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait \
  --wait-for-jobs
```

Phase 9 exposes the portal at:

```text
https://vdiforge.local
```

## Install Phase 10 API Autoscaling

Load the Phase 10 API image and install or upgrade with all prior phase values plus the autoscaling values:

```bash
PHASE7_IMAGE=localhost/vdiforge-api:0.10.0 \
  PHASE7_IMAGE_TAR=/tmp/vdiforge-api-0.10.0.tar \
  bash scripts/phase7-build-load-image.sh
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

Phase 10 creates an `autoscaling/v2` HPA for `vdiforge-api` only. Provisioner HPA is intentionally disabled until reconciliation has safe multi-worker coordination.

## Install Phase 11 Observability

Install the upstream monitoring stack and upgrade the VDIForge chart with Phase 11 resources:

```bash
bash scripts/phase11-install-monitoring.sh
```

That helper creates local Grafana credentials and TLS Secrets, installs `prometheus-community/kube-prometheus-stack` `88.6.1` into `monitoring`, patches KubeVirt monitoring integration, builds/loads `localhost/vdiforge-api:0.11.0`, and upgrades the `vdiforge` release with all Phase 1-11 values.

Manual equivalent for the VDIForge chart portion:

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
  --values ./helm/vdiforge/values-phase11-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait \
  --wait-for-jobs
```

Grafana is exposed at:

```text
https://grafana.vdiforge.local
```

Read the generated local admin password only from ignored runtime state:

```bash
cat .local/phase11/phase11.env
```

## Validate

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

Render with remote desktop enabled:

```bash
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --kube-version 1.36.4
```

Render with the React portal enabled:

```bash
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --values ./helm/vdiforge/values-phase5-local.yaml \
  --values ./helm/vdiforge/values-phase7-local.yaml \
  --values ./helm/vdiforge/values-phase8-local.yaml \
  --values ./helm/vdiforge/values-phase9-local.yaml \
  --kube-version 1.36.4
```

Render with API autoscaling enabled:

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

For live validation:

```bash
bash scripts/validate-phase4-live.sh
bash scripts/validate-phase5-live.sh
bash scripts/validate-phase7-live.sh
bash scripts/validate-phase8-live.sh
bash scripts/validate-phase9-live.sh
bash scripts/validate-phase10-live.sh
bash scripts/validate-phase11-live.sh
```

## Values

`values.yaml` contains environment-neutral defaults. `values-local.yaml` contains local-lab overrides for the current VirtualBox/kubeadm cluster.

The values file includes disabled future sections for:

- frontend
- API
- provisioner
- ingress
- Guacamole
- monitoring

These values are extension points unless enabled by a phase-specific values file. Phase 7 enables the API/provisioner values, Phase 8 enables Guacamole values, Phase 9 enables frontend values, Phase 10 enables API autoscaling values, and Phase 11 enables VDIForge-specific observability resources.

`keycloak.enabled` remains `false` in `values.yaml`. Phase 5 enables it only through `values-phase5-local.yaml`.
`api.enabled`, `provisioner.enabled`, `applicationDatabase.enabled`, and `migrations.enabled` remain `false` in `values.yaml`. Phase 7 enables them only through `values-phase7-local.yaml`.
`guacamole.enabled` remains `false` in `values.yaml`. Phase 8 enables it only through `values-phase8-local.yaml`.
`frontend.enabled` remains `false` in `values.yaml`. Phase 9 enables it only through `values-phase9-local.yaml`.
`api.autoscaling.enabled` and `api.loadTest.enabled` remain `false` in `values.yaml`. Phase 10 enables them only through `values-phase10-local.yaml`.
`monitoring.enabled`, `monitoring.serviceMonitor.enabled`, `monitoring.prometheusRule.enabled`, and `monitoring.grafanaDashboard.enabled` remain `false` in `values.yaml`. Phase 11 enables them only through `values-phase11-local.yaml`.

## Ownership

After Phase 4, VDIForge platform resources should be changed through Git and Helm values, not casual `kubectl edit` changes. Manual edits create drift from the Helm release.

Expected flow:

```text
Git / Helm values
      |
      v
Helm release
      |
      v
Kubernetes resources
```

Use `helm diff` in a future phase if drift comparison needs to become more formal.
