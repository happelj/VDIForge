# ubuntu-base

`ubuntu-base` is the common VDIForge Ubuntu desktop foundation.

It starts from the pinned Ubuntu 26.04 LTS amd64 cloud image, uses the Packer QEMU builder with KVM, and applies the Ansible roles:

```text
image-common
image-desktop
image-cleanup
```

The image installs a lightweight XFCE desktop, `xrdp`/`xorgxrdp` prerequisites for future Guacamole integration, OpenSSH, cloud-init, and `qemu-guest-agent`.

Generated QCOW2 files are written under `artifacts/images/ubuntu-base/1.0.0/` and are not committed.
