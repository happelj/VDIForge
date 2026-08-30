# VDIForge Limitations

This document records known limitations so VDIForge is presented accurately as a portfolio platform and not as a production VDI service.

## Local Lab Scope

- The current platform runs on one Windows 10 Pro host using Oracle VirtualBox.
- The three Ubuntu Server nodes are separate VMs, not separate physical failure domains.
- The Kubernetes control plane is single-node and not highly available.
- Host failure, VirtualBox failure, or host disk failure can stop the entire lab.
- Local `.local` DNS is provided through hosts-file entries or equivalent local DNS, not public DNS.

## Virtualization

- KubeVirt hardware acceleration depends on nested virtualization being exposed by VirtualBox and the host CPU.
- `/dev/kvm` and the KubeVirt KVM device are verified on `vdi-worker-02`, but this does not imply production-grade performance.
- KubeVirt software emulation remains a development fallback only and is not equivalent to hardware acceleration.

## Storage

- `vdiforge-local-path` is suitable for this lab but not highly available.
- VM disks and source PVCs are tied to local node storage.
- No distributed storage, backup, restore, snapshot, or live migration storage design is implemented.
- The final demo retains the source PVCs needed for the current image catalog and avoids launching every image concurrently to protect the small VDI worker disk.
- Repeated final-demo validation may remove superseded generated QCOW2 files from the ignored Phase 6 artifact directory after the active source PVCs have been imported. This is a local disk-pressure control, not an image-registry or backup strategy.

## Images

- The final demo catalog exposes Ubuntu Base `1.0.0`, Ubuntu Developer `1.0.0`, and Ubuntu DevOps `1.2.0`.
- The primary browser VDI proof uses Ubuntu DevOps `1.2.0`.
- Earlier DevOps source versions are kept as catalog history or deprecated entries, not as the current demo launch path.
- Full QCOW2 image builds remain local/manual because they require KVM-capable build resources and large local artifacts.

## Identity And Sessions

- Keycloak is deployed for local-lab identity and demo users only.
- Demo passwords are generated locally and must not be committed.
- Browser token storage is a practical local-lab implementation, not a high-assurance enterprise session design.
- Grafana OIDC integration is deferred; local admin credentials are used for the demo.

## Remote Desktop

- Apache Guacamole and xrdp provide a free browser remote desktop path.
- The project does not use PCoIP and does not claim protocol equivalence with PCoIP.
- Clipboard, audio, file transfer, session recording, and persistent user profile policies remain future enhancements.
- Browser close does not necessarily delete a desktop; the user must stop or delete desktops through the portal/API.

## Security

- NetworkPolicies, RBAC, CORS, headers, rate limits, and audit hardening are implemented for the local lab.
- No external WAF, SIEM, cloud KMS, external secret manager, or Vault cluster is deployed.
- Audit hash chaining is tamper-evident in the application database but not an immutable external audit store.
- In-process rate limiting is per API pod under HPA.

## Observability

- Prometheus/Grafana provide metrics and dashboard proof.
- Alertmanager is local-only and has no external notification receiver.
- Log aggregation and long-term metrics retention are not implemented.
- Some Grafana panels naturally show no recent data when no desktops are running or no API traffic occurred in the selected time range.

## CI/CD

- GitHub Actions validates CI-safe checks and builds/scans custom containers.
- CI does not connect to the home lab, use local kubeconfigs, or deploy to Kubernetes.
- CI does not build full QCOW2 golden images on every pull request.
- Live KubeVirt/Guacamole/browser validation remains a local/manual path.

## Production Evolution

Productionizing VDIForge would require new ADRs for HA control plane, physical or cloud failure domains, production storage, managed DNS/TLS, backup/restore, external secrets, stronger tenant isolation, image promotion rings, and operational support boundaries.
