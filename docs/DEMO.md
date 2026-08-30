# VDIForge Final Demo Plan

This document defines the Phase 14 final portfolio demonstration. It is designed for a 10 to 12 minute walkthrough on the local VirtualBox/Kubernetes lab.

## Demo Goals

- Show the three-node Kubernetes/KubeVirt architecture.
- Prove users authenticate through Keycloak and receive role-based image access.
- Launch a KubeVirt-backed Ubuntu DevOps desktop from the React portal.
- Connect through Apache Guacamole in a browser without exposing reusable remote-desktop credentials.
- Prove Terraform, Helm, kubectl, Python, and Git execute inside the remote VDI VM, not on the client.
- Show HPA, Prometheus/Grafana, and audit evidence.
- Delete the desktop and verify Kubernetes cleanup.

## Pre-Flight Checklist

Run these before an interview or recording.

1. Confirm the Windows hosts file or local DNS maps the demo names to the ingress IP:

   ```text
   192.168.56.11 vdiforge.local api.vdiforge.local auth.vdiforge.local remote.vdiforge.local grafana.vdiforge.local
   ```

2. Confirm all three nodes are ready:

   ```bash
   kubectl get nodes -o wide
   ```

3. Confirm placement labels:

   ```bash
   kubectl get nodes --show-labels
   ```

4. Confirm KubeVirt, CDI, Metrics Server, Keycloak, API, provisioner, frontend, Guacamole, and monitoring are healthy:

   ```bash
   kubectl get pods -A
   kubectl get kubevirt -n kubevirt
   kubectl get cdi -n cdi
   kubectl top nodes
   helm list -A
   ```

5. Confirm final source images exist:

   ```bash
   kubectl -n vdiforge-desktops get datavolume,pvc
   ```

   Expected current demo source PVCs:

   | Image | Version | Source PVC |
   | --- | --- | --- |
   | Ubuntu Base | `1.0.0` | `vdiforge-golden-ubuntu-base-1-0-0` |
   | Ubuntu Developer | `1.0.0` | `vdiforge-golden-ubuntu-developer-1-0-0` |
   | Ubuntu DevOps | `1.2.0` | `vdiforge-golden-ubuntu-devops-1-2-0` |

6. Confirm API image catalog authorization:

   ```bash
   python3 scripts/phase14-role-image-test.py \
     --env ~/vdiforge-phase5-validation/.local/phase5/phase5.env \
     --ca ~/vdiforge-phase5-validation/.local/phase5/tls/vdiforge-local-ca.crt \
     --resolve-ip 192.168.56.11
   ```

7. Confirm the portal opens:

   ```text
   https://vdiforge.local
   ```

8. Confirm Grafana opens:

   ```text
   https://grafana.vdiforge.local
   ```

9. Confirm no stale running demo desktop needs cleanup:

   ```bash
   kubectl -n vdiforge-desktops get vm,vmi,svc,pvc
   ```

## Demo Accounts

Credentials are generated locally and are not committed to Git. Retrieve them on `vdi-control-01` from the Phase 5 environment file:

```bash
grep -E 'DEMO_(USER|DEVELOPER|DEVOPS|ADMIN)_PASSWORD' ~/vdiforge-phase5-validation/.local/phase5/phase5.env
```

Use these usernames:

| User | Role Intent | Expected Images |
| --- | --- | --- |
| `demo-user` | ordinary VDI user | Ubuntu Base |
| `demo-developer` | developer user | Ubuntu Base, Ubuntu Developer |
| `demo-devops` | platform/DevOps user | Ubuntu Base, Ubuntu Developer, Ubuntu DevOps |
| `demo-admin` | VDI administrator | Ubuntu Base, Ubuntu Developer, Ubuntu DevOps |

## Numbered Demo Script

### 1. Open With The Architecture

Show the architecture diagram in [ARCHITECTURE.md](ARCHITECTURE.md) or explain:

```text
Browser -> React portal -> Keycloak -> FastAPI -> Provisioner -> Kubernetes -> KubeVirt -> Ubuntu VM -> xrdp -> Guacamole -> Browser
```

Say explicitly: the client does not download or boot Ubuntu. The Ubuntu desktop runs in a remote KubeVirt VM; the browser receives a remote graphical session and sends keyboard/mouse input.

### 2. Show The Cluster

Run:

```bash
kubectl get nodes -o wide
kubectl get nodes --show-labels
```

Point out:

- `vdi-control-01` is the control-plane node.
- `vdi-worker-01` is the platform worker.
- `vdi-worker-02` is the VDI/KubeVirt worker.
- This is not a production HA control plane and all VMs share one physical host.

### 3. Show KubeVirt And KVM

Run:

```bash
kubectl get kubevirt -n kubevirt
kubectl get node vdi-worker-02 -o jsonpath='{.status.allocatable.devices\.kubevirt\.io/kvm}{"\n"}'
```

Expected result: KubeVirt is available and the KVM resource exists on `vdi-worker-02`.

### 4. Show Role-Based Image Visibility

Open:

```text
https://vdiforge.local
```

Login through Keycloak and show these views:

1. Login as `demo-user`: only Ubuntu Base should appear.
2. Logout.
3. Login as `demo-developer`: Ubuntu Base and Ubuntu Developer should appear.
4. Logout.
5. Login as `demo-devops`: Ubuntu Base, Ubuntu Developer, and Ubuntu DevOps should appear.

Optional admin proof: login as `demo-admin` and show the same three images plus admin desktop visibility behavior where applicable.

### 5. Launch Ubuntu DevOps

As `demo-devops`, choose Ubuntu DevOps and click Launch.

Expected behavior:

- Portal accepts the launch.
- API returns quickly.
- Desktop appears in the lifecycle list.
- State progresses through `Requested`, `Provisioning`, `Booting`, and `Ready`.

### 6. Watch Kubernetes Resources

In a terminal on `vdi-control-01`, run:

```bash
watch -n 2 'kubectl -n vdiforge-desktops get vm,vmi,dv,pvc,svc'
```

Expected behavior:

- A KubeVirt `VirtualMachine` appears.
- A `VirtualMachineInstance` schedules on `vdi-worker-02`.
- A cloned DataVolume/PVC appears for the desktop root disk.
- A ClusterIP Service exposes the desktop RDP endpoint inside the cluster.

### 7. Connect Through Guacamole

When the portal shows `Ready`, click Connect.

Expected behavior:

- Browser opens `remote.vdiforge.local`.
- Guacamole uses the API-brokered connection handoff.
- No reusable xrdp password is visible in the portal or browser URL.
- The remote Ubuntu desktop appears.

If Guacamole shows a login screen, use the newly generated connection URL from the portal rather than a stale tab. If the browser reports that a connection does not exist, close that tab and click Connect again from the current Ready desktop row.

### 8. Prove Tools Run Remotely

Inside the remote Ubuntu DevOps desktop, open a terminal and run:

```bash
hostname
terraform version
helm version
kubectl version --client
python --version
git --version
```

Explain that these commands execute inside the remote VDI VM. The thin client only needs a browser and network access.

### 9. Show HPA

Run the safe load test from `vdi-control-01`:

```bash
python3 scripts/load-test-api.py \
  --env ~/vdiforge-phase5-validation/.local/phase5/phase5.env \
  --ca ~/vdiforge-phase5-validation/.local/phase5/tls/vdiforge-local-ca.crt \
  --resolve-ip 192.168.56.11 \
  --duration 60 \
  --concurrency 8 \
  --iterations 150000
```

In another terminal, watch:

```bash
watch -n 5 'kubectl -n vdiforge-system get hpa,deploy vdiforge-api'
```

This load endpoint is intentionally safe and does not launch desktops.

### 10. Show Grafana

Open:

```text
https://grafana.vdiforge.local
```

Open the `VDIForge Overview` dashboard. Use `Last 24 hours` if a shorter range shows no data.

Point out:

- active desktops
- desktops by state
- API request rate and latency
- API error rate
- provisioning requests and latency
- API replicas and HPA desired/current replicas
- worker-node CPU/memory
- KubeVirt and remote-session related signals where visible

### 11. Show Audit Evidence

Use the portal/admin API or export path to show audit records. From `vdi-control-01`, run the Phase 12 security/audit validation if you need a scripted proof:

```bash
python3 scripts/phase12-api-security-test.py \
  --env ~/vdiforge-phase5-validation/.local/phase5/phase5.env \
  --ca ~/vdiforge-phase5-validation/.local/phase5/tls/vdiforge-local-ca.crt \
  --resolve-ip 192.168.56.11
```

Expected audit concepts:

- desktop requested
- desktop created or started
- connection requested
- denied cross-user or guessed-ID access
- desktop stopped/deleted
- event hashes present
- no password, token, or xrdp credential appears

### 12. Delete The Desktop

Return to the portal and delete the demo desktop.

Watch cleanup:

```bash
watch -n 2 'kubectl -n vdiforge-desktops get vm,vmi,dv,pvc,svc'
```

Expected behavior:

- Per-desktop VM/VMI/DataVolume/PVC/Service resources are removed.
- Source image PVCs remain.
- The API history may still show deleted records because audit/state history is retained.

### 13. Close The Demo

State the main engineering boundary:

- VDIForge is a free local portfolio lab, not a production commercial VDI product.
- The local cluster is not HA.
- HPA scales API pods, not worker nodes.
- KubeVirt provides VM lifecycle, not Kubernetes itself as a hypervisor.
- Guacamole/RDP is a free browser remote desktop path, not PCoIP.

## Final Validation Command

Run this on `vdi-control-01` from the Phase 14 repository checkout:

```bash
bash scripts/validate-phase14-live.sh
```

This performs automated live validation for cluster health, source image PVC readiness, role/image catalog policy, DevOps remote desktop lifecycle, HPA/load regression, security/audit export regression, and final platform health.

Manual browser proof is still part of the portfolio demo because automated API checks cannot fully prove the human-visible remote desktop experience.

## Evidence To Capture

- `kubectl get nodes -o wide`
- `kubectl get nodes --show-labels`
- final image catalog by role
- portal desktop lifecycle reaching `Ready`
- KubeVirt VM/VMI scheduled on `vdi-worker-02`
- remote Ubuntu DevOps terminal with tool versions
- Grafana `VDIForge Overview` dashboard
- audit event/export showing lifecycle and connection events
- cleanup output after deleting the desktop
