# Terraform

This directory contains the Phase 2 local infrastructure specification and remains the home for future infrastructure lifecycle code.

## Boundary

Terraform manages infrastructure, not per-user desktop launches.

Responsibilities:

- validated local lab node specifications
- host-only network metadata
- reusable infrastructure modules
- environment-level infrastructure configuration
- future local KVM/libvirt or cloud infrastructure where practical

Desktop launches are handled by the VDIForge backend through Kubernetes/KubeVirt APIs.

## Local Environment

The current Phase 2 host uses Oracle VirtualBox 7.2.16 on Windows 10 Pro. VirtualBox VM lifecycle is managed through the VirtualBox GUI or `VBoxManage` on this host.

The repository intentionally does not make an alpha or weakly maintained VirtualBox Terraform provider authoritative. Terraform records and validates the local lab specification using the built-in `terraform_data` resource. See [Local Infrastructure](../docs/LOCAL-INFRASTRUCTURE.md) and [ADR 0009](../docs/ADR/0009-virtualbox-local-lab-on-windows.md).

Commands:

```powershell
terraform -chdir=terraform/environments/local init
terraform -chdir=terraform/environments/local fmt -check -recursive
terraform -chdir=terraform/environments/local validate
terraform -chdir=terraform/environments/local plan
terraform -chdir=terraform/environments/local output
```

When `make` is installed, the aliases are `make infra-init`, `make infra-plan`, `make infra-apply`, and `make infra-output`. `make infra-destroy-spec` removes Terraform's local specification state only; it does not delete VirtualBox VMs because Terraform does not own VM lifecycle on this host.

## State

Terraform state, tfvars containing secrets, generated plans, and provider caches must not be committed.

## Structure

```text
terraform/
  modules/
    virtualbox-lab-node/
  environments/
    local/
```
