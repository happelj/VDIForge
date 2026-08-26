# ADR 0007: Packer and Ansible for Image Pipeline

## Status

Accepted for MVP architecture.

## Context

VDIForge needs repeatable Ubuntu desktop images with different toolsets. Manual image modification would be hard to reproduce, test, patch, or roll back. The project should demonstrate automated OS image management and immutable/versioned image practices.

## Decision

Use Packer to build image artifacts and Ansible to configure the operating system inside the images.

Initial images:

- `ubuntu-base`
- `ubuntu-developer`
- `ubuntu-devops`

Patching is handled by rebuilding versioned images and promoting new versions.

## Alternatives Considered

- Manual VM customization: rejected because it is not reproducible.
- Cloud-init only: useful for first boot, but insufficient as the full golden image build pipeline.
- Ansible against long-running desktops only: useful for host configuration, but weaker than immutable image rebuilds for patching and rollback.
- Container images: rejected because the VDI desktop target is a VM image.

## Consequences

- Image build definitions become source-controlled artifacts.
- The image pipeline needs validation and security checks.
- Rollback changes new launch selection and does not silently mutate running desktops.
- Phase 6 must choose exact image format and import path for KubeVirt.
