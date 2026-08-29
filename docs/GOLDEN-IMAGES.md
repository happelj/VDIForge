# Golden Images

This document records the Phase 6 Ubuntu golden-image pipeline for VDIForge. It covers image definitions, build environment, artifact format, validation, CDI import, and KubeVirt boot proof. Phase 8 reuses the image pipeline to produce a remote-enabled DevOps image version for Guacamole/RDP validation.

## Status

Phase 6 adds source-controlled image definitions and validation automation for:

| Image | Version | Purpose |
| --- | --- | --- |
| `ubuntu-base` | `1.0.0` | Minimal Ubuntu desktop foundation. |
| `ubuntu-developer` | `1.0.0` | Developer desktop with Git, Python, build tools, and Geany. |
| `ubuntu-devops` | `1.0.0` | Platform desktop with Terraform, Ansible, kubectl, Helm, Git, and Python. |
| `ubuntu-devops` | `1.1.0` | Phase 8 remote-enabled DevOps desktop source for Guacamole/RDP validation. |

Generated QCOW2 artifacts and runtime manifests are produced under `artifacts/images/` and are not committed to Git.

## Compatibility Matrix

| Component | Selected version | Compatibility | Evidence |
| --- | --- | --- | --- |
| Ubuntu source | Ubuntu 26.04 LTS `resolute` amd64 cloud image | PASS | Official Ubuntu cloud-image release directory publishes `ubuntu-26.04-server-cloudimg-amd64.img` and SHA256SUMS. |
| Packer | `1.16.0` | PASS | HashiCorp Packer install and release pages publish Linux amd64 binaries and checksums. |
| Packer QEMU plugin | `1.1.6` | PASS | Official HashiCorp QEMU plugin supports KVM/QEMU image builds. |
| Packer Ansible plugin | `1.1.6` | PASS | Official HashiCorp Ansible plugin provides the remote Ansible provisioner used by the image templates. |
| Ansible | Ubuntu 26.04 package, validated by `ansible --version` | PASS | Packer invokes image playbooks through the Ansible provisioner. |
| QEMU/KVM | Ubuntu `qemu-system-x86`, `qemu-utils`, `/dev/kvm` | PASS when build host access is verified | `vdi-worker-02` has verified nested virtualization and KubeVirt KVM exposure. |
| Artifact format | QCOW2 | PASS | QEMU/KVM and CDI support QCOW2 disk images. |
| CDI | `v1.66.0` | PASS | Phase 3 installed CDI for DataVolume/PVC import workflows. |
| KubeVirt | `v1.9.0` | PASS | Phase 3 validated KubeVirt and KVM on `vdi-worker-02`. |

Authoritative references:

- [Packer install documentation](https://developer.hashicorp.com/packer/install)
- [Packer QEMU plugin](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu)
- [Packer QEMU builder](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu)
- [Packer Ansible plugin](https://developer.hashicorp.com/packer/integrations/hashicorp/ansible)
- [Ubuntu 26.04 cloud-image release](https://cloud-images.ubuntu.com/releases/resolute/release/)
- [CDI DataVolumes](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md)
- [KubeVirt VM access](https://kubevirt.io/user-guide/user_workloads/accessing_virtual_machines/)

## Trusted Ubuntu Source

The templates use the official Ubuntu 26.04 LTS amd64 cloud image:

```text
https://cloud-images.ubuntu.com/releases/resolute/release/ubuntu-26.04-server-cloudimg-amd64.img
```

Pinned SHA-256 checksum:

```text
8196be9d7958059cb56c6c75c80fdf6cee8a8885bc149ea791d7db1c7ef93035
```

Packer verifies this checksum before building. The pipeline must fail if the downloaded source image does not match.

## Build Environment

Phase 6 builds run on `vdi-worker-02` for the current lab because:

- the Windows host does not provide native Linux KVM to Packer
- `vdi-worker-02` has verified `/dev/kvm`
- the VDI worker has the largest CPU/RAM/disk allocation
- no new hardware or paid cloud resources are required

This is a local-lab compromise, not a production recommendation. Builds must run sequentially and should not overlap with KubeVirt boot validation.

Install build tooling on `vdi-worker-02`:

```bash
cd ~/vdiforge-phase6-build
sudo bash scripts/phase6-install-build-tools.sh
exec "$SHELL" -l
```

Important build tools:

| Tool | Version or source |
| --- | --- |
| Packer | `1.16.0` installed under `~/.local/bin/packer` |
| QEMU | Ubuntu 26.04 `qemu-system-x86` packages |
| libguestfs | Ubuntu 26.04 `libguestfs-tools` for offline generalization |
| Ansible | Ubuntu 26.04 package |

On the current Ubuntu 26.04 build host, `/boot/vmlinuz-$(uname -r)` is root-readable by default. `scripts/phase6-install-build-tools.sh` sets that kernel image to mode `0644` so libguestfs `supermin` can build its appliance as the non-root `vdiadmin` build user. Rerun the installer after host kernel upgrades.

## Packer Layout

```text
packer/
  shared/
    cloud-init/user-data.pkrtpl
    scripts/generalize-artifact.sh
    scripts/validate-image.sh
    scripts/write-manifest.sh
  ubuntu-base/
  ubuntu-developer/
  ubuntu-devops/
```

Each image directory contains:

- `<image>.pkr.hcl`
- `variables.pkr.hcl`
- `README.md`

The templates pin:

- Packer `>= 1.16.0, < 1.17.0`
- QEMU plugin `1.1.6`
- Ansible plugin `1.1.6`
- Ubuntu source URL and checksum
- QCOW2 output format

## Ansible Layout

Image roles are separate from host/Kubernetes roles:

```text
ansible/roles/image-common
ansible/roles/image-desktop
ansible/roles/image-developer
ansible/roles/image-devops
ansible/roles/image-cleanup
```

Packer invokes:

```text
ansible/playbooks/image-ubuntu-base.yml
ansible/playbooks/image-ubuntu-developer.yml
ansible/playbooks/image-ubuntu-devops.yml
```

## Image Contents

### ubuntu-base

Includes:

- Ubuntu 26.04 LTS
- XFCE desktop
- `xrdp` and `xorgxrdp` prerequisites
- OpenSSH server
- cloud-init
- `qemu-guest-agent`
- common CLI utilities

Phase 6 did not connect this image to Guacamole. Phase 8 validates Guacamole/RDP against the DevOps image path.

### ubuntu-developer

Includes `ubuntu-base` plus:

- Git
- Python 3, pip, venv, and development headers
- build essentials
- `ripgrep`, `tree`, `shellcheck`, and common CLI utilities
- Geany graphical editor

### ubuntu-devops

Includes `ubuntu-developer` plus:

- Terraform `1.16.0`
- kubectl `v1.36.4`
- Helm `v4.2.4`
- Ansible

The final proof validates these commands inside a VM booted from the built artifact:

```bash
hostname
terraform version
ansible --version
kubectl version --client
helm version
python3 --version
git --version
```

## Build Commands

Build one image:

```bash
bash scripts/phase6-build-image.sh ubuntu-devops
```

Build all images sequentially:

```bash
bash scripts/phase6-build-all.sh
```

Output path:

```text
artifacts/images/<image>/<version>/<image>-<version>-amd64.qcow2
```

Each build also writes:

```text
<image>-<version>.manifest.json
<image>-<version>.sha256
```

## Image Generalization

The final artifact generalization step uses `virt-sysprep` to remove:

- temporary Packer user
- temporary sudoers entries
- SSH host keys
- machine ID
- shell history
- log files
- temporary files

The build process must not bake personal SSH keys, passwords, kubeconfigs, cloud credentials, access tokens, or refresh tokens into the image.

## Image Catalog

The catalog is:

```text
images/catalog.json
```

It records:

- image IDs
- display names
- default versions
- allowed Keycloak roles
- artifact format
- lifecycle state
- generated manifest path

The catalog expresses image policy only. Phase 7 consumes the catalog and enforces server-side authorization.

Phase 8 preserves the `ubuntu-devops:1.0.0` catalog record and adds `ubuntu-devops:1.1.0` as the current default launchable DevOps version for Guacamole/RDP validation. The Phase 8 source PVC is:

```text
vdiforge-golden-ubuntu-devops-1-1-0
```

The Phase 8 build wrapper sets `VDIFORGE_IMAGE_DISK_SIZE=15G` by default for `ubuntu-devops:1.1.0` and imports that artifact into a `20Gi` CDI source DataVolume. The smaller virtual disk is a local-lab accommodation for the current 60 GiB VDI worker and the temporary scratch/clone storage CDI needs during validation. The earlier Phase 6 Packer templates still default to `24G`.

## CDI Import

Phase 6 uses CDI HTTP import with checksum validation:

```text
QCOW2 artifact
  |
  v
temporary host-only HTTP endpoint on vdi-worker-02
  |
  v
CDI DataVolume
  |
  v
PVC using vdiforge-local-path
```

The HTTP endpoint is bound to `192.168.56.12` and stopped after validation. It is not exposed publicly.

CDI may allocate a scratch PVC when importing qcow2 images for conversion. The Phase 8 import path configures CDI `scratchSpaceStorageClass` to `vdiforge-local-path` before preparing the remote-enabled `ubuntu-devops:1.1.0` source PVC.

## KubeVirt Boot Proof

Run from `vdi-control-01` after the image builds exist on `vdi-worker-02`:

```bash
bash scripts/phase6-cdi-kubevirt-test.sh
```

The test:

1. imports `ubuntu-devops:1.0.0` through CDI
2. creates a disposable KubeVirt VM
3. schedules it using `vdiforge.io/node-role=vdi`
4. verifies it lands on `vdi-worker-02`
5. verifies the launcher pod requests `devices.kubevirt.io/kvm`
6. waits for guest SSH
7. runs DevOps tool checks inside the guest
8. stops and restarts the VM
9. deletes the VM, DataVolume, and PVC

Required hardware result for Phase 6 PASS:

```text
KUBEVIRT_KVM_VERIFIED
```

## Promotion And Rollback

Image lifecycle states:

```text
candidate -> available -> deprecated
candidate -> blocked
available -> blocked
```

Failed builds remain `candidate` or become `blocked`; they must not be promoted to `available`.

Rollback affects new launches by changing the catalog default or lifecycle state. Rollback does not modify already-running VMs.

## Patching

Patch by rebuilding:

```text
Ubuntu/security update
  |
  v
Packer rebuild
  |
  v
new image version
  |
  v
validation
  |
  v
catalog promotion
```

Routine patching should not rely on manually SSHing into every desktop.

## Resource Use

Default Phase 6 profiles:

| Workload | vCPU | RAM | Disk |
| --- | ---: | ---: | ---: |
| Packer build VM | 2 | 3072 MiB | 24-28 GiB |
| KubeVirt boot test VM | 2 | 2 GiB | 32 GiB PVC |

Monitor the lab:

```bash
kubectl top nodes
kubectl top pods -A
```

Do not build images concurrently on `vdi-worker-02`.

## Validation

Static validation:

```powershell
pwsh -NoProfile -File ./scripts/validate-phase6.ps1
```

Live validation from `vdi-control-01`:

```bash
bash scripts/validate-phase6-live.sh
```

The live validator checks:

- cluster health
- KubeVirt/CDI/storage health
- image catalog policy
- Packer fmt/validate
- Ansible syntax/lint
- all three image builds
- artifact checksums
- CDI import
- KubeVirt/KVM boot proof
- DevOps tool validation inside the guest
- cleanup

## Limitations

- Building on `vdi-worker-02` competes with the VDI worker's cluster duties.
- `vdiforge-local-path` is not high availability storage.
- The catalog starts as a policy foundation; the API consumes it for server-side authorization.
- Phase 8 implements Guacamole integration for the DevOps image path; base and developer images remain candidates.
- Generated artifacts are local; rebuilding from source is the portable recovery path.
