# VDIForge Helm Chart

This chart establishes the Phase 4 Helm/platform foundation for VDIForge. It intentionally does not deploy Keycloak, Guacamole, FastAPI, React, Prometheus, Grafana, Packer image builds, or VDI desktops.

## Scope

Chart-managed resources:

- VDIForge platform ConfigMap conventions
- `vdiforge-api` ServiceAccount without automatic Kubernetes API token mounting
- `vdiforge-provisioner` ServiceAccount with a narrow namespace-scoped Role
- provisioner Role and RoleBinding in the desktop namespace
- lab-safe ResourceQuotas
- a platform namespace LimitRange
- baseline NetworkPolicies for future platform isolation

Cluster add-ons from Phase 3 remain outside this chart:

- Calico
- Metrics Server
- KubeVirt
- CDI
- local-path provisioner
- namespace bootstrap manifests

## Install

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

## Validate

```bash
helm lint ./helm/vdiforge
helm template vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --kube-version 1.36.4
```

For live validation:

```bash
bash scripts/validate-phase4-live.sh
```

## Values

`values.yaml` contains environment-neutral defaults. `values-local.yaml` contains local-lab overrides for the current VirtualBox/kubeadm cluster.

The values file includes disabled future sections for:

- frontend
- API
- provisioner
- ingress
- autoscaling
- Keycloak
- Guacamole
- monitoring

These values are extension points only. Phase 4 does not create nonfunctional Deployments for services that do not exist yet.

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
