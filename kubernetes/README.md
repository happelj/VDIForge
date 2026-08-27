# Kubernetes

This directory contains Phase 3 Kubernetes foundation manifests that are not owned by the later VDIForge Helm chart.

## Contents

```text
kubernetes/
  calico/
  metrics-server/
  namespaces/
  kubevirt/
  rbac/
  storage/
```

## Boundary

- Core application resources belong in `helm/vdiforge`.
- Phase 3 KubeVirt installation uses pinned upstream manifests through Ansible, not copied generated manifests.
- `kubernetes/kubevirt/phase3-test-vm.yaml` is a disposable validation VM only.
- Shared namespace, RBAC, storage, Metrics Server patch, and Calico custom resources live here because they are platform foundation resources.
- Do not add Keycloak, Guacamole, FastAPI, React, Prometheus, Grafana, or VDI desktop resources in Phase 3.

## Phase 3 Manifests

| Path | Purpose |
| --- | --- |
| `calico/custom-resources.yaml` | Calico v3.32.1 operator custom resources for VXLAN pod networking. |
| `metrics-server/metrics-server-local-patch.yaml` | Local-lab Metrics Server kubelet address/TLS patch. |
| `namespaces/vdiforge-namespaces.yaml` | Minimal namespace foundation. |
| `rbac/vdiforge-provisioner-foundation.yaml` | Future provisioner ServiceAccount and namespace-scoped Role skeleton. |
| `storage/local-path-provisioner.yaml` | Rancher local-path provisioner v0.0.32 and StorageClass `vdiforge-local-path`. |
| `kubevirt/phase3-test-vm.yaml` | Disposable CirrOS KubeVirt VM using CDI DataVolumeTemplate. |

## Validation

Run live validation from `vdi-control-01` after the cluster is bootstrapped:

```bash
cd ~/vdiforge-phase3-validation
bash scripts/validate-phase3-live.sh
```

## Rules

- Pin versions.
- Prefer declarative YAML.
- Validate manifests before applying.
- Do not grant broad Kubernetes permissions for convenience.
- Remove disposable validation resources after tests.
