# ADR 0002: KubeVirt for VM Workloads

## Status

Accepted for MVP architecture with nested virtualization risk tracked.

## Context

VDIForge desktops must be real Ubuntu desktop VMs. Ordinary containers should not be represented as traditional VDI VMs. KubeVirt provides Kubernetes-native resources for VM lifecycle management while using QEMU/KVM underneath.

KubeVirt normally requires hardware virtualization through `/dev/kvm`. The local lab may run Kubernetes nodes as VMs, so nested virtualization must be validated.

## Decision

Use KubeVirt as the VM lifecycle layer for VDIForge desktops.

Target resources:

- `VirtualMachine`
- `VirtualMachineInstance`
- `DataVolume` where image import or cloning requires CDI
- `PersistentVolumeClaim`
- `Service`

The preferred local deployment target is a Linux KVM/libvirt host that exposes nested virtualization to Kubernetes worker-node VMs. KubeVirt software emulation may be used only as a development fallback.

Phase 2 update: the actual developer host cannot use bare-metal Linux KVM/libvirt. [ADR 0009](0009-virtualbox-local-lab-on-windows.md) accepts VirtualBox on Windows 10 Pro for this local lab because `vdi-worker-02` exposes `svm` CPU flags and `/dev/kvm` inside the Ubuntu guest.

## Alternatives Considered

- Containers with desktop packages: rejected because they are not traditional VDI VMs and would misrepresent the platform.
- Plain libvirt API from the backend: simpler for local VM creation, but bypasses Kubernetes scheduling, RBAC, and KubeVirt learning goals.
- OpenStack: provides VM management but adds substantial complexity not justified by the MVP.
- KubeVirt software emulation only: useful fallback, but too slow for a strong remote desktop performance demo.

## Consequences

- The project demonstrates VM lifecycle through Kubernetes APIs.
- Hardware virtualization is a critical Phase 2 validation item.
- If nested virtualization is unavailable, Phase 2 must choose a fallback before implementation continues.
- The design must keep KubeVirt as the target architecture unless hands-on validation shows a compelling blocker.
- Documentation must remain clear that KubeVirt provides VM integration on Kubernetes; ordinary containers are not the VDI desktop model.
