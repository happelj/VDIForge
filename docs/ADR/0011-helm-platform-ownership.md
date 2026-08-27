# ADR 0011: Helm Ownership for VDIForge Platform Foundation

## Status

Accepted.

## Context

Phase 3 created Kubernetes namespaces and a minimal provisioner RBAC skeleton with raw manifests. Phase 4 introduces the VDIForge Helm chart, which needs to own future platform resources without taking over cluster add-ons such as Calico, Metrics Server, KubeVirt, CDI, or local-path storage.

Helm v4 uses server-side apply. Existing Phase 3 resources created by `kubectl apply` have managed fields owned by the kubectl client-side apply manager, so Helm adoption requires both Helm metadata ownership and field-ownership conflict handling.

## Decision

Use Helm v4.2.4 as the Phase 4 deployment client from `vdi-control-01`.

The `helm/vdiforge` chart owns VDIForge platform foundation resources:

- platform ConfigMap
- VDIForge ServiceAccounts
- provisioner Role and RoleBinding
- ResourceQuotas
- platform LimitRange
- platform NetworkPolicies

The chart does not own Phase 3 cluster add-ons. The local lab namespaces remain owned by the Phase 3 namespace manifest, and `namespaces.create` remains `false` in `values-local.yaml`.

For the first install on the current lab, Helm adopts the existing Phase 3 provisioner ServiceAccount, Role, and RoleBinding with:

```bash
helm upgrade --install vdiforge ./helm/vdiforge \
  --namespace vdiforge-system \
  --values ./helm/vdiforge/values-local.yaml \
  --take-ownership \
  --force-conflicts \
  --wait
```

Future changes to Helm-managed objects should be made through Git and Helm values, not ad hoc `kubectl edit`.

## Alternatives Considered

- Keep all platform resources as raw manifests: simple, but fails the Phase 4 goal of repeatable Helm lifecycle management.
- Make Helm own namespaces and all cluster add-ons: too broad for Phase 4 and risks conflict with Phase 3 ownership.
- Delete and recreate Phase 3 RBAC resources under Helm: unnecessary and riskier than adopting existing objects.
- Add Argo CD or another GitOps controller: not justified for this MVP phase.
- Put Keycloak, Guacamole, Prometheus, and Grafana into the VDIForge chart now: premature and likely less maintainable than evaluating upstream charts in their implementation phases.

## Consequences

- Helm lifecycle operations can now validate install, upgrade, repeated upgrade, and rollback.
- Operators must treat Helm values and templates as desired state for chart-managed resources.
- Existing Phase 3 namespace manifests remain valid for bootstrap, but platform RBAC changes now belong in the Helm chart after adoption.
- Helm history may show failed adoption attempts if operators omit required adoption flags; the desired final state is a deployed release.
- Future phases must extend the chart rather than manually applying application resources.
