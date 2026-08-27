# ADR 0005: Terraform Infrastructure Boundary

## Status

Accepted for MVP architecture.

## Context

VDIForge should demonstrate infrastructure-as-code while keeping responsibilities clear. Terraform is appropriate for infrastructure lifecycle, but it is not appropriate as a per-user desktop launch mechanism inside the application request path.

The local lab may use KVM/libvirt. The `dmacvicar/libvirt` Terraform provider has a maintained 0.9.x release line and documentation for managing libvirt resources.

## Decision

Use Terraform for infrastructure lifecycle where practical:

- local KVM/libvirt VM and network definitions
- reusable modules
- future cloud infrastructure
- environment-level infrastructure configuration

Do not invoke Terraform for each end-user desktop launch. The application launches desktops by creating Kubernetes/KubeVirt resources.

Use the maintained `dmacvicar/libvirt` provider as the preferred local Terraform provider candidate. If it proves impractical on the user's host, document a fallback and preserve Terraform for future cloud or libvirt-capable environments.

Phase 2 update: the actual developer host uses VirtualBox on Windows 10 Pro. VDIForge intentionally does not depend on an alpha or weakly maintained VirtualBox provider. Terraform records and validates the local lab specification with built-in resources; VirtualBox GUI or `VBoxManage` owns VM lifecycle on this host. See [ADR 0009](0009-virtualbox-local-lab-on-windows.md).

## Alternatives Considered

- Terraform for every desktop launch: rejected because it couples user actions to infrastructure state operations and is poorly suited for high-frequency VM lifecycle.
- Abandoned local hypervisor provider: rejected because maintainability matters more than keyword coverage.
- Manual-only infrastructure: acceptable fallback for local VM creation, but less reproducible than Terraform where the provider works.
- Future cloud provider modules only: useful later, but does not help the local lab.

## Consequences

- Terraform usage remains meaningful and properly scoped.
- Terraform state must not be committed.
- Desktop lifecycle belongs to VDIForge plus Kubernetes/KubeVirt.
- Phase 2 validated that local KVM/libvirt Terraform is not practical on the actual host without changing the user's hardware or operating-system layout.
