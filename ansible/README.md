# Ansible

This directory contains the Phase 2 operating-system baseline foundation and remains the home for later Kubernetes and image configuration roles.

## Phase 2 Roles

```text
common
security-baseline
```

Later roles:

```text
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

Phase 2 does not install containerd, kubeadm, Kubernetes, KubeVirt, Keycloak, Guacamole, Prometheus, Grafana, or application workloads.

Ansible playbooks should be idempotent and safe to rerun.

## Execution

The current Windows host does not have a native Ansible control environment. Phase 2 validation used `vdi-control-01` as a temporary Ubuntu VM controller. For routine use, run from Linux, WSL, or an Ubuntu VM controller:

```bash
cd ansible
ansible-playbook --syntax-check playbooks/baseline.yml
ansible-playbook playbooks/baseline.yml --ask-become-pass
ansible-playbook playbooks/baseline.yml --ask-become-pass
```

The second full playbook run is the idempotency check.

## Structure

```text
ansible/
  inventory/
    local/
      group_vars/
  roles/
    common/
    security-baseline/
  playbooks/
```
