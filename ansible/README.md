# Ansible

This directory is reserved for operating-system and host configuration.

## Planned Roles

```text
common
security-baseline
containerd
kubernetes-common
kubernetes-control-plane
kubernetes-worker
```

Additional image-specific roles will be added under the image pipeline work when needed.

## Responsibilities

- common Ubuntu host baseline
- SSH and package configuration
- containerd installation/configuration
- kubeadm prerequisites
- control-plane bootstrap tasks
- worker join tasks
- validation commands
- image configuration roles used by Packer

Ansible playbooks should be idempotent and safe to rerun.

## Structure

```text
ansible/
  inventory/
  roles/
  playbooks/
```
