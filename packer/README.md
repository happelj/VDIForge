# Packer

This directory is reserved for Ubuntu golden image build definitions.

## Planned Images

- `ubuntu-base`
- `ubuntu-developer`
- `ubuntu-devops`

Packer will orchestrate image builds. Ansible will configure the operating system inside each image.

## Lifecycle

See [../docs/IMAGE-PIPELINE.md](../docs/IMAGE-PIPELINE.md) for the authoritative image lifecycle.

## Rules

- Pin Ubuntu sources.
- Verify source checksums or signatures where available.
- Produce versioned artifacts.
- Do not commit generated image files.
- Promote images only after validation and security checks.
