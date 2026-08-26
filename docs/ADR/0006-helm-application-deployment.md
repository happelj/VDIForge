# ADR 0006: Helm for Application Deployment

## Status

Accepted for MVP architecture.

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
