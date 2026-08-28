# Image Catalog

`catalog.json` is the machine-readable image catalog for the FastAPI control plane.

The catalog records image identity, default version, role policy, manifest path, lifecycle state, and optional launch source PVC for locally generated artifacts. It does not implement authorization logic by itself; Phase 7 enforces policy server-side using trusted Keycloak role claims.

In Phase 7, only `ubuntu-devops:1.0.0` is marked `available` and includes source PVC `vdiforge-golden-ubuntu-devops-1-0-0`. `ubuntu-base` and `ubuntu-developer` remain `candidate` entries.

Generated QCOW2 files and build manifests live under `artifacts/images/` and are intentionally excluded from Git.
