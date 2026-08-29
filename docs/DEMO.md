# Portfolio Demo Plan

This document defines the target final VDIForge portfolio demonstration. The demo is planned for approximately 10 minutes after implementation phases are complete.

## Demo Goals

- Show the architecture clearly.
- Prove the system uses Kubernetes and KubeVirt for VM lifecycle management.
- Show that users authenticate through Keycloak.
- Demonstrate RBAC-controlled image access.
- Launch an Ubuntu DevOps desktop.
- Connect through a browser-based remote desktop session.
- Prove DevOps tools execute on the remote VM, not on the thin client.
- Show HPA behavior under controlled API load.
- Show Grafana and audit evidence.
- Delete the desktop and verify cleanup.

## Pre-Flight Checklist

Validate before an interview:

- `git status` is clean on the demo branch or release tag.
- Three Kubernetes nodes are Ready.
- Node labels exist:
  - `vdiforge.io/node-role=platform`
  - `vdiforge.io/node-role=vdi`
- KubeVirt is available.
- `/dev/kvm` is available on the VDI worker, or the demo is explicitly marked as using slow development emulation.
- Keycloak realm `vdiforge` exists.
- Demo users exist and have expected roles.
- Image catalog contains Ubuntu Base, Ubuntu Developer, and Ubuntu DevOps.
- Ubuntu DevOps image has passed validation.
- `ubuntu-devops:1.2.0` source PVC exists for the current portal remote desktop demo path.
- Guacamole and guacd are healthy.
- `remote.vdiforge.local` resolves to the local ingress endpoint from the demo client.
- Prometheus targets are up.
- Grafana dashboard loads.
- HPA is configured for the API demo.
- The HPA load test path cannot create desktops.
- Audit events are visible.
- Thin-client VM or laptop has only a browser and normal network tooling.
- Thin client does not have Terraform, Helm, kubectl, backend tools, or development Python environment installed.
- A cleanup command or UI path has been tested.

## 10-Minute Demo Script

### 1. Architecture, 45 seconds

Show [ARCHITECTURE.md](ARCHITECTURE.md) and explain the flow:

```text
Browser -> Portal -> Keycloak -> FastAPI -> Provisioner -> Kubernetes -> KubeVirt -> Ubuntu VM -> Guacamole -> Browser
```

State clearly that the browser receives a remote session. The Ubuntu OS and applications run on the remote VM.

### 2. Cluster, 45 seconds

Show:

```bash
kubectl get nodes -o wide
kubectl get nodes --show-labels
```

Point out:

- one control-plane node
- two worker nodes
- platform and VDI labels
- local lab is not production HA

### 3. KubeVirt, 45 seconds

Show:

```bash
kubectl -n kubevirt get pods
kubectl api-resources | grep -i kubevirt
kubectl -n vdiforge-desktops get vm,vmi
```

Explain that KubeVirt provides VM lifecycle integration through Kubernetes.

### 4. Thin Client, 30 seconds

Show the thin-client VM or laptop. It should have:

- lightweight OS
- browser
- network access

It should not have platform engineering tools installed locally.

### 5. Keycloak Login, 45 seconds

Open VDIForge from the thin client. Authenticate as:

```text
demo-devops
```

Show that login redirects through Keycloak.

### 6. Image Catalog, 45 seconds

Show the authorized images. As `demo-devops`, the user should see:

- Ubuntu Base
- Ubuntu Developer
- Ubuntu DevOps

Optionally show that `demo-user` cannot see Ubuntu Developer or Ubuntu DevOps.

### 7. Launch Ubuntu DevOps, 60 seconds

Select:

```text
Image: Ubuntu DevOps
Profile: approved MVP profile
```

Click Launch. Show that the API returns quickly and the desktop enters provisioning.

### 8. VM Appears in Kubernetes, 60 seconds

Show:

```bash
kubectl -n vdiforge-desktops get vm,vmi,pvc,svc
kubectl -n vdiforge-desktops describe vm <desktop-vm-name>
```

Explain desired state vs observed VM state.

### 9. READY and Connect, 60 seconds

Return to the portal and show the desktop reaching READY. Click Connect.

Show the browser-based session through Guacamole by clicking Connect in the React portal. The portal opens the API-returned brokered URL from `POST /api/v1/desktops/{id}/connect`.

### 10. Remote Terminal Proof, 90 seconds

Inside the remote Ubuntu desktop, open a terminal and run:

```bash
hostname
terraform version
helm version
kubectl version --client
python --version
git --version
```

Explain that these commands run on the remote Ubuntu DevOps VM. The thin client is only rendering the browser session and sending input.

### 11. HPA Demo, 60 seconds

Run controlled load against a safe API endpoint that does not create desktops.

Show:

```bash
kubectl -n vdiforge-system get hpa
kubectl -n vdiforge-system get deploy vdiforge-api
```

Show replicas increase under load and begin scaling down after load stops.

### 12. Grafana, 45 seconds

Open Grafana and show:

- active desktops
- provisioning latency
- API request rate
- API error rate
- HPA desired/current replicas
- worker-node CPU/memory
- active remote sessions

### 13. Audit Event, 45 seconds

Show an audit event for:

- `DESKTOP_REQUESTED`
- `DESKTOP_CONNECTION_REQUESTED`
- or `DESKTOP_DELETED`

Point out request ID, user ID, action, resource ID, result, and timestamp.

### 14. Delete and Cleanup, 60 seconds

Delete the desktop from the portal. Show:

```bash
kubectl -n vdiforge-desktops get vm,vmi,pvc,svc
```

Verify the associated resources are removed or marked for cleanup according to policy.

## Failure Talking Points

Be prepared to explain:

- what happens when capacity is insufficient
- what happens when the image is unavailable
- why HPA is separate from node autoscaling
- why KubeVirt needs KVM or development emulation
- why Guacamole is not PCoIP
- why local three-node topology is not production HA

## Demo Evidence to Capture

- screenshot of Ready nodes
- screenshot of KubeVirt resources
- screenshot of image catalog
- screenshot of remote Ubuntu DevOps terminal
- screenshot of Grafana dashboard
- audit event row or JSON record
- cleanup command output
