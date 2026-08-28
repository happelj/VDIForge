# Packer

This directory contains the Phase 6 Ubuntu golden-image definitions.

## Images

| Image | Template | Purpose |
| --- | --- | --- |
| `ubuntu-base` | `ubuntu-base/ubuntu-base.pkr.hcl` | Minimal XFCE Ubuntu desktop foundation. |
| `ubuntu-developer` | `ubuntu-developer/ubuntu-developer.pkr.hcl` | Base desktop plus developer tools. |
| `ubuntu-devops` | `ubuntu-devops/ubuntu-devops.pkr.hcl` | Developer image plus Terraform, Ansible, kubectl, and Helm. |

## Version Pins

| Component | Version |
| --- | --- |
| Ubuntu source | Ubuntu 26.04 LTS cloud image, amd64 |
| Packer | `1.16.0` |
| Packer QEMU plugin | `1.1.6` |
| Packer Ansible plugin | `1.1.6` |
| Artifact format | QCOW2 |

The Ubuntu source checksum is pinned in each image's `variables.pkr.hcl`.

## Build Workflow

Run builds from a Linux KVM-capable build host. For the current lab that is `vdi-worker-02`; it has verified `/dev/kvm` exposure.

```bash
sudo bash scripts/phase6-install-build-tools.sh
exec "$SHELL" -l
bash scripts/phase6-build-all.sh
```

Generated images and manifests are written under:

```text
artifacts/images/<image-id>/<version>/
```

The `artifacts/` directory is intentionally ignored by Git. Image definitions, Ansible roles, validation scripts, and the image catalog are source-controlled; generated QCOW2 artifacts are not.

## Validation

Each Packer build invokes Ansible and then runs in-guest validation. The final integration proof imports `ubuntu-devops:1.0.0` through CDI and boots it as a KubeVirt VM on the VDI worker:

```bash
bash scripts/phase6-cdi-kubevirt-test.sh
```

See [../docs/GOLDEN-IMAGES.md](../docs/GOLDEN-IMAGES.md) and [../docs/IMAGE-PIPELINE.md](../docs/IMAGE-PIPELINE.md).
