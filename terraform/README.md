# Terraform

This directory is reserved for infrastructure lifecycle code.

## Boundary

Terraform manages infrastructure, not per-user desktop launches.

Planned responsibilities:

- local KVM/libvirt VM and network definitions where practical
- reusable infrastructure modules
- future cloud infrastructure
- environment-level infrastructure configuration

Desktop launches are handled by the VDIForge backend through Kubernetes/KubeVirt APIs.

## Local Environment

The preferred local Terraform target is KVM/libvirt using the maintained `dmacvicar/libvirt` provider. Phase 2 must validate this on the actual host.

If local Terraform is not practical, document the reason and use a repeatable fallback for local VM creation while preserving Terraform for environments where it is appropriate.

## State

Terraform state, tfvars containing secrets, generated plans, and provider caches must not be committed.

## Structure

```text
terraform/
  modules/
  environments/
    local/
```
