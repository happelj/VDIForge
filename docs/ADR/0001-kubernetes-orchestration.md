# ADR 0001: Kubernetes for Orchestration

## Status

Accepted for MVP architecture.

## Context

VDIForge needs to demonstrate platform engineering skills around scheduling, workload placement, resource management, service discovery, RBAC, NetworkPolicies, observability integration, and declarative deployment. The project also needs a control plane that can integrate with KubeVirt for VM lifecycle management.

The initial environment must be reproducible with free and open-source software and should not require paid cloud resources.

## Decision

Use Kubernetes as the orchestration layer for the VDIForge platform and KubeVirt VM workloads.

Use kubeadm and containerd for the local lab where practical. Use a CNI that supports Kubernetes NetworkPolicies.

## Alternatives Considered

- Docker Compose: simpler for a web application, but it does not demonstrate Kubernetes scheduling, RBAC, NetworkPolicies, or KubeVirt.
- Plain libvirt without Kubernetes: useful for VM hosting, but it would not demonstrate Kubernetes platform patterns.
- OpenStack: powerful VM platform, but too complex for the MVP and unnecessary for a reliable portfolio demo.
- Managed Kubernetes in cloud: useful later, but violates the initial no-cost local lab goal if required.

## Consequences

- The project can demonstrate real Kubernetes skills.
- KubeVirt can extend the Kubernetes API with VM resources.
- The local lab must handle Kubernetes operational complexity.
- The first topology is not production HA.
- Later phases must avoid implying that Kubernetes itself provides the virtualization layer; KubeVirt and KVM/QEMU provide that integration.
