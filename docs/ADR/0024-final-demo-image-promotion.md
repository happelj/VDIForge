# 0024: Final Demo Image Promotion

## Status

Accepted

## Context

Earlier phases built and validated the golden-image pipeline, then used `ubuntu-devops` as the primary KubeVirt and browser remote desktop proof. Phase 14 needs the portfolio demo to show the complete role-based image catalog from the original requirements:

- Ubuntu Base for all VDI users.
- Ubuntu Developer for developer, DevOps, and admin users.
- Ubuntu DevOps for DevOps and admin users.

The local lab has limited disk capacity on `vdi-worker-02`. Launching all three image variants during every final validation would consume unnecessary storage and add time without materially improving confidence in the browser VDI path. The DevOps image remains the best primary demo image because it proves the remote desktop workflow and includes the infrastructure tools used in the final script.

## Decision

Phase 14 promotes the final image catalog as follows:

| Image | Default Version | Source PVC | Demo Role Access |
| --- | --- | --- | --- |
| `ubuntu-base` | `1.0.0` | `vdiforge-golden-ubuntu-base-1-0-0` | `vdi-user`, `vdi-developer`, `vdi-devops`, `vdi-admin` |
| `ubuntu-developer` | `1.0.0` | `vdiforge-golden-ubuntu-developer-1-0-0` | `vdi-developer`, `vdi-devops`, `vdi-admin` |
| `ubuntu-devops` | `1.2.0` | `vdiforge-golden-ubuntu-devops-1-2-0` | `vdi-devops`, `vdi-admin` |

`ubuntu-devops:1.0.0` and `ubuntu-devops:1.1.0` are retained as catalog history with deprecated lifecycle status and are not advertised as current launchable sources. Phase 14 validation prepares source DataVolumes/PVCs for Base and Developer, preserves DevOps `1.2.0`, validates role-specific catalog visibility, and runs the full browser VDI lifecycle against DevOps `1.2.0`.

## Alternatives Considered

1. Launch and connect to all three images during final validation.
   - Rejected for the local lab because it adds disk pressure and run time while duplicating the same KubeVirt provisioning path.

2. Keep only Ubuntu DevOps visible.
   - Rejected because it fails the portfolio requirement to demonstrate role-based access to all three image variants.

3. Publish all images to GHCR or another registry before the final demo.
   - Deferred. The local CDI source PVC path is already validated and avoids introducing registry credentials or large external artifacts into the final phase.

4. Remove old DevOps versions entirely from the catalog.
   - Rejected. Keeping deprecated entries preserves version history while preventing stale versions from being offered for new launches.

## Consequences

- The final demo clearly shows RBAC differences across `demo-user`, `demo-developer`, `demo-devops`, and `demo-admin`.
- The primary remote desktop proof remains focused and reliable with Ubuntu DevOps `1.2.0`.
- The local VDI worker retains source PVCs for the active catalog without requiring concurrent VM launches for every image.
- Future work can add staged image promotion, registry-backed imports, and automated image rollback without changing the Phase 14 demo contract.
