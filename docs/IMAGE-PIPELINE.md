# Ubuntu Golden Image Pipeline

VDIForge builds desktop images with Packer and Ansible. Phase 6 establishes the source-controlled image pipeline, image catalog foundation, artifact validation, CDI import path, and KubeVirt boot proof for `ubuntu-devops:1.0.0`.

## Image Catalog

Initial images:

| Image | Purpose | Example version |
| --- | --- | --- |
| `ubuntu-base` | Minimal XFCE Ubuntu desktop suitable for future remote access. | `ubuntu-base:1.0.0` |
| `ubuntu-developer` | Developer desktop with Git, Python, build tools, CLI utilities, and Geany. | `ubuntu-developer:1.0.0` |
| `ubuntu-devops` | Infrastructure desktop with Terraform, Ansible, kubectl, Helm, Git, and Python. | `ubuntu-devops:1.0.0` |

The machine-readable catalog is [../images/catalog.json](../images/catalog.json).

## Lifecycle

```text
Trusted Ubuntu Source
        |
        v
 Packer QEMU Builder
        |
        v
      Ansible
        |
        v
   Configuration
        |
        v
    Validation
        |
        v
 Security Checks
        |
        v
 Versioned QCOW2
        |
        v
   CDI Import
        |
        v
 KubeVirt Boot Test
        |
        v
     Promotion
```

## Source Verification

The Packer templates:

- use the official Ubuntu 26.04 LTS amd64 cloud image
- pin the source URL
- verify the published SHA-256 checksum
- fail closed if the source image cannot be verified
- record source metadata in the generated image manifest

Source:

```text
https://cloud-images.ubuntu.com/releases/resolute/release/ubuntu-26.04-server-cloudimg-amd64.img
```

Checksum:

```text
8196be9d7958059cb56c6c75c80fdf6cee8a8885bc149ea791d7db1c7ef93035
```

The pipeline must not build from an unverified ad hoc ISO or disk file.

## Packer Responsibility

Packer owns image build orchestration:

- source image definition
- builder selection
- disk format output
- bootstrapping Ansible
- invoking validation scripts
- producing image metadata
- writing a versioned manifest

Packer uses the QEMU builder with KVM and emits QCOW2 artifacts under `artifacts/images/`. It should not contain large shell scripts when an Ansible role can express the configuration more clearly.

## Ansible Responsibility

Ansible owns operating-system configuration inside images:

- package installation
- user/session defaults
- remote desktop service installation
- graphical desktop configuration
- common security baseline
- developer or DevOps tool installation
- cleanup of temporary build artifacts
- validation commands

Image roles:

```text
image-common
image-desktop
image-developer
image-devops
image-cleanup
```

## Image Contents

### ubuntu-base

Contents:

- XFCE graphical desktop environment
- `xrdp` and `xorgxrdp` prerequisites for future Guacamole integration
- terminal and lightweight graphical utilities
- guest agent where useful for KubeVirt readiness
- minimal common CLI utilities
- security baseline

### ubuntu-developer

Includes `ubuntu-base` plus:

- Git
- Python
- build tools
- useful CLI utilities
- Geany graphical editor

### ubuntu-devops

Includes `ubuntu-base` plus:

- Terraform
- Ansible
- kubectl
- Helm
- Git
- Python
- useful infrastructure CLI utilities

The final demo uses this image to prove that infrastructure tools execute on the remote VM, not on the thin client.

Pinned binary tools:

| Tool | Version |
| --- | --- |
| Terraform | `1.16.0` |
| kubectl | `v1.36.4` |
| Helm | `v4.2.4` |

## Validation

Every promoted image must pass:

- boots successfully under the target KubeVirt runtime
- remote desktop prerequisites are installed
- expected tools are installed
- no known default passwords remain
- package cache and build-time secrets are removed
- guest user and session behavior match the MVP design
- image metadata includes name, version, source, build time, and commit reference

Phase 13 adds CI-safe Packer validation through GitHub Actions. The pipeline runs `packer init`, `packer fmt -check`, and `packer validate` for the three image templates, but it does not build full QCOW2 artifacts on ordinary pull requests. Full image builds remain local/manual because they require KVM, large disk artifacts, and the VDIForge image build environment.

Example validation commands for `ubuntu-devops`:

```bash
hostname
terraform version
helm version
kubectl version --client
python3 --version
git --version
```

## Versioning

Use semantic image versions:

```text
ubuntu-base:1.0.0
ubuntu-developer:1.0.0
ubuntu-devops:1.0.0
```

Version metadata should include:

- image name
- version
- source Ubuntu release
- package manifest
- Packer template commit
- Ansible role commit
- build timestamp
- validation result

Generated manifests and QCOW2 files are local build outputs under `artifacts/images/` and are ignored by Git.

## Patching

Patch by rebuilding images:

1. Update package sources or image definitions.
2. Run Packer and Ansible.
3. Validate the image.
4. Scan for vulnerabilities where practical.
5. Promote the new version.
6. Offer the new version for new desktop launches.

Do not manually mutate every deployed desktop as the primary patching strategy.

## Promotion and Rollback

Promotion changes the image catalog so authorized users can launch a specific image version.

Rollback changes the promoted version for new launches. Rollback does not automatically modify already-running VMs. Running desktops should be handled by policy: allow until expiration, notify users, force replacement for critical security cases, or delete according to documented administrative policy.

## Deprecation

Images can be marked:

- `candidate`
- `promoted`
- `deprecated`
- `blocked`

Deprecated images may remain available for existing desktops but should not be offered for new launches unless an admin explicitly overrides policy. Blocked images must not be used for new launches.

## CDI Import and KubeVirt Test

Phase 6 imports `ubuntu-devops:1.0.0` through CDI using a temporary host-only HTTP source and SHA-256 validation. The imported DataVolume backs a disposable KubeVirt VM scheduled by `vdiforge.io/node-role=vdi`. The test validates KVM use by checking the virt-launcher pod's `devices.kubevirt.io/kvm` request.

The final result required for Phase 6 PASS is:

```text
KUBEVIRT_KVM_VERIFIED
```

## Open Questions

- Should the MVP support persistent home directories or treat desktops as disposable?
- Whether future image builds should move from `vdi-worker-02` to a dedicated Linux/KVM build host.

Closed in Phase 14: the final portfolio demo continues to use local CDI-imported source PVCs because the live lab already validates that path and full QCOW2 artifacts are too large and environment-specific for ordinary CI. GHCR publishing remains useful for container images, not for this local golden-image handoff.
