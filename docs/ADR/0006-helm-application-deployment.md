# ADR 0006: Helm for Application Deployment

## Status

Accepted for MVP architecture. Updated by Phase 4 implementation.

## Context

VDIForge needs repeatable application deployment into Kubernetes. The project should demonstrate Kubernetes manifests, Services, Ingress, ConfigMaps, ServiceAccounts, RBAC, NetworkPolicies, and HPA without hand-applying unrelated YAML files.

## Decision

Use Helm to package and deploy VDIForge application components.

The eventual deployment command should approximate:

```bash
helm upgrade --install vdiforge ./helm/vdiforge
```

The VDIForge chart should include:

- frontend
- FastAPI
- provisioning worker
- Services
- Ingress
- ConfigMaps
- ServiceAccounts
- Kubernetes RBAC
- NetworkPolicies
- HPA

Use established upstream charts or images for third-party products where that is more maintainable.

Phase 4 update: Helm v4.2.4 is selected for the local lab because Helm v4 is the current stable major release and v4.2.x supports Kubernetes 1.36.x. The Phase 4 chart at `helm/vdiforge` establishes platform foundations only: ConfigMap conventions, ServiceAccounts, provisioner RBAC, ResourceQuotas, a platform LimitRange, and baseline NetworkPolicies. It does not deploy application workloads yet.

The local lab release is installed into `vdiforge-system` and uses existing Phase 3 namespaces. Namespace creation remains disabled in `values-local.yaml` to avoid competing ownership with the Phase 3 namespace bootstrap manifests.

## Alternatives Considered

- Raw `kubectl apply`: simple early on, but harder to parameterize and upgrade cleanly.
- Kustomize only: viable, but Helm better matches the requested deployment experience and common application packaging pattern.
- Argo CD: useful in larger GitOps environments, but not justified for the MVP.
- Custom deployment scripts: less declarative and less idiomatic for Kubernetes application packaging.

## Consequences

- Chart values become the primary local deployment interface.
- Helm lint/template validation must be part of CI.
- Third-party chart values must be pinned and reviewed.
- Helm should not become the image build or infrastructure provisioning tool.
- Helm-managed resources should be changed through chart templates and values, not ad hoc `kubectl edit`.
- The first Phase 4 install on the current lab must adopt the Phase 3 provisioner RBAC resources with Helm ownership flags documented in [ADR 0011](0011-helm-platform-ownership.md).
