# Kubernetes

This directory is reserved for Kubernetes resources that are not owned by the VDIForge Helm chart or an upstream chart.

## Planned Contents

```text
kubernetes/
  namespaces/
  kubevirt/
  policies/
```

## Boundary

- Core application resources belong in `helm/vdiforge`.
- KubeVirt installation and validation assets belong under `kubernetes/kubevirt` until a later phase chooses a chart/operator workflow.
- Shared namespace and policy definitions may live here when they are not chart-specific.

## Rules

- Pin versions.
- Prefer declarative YAML.
- Validate manifests before applying.
- Do not grant broad Kubernetes permissions for convenience.
