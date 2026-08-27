# ADR 0009: VirtualBox Local Lab on Windows

## Status

Accepted for this local Phase 2/Phase 3 host.

## Context

Phase 1 preferred Linux KVM/libvirt because it aligns directly with KubeVirt's `/dev/kvm` requirement and has a maintained Terraform provider. The actual development host is Windows 10 Pro on an AMD Ryzen 7 1700. The user cannot install Ubuntu directly on bare metal, dual boot, add another SSD, or spend more money.

Initial inspection showed Hyper-V present and VirtualBox nested virtualization unavailable. After disabling the Windows hypervisor and rebooting, VirtualBox allowed nested VT-x/AMD-V to be enabled for `vdi-worker-02`.

The critical requirement is that the future VDI worker can expose hardware virtualization to KubeVirt.

## Decision

Use Oracle VirtualBox 7.2.16 on Windows 10 Pro for the Phase 2 local lab.

Use three Ubuntu Server VMs:

```text
vdi-control-01
vdi-worker-01
vdi-worker-02
```

Use NAT for outbound Internet and a host-only adapter on `192.168.56.0/24` for host-to-node and node-to-node access.

Require nested VT-x/AMD-V only on `vdi-worker-02`. Classify KubeVirt readiness as verified only because `/dev/kvm` exists inside that guest and `svm` CPU flags appear in `/proc/cpuinfo`.

Do not use the older `terra-farm/virtualbox` Terraform provider as an authoritative VM lifecycle dependency because it is alpha and indicates a maintainer gap. Terraform records and validates the local lab specification instead.

## Alternatives Considered

- Linux KVM/libvirt on bare metal: technically preferred, but unavailable because the user cannot install Linux directly or add storage.
- Windows Hyper-V: not selected because the current Windows 10 AMD host did not provide a viable verified nested virtualization path.
- WSL2: not selected because no WSL distribution was installed and WSL2 is not the intended layer for three persistent Kubernetes node VMs.
- VirtualBox with Hyper-V active: rejected because nested VT-x/AMD-V was unavailable and `/dev/kvm` was missing inside the guest.
- VMware Player: not selected because the Phase 1 constraints avoid commercial VMware products and the Terraform story is weak for this portfolio lab.
- Terraform VirtualBox provider: rejected for authoritative lifecycle because the common provider is alpha and maintainer status is weak.

## Consequences

- Phase 2 is unblocked without new hardware or paid software.
- `vdi-worker-02` has verified `/dev/kvm` availability for future KubeVirt testing.
- The local lab remains a single physical failure domain.
- VM lifecycle is partially manual through VirtualBox GUI or `VBoxManage`, not fully Terraform-managed.
- Terraform still defines, validates, and outputs the lab specification.
- Ansible runs from `vdi-control-01` for Phase 3 because the Windows host does not provide a native Ansible control environment.
- Phase 3 must validate Kubernetes/KubeVirt compatibility on Ubuntu Server 26.04 LTS before installing cluster components and must prove KubeVirt can consume KVM on `vdi-worker-02`.
- Phase 3 validation showed the control plane needs 4 vCPU and 6144 MiB RAM on this host for reliable Kubernetes/KubeVirt add-on reconciliation.
