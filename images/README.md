# Image Catalog

`catalog.json` is the machine-readable image catalog for the FastAPI control plane.

The catalog records image identity, default version, role policy, manifest path, lifecycle state, and optional launch source PVC for locally generated artifacts. It does not implement authorization logic by itself; the API enforces policy server-side using trusted Keycloak role claims.

In Phase 14, the final demo catalog exposes three current launchable image entries by role:

| Image | Default version | Source PVC | Roles |
| --- | --- | --- | --- |
| `ubuntu-base` | `1.0.0` | `vdiforge-golden-ubuntu-base-1-0-0` | `vdi-user`, `vdi-developer`, `vdi-devops`, `vdi-admin` |
| `ubuntu-developer` | `1.0.0` | `vdiforge-golden-ubuntu-developer-1-0-0` | `vdi-developer`, `vdi-devops`, `vdi-admin` |
| `ubuntu-devops` | `1.2.0` | `vdiforge-golden-ubuntu-devops-1-2-0` | `vdi-devops`, `vdi-admin` |

`ubuntu-devops:1.2.0` remains the primary browser remote-desktop proof image because it carries the permanent XFCE/xrdp session fix validated during the portal and Guacamole phases. `ubuntu-devops:1.0.0` and `ubuntu-devops:1.1.0` remain recorded as deprecated history and are not advertised as current launchable sources.

Generated QCOW2 files and build manifests live under `artifacts/images/` and are intentionally excluded from Git.
