# ubuntu-devops

`ubuntu-devops` is the infrastructure/platform desktop image used by the eventual thin-client demo.

It includes the developer desktop foundation plus pinned infrastructure tools:

- Terraform `1.16.0`
- kubectl `v1.36.4`
- Helm `v4.2.4`
- Ansible from Ubuntu 26.04 packages
- Git and Python 3

Phase 6 validates that the following commands execute inside a VM booted from the built image:

```bash
hostname
terraform version
ansible --version
kubectl version --client
helm version
python3 --version
git --version
```

Generated QCOW2 files are written under `artifacts/images/ubuntu-devops/1.0.0/` and are not committed.
