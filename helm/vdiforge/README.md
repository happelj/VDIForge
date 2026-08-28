# VDIForge Helm Chart

This chart establishes the Helm-managed VDIForge platform foundation. Phase 4 rendered only shared foundation resources. Phase 5 enables the Keycloak identity foundation through `values-phase5-local.yaml`. Phase 6 adds the separate Packer/Ansible golden-image pipeline outside Helm because it produces VM disk artifacts. Guacamole, FastAPI, React, Prometheus, Grafana, and self-service VDI desktops remain unimplemented.

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

For live validation:

```bash
bash scripts/validate-phase4-live.sh
bash scripts/validate-phase5-live.sh
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

These values are extension points only. Phase 4 does not create nonfunctional Deployments for services that do not exist yet.

`keycloak.enabled` remains `false` in `values.yaml`. Phase 5 enables it only through `values-phase5-local.yaml`.

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
