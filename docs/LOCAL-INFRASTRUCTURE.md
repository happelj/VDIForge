# Local Infrastructure

This document records the Phase 2 local infrastructure implementation for VDIForge.

## Status

Phase 2 local infrastructure is host-validated on the current Windows workstation with VirtualBox. Phase 3 builds Kubernetes and KubeVirt on top of this foundation; see [Kubernetes and KubeVirt Foundation](KUBERNETES-KUBEVIRT.md). Keycloak, Guacamole, Helm application deployment, the VDIForge application, Prometheus, and Grafana remain later-phase work.

## Host Findings

| Item | Finding |
| --- | --- |
| Host OS | Microsoft Windows 10 Pro 10.0.19045 |
| CPU | AMD Ryzen 7 1700, 8 cores / 16 logical CPUs |
| RAM | 32 GB installed |
| Working drive | `F:` with more than 250 GB free during Phase 2 validation |
| Virtualization firmware | Enabled |
| Hyper-V state during initial check | Hypervisor present; VirtualBox nested virtualization was unavailable until Hyper-V was disabled and the host rebooted |
| VirtualBox | 7.2.16 r174877 |
| Terraform | 1.15.8 |
| Ansible | Installed on `vdi-control-01` for Phase 2 validation; not installed natively on the Windows host |
| SSH tooling | Windows OpenSSH client available |

## Hypervisor Decision

Selected local hypervisor:

```text
Oracle VirtualBox 7.2.16 on Windows 10 Pro
```

Reason:

- The user cannot install Ubuntu directly on bare metal, dual boot, or add another SSD.
- Hyper-V on Windows 10 with AMD did not provide a viable nested virtualization path for this host.
- VirtualBox became viable after disabling the Windows hypervisor and rebooting.
- `vdi-worker-02` exposes `svm` CPU flags and `/dev/kvm` inside the Ubuntu guest.
- VirtualBox is free for this local lab use case.

This is recorded in [ADR 0009](ADR/0009-virtualbox-local-lab-on-windows.md).

## Operating System

The current lab nodes were installed from:

```text
ubuntu-26.04-live-server-amd64.iso
```

Ubuntu 26.04 LTS is a supported LTS release published on April 23, 2026 and supported with standard maintenance until 2031. Phase 3 evaluates Kubernetes 1.36 and KubeVirt compatibility on this exact OS/kernel combination before installing cluster components.

Phase 1 originally listed Ubuntu Server 24.04 LTS as a candidate baseline. Phase 2 updates the actual local lab baseline to Ubuntu Server 26.04 LTS because it is the current supported LTS installed and validated on this host. This is not a license to use floating or unpinned Ubuntu versions.

## Node Topology

| Node | Future role | CPU | RAM | Disk | Host-only IP | Nested virtualization |
| --- | --- | ---: | ---: | ---: | --- | --- |
| `vdi-control-01` | Kubernetes control plane | 4 vCPU | 6144 MiB | 40 GiB | `192.168.56.10` | Not required |
| `vdi-worker-01` | Future platform workloads | 2 vCPU | 6144 MiB | 50 GiB | `192.168.56.11` | Not required |
| `vdi-worker-02` | Future KubeVirt/VDI workloads | 4 vCPU | 8192 MiB | 60 GiB | `192.168.56.12` | Verified |

Virtual disk files:

```text
F:\VirtualBox VMs\vdi-control-01\vdi-control-01.vdi
F:\VirtualBox VMs\vdi-worker-01\vdi-worker-01.vdi
F:\VirtualBox VMs\vdi-worker-02\vdi-worker-02.vdi
```

All disks are dynamically allocated VDI disks.

Phase 3 stability update: after Kubernetes 1.36.4, Calico, Metrics Server, KubeVirt, and CDI were installed, the original 2 vCPU / 4096 MiB control-plane VM showed sustained API-server pressure during idempotency validation. `vdi-control-01` was gracefully shut down, resized to 4 vCPU / 6144 MiB RAM, restarted, and revalidated. Terraform and validation expectations now record the resized control-plane allocation.

## Network Design

Each VM has two adapters:

| Adapter | Type | Purpose |
| --- | --- | --- |
| Adapter 1 | NAT | Outbound Internet access for package installation and updates. |
| Adapter 2 | Host-only Adapter | Host-to-node SSH and node-to-node lab traffic. |

Host-only network:

| Field | Value |
| --- | --- |
| Adapter | `VirtualBox Host-Only Ethernet Adapter` |
| Host IP | `192.168.56.1` |
| Subnet | `192.168.56.0/24` |
| DHCP | Disabled |
| DNS | NAT-provided for outbound traffic through Adapter 1 |
| Public exposure | None intended |

Netplan assigns the static host-only IP on `enp0s8`. NAT remains DHCP on `enp0s3`.

Example `vdi-worker-02` netplan pattern:

```yaml
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.12/24
```

Do not set a default gateway on the host-only interface.

## SSH Access

Administrative user:

```text
vdiadmin
```

SSH targets:

```powershell
ssh vdiadmin@192.168.56.10
ssh vdiadmin@192.168.56.11
ssh vdiadmin@192.168.56.12
```

Private SSH keys must not be committed. Password authentication is acceptable during local bootstrap, but key-based authentication should be configured before disabling password login.

## KubeVirt Readiness

`vdi-worker-02` was manually validated after enabling VirtualBox nested virtualization:

```bash
grep -E -m 5 '(vmx|svm)' /proc/cpuinfo
ls -l /dev/kvm
```

Evidence observed:

```text
svm flags are present in /proc/cpuinfo
/dev/kvm exists as root:kvm character device
```

Phase 2 classification:

```text
vdi-worker-02 nested virtualization: VERIFIED
/dev/kvm inside vdi-worker-02: available
```

KubeVirt software emulation remains a fallback concept, but the current Phase 2 lab has hardware virtualization exposed to the future VDI worker.

## Terraform Workflow

Terraform files:

```text
terraform/modules/virtualbox-lab-node/
terraform/environments/local/
```

Commands:

```powershell
terraform -chdir=terraform/environments/local init
terraform -chdir=terraform/environments/local fmt -check -recursive
terraform -chdir=terraform/environments/local validate
terraform -chdir=terraform/environments/local plan
terraform -chdir=terraform/environments/local output
```

Terraform state remains local and is ignored by Git.

Optional Makefile targets when `make` is installed:

```bash
make infra-init
make infra-plan
make infra-apply
make infra-output
make validate-phase2
```

`make infra-destroy-spec` only destroys Terraform's local specification state. It does not delete VirtualBox VMs, disks, or snapshots because Terraform is not the VirtualBox lifecycle authority on this host.

### Terraform Boundary

The older `terra-farm/virtualbox` provider is alpha and indicates a maintainer gap. Phase 2 therefore does not make a third-party VirtualBox provider authoritative for VM lifecycle. Terraform records and validates the infrastructure specification and exposes outputs; VirtualBox GUI or `VBoxManage` performs VM lifecycle on this host.

This is the maximum technically responsible Terraform scope for the selected local platform without introducing an abandoned provider.

## Ansible Workflow

Ansible files:

```text
ansible/ansible.cfg
ansible/inventory/local/hosts.yml
ansible/inventory/local/group_vars/all.yml
ansible/playbooks/baseline.yml
ansible/roles/common/
ansible/roles/security-baseline/
```

Planned baseline responsibilities:

- hostname
- `/etc/hosts`
- apt metadata
- common packages
- OpenSSH server
- time synchronization
- future Kubernetes swap prerequisite
- SSH root-login policy
- public-key authentication
- sudo group policy

Run from a Linux, WSL, or Ubuntu VM Ansible controller:

```bash
cd ansible
ansible-playbook --syntax-check playbooks/baseline.yml
ansible-playbook playbooks/baseline.yml --ask-become-pass
ansible-playbook playbooks/baseline.yml --ask-become-pass
```

The second run is the idempotency check. It should report no unnecessary changes except for service restarts caused by intentional configuration changes.

Phase 2 validation used `vdi-control-01` as the temporary Ansible controller. Phase 3 continues to use `vdi-control-01` as the practical Ansible controller because the Windows host does not have native Ansible. Validation passed:

```text
ansible-playbook --syntax-check: PASS
ansible-lint: PASS
Ansible ping to all nodes: PASS
Second baseline playbook run: changed=0, failed=0, unreachable=0 on all nodes
```

A temporary passwordless sudoers file was used only for validation and removed afterward from all three nodes.

Optional Makefile target when Ansible is available:

```bash
make configure
```

## Validation

Static validation:

```powershell
.\scripts\validate-phase1.ps1
.\scripts\validate-phase2.ps1
```

Optional live validation after key-based SSH is configured:

```powershell
.\scripts\validate-phase2.ps1 -Live
```

Manual live checks completed during Phase 2:

```text
Host -> vdi-control-01 SSH: passed
Host -> vdi-worker-01 SSH: passed
Host -> vdi-worker-02 SSH: passed
Node-to-node pings: passed
Outbound connectivity on all nodes: passed
vdi-worker-02 /dev/kvm: exists
```

## Start, Stop, and Rebuild

Start VMs from VirtualBox Manager or:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm vdi-control-01 --type headless
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm vdi-worker-01 --type headless
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm vdi-worker-02 --type headless
```

Gracefully stop from inside each VM:

```bash
sudo shutdown now
```

Do not delete VM folders unless intentionally rebuilding the lab. Rebuild procedure:

1. Shut down the VM.
2. Remove the VM in VirtualBox.
3. Delete only that VM's folder under `F:\VirtualBox VMs`.
4. Recreate it with the documented CPU, RAM, disk, and network settings.
5. Reapply static netplan IP.
6. Revalidate SSH, node-to-node ping, and `/dev/kvm` where applicable.

## Limitations

- This is not production HA.
- All three VMs run on one Windows host and share one physical failure domain.
- VirtualBox is selected for this host because bare-metal Linux KVM/libvirt is unavailable to the user.
- Terraform does not directly create the VirtualBox VMs because no selected provider met the maintainability bar.
- Ansible is validated from `vdi-control-01`; decide in a later phase whether routine operations should remain there, use WSL, or use another Linux controller.
- Phase 3 Kubernetes/KubeVirt details, including storage and KVM verification, are documented separately in [Kubernetes and KubeVirt Foundation](KUBERNETES-KUBEVIRT.md).

## Sources

- [Ubuntu 26.04 LTS release notes](https://documentation.ubuntu.com/release-notes/26.04/)
- [Ubuntu release lifecycle](https://ubuntu.com/about/release-cycle)
- [Kubernetes kubeadm installation docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Terraform VirtualBox provider registry listing](https://registry.terraform.io/providers/terra-farm/virtualbox/latest)
- [VirtualBox nested virtualization documentation](https://docs.oracle.com/en/virtualization/virtualbox/6.0/admin/nested-virt.html)
