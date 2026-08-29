# Kubernetes and KubeVirt Foundation

This document records the Phase 3 Kubernetes and KubeVirt foundation for the VDIForge local lab. It covers the selected version set, bootstrap workflow, cluster add-ons, validation approach, and limitations. Phase 7 consumes this foundation through the FastAPI provisioner, and Phase 8 adds Guacamole remote desktop delivery on top of the KubeVirt desktop resources. This document remains the lower-layer Kubernetes/KubeVirt reference.

## Status

Phase 3 automation is defined for the current three-node VirtualBox lab:

| Node | Role | IP | CPU | RAM | Disk |
| --- | --- | --- | ---: | ---: | ---: |
| `vdi-control-01` | Kubernetes control plane | `192.168.56.10` | 4 vCPU | 6 GiB | 40 GiB |
| `vdi-worker-01` | Platform worker | `192.168.56.11` | 2 vCPU | 6 GiB | 50 GiB |
| `vdi-worker-02` | VDI/KubeVirt worker | `192.168.56.12` | 4 vCPU | 8 GiB | 60 GiB |

Phase 3 live validation passed on 2026-08-27. The final hardware-virtualization classification is `KUBEVIRT_KVM_VERIFIED` on `vdi-worker-02`.

The control-plane VM was resized from the original Phase 2 2 vCPU / 4 GiB recommendation to 4 vCPU / 6 GiB during Phase 3 after Kubernetes add-on reconciliation caused sustained API-server pressure. The resize was validated with a clean Ansible idempotency pass and live cluster validation.

## Compatibility Matrix

The Phase 3 version set is pinned before installation. The versions below are selected for Ubuntu Server 26.04 LTS and Kubernetes 1.36.

| Component | Selected version | Compatibility | Evidence |
| --- | --- | --- | --- |
| Ubuntu Server | 26.04 LTS, Linux 7.0 kernel | PASS | Ubuntu 26.04 LTS is a supported LTS release through 2031; the installed nodes report Ubuntu 26.04 LTS and kernel `7.0.0-30-generic`. |
| Kubernetes | 1.36.4 | PASS | Kubernetes 1.36 is an active supported release line; v1.36.4 is available from the official versioned v1.36 package repository on the lab nodes. |
| kubeadm/kubelet/kubectl | 1.36.4-1.1 packages from `pkgs.k8s.io/core:/stable:/v1.36/deb/` | PASS | Kubernetes kubeadm documentation directs installs to the versioned `pkgs.k8s.io` repository and supports package pinning; `apt-cache madison` confirmed this package revision is available. |
| containerd | 2.2.2-0ubuntu1.1 | PASS | Ubuntu 26.04 package candidate on all three nodes; Kubernetes supports containerd through CRI v1 when configured with compatible cgroups. |
| Calico | v3.32.1 | PASS | Calico 3.32 documentation lists Kubernetes 1.34, 1.35, and 1.36 as tested versions and supports Ubuntu 20.04+ with Linux 5.10+. |
| Metrics Server | v0.8.1 | PASS | Metrics Server 0.8.x supports Kubernetes 1.31 and newer. |
| KubeVirt | v1.9.0 | PASS | KubeVirt release support matrix lists Kubernetes 1.36 support for KubeVirt 1.9. |
| CDI | v1.66.0 | PASS | KubeVirt 1.9 release schedule pairs CDI v1.66.0 with the 1.9 release train. |
| Local-path provisioner | v0.0.32 | PASS | Current Rancher local-path release supports simple dynamic local PV provisioning with `WaitForFirstConsumer`. |

Authoritative references:

- [Ubuntu 26.04 LTS release notes](https://documentation.ubuntu.com/release-notes/26.04/)
- [Kubernetes 1.36 releases](https://v1-36.docs.kubernetes.io/releases/)
- [Kubernetes v1.36.4 release tag](https://cos.googlesource.com/third_party/kubernetes/+/refs/tags/v1.36.4)
- [Kubernetes kubeadm installation](https://v1-36.docs.kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Kubernetes container runtime requirements](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [containerd CRI configuration](https://github.com/containerd/containerd/blob/main/docs/cri/config.md)
- [Calico Kubernetes requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements)
- [Calico quickstart manifests](https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart)
- [KubeVirt installation guide](https://kubevirt.io/user-guide/cluster_admin/installation/)
- [KubeVirt Kubernetes support matrix](https://github.com/kubevirt/sig-release/blob/main/releases/k8s-support-matrix.md)
- [KubeVirt v1.9 release schedule](https://github.com/kubevirt/sig-release/blob/main/releases/v1.9/schedule.md)
- [CDI DataVolumes](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md)
- [CDI WaitForFirstConsumer handling](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/waitforfirstconsumer-storage-handling.md)
- [Rancher local-path provisioner](https://github.com/rancher/local-path-provisioner)
- [Metrics Server releases](https://github.com/kubernetes-sigs/metrics-server/releases)

## Bootstrap Workflow

Phase 3 uses Ansible from an Ubuntu controller, normally `vdi-control-01`, because the Windows host does not have a native Ansible runtime.

```bash
cd ~/vdiforge-phase3-validation
ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/phase3.yml --private-key ~/.ssh/vdiforge_ansible
```

The aggregate Phase 3 playbook imports:

1. `ansible/playbooks/baseline.yml`
2. `ansible/playbooks/kubernetes.yml`
3. `ansible/playbooks/cluster-addons.yml`

Temporary passwordless sudo may be used only for lab bootstrap when interactive sudo prompts block Ansible automation. Remove it after validation:

```bash
ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/remove-temporary-sudo.yml --private-key ~/.ssh/vdiforge_ansible
```

No kubeadm join token, admin kubeconfig, SSH private key, certificate private key, or other live credential is committed.

## Container Runtime

Phase 3 uses containerd and configures it for Kubernetes CRI:

- socket: `/run/containerd/containerd.sock`
- CRI socket for kubeadm: `unix:///run/containerd/containerd.sock`
- snapshotter: `overlayfs`
- cgroup driver: `systemd`
- pause image: `registry.k8s.io/pause:3.10.2`

Validation:

```bash
containerd --version
systemctl is-active containerd
crictl info
```

## Kubernetes Cluster

The control plane is initialized with kubeadm on `vdi-control-01` using `ansible/roles/kubernetes-control-plane/templates/kubeadm-init.yaml.j2`.

Important cluster settings:

| Setting | Value |
| --- | --- |
| Kubernetes version | `v1.36.4` |
| API endpoint | `192.168.56.10:6443` |
| pod CIDR | `10.244.0.0/16` |
| service CIDR | `10.96.0.0/12` |
| CRI socket | `unix:///run/containerd/containerd.sock` |
| kubelet node IP | host-only IP from inventory |

Workers join with a short-lived kubeadm token generated at deployment time. Tokens are not stored in Git.

Expected node result:

```text
vdi-control-01   Ready
vdi-worker-01    Ready
vdi-worker-02    Ready
```

## Node Placement

Phase 3 applies the logical labels established in the architecture:

| Node | Label |
| --- | --- |
| `vdi-worker-01` | `vdiforge.io/node-role=platform` |
| `vdi-worker-02` | `vdiforge.io/node-role=vdi` |

The control-plane node remains reserved for control-plane components. Normal VDIForge workloads are not intentionally scheduled there.

## Calico CNI

Calico v3.32.1 is installed through pinned Tigera operator manifests and a local custom resource:

- BGP disabled
- VXLAN encapsulation
- pod CIDR `10.244.0.0/16`
- Kubernetes NetworkPolicy support

Validation:

```bash
kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
kubectl get pods -n calico-system
kubectl get pods -n tigera-operator
```

## Metrics Server

Metrics Server v0.8.1 is installed to support future HPA work. The local lab patches Metrics Server to prefer node `InternalIP` addresses.

The patch currently includes `--kubelet-insecure-tls` because kubeadm's default kubelet serving certificates in this lab are not provisioned with a full trusted serving-certificate chain for Metrics Server. This is a documented local-lab exception and must be revisited before any non-lab deployment.

Validation:

```bash
kubectl top nodes
kubectl top pods -A
```

## KubeVirt

KubeVirt v1.9.0 is installed through the official pinned operator and custom resource manifests:

```bash
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/v1.9.0/kubevirt-operator.yaml
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/v1.9.0/kubevirt-cr.yaml
```

Validation:

```bash
kubectl get kubevirt -n kubevirt
kubectl get pods -n kubevirt
kubectl wait kubevirt/kubevirt -n kubevirt --for=condition=Available --timeout=180s
```

## KVM Verification

Phase 2 verified `/dev/kvm` inside `vdi-worker-02`. Phase 3 must also prove that KubeVirt exposes and consumes that capability.

Live validation checks:

```bash
kubectl get node vdi-worker-02 -o json | jq -r '.status.allocatable["devices.kubevirt.io/kvm"]'
kubectl get pod -n vdiforge-desktops -l kubevirt.io=virt-launcher,app.kubernetes.io/name=phase3-cirros -o json | jq -r '[.items[0].spec.containers[].resources.requests["devices.kubevirt.io/kvm"] // empty] | first'
```

Required final classification:

```text
KUBEVIRT_KVM_VERIFIED
```

Observed Phase 3 evidence:

```text
vdi-worker-02 capacity devices.kubevirt.io/kvm: 1k
vdi-worker-02 allocatable devices.kubevirt.io/kvm: 1k
phase3-cirros scheduled node: vdi-worker-02
phase3-cirros virt-launcher KVM request: 1
phase3-cirros guest IP during validation: 10.244.34.237
```

If KVM is unavailable, Phase 3 fails unless a later ADR explicitly changes the acceptance condition. Software emulation remains a development fallback, not equivalent hardware acceleration.

## CDI

CDI v1.66.0 is installed because the planned VDIForge image workflow needs DataVolumes to import or clone VM disk images into PVCs. Phase 3 does not build golden Ubuntu images; it uses CDI only to validate the KubeVirt image/storage foundation with a disposable test VM.

Validation:

```bash
kubectl get pods -n cdi
kubectl wait cdi/cdi -n cdi --for=condition=Available --timeout=180s
```

## Storage

Phase 3 uses Rancher local-path provisioner v0.0.32 with StorageClass `vdiforge-local-path`.

| Attribute | Value |
| --- | --- |
| Provisioner | `rancher.io/local-path` |
| StorageClass | `vdiforge-local-path` |
| Volume binding mode | `WaitForFirstConsumer` |
| Reclaim policy | `Delete` |
| Backing path | `/opt/local-path-provisioner` on the selected node |

This is intentionally simple and free. It is not physically highly available and does not support live migration semantics expected from distributed storage. Production alternatives may include distributed block storage, CSI drivers backed by cloud disks, or a purpose-built storage platform justified by a later ADR.

Because `vdiforge-local-path` uses `WaitForFirstConsumer`, later provisioners must create a schedulable workload that consumes a new PVC before waiting for the PVC/DataVolume to become ready. Phase 7 follows this by creating the per-desktop `DataVolume`, `VirtualMachine`, and Service before waiting for the clone to finish, which lets the PVC bind on the selected VDI worker. Phase 8 adds the per-desktop remote credential Secret needed by KubeVirt cloud-init and Guacamole brokering.

CDI qcow2 imports may require temporary scratch space during conversion. The local lab uses the same `vdiforge-local-path` StorageClass for scratch storage by setting CDI `scratchSpaceStorageClass` during Phase 8 source PVC preparation. This is a lab-appropriate choice, not a production HA storage design.

The storage decision is recorded in [ADR 0010](ADR/0010-local-path-storage-for-phase3.md).

## Namespace Foundation

Phase 3 creates only namespace foundations, not applications:

| Namespace | Purpose |
| --- | --- |
| `vdiforge-system` | Future VDIForge platform services |
| `vdiforge-desktops` | Future KubeVirt desktop resources and the disposable Phase 3 test VM |
| `keycloak` | Future identity service |
| `guacamole` | Guacamole remote desktop gateway |
| `monitoring` | Future Prometheus/Grafana resources |

The `vdiforge-desktops` namespace uses privileged pod security enforcement because KubeVirt VM launcher pods require privileges. Other VDIForge namespaces start at baseline enforcement with restricted audit/warn labels.

## RBAC Foundation

Phase 3 creates an initial least-privilege Kubernetes boundary for the future provisioner:

- ServiceAccount: `vdiforge-provisioner` in `vdiforge-system`
- Role: `vdiforge-provisioner-vdi-manager` in `vdiforge-desktops`
- RoleBinding from that Role to the ServiceAccount

The Role is namespace-scoped to KubeVirt, CDI, PVC, Service, Secret, Event, and read-only Pod resources needed for VM reconciliation and per-desktop remote credential management. It does not grant `cluster-admin`.

## NetworkPolicy Validation

Phase 3 proves that NetworkPolicy enforcement works without deploying the final application policy model.

Script:

```bash
bash scripts/phase3-networkpolicy-test.sh
```

The script:

1. Creates disposable namespace `vdiforge-netpol-test`.
2. Confirms client-to-server pod traffic initially works.
3. Applies a deny-ingress NetworkPolicy.
4. Confirms the traffic is blocked.
5. Applies an explicit allow policy.
6. Confirms intended traffic works again.
7. Deletes all disposable resources.

## Disposable KubeVirt Test VM

The primary Phase 3 functional test is a disposable CirrOS VM:

| Attribute | Value |
| --- | --- |
| VM | `phase3-cirros` |
| Namespace | `vdiforge-desktops` |
| Disk source | `https://download.cirros-cloud.net/0.6.3/cirros-0.6.3-x86_64-disk.img` |
| Storage | CDI DataVolumeTemplate using `vdiforge-local-path` |
| Scheduling | `nodeSelector: vdiforge.io/node-role=vdi` |
| Expected node | `vdi-worker-02` |

Script:

```bash
bash scripts/phase3-kubevirt-test-vm.sh
```

The manifest does not commit guest credentials. The script validates create, boot, `Running`, node placement, KVM resource request, guest interface IP, stop, restart, delete, and cleanup. This VM is not a VDIForge golden image and must not remain running after validation.

## Live Validation

Run static validation from the repository root:

```powershell
pwsh -NoProfile -File ./scripts/validate-phase3.ps1
```

Run live validation from `vdi-control-01` after the cluster is bootstrapped:

```bash
cd ~/vdiforge-phase3-validation
bash scripts/validate-phase3-live.sh
```

The live validator checks:

- Ansible syntax
- Ansible lint
- expected Kubernetes node count
- node Ready status
- expected node labels
- CoreDNS health
- Calico health
- Metrics Server health
- node and pod metrics
- StorageClass
- KubeVirt health
- CDI health
- KubeVirt KVM resource on `vdi-worker-02`
- NetworkPolicy enforcement
- disposable KubeVirt VM lifecycle

Latest live result:

```text
Ansible idempotency: changed=0, failed=0, unreachable=0 on all nodes
Phase 3 live validation: PASS
KubeVirt VM lifecycle: create, boot, stop, restart, delete, cleanup PASS
KubeVirt hardware acceleration: KUBEVIRT_KVM_VERIFIED
```

## Recovery Notes

Do not reset a healthy cluster merely to demonstrate rebuild behavior. Use targeted diagnostics first.

Common commands:

```bash
kubectl get nodes -o wide
kubectl describe node vdi-worker-02
kubectl get pods -A
kubectl describe pod -n kube-system <pod>
kubectl describe pod -n kubevirt <pod>
journalctl -u kubelet -n 200 --no-pager
journalctl -u containerd -n 200 --no-pager
```

If kubeadm initialization fails before a usable cluster exists, diagnose the preflight failure, correct the host issue, and then use kubeadm reset only with explicit operator intent. Do not run destructive reset commands as an unattended default.

## Scope Boundary

Phase 3 does not deploy:

- VDIForge Helm chart
- Keycloak configuration
- OIDC integration
- FastAPI API
- React portal
- Guacamole
- xrdp/VNC desktop integration
- Prometheus or Grafana
- Packer golden images
- final Ubuntu desktop images

The cluster ends Phase 3 as a Kubernetes/KubeVirt foundation only.

Phase 4 builds on this cluster with Helm-managed VDIForge platform foundation resources. See [Helm Platform Foundation](HELM-PLATFORM.md) for chart ownership, lifecycle validation, quotas, RBAC, and NetworkPolicy conventions.

Phase 5 adds Keycloak/OIDC/RBAC on top of this foundation without modifying KubeVirt. See [Keycloak, OIDC, and RBAC Foundation](KEYCLOAK-OIDC.md).

Phase 6 uses the existing KubeVirt, CDI, and `vdiforge-local-path` foundation to validate a generated Ubuntu golden-image artifact. The `ubuntu-devops:1.0.0` QCOW2 is imported through CDI into a disposable DataVolume/PVC, booted as a KubeVirt VM scheduled with `vdiforge.io/node-role=vdi`, verified on `vdi-worker-02` with a `devices.kubevirt.io/kvm` launcher request, and then cleaned up. See [Golden Images](GOLDEN-IMAGES.md).

Phase 7 uses the same KubeVirt/CDI/storage foundation to clone promoted source PVCs into per-desktop DataVolumes and to create KubeVirt `VirtualMachine` resources from the provisioner. Phase 8 uses `ubuntu-devops:1.1.0` for remote desktop validation and restricts RDP access to the Guacamole path. See [FastAPI VDI Control Plane](API-CONTROL-PLANE.md) and [Remote Desktop Delivery](REMOTE-DESKTOP.md).
