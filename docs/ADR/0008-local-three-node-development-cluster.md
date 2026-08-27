# ADR 0008: Local Three-Node Development Cluster

## Status

Accepted for MVP architecture with feasibility validation required.

## Context

VDIForge should demonstrate Kubernetes concepts beyond a single-node toy cluster while staying possible on local hardware. A three-node lab provides separate control-plane and worker roles and supports logical workload placement.

The design must not imply production HA when the nodes are VMs on one physical host.

## Decision

Use an initial local topology with:

```text
vdi-control-01  - Kubernetes control-plane node
vdi-worker-01   - platform/general workloads
vdi-worker-02   - VDI-oriented workloads
```

Use labels:

```text
vdiforge.io/node-role=platform
vdiforge.io/node-role=vdi
```

Use taints, tolerations, node selectors, and affinity only where they are technically justified.

Phase 2 update: the three nodes were created as VirtualBox Ubuntu Server VMs on one Windows host. The host-only management subnet is `192.168.56.0/24`, and `/dev/kvm` is verified on `vdi-worker-02`.

## Alternatives Considered

- Single-node Kubernetes: easier, but weaker demonstration of scheduling, node roles, and placement.
- Three control-plane nodes: closer to HA, but more resource-intensive and unnecessary for the MVP.
- Full bare-metal cluster from the start: strong target, but not always practical for a portfolio lab.
- Cloud-only lab: useful later, but violates the initial no-cost assumption if required.

## Consequences

- The MVP can demonstrate real Kubernetes placement concepts.
- The lab remains small enough for local hardware.
- If all nodes run on one physical computer, physical HA is not demonstrated.
- KubeVirt nested virtualization must be validated on the worker that hosts VDI VMs.
- Future production evolution should include HA control plane and independent failure domains.
