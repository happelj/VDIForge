# Image Catalog

`catalog.json` is the machine-readable image catalog for the FastAPI control plane.

The catalog records image identity, default version, role policy, manifest path, lifecycle state, and optional launch source PVC for locally generated artifacts. It does not implement authorization logic by itself; the API enforces policy server-side using trusted Keycloak role claims.

In Phase 8, `ubuntu-devops:1.1.0` is the default launchable version and includes source PVC `vdiforge-golden-ubuntu-devops-1-1-0`. `ubuntu-devops:1.0.0` remains recorded and available for rollback/history. `ubuntu-base` and `ubuntu-developer` remain `candidate` entries.

Generated QCOW2 files and build manifests live under `artifacts/images/` and are intentionally excluded from Git.
