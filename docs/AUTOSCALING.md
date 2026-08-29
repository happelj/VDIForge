# Autoscaling and Capacity

VDIForge distinguishes three different scaling concepts:

- Application pod autoscaling: implemented in Phase 10 for `vdiforge-api`.
- Provisioning throughput scaling: deferred until the provisioner has explicit concurrency coordination.
- Kubernetes node autoscaling: not implemented in the fixed local VirtualBox lab.

The local cluster remains one control-plane node and two worker nodes. HorizontalPodAutoscaler changes pod replica counts; it does not add Kubernetes worker nodes, allocate more RAM to VirtualBox, or increase physical host capacity.

## Phase 10 Status

Phase 10 adds a Helm-managed Kubernetes `autoscaling/v2` HPA for the FastAPI service.

| Item | Value |
| --- | --- |
| Target Deployment | `vdiforge-api` |
| HPA | `vdiforge-api` in `vdiforge-system` |
| Chart version | `0.10.0` |
| Enabled by | `helm/vdiforge/values-phase10-local.yaml` |
| Metric | CPU resource utilization |
| API CPU request | `100m` |
| API CPU limit | `500m` |
| Minimum replicas | `1` |
| Maximum replicas | `3` |
| CPU target | `50%` of requested CPU |
| Scale-up behavior | up to 2 pods or 200% every 15 seconds |
| Scale-down behavior | 60-second stabilization, up to 1 pod every 30 seconds |

The Phase 10 local values also enable a protected load-test endpoint:

```text
GET /api/v1/health/load-test
```

That endpoint is disabled by default in `values.yaml`, requires normal bearer-token authentication, performs bounded CPU work, and does not create, mutate, or delete desktops.

## Architecture

```text
                    Kubernetes Cluster

                      HPA Controller
                           |
                           v
                    VDIForge API
                     /    |    \
                  Pod 1  Pod 2  Pod 3
                           |
                           v
                    PostgreSQL / Keycloak / K8s
```

```text
HPA
 |
 +--> creates/removes API pod replicas
 |
 X--> does NOT create Kubernetes worker nodes
 |
 X--> does NOT create VDI desktop VMs
```

## Helm Values

Autoscaling is opt-in through values:

```yaml
api:
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 3
    targetCPUUtilizationPercentage: 50
  loadTest:
    enabled: true
    defaultIterations: "150000"
    maxIterations: "1500000"
```

When `api.autoscaling.enabled` is true, the API Deployment does not set a fixed `spec.replicas` value. The HPA owns replica count.

The default `values.yaml` keeps both `api.autoscaling.enabled` and `api.loadTest.enabled` false. This prevents the local load-test endpoint from being enabled by accident in non-test-style values.

## Provisioner Scaling Decision

Provisioner HPA is explicitly deferred.

The Phase 7 reconciler scans non-terminal desktop records and reconciles desired state into KubeVirt resources. The current design is idempotent for one provisioner, but it does not yet include leader election, database row claiming, `SELECT FOR UPDATE SKIP LOCKED`, or another work-partitioning mechanism.

Running multiple provisioner replicas today could create duplicate reconciliation attempts, extra Kubernetes API pressure, and confusing race conditions during desktop lifecycle transitions. Phase 10 therefore implements API autoscaling only and leaves `provisioner.autoscaling.enabled: false`.

Future provisioner scaling requires one of:

- leader election for an active/passive provisioner
- database-backed work claiming with row locks
- a reconciler design that partitions work safely across replicas
- metrics that describe reconciliation backlog or lag

## Resource Capacity

The current platform worker is intentionally small:

| Node | Role | CPU | Memory |
| --- | --- | ---: | ---: |
| `vdi-worker-01` | platform | 2 vCPU | 6 GiB |
| `vdi-worker-02` | VDI/KubeVirt | 4 vCPU | 8 GiB |

`maxReplicas: 3` is selected so the API can demonstrate real scale-out without consuming the whole platform worker. Each API replica requests `100m` CPU and `256Mi` memory and limits at `500m` CPU and `512Mi` memory.

This HPA cannot solve cluster capacity exhaustion. If the platform worker is full, new API replicas may remain Pending while existing replicas continue serving traffic. That is a capacity signal, not node autoscaling.

## Safe Load Test

The load generator is:

```bash
python3 scripts/load-test-api.py \
  --env ~/.local-or-phase5/phase5.env \
  --ca ~/.local-or-phase5/tls/vdiforge-local-ca.crt \
  --resolve-ip 192.168.56.11 \
  --duration 180 \
  --concurrency 20 \
  --iterations 150000
```

In the standard lab, run the live validator instead:

```bash
bash scripts/validate-phase10-live.sh
```

The load test:

- authenticates through Keycloak using Authorization Code Flow with PKCE
- sends authenticated `GET` requests to the API
- uses the local development CA without disabling TLS validation
- records request count, success count, error rate, and P50/P95 latency
- never posts to `/api/v1/desktops`
- checks that the desktop count before and after the test is unchanged

## Demonstration Flow

Baseline:

```bash
kubectl get hpa -n vdiforge-system
kubectl get deployment vdiforge-api -n vdiforge-system
kubectl top pods -n vdiforge-system
```

Start safe load:

```bash
python3 scripts/load-test-api.py ...
```

Observe:

```bash
kubectl get hpa vdiforge-api -n vdiforge-system -w
kubectl get deployment vdiforge-api -n vdiforge-system -w
kubectl get endpointslice -n vdiforge-system -l kubernetes.io/service-name=vdiforge-api
```

Expected result:

```text
baseline API replicas -> CPU above target -> HPA desired replicas increases -> new API pods Ready -> load ends -> HPA scales back down
```

The test is valid only if replicas change automatically through HPA. Manually editing the Deployment replica count does not satisfy Phase 10.

## Validation Evidence

Phase 10 validation records:

```text
baseline_replicas
peak_replicas
baseline_cpu
baseline_pod_cpu
peak_cpu
target_cpu
scale_up_seconds
scale_down_result
scale_down_seconds
final_replicas
desktop_count_before
desktop_count_after
final_helm_revision
```

Latest observed live result from `scripts/validate-phase10-live.sh` on August 29, 2026:

| Evidence | Observed Value |
| --- | --- |
| Baseline API replicas | `1` |
| Peak API replicas | `3` |
| Baseline HPA CPU | `3%` |
| Baseline API pod CPU | `2m` |
| Peak HPA CPU | `502%` |
| HPA target CPU | `50%` |
| Scale-up time | `53s` |
| Scale-down result | `PASS` |
| Scale-down time | `123s` |
| Final API replicas | `1` |
| Desktop count before/after | `1` / `1` |
| Platform worker baseline | `vdi-worker-01 484m CPU, 2484Mi memory` |
| Platform worker peak | `1096m CPU, 2792Mi memory` |
| Final Helm revision | `80` |

The live validator also proves:

- Metrics Server returns node and pod metrics.
- HPA reports real metrics instead of `<unknown>`.
- CPU crosses the configured target.
- API replicas scale up automatically.
- new replicas become Ready and enter the Service endpoint set.
- authenticated `/api/v1/images` and `/api/v1/desktops` reads continue succeeding under multiple replicas.
- the React portal remains reachable.
- KubeVirt/CDI/Calico/CoreDNS remain healthy.

## Troubleshooting

Inspect HPA:

```bash
kubectl describe hpa vdiforge-api -n vdiforge-system
kubectl get hpa vdiforge-api -n vdiforge-system -o yaml
```

Inspect metrics:

```bash
kubectl top nodes
kubectl top pods -A
kubectl describe apiservice v1beta1.metrics.k8s.io
```

Inspect API scale-out:

```bash
kubectl get deploy,pod,endpointslice -n vdiforge-system -l app.kubernetes.io/component=api
kubectl logs deploy/vdiforge-api -n vdiforge-system
kubectl get events -n vdiforge-system --sort-by=.lastTimestamp
```

If HPA metrics remain `<unknown>`, fix Metrics Server or API resource requests before rerunning the load test. If new API pods remain Pending, inspect platform-worker capacity and quotas rather than increasing HPA limits.

## Future Work

Phase 11 will add Prometheus/Grafana observability. It should scrape and visualize API request metrics, HPA desired/current replicas, pod CPU/memory, provisioning latency, and remote-session metrics.

Future cloud or bare-metal deployments may add true node autoscaling. That requires separate infrastructure automation and capacity management and is not part of the local MVP.
