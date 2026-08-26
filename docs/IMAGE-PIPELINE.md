# Ubuntu Golden Image Pipeline

VDIForge will build desktop images with Packer and Ansible. This document defines the planned image lifecycle for later implementation phases.

## Image Catalog

Initial images:

| Image | Purpose | Example version |
| --- | --- | --- |
| `ubuntu-base` | Minimal graphical Ubuntu desktop suitable for remote access. | `ubuntu-base:v1.0.0` |
| `ubuntu-developer` | Developer desktop with Git, Python, build tools, CLI utilities, and a graphical editor or IDE. | `ubuntu-developer:v1.0.0` |
| `ubuntu-devops` | Infrastructure desktop with Terraform, Ansible, kubectl, Helm, Git, Python, and useful infrastructure CLIs. | `ubuntu-devops:v1.0.0` |

## Lifecycle

```text
Trusted Ubuntu Source
        |
        v
      Packer
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
 Versioned Artifact
        |
        v
      Testing
        |
        v
     Promotion
```

## Source Verification

Later Packer templates must:

- use a documented Ubuntu source URL
- pin the Ubuntu release and image variant
- verify checksums or signatures where available
- fail closed if the source image cannot be verified
- record source metadata in the image manifest

The pipeline must not build from an unverified ad hoc ISO or image file.

## Packer Responsibility

Packer owns image build orchestration:

- source image definition
- builder selection
- disk format output
- bootstrapping Ansible
- invoking validation scripts
- producing image metadata
- writing a versioned manifest

Packer should not contain large shell scripts when an Ansible role can express the configuration more clearly.

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

Planned image roles:

```text
image-common
image-desktop
image-remote-access
image-developer-tools
image-devops-tools
image-validation
```

## Image Contents

### ubuntu-base

Planned contents:

- Ubuntu graphical desktop environment
- remote desktop service
- basic browser and terminal
- guest agent where useful for KubeVirt readiness
- minimal common CLI utilities
- security baseline

### ubuntu-developer

Includes `ubuntu-base` plus:

- Git
- Python
- build tools
- useful CLI utilities
- appropriate graphical editor or IDE
- optional language tooling approved in later phases

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

## Validation

Every promoted image should pass:

- boots successfully under the target KubeVirt runtime
- remote desktop service starts
- expected ports are reachable only through approved network paths
- expected tools are installed
- no known default passwords remain
- package cache and build-time secrets are removed
- guest user and session behavior match the MVP design
- image metadata includes name, version, source, build time, and commit reference

Example validation commands for `ubuntu-devops`:

```bash
hostname
terraform version
helm version
kubectl version --client
python --version
git --version
```

## Versioning

Use semantic image versions:

```text
ubuntu-base:v1.0.0
ubuntu-developer:v1.0.0
ubuntu-devops:v1.0.0
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

## Open Questions

- Which exact Ubuntu Desktop flavor provides the best balance of performance and remote desktop compatibility?
- Which image artifact format will be best for the selected KubeVirt/CDI import path?
- Should the MVP support persistent home directories or treat desktops as disposable?
- Which vulnerability scanner will be used in CI without requiring paid services?
