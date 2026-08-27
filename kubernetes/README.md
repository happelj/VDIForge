# Kubernetes

This directory contains Phase 3 Kubernetes foundation manifests. Phase 4 moves VDIForge platform application ownership into `helm/vdiforge`; cluster add-ons and bootstrap namespace manifests remain here.

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
- Shared namespace, storage, Metrics Server patch, and Calico custom resources live here because they are cluster foundation resources.
- The Phase 3 RBAC manifest remains as bootstrap history, but Phase 4 adopts `vdiforge-provisioner` RBAC into Helm ownership. Future changes to that RBAC boundary should be made in `helm/vdiforge`.
- Do not add Keycloak, Guacamole, FastAPI, React, Prometheus, Grafana, or VDI desktop application resources to this raw manifest tree without a later ADR.

## Phase 3 Manifests

| Path | Purpose |
| --- | --- |
| `calico/custom-resources.yaml` | Calico v3.32.1 operator custom resources for VXLAN pod networking. |
| `metrics-server/metrics-server-local-patch.yaml` | Local-lab Metrics Server kubelet address/TLS patch. |
| `namespaces/vdiforge-namespaces.yaml` | Minimal namespace foundation. |
| `rbac/vdiforge-provisioner-foundation.yaml` | Phase 3 bootstrap provisioner RBAC skeleton; adopted by Helm in Phase 4. |
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
