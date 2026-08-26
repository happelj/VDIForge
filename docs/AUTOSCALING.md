# Autoscaling and Capacity

VDIForge distinguishes platform autoscaling from cluster or node autoscaling.

## Platform Autoscaling

Platform autoscaling uses Kubernetes HorizontalPodAutoscaler for suitable stateless components.

Initial HPA targets:

- FastAPI API pods
- provisioning worker pods

Initial metrics:

- CPU utilization
- memory utilization where appropriate

Future metrics:

- provisioning queue depth
- reconciliation lag
- API request latency
- Guacamole active session count, if useful for supporting components

## HPA Demonstration

The final portfolio demo should include controlled API load:

```text
2 API replicas
      |
API load
      |
CPU rises
      |
HPA reacts
      |
4+ replicas
      |
load ends
      |
scale-down
```

The load test must target a no-op or read-only API path. It must not create hundreds of VDI desktops.

Example safe test target for a later phase:

```text
GET /api/v1/health/load-test
```

The endpoint should be intentionally cheap in dependencies but CPU-bounded enough to demonstrate HPA behavior in a controlled lab.

## Cluster and Node Autoscaling

The local lab has fixed node capacity:

```text
vdi-control-01
vdi-worker-01
vdi-worker-02
```

HPA changes pod replica counts. HPA does not create Kubernetes worker nodes or add physical compute capacity.

True node autoscaling is a future deployment capability for cloud or a more advanced bare-metal environment. It should be designed separately from the local MVP and may require cloud autoscaling groups, Cluster Autoscaler, Karpenter-like systems, or custom bare-metal capacity management. Those systems are not part of Phase 1 or the local MVP.

## Capacity Model

VDIForge should track capacity using Kubernetes observed state and backend policy.

Inputs:

- worker-node allocatable CPU and memory
- storage class capacity, where observable
- existing active desktop requests
- resource profiles
- Kubernetes scheduling failures
- KubeVirt VMI phase and conditions

Example resource profiles to define later:

| Profile | CPU | Memory | Use |
| --- | ---: | ---: | --- |
| `small` | 2 vCPU | 4 GiB | Basic Ubuntu desktop demo. |
| `medium` | 4 vCPU | 8 GiB | Developer or DevOps desktop. |

Actual values must be validated against local hardware.

## Insufficient Capacity Behavior

When capacity is insufficient, the system should:

- reject new launches before creating Kubernetes resources when policy can detect the shortage
- return a consistent API error with request ID
- record an audit event for rejected desktop launch attempts
- emit metrics for capacity denials
- avoid retrying indefinitely
- leave existing desktops unaffected unless an admin policy acts on them

If Kubernetes accepts a VM but cannot schedule it, the provisioner should:

- observe `Pending` and scheduling events
- update the desktop with a clear reason
- retry only within bounded policy
- transition to `FAILED` after timeout
- clean up incomplete resources where safe

## Scaling Boundaries

Can scale in MVP:

- API replicas
- provisioning worker replicas, if the reconciler uses safe idempotency and leader/work partitioning
- frontend replicas

Should not autoscale in MVP:

- Keycloak, unless using a validated chart and database configuration
- PostgreSQL, unless using a supported HA design
- KubeVirt control components beyond upstream installation defaults
- desktop VM count without explicit quota and capacity policy

## Risks

- Provisioner HPA can increase Kubernetes API pressure if reconciliation loops are not bounded.
- API load tests can distort capacity if they share a worker with VM workloads.
- Local single-host labs cannot demonstrate true infrastructure elasticity.
- Desktop VMs consume larger resources than typical stateless pods, so HPA behavior for API pods does not imply desktop capacity is available.
