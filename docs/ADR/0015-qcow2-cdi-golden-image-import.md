# ADR 0015: QCOW2 and CDI Import for Golden Images

## Status

Accepted for the current local lab.

## Context

VDIForge needs a reproducible path from a generated golden-image artifact into a KubeVirt disk. Phase 3 installed CDI because KubeVirt image workflows commonly use DataVolumes to import disk images into PVCs. The current StorageClass is `vdiforge-local-path`, which is sufficient for local validation but not physically highly available.

Phase 6 must avoid manually copying arbitrary VM disks into Kubernetes storage and must not expose upload services publicly.

## Decision

Use QCOW2 as the Packer artifact format and import the artifact through CDI into a DataVolume/PVC.

For the local lab, the validation script starts a temporary HTTP server bound to the host-only management address of `vdi-worker-02` and creates a CDI DataVolume with a pinned SHA-256 checksum. The server is stopped after validation, and the disposable VM/DataVolume/PVC are deleted.

The pipeline is:

```text
QCOW2 artifact
  |
  v
temporary host-only HTTP endpoint with checksum
  |
  v
CDI DataVolume
  |
  v
PVC on vdiforge-local-path
  |
  v
KubeVirt VM
```

## Alternatives Considered

- CDI upload proxy with `virtctl image-upload`: valid, but local TLS and port-forward handling add more moving parts for this phase.
- Manual PVC population on the node filesystem: rejected because it bypasses CDI and is not a clean, reproducible Kubernetes workflow.
- ContainerDisk images: useful for tiny test VMs, but not ideal for mutable Ubuntu desktop disk artifacts produced by Packer.
- Raw disk artifacts: supported by KubeVirt/CDI, but QCOW2 is smaller for local storage and is a normal QEMU/KVM image format.

## Consequences

- CDI remains the import authority for golden-image test disks.
- The HTTP import endpoint is temporary and limited to the VirtualBox host-only network.
- SHA-256 checksum validation protects against accidental or tampered artifact mismatch.
- Local-path storage can validate the workflow but does not provide production storage semantics or high availability.
