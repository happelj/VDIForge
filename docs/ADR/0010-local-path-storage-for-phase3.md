# ADR 0010: Local-Path Storage for Phase 3 KubeVirt Validation

## Status

Accepted

## Context

Phase 3 needs a functional StorageClass for a disposable KubeVirt test VM and CDI DataVolume import. The local lab runs three Ubuntu Server VMs on one Windows 10 Pro host through VirtualBox. The lab is not physically highly available and should not introduce distributed storage complexity before the VDIForge control plane exists.

The storage solution must be free, reproducible, understandable, compatible with KubeVirt/CDI validation, and appropriate for a local portfolio lab. Earlier phases explicitly avoided Ceph and other complex infrastructure unless justified by a real requirement.

## Decision

Use Rancher local-path provisioner v0.0.32 for Phase 3 with StorageClass `vdiforge-local-path`.

The StorageClass uses:

- provisioner `rancher.io/local-path`
- `WaitForFirstConsumer` binding mode
- `Delete` reclaim policy
- local backing path `/opt/local-path-provisioner`

CDI is installed for the KubeVirt image import foundation. The disposable Phase 3 CirrOS test VM uses a CDI DataVolumeTemplate backed by `vdiforge-local-path` and schedules onto `vdi-worker-02`.

## Alternatives Considered

- Static hostPath PVs: simple, but more manual and less representative of dynamic provisioning workflows needed by the later platform.
- Kubernetes local persistent volumes without a dynamic provisioner: explicit and understandable, but operationally heavier for repeated test VM lifecycle validation.
- Ceph/Rook: more production-like for distributed storage, but excessive for this single-host lab and contrary to the project principle of reliable demonstrability over impressive complexity.
- NFS: feasible, but adds a separate storage service and failure mode without improving Phase 3's KubeVirt/KVM validation.
- Cloud block storage CSI: inappropriate for the no-cost local MVP.

## Consequences

Positive:

- Provides a simple dynamic StorageClass for CDI and KubeVirt validation.
- Keeps the lab free and reproducible.
- Avoids adding distributed storage before the project needs it.
- `WaitForFirstConsumer` better matches local PV placement with scheduled workloads.

Negative:

- Volumes are tied to a node and are not physically highly available.
- Live migration and cross-node recovery expectations are limited.
- Storage capacity is limited by the VirtualBox disk backing the selected node.
- Production deployment will need a separate storage decision.

Future phases may replace this with a different CSI/storage architecture if persistent user profiles, live migration, snapshots, backup/restore, or multi-node resilience become explicit requirements.
