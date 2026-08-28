# VDIForge Helm Chart

This chart establishes the Helm-managed VDIForge platform foundation. Phase 4 rendered only shared foundation resources. Phase 5 enables the Keycloak identity foundation through `values-phase5-local.yaml`. Phase 6 adds the separate Packer/Ansible golden-image pipeline outside Helm because it produces VM disk artifacts. Phase 7 enables the FastAPI API, asynchronous provisioner, application PostgreSQL, migrations, API ingress, and API-specific NetworkPolicies through `values-phase7-local.yaml`. Guacamole, React, Prometheus, Grafana, and browser remote desktop sessions remain unimplemented.

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

Cluster add-ons from Phase 3 remain outside this chart:

- Calico
- Metrics Server
- KubeVirt
- CDI
- local-path provisioner
- namespace bootstrap manifests

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

Phase 7 deploys only the backend control plane and a disposable-capable KubeVirt provisioning path. Guacamole connection brokering remains Phase 8.

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

For live validation:

```bash
bash scripts/validate-phase4-live.sh
bash scripts/validate-phase5-live.sh
bash scripts/validate-phase7-live.sh
```

## Values

`values.yaml` contains environment-neutral defaults. `values-local.yaml` contains local-lab overrides for the current VirtualBox/kubeadm cluster.

The values file includes disabled future sections for:

- frontend
- API
- provisioner
- ingress
- autoscaling
- Guacamole
- monitoring

These values are extension points unless enabled by a phase-specific values file. Phase 7 enables the API/provisioner values; frontend, Guacamole, monitoring, and HPA remain future work.

`keycloak.enabled` remains `false` in `values.yaml`. Phase 5 enables it only through `values-phase5-local.yaml`.
`api.enabled`, `provisioner.enabled`, `applicationDatabase.enabled`, and `migrations.enabled` remain `false` in `values.yaml`. Phase 7 enables them only through `values-phase7-local.yaml`.

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
