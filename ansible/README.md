# Ansible

This directory contains the Phase 2 operating-system baseline foundation and the Phase 3 Kubernetes/KubeVirt bootstrap roles.

## Roles

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
- hostname management
- `/etc/hosts` management
- apt metadata and baseline package installation
- OpenSSH server state
- time synchronization
- swap handling for future Kubernetes prerequisites
- root-login and password-authentication policy
- sudo group policy
- containerd installation and CRI configuration
- Kubernetes package repository and pinned package installation
- kubeadm control-plane initialization
- worker join with short-lived token
- node labeling
- Phase 3 add-on installation

Phase 3 installs Kubernetes, Calico, Metrics Server, KubeVirt, CDI, and storage foundations. It does not install Keycloak, Guacamole, Prometheus, Grafana, Helm application resources, backend, frontend, or VDI desktop images.

Ansible playbooks should be idempotent and safe to rerun.

## Execution

The current Windows host does not have a native Ansible control environment. Phase 2 validation used `vdi-control-01` as a temporary Ubuntu VM controller. For routine use, run from Linux, WSL, or an Ubuntu VM controller:

```bash
cd ansible
ansible-playbook --syntax-check playbooks/baseline.yml
ansible-playbook --syntax-check playbooks/phase3.yml
ansible-playbook playbooks/phase3.yml --private-key ~/.ssh/vdiforge_ansible
ansible-playbook playbooks/phase3.yml --private-key ~/.ssh/vdiforge_ansible
```

The second full Phase 3 playbook run is the idempotency check. It must not reset or recreate a healthy cluster.

If temporary passwordless sudo was enabled for lab bootstrap, remove it after validation:

```bash
ansible-playbook playbooks/remove-temporary-sudo.yml --private-key ~/.ssh/vdiforge_ansible
```

## Structure

```text
ansible/
  inventory/
    local/
      group_vars/
  roles/
    common/
    security-baseline/
    containerd/
    kubernetes-common/
    kubernetes-control-plane/
    kubernetes-worker/
  playbooks/
```
