# Image Catalog

`catalog.json` is the Phase 6 machine-readable image catalog foundation for the future FastAPI control plane.

The catalog records image identity, default version, role policy, and the expected manifest path for locally generated artifacts. It does not implement authorization logic; Phase 7 will enforce policy server-side using trusted Keycloak role claims.

Generated QCOW2 files and build manifests live under `artifacts/images/` and are intentionally excluded from Git.
