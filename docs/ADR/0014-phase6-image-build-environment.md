# ADR 0014: Phase 6 Image Build Environment

## Status

Accepted for the current local lab.

## Context

Phase 6 must build Ubuntu golden-image artifacts with Packer and Ansible and prove at least the `ubuntu-devops:1.0.0` artifact can boot under KubeVirt with KVM acceleration. The Windows 10 Pro host runs VirtualBox 7.2.16 and does not provide native Linux KVM directly to Packer. Phase 3 verified that `vdi-worker-02` exposes `/dev/kvm` to Ubuntu and that KubeVirt can consume it.

The build environment must remain free, reproducible, and compatible with QCOW2/KVM tooling. It must also avoid destabilizing the small three-node Kubernetes lab.

## Decision

Run Phase 6 Packer builds on `vdi-worker-02` for the current MVP lab.

Operational constraints:

- build images sequentially, not concurrently
- use small QEMU build profiles
- do not run image builds at the same time as KubeVirt VM validation
- monitor `kubectl top nodes` before and after builds
- keep generated artifacts under `artifacts/images/`, outside Git
- install build tools through `scripts/phase6-install-build-tools.sh`

This is accepted as a local-lab compromise because `vdi-worker-02` is the only current node with verified KVM exposure and enough spare disk/RAM to build and validate images without buying additional hardware.

## Alternatives Considered

- Windows host build: rejected because the Windows host does not provide native Linux KVM to Packer.
- `vdi-control-01`: rejected because it hosts the Kubernetes control plane and has less safe capacity for QEMU builds.
- `vdi-worker-01`: rejected because it hosts platform services such as Keycloak and does not need nested virtualization for its role.
- New dedicated Linux build VM: technically cleaner, but it adds another VM and resource pressure to the user's no-new-hardware constraint.
- Paid cloud image build host: rejected because the MVP lab must remain approximately zero-cost.

## Consequences

- Phase 6 build throughput is limited by `vdi-worker-02` capacity.
- Build tooling is installed on a Kubernetes worker, which is acceptable for the lab but not the preferred production pattern.
- Later phases should consider a dedicated Linux/KVM build host if builds become slow or disruptive.
- KubeVirt acceptance still requires `KUBEVIRT_KVM_VERIFIED`; software emulation is not treated as equivalent.
