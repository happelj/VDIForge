# Ansible

This directory contains the Phase 2 operating-system baseline foundation, the Phase 3 Kubernetes/KubeVirt bootstrap roles, and the Phase 6 golden-image configuration roles.

## Roles

```text
common
security-baseline
containerd
kubernetes-common
kubernetes-control-plane
kubernetes-worker
image-common
image-desktop
image-developer
image-devops
image-cleanup
```

The image roles are intentionally separate from host and Kubernetes configuration. They run inside disposable Packer build guests and configure generated Ubuntu desktop artifacts, not the Kubernetes nodes themselves.

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
- Ubuntu golden image package installation
- lightweight XFCE desktop configuration
- future xrdp prerequisites for browser-based remote desktop integration
- image cleanup and generalization support

Phase 3 installs Kubernetes, Calico, Metrics Server, KubeVirt, CDI, and storage foundations. Phase 6 adds image build roles only. It does not install FastAPI, Guacamole, React, Prometheus, Grafana, or self-service VDI provisioning.

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
    image-common/
    image-desktop/
    image-developer/
    image-devops/
    image-cleanup/
  playbooks/
```

## Image Playbooks

Packer invokes these playbooks through its Ansible provisioner:

```bash
cd ansible
ansible-playbook -i localhost, playbooks/image-ubuntu-base.yml --syntax-check
ansible-playbook -i localhost, playbooks/image-ubuntu-developer.yml --syntax-check
ansible-playbook -i localhost, playbooks/image-ubuntu-devops.yml --syntax-check
```

The image playbooks expect to run as the temporary Packer build user inside a booted image build VM. Build credentials are removed from the final QCOW2 artifact by the offline generalization step.
