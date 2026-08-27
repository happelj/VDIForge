# Local Terraform Environment

This environment codifies the Phase 2 VirtualBox lab specification:

- `vdi-control-01`
- `vdi-worker-01`
- `vdi-worker-02`

The actual VMs were created in VirtualBox because there is no sufficiently trustworthy VirtualBox Terraform provider selected for this project. Terraform is still used to validate and expose the node definitions, resource allocations, IP addresses, and SSH targets.

## Commands

```powershell
terraform -chdir=terraform/environments/local init
terraform -chdir=terraform/environments/local fmt -check -recursive
terraform -chdir=terraform/environments/local validate
terraform -chdir=terraform/environments/local plan
terraform -chdir=terraform/environments/local output
```

Terraform state remains local and must not be committed.
