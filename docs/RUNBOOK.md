# Operations Runbook

This runbook defines troubleshooting procedures for the VDIForge local lab and planned platform. Kubernetes foundation commands apply to Phase 3 and application commands apply to later phases where noted.

## VirtualBox VM Does Not Start

| Area | Detail |
| --- | --- |
| Symptoms | VM fails to power on, exits immediately, or reports virtualization-related startup errors. |
| Likely causes | Windows hypervisor still active, virtualization disabled in firmware, insufficient host RAM, stale VirtualBox process, corrupt VM metadata. |
| Diagnostics | Check VirtualBox error dialog; verify Windows features for Hyper-V/Virtual Machine Platform; inspect VM Settings -> System -> Acceleration; run `systeminfo` on Windows; check available RAM. |
| Remediation | Shut down other VMs, reboot host, confirm virtualization is enabled in BIOS/UEFI, keep Hyper-V disabled for the VirtualBox nested-virtualization lab, recreate only the affected VM if metadata is corrupt. |
| Logs/metrics | VirtualBox VM log under `F:\VirtualBox VMs\<vm-name>\Logs`, Windows Event Viewer, host RAM usage. |

## Host-Only IP Missing

| Area | Detail |
| --- | --- |
| Symptoms | `ip -br addr` in a guest does not show `192.168.56.x/24` on `enp0s8`; host cannot SSH to the node. |
| Likely causes | Adapter 2 not enabled, Adapter 2 attached to the wrong network, netplan static address missing, netplan not applied. |
| Diagnostics | In VirtualBox verify Adapter 2 is `Host-only Adapter` using `VirtualBox Host-Only Ethernet Adapter`; in the guest run `ip -br addr`, `ip route`, and `sudo netplan get`. |
| Remediation | Power off the VM, correct Adapter 2, boot the VM, add the documented static `enp0s8` address, then run `sudo netplan apply`. Do not set a default gateway on the host-only adapter. |
| Logs/metrics | `journalctl -u systemd-networkd` or NetworkManager logs, netplan apply output. |

## Host SSH Failure

| Area | Detail |
| --- | --- |
| Symptoms | `ssh vdiadmin@192.168.56.10`, `.11`, or `.12` fails from Windows. |
| Likely causes | Guest SSH server not installed or not running, wrong host-only IP, Windows host-only adapter down, firewall policy, wrong credentials. |
| Diagnostics | From Windows run `ping 192.168.56.x`; from guest run `systemctl status ssh`, `ip -br addr`, and `sudo ss -tlnp | grep :22`. |
| Remediation | Start SSH with `sudo systemctl enable --now ssh`, correct netplan, confirm the host-only adapter is enabled, use the documented `vdiadmin` account, move to key-based SSH before disabling password auth. |
| Logs/metrics | Guest `journalctl -u ssh`, Windows OpenSSH client error, VirtualBox network settings. |

## Node-to-Node Ping Failure

| Area | Detail |
| --- | --- |
| Symptoms | One VM cannot ping another VM on `192.168.56.0/24`. |
| Likely causes | One node has the wrong host-only IP, Adapter 2 disconnected, duplicate IP, local firewall. |
| Diagnostics | On each node run `ip -br addr`; run pings between all pairs; verify all VMs use the same host-only adapter. |
| Remediation | Correct static IP assignment, reconnect Adapter 2, remove duplicate IPs, restart networking with `sudo netplan apply`. |
| Logs/metrics | Netplan state, systemd-networkd logs, VirtualBox adapter configuration. |

## `/dev/kvm` Missing on `vdi-worker-02`

| Area | Detail |
| --- | --- |
| Symptoms | `ls -l /dev/kvm` reports no such file; `grep -E '(vmx|svm)' /proc/cpuinfo` returns nothing. |
| Likely causes | Nested VT-x/AMD-V not enabled for `vdi-worker-02`, Windows hypervisor active, host firmware virtualization disabled, VM booted before setting change. |
| Diagnostics | Power off the VM and check VirtualBox Settings -> System -> Processor -> Nested VT-x/AMD-V; inside the guest run `grep -E -m 5 '(vmx|svm)' /proc/cpuinfo` and `ls -l /dev/kvm`. |
| Remediation | Shut down the VM, disable the Windows hypervisor path used during Phase 2, reboot Windows, enable Nested VT-x/AMD-V for `vdi-worker-02`, boot the guest, recheck `/dev/kvm`. |
| Logs/metrics | VirtualBox VM log, guest `dmesg | grep -i kvm`, `/proc/cpuinfo`. |

## Local Disk Capacity

| Area | Detail |
| --- | --- |
| Symptoms | VM creation fails, VM pauses, package installation fails, or disk images cannot grow. |
| Likely causes | Insufficient free space on `F:`, dynamic VDI growth, orphaned VM folders, ISO or logs consuming space. |
| Diagnostics | Check Windows drive free space; inspect `F:\VirtualBox VMs`; use VirtualBox Media Manager for orphaned disks. |
| Remediation | Delete only intentionally removed VM folders, prune old ISOs and logs, keep Terraform state and credentials out of Git, recreate affected VMs only from the documented procedure. |
| Logs/metrics | Windows drive properties, VirtualBox Media Manager, VM logs. |

## Phase 6 Build Host Not Ready

| Area | Detail |
| --- | --- |
| Symptoms | `scripts/validate-phase6-live.sh` reports that the Phase 6 build host is not ready; `packer`, `qemu-system-x86_64`, `virt-sysprep`, `ansible-lint`, `/dev/kvm`, or `/boot/vmlinuz-*` checks fail. |
| Likely causes | `scripts/phase6-install-build-tools.sh` has not been run on `vdi-worker-02`, the current SSH session has not picked up `kvm` group membership, the current kernel image is not readable by the build user for libguestfs, or nested virtualization regressed. |
| Diagnostics | On `vdi-worker-02`, run `command -v packer`, `qemu-system-x86_64 --version`, `virt-sysprep --version`, `ansible-lint --version`, `ls -l /dev/kvm`, `ls -l /boot/vmlinuz-$(uname -r)`, `id`, and `groups`. |
| Remediation | Copy or clone the repository to `~/vdiforge-phase6-build`, run `sudo bash scripts/phase6-install-build-tools.sh`, start a new SSH session, verify `/dev/kvm` is readable and writable by the build user and `/boot/vmlinuz-$(uname -r)` is readable, then rerun live validation. |
| Logs/metrics | Build-host command output, `/tmp/vdiforge-phase6-*` logs, `kubectl top nodes`. |

## Packer Source Checksum Failure

| Area | Detail |
| --- | --- |
| Symptoms | Packer fails before booting the build VM with an Ubuntu source checksum mismatch. |
| Likely causes | The upstream Ubuntu cloud image was refreshed after the pinned checksum was recorded, the download is corrupt, or the source URL was changed without updating the checksum. |
| Diagnostics | Compare `packer/ubuntu-*/variables.pkr.hcl` against the official Ubuntu `SHA256SUMS`; inspect Packer download logs; remove only the relevant ignored `packer_cache` entry and retry. |
| Remediation | If Ubuntu intentionally published a new image revision, update the source checksum in all three templates and document the new source date. Do not bypass checksum validation. |
| Logs/metrics | Packer output, official Ubuntu cloud-image release directory, local `packer_cache`. |

## Packer Image Build Failure

| Area | Detail |
| --- | --- |
| Symptoms | `phase6-build-image.sh` or `phase6-build-all.sh` fails during SSH, Ansible provisioning, package installation, image validation, shutdown, or artifact generalization. |
| Likely causes | Build host lacks KVM access, insufficient RAM/disk, Ubuntu package mirror issue, Packer SSH timeout, QEMU process left behind, Ansible role error, unreadable `/boot/vmlinuz-*` for libguestfs, or `virt-sysprep` failure. |
| Diagnostics | On `vdi-worker-02`, run `df -h`, `free -h`, `ps aux | grep qemu`, `packer version`, `qemu-img info <artifact>`, `libguestfs-test-tool`, and inspect the Packer console output. |
| Remediation | Stop stale QEMU processes only after confirming they belong to the failed Packer build, rerun `sudo bash scripts/phase6-install-build-tools.sh` after host kernel updates, free disk space, rerun the specific image build, and keep builds sequential. Do not commit partial artifacts. |
| Logs/metrics | Packer build output, `artifacts/images/<image>/<version>/`, `/tmp`, `kubectl top nodes`. |

## CDI Import Failure For Golden Image

| Area | Detail |
| --- | --- |
| Symptoms | Phase 6 or Phase 8 DataVolume does not reach Ready; importer pod fails; PVC remains Pending; DataVolume condition says `scratch space required and none found`. |
| Likely causes | Temporary HTTP artifact endpoint unreachable, checksum mismatch, insufficient storage, local-path provisioner issue, CDI pod failure, or CDI scratch storage class not configured for qcow2 conversion. |
| Diagnostics | `kubectl get datavolume,pvc -n vdiforge-desktops`; `kubectl describe datavolume <name> -n vdiforge-desktops`; `kubectl get cdiconfig config -o jsonpath='{.status.scratchSpaceStorageClass}'`; `kubectl get pods -n cdi`; check `curl -I http://192.168.56.12:18080/<artifact>` or the Phase 8 import port. |
| Remediation | Restart the temporary artifact HTTP server, verify the artifact checksum, confirm `vdiforge-local-path` exists, free space on `vdi-worker-02`, configure CDI scratch storage with `kubectl patch cdi cdi -n cdi --type merge --patch '{"spec":{"config":{"scratchSpaceStorageClass":"vdiforge-local-path"}}}'`, delete only the incomplete DataVolume/PVC, and rerun the relevant Phase 6 or Phase 8 import script. |
| Logs/metrics | CDI importer pod logs, DataVolume conditions, local-path provisioner logs, `/tmp/vdiforge-phase6-image-http.log` on `vdi-worker-02`. |

## Phase 6 KubeVirt Boot Validation Failure

| Area | Detail |
| --- | --- |
| Symptoms | `phase6-ubuntu-devops` VMI does not reach Running/Ready, schedules on the wrong node, does not request KVM, guest SSH never becomes ready, or DevOps tool checks fail. |
| Likely causes | Node label missing, KVM resource unavailable, image did not generalize correctly, cloud-init failed, SSH key injection failed, guest networking failed, or required tools were not installed. |
| Diagnostics | `kubectl get vmi,vm,pods -n vdiforge-desktops -o wide`; `kubectl describe vmi phase6-ubuntu-devops -n vdiforge-desktops`; inspect virt-launcher pod resources for `devices.kubevirt.io/kvm`; use `virtctl console` only when needed. |
| Remediation | Verify `vdi-worker-02` has `vdiforge.io/node-role=vdi` and KVM allocatable, rebuild the image if tool validation fails, inspect cloud-init in the guest, and rerun cleanup with `bash scripts/phase6-cdi-kubevirt-test.sh --cleanup-only` before retrying. |
| Logs/metrics | VMI conditions, virt-launcher pod logs, KubeVirt events, guest cloud-init logs when reachable, `kubectl top nodes`. |

## Phase 2 Rebuild Procedure

| Area | Detail |
| --- | --- |
| Symptoms | A node is misconfigured beyond quick repair or needs a clean rebuild. |
| Likely causes | Wrong OS selection, wrong disk size, wrong hostname, incorrect network adapter order, failed manual configuration. |
| Diagnostics | Compare the VM to [Local Infrastructure](LOCAL-INFRASTRUCTURE.md); inspect VM Settings -> System, Storage, Network; verify `ip -br addr`, hostname, and disk size. |
| Remediation | Shut down the affected VM, remove only that VM in VirtualBox, delete only that VM folder under `F:\VirtualBox VMs`, recreate it with documented values, reapply static networking, then validate ping, SSH, and `/dev/kvm` where applicable. |
| Logs/metrics | VirtualBox metadata, validation script output, manual ping/SSH evidence. |

## Control Plane API Pressure

| Area | Detail |
| --- | --- |
| Symptoms | `kubectl` commands hang or time out, Ansible reports OpenAPI/TLS handshake timeouts, add-on pods restart during reconciliation, and SSH to `vdi-control-01` is delayed. |
| Likely causes | Control-plane VM undersized for Kubernetes, Calico, Metrics Server, KubeVirt, and CDI; many add-on controllers reconciling at once; no swap; host CPU pressure. |
| Diagnostics | On `vdi-control-01`, run `uptime`, `free -h`, `kubectl top nodes`, `kubectl get pods -A`, and inspect kube-apiserver/controller-manager restart counts. From Windows, verify VM resources with `VBoxManage showvminfo vdi-control-01 --machinereadable`. |
| Remediation | Prefer waiting for reconciliation to settle, then rerun validation. If pressure remains sustained, gracefully shut down `vdi-control-01`, increase it to the documented 4 vCPU / 6144 MiB allocation, restart it, wait for Kubernetes to recover, and rerun Phase 3 idempotency and live validation. |
| Logs/metrics | `kubectl top nodes`, kube-apiserver logs, controller-manager logs, VirtualBox VM metadata, Ansible timeout output. |

## Kubernetes Node NotReady

| Area | Detail |
| --- | --- |
| Symptoms | `kubectl get nodes` shows `NotReady`; pods evicted or stuck; desktops unavailable on affected node. |
| Likely causes | kubelet down, containerd down, network outage, disk pressure, host reboot, CNI failure. |
| Diagnostics | `kubectl describe node <node>`; `kubectl get events -A --sort-by=.lastTimestamp`; `systemctl status kubelet`; `systemctl status containerd`; `journalctl -u kubelet -xe`; for VDI worker disk pressure also check `df -h /` on `vdi-worker-02`. |
| Remediation | Restore host/network, restart failed services, clear disk pressure, verify CNI pods, cordon/drain only when safe. If Phase 9 validation already imported `ubuntu-devops:1.2.0` into CDI, it is safe to remove the generated QCOW2 file from the ignored Phase 6 build artifact directory while leaving the CDI source PVC in place. |
| Logs/metrics | Node conditions, kubelet logs, containerd logs, Calico pod logs, node CPU/memory/disk metrics. |

## kubeadm Initialization Failure

| Area | Detail |
| --- | --- |
| Symptoms | `ansible/playbooks/phase3.yml` fails during control-plane initialization; `/etc/kubernetes/admin.conf` is absent. |
| Likely causes | containerd not active, swap enabled, missing kernel modules, port `6443` conflict, package mismatch, host-only IP not bound. |
| Diagnostics | `systemctl status containerd`; `systemctl status kubelet`; `journalctl -u kubelet -n 200 --no-pager`; `sudo kubeadm init phase preflight --config /etc/kubernetes/kubeadm-init.yaml`; `ip -br addr`. |
| Remediation | Fix the failing preflight condition, rerun the Ansible playbook, and avoid `kubeadm reset` unless initialization partially succeeded and the operator explicitly chooses a rebuild. |
| Logs/metrics | kubeadm output, kubelet logs, containerd logs, `/var/log/syslog`. |

## Worker Join Failure

| Area | Detail |
| --- | --- |
| Symptoms | One or both workers are missing from `kubectl get nodes`; Ansible fails during `kubernetes-worker`. |
| Likely causes | expired join token, API endpoint unreachable, wrong CRI socket, kubelet package mismatch, host-only network issue. |
| Diagnostics | From worker: `nc -vz 192.168.56.10 6443`; `systemctl status kubelet`; `journalctl -u kubelet -n 200 --no-pager`; from control: `kubeadm token list`. |
| Remediation | Confirm host-only network reachability, rerun the Phase 3 playbook to generate a fresh short-lived token, and inspect kubelet logs before any reset. |
| Logs/metrics | kubelet logs, kubeadm join output, control-plane API server logs. |

## Calico Failure

| Area | Detail |
| --- | --- |
| Symptoms | Nodes remain NotReady after kubeadm, CoreDNS Pending/NotReady, or pod networking fails. |
| Likely causes | Calico operator not Available, wrong pod CIDR, image pull failure, host firewall or kernel module issue. |
| Diagnostics | `kubectl get tigerastatus`; `kubectl get pods -n tigera-operator`; `kubectl get pods -n calico-system`; `kubectl describe installation default`; `kubectl get ippools.crd.projectcalico.org -o yaml`. |
| Remediation | Confirm pod CIDR `10.244.0.0/16` matches kubeadm config, fix image pull or network issues, reapply pinned Calico manifests, and rerun live validation. |
| Logs/metrics | Tigera operator logs, Calico node logs, node conditions. |

## CoreDNS Failure

| Area | Detail |
| --- | --- |
| Symptoms | `kubectl -n kube-system rollout status deployment/coredns` fails; pods cannot resolve service names. |
| Likely causes | CNI not ready, CoreDNS image pull failure, insufficient resources, malformed CoreDNS config. |
| Diagnostics | `kubectl get pods -n kube-system -l k8s-app=kube-dns`; `kubectl describe pod -n kube-system -l k8s-app=kube-dns`; `kubectl logs -n kube-system deploy/coredns`. |
| Remediation | Fix CNI first, confirm node readiness, then restart CoreDNS only if configuration and networking are healthy. |
| Logs/metrics | CoreDNS logs, pod events, Calico status. |

## Metrics Server Failure

| Area | Detail |
| --- | --- |
| Symptoms | `kubectl top nodes` fails; Metrics Server pod is not Ready. |
| Likely causes | kubelet serving certificate trust issue, wrong preferred node address, image pull failure, API aggregation issue. |
| Diagnostics | `kubectl logs -n kube-system deploy/metrics-server`; `kubectl describe apiservice v1beta1.metrics.k8s.io`; `kubectl get endpoints -n kube-system metrics-server`. |
| Remediation | In the local lab, confirm the documented `metrics-server-local-patch.yaml` is applied. For non-lab environments, provision proper kubelet serving certificates instead of relying on `--kubelet-insecure-tls`. |
| Logs/metrics | Metrics Server logs, APIService status, kube-apiserver aggregation errors. |

## KubeVirt Failure

| Area | Detail |
| --- | --- |
| Symptoms | `kubectl wait kubevirt/kubevirt -n kubevirt --for=condition=Available` fails; virt pods Pending or CrashLoopBackOff. |
| Likely causes | unsupported Kubernetes/KubeVirt version pair, missing privileges, image pull failure, no schedulable nodes, KVM device issue. |
| Diagnostics | `kubectl get kubevirt -n kubevirt -o yaml`; `kubectl get pods -n kubevirt`; `kubectl logs -n kubevirt deploy/virt-operator`; `kubectl describe ds -n kubevirt virt-handler`. |
| Remediation | Verify selected versions, inspect operator logs, confirm node health, confirm `vdi-worker-02` exposes `/dev/kvm`, and reapply pinned KubeVirt manifests if needed. |
| Logs/metrics | virt-operator logs, virt-handler logs, KubeVirt conditions. |

## KubeVirt KVM Resource Missing

| Area | Detail |
| --- | --- |
| Symptoms | `devices.kubevirt.io/kvm` is missing or zero on `vdi-worker-02`; test VM does not request KVM. |
| Likely causes | `/dev/kvm` unavailable inside the node, nested virtualization disabled after reboot, KubeVirt virt-handler not running on the node, node label mismatch. |
| Diagnostics | On `vdi-worker-02`: `ls -l /dev/kvm`, `grep -E -m 5 '(vmx|svm)' /proc/cpuinfo`; in Kubernetes: `kubectl describe node vdi-worker-02`; `kubectl get pods -n kubevirt -o wide`. |
| Remediation | Shut down the VM, re-enable VirtualBox Nested VT-x/AMD-V, ensure the Windows hypervisor remains disabled for this lab, boot the node, and restart/reconcile KubeVirt. Do not switch to software emulation unless an ADR changes Phase 3 acceptance. |
| Logs/metrics | guest `dmesg`, virt-handler logs, node allocatable resources. |

## Disposable KubeVirt Test VM Failure

| Area | Detail |
| --- | --- |
| Symptoms | `scripts/phase3-kubevirt-test-vm.sh` fails, DataVolume not Ready, VMI not Running, or VM schedules on the wrong node. |
| Likely causes | CDI unavailable, storage provisioning failure, local-path capacity issue, node selector missing, KVM resource unavailable, image download failure. |
| Diagnostics | `kubectl get vm,vmi,dv,pvc -n vdiforge-desktops`; `kubectl describe datavolume phase3-cirros-dv -n vdiforge-desktops`; `kubectl describe vmi phase3-cirros -n vdiforge-desktops`; `kubectl get pods -n vdiforge-desktops -o wide`. |
| Remediation | Fix CDI/storage/KVM root cause, run `bash scripts/phase3-kubevirt-test-vm.sh --cleanup-only`, then rerun the test. The disposable VM should not remain running after validation. |
| Logs/metrics | CDI importer logs, PVC events, virt-launcher logs, VMI conditions. |

## Storage Provisioning Failure

| Area | Detail |
| --- | --- |
| Symptoms | PVC or DataVolume remains Pending; local-path provisioner pod is unhealthy; test VM cannot attach disk. |
| Likely causes | local-path provisioner not running, no backing directory, disk full, node affinity mismatch, image import failure. |
| Diagnostics | `kubectl get storageclass`; `kubectl get pods -n local-path-storage`; `kubectl logs -n local-path-storage deploy/local-path-provisioner`; `kubectl describe pvc -n vdiforge-desktops phase3-cirros-dv`; `df -h /opt/local-path-provisioner`. |
| Remediation | Restore local-path provisioner, create/fix `/opt/local-path-provisioner`, free disk space, delete failed disposable test resources, and rerun validation. |
| Logs/metrics | local-path provisioner logs, PVC events, node disk metrics. |

## Pod Pending

| Area | Detail |
| --- | --- |
| Symptoms | Platform pod or virt-launcher pod remains `Pending`. |
| Likely causes | insufficient CPU/memory, unbound PVC, node selector mismatch, taint without toleration, image pull issue. |
| Diagnostics | `kubectl describe pod <pod> -n <namespace>`; `kubectl get events -n <namespace>`; `kubectl describe pvc <pvc> -n <namespace>`; `kubectl get nodes --show-labels`. |
| Remediation | Adjust resource requests, fix storage class/PVC, correct labels/affinity, add justified toleration, resolve image pull credentials. |
| Logs/metrics | Scheduler events, PVC events, node allocatable metrics, HPA state. |

## CrashLoopBackOff

| Area | Detail |
| --- | --- |
| Symptoms | Pod restarts repeatedly; service unavailable. |
| Likely causes | bad configuration, missing Secret, failed database connection, failed startup migration, image bug. |
| Diagnostics | `kubectl logs <pod> -n <namespace> --previous`; `kubectl describe pod <pod> -n <namespace>`; `kubectl get configmap,secret -n <namespace>`. |
| Remediation | Fix configuration, restore missing dependency, roll back image or chart version, inspect readiness/liveness probes. |
| Logs/metrics | Container logs, restart count, readiness probe failures, API error rate. |

## Insufficient Cluster Resources

| Area | Detail |
| --- | --- |
| Symptoms | Desktop launch denied, VM Pending, scheduler reports insufficient CPU or memory. |
| Likely causes | too many active desktops, resource profiles too large, platform pods consuming VDI worker capacity. |
| Diagnostics | `kubectl describe pod <virt-launcher-pod> -n vdiforge-desktops`; `kubectl top nodes`; `kubectl top pods -A`; `kubectl describe node vdi-worker-02`. |
| Remediation | Delete unused desktops, reduce resource profile size, move platform workloads, add capacity in future phases. |
| Logs/metrics | Active desktops, failed desktops, scheduler events, node CPU/memory. |

## Storage Exhaustion

| Area | Detail |
| --- | --- |
| Symptoms | PVC pending, VM disk errors, database writes fail, image import fails. |
| Likely causes | local storage full, orphaned PVCs, oversized images, no storage quota. |
| Diagnostics | `kubectl get pvc -A`; `kubectl describe pvc <pvc> -n <namespace>`; `df -h`; storage provisioner logs. |
| Remediation | Delete orphaned resources, expand storage if available, prune old image artifacts, lower desktop quotas. |
| Logs/metrics | PVC status, node disk metrics, provisioner cleanup logs. |

## Helm Release Install or Upgrade Failure

| Area | Detail |
| --- | --- |
| Symptoms | `helm upgrade --install vdiforge ./helm/vdiforge` fails, release status is `failed`, or expected VDIForge foundation resources are missing. |
| Likely causes | chart rendering error, Kubernetes schema rejection, existing Phase 3 RBAC resources not adopted, missing namespace, API-server pressure, insufficient permissions. |
| Diagnostics | `helm lint ./helm/vdiforge`; `helm template vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --kube-version 1.36.4`; `helm upgrade --install vdiforge ./helm/vdiforge --namespace vdiforge-system --values ./helm/vdiforge/values-local.yaml --take-ownership --force-conflicts --dry-run=server`; `helm status vdiforge --namespace vdiforge-system`; `helm history vdiforge --namespace vdiforge-system`; `kubectl get events -n vdiforge-system --sort-by=.lastTimestamp`. |
| Remediation | Fix chart or values, confirm `vdiforge-system` exists, include `--take-ownership --force-conflicts` for the first Phase 4 adoption on this lab, wait for API pressure to settle, then rerun the Phase 4 live validator. |
| Logs/metrics | Helm status/history, Kubernetes events, API-server logs, `scripts/validate-phase4-live.sh` output. |

## Helm Ownership Drift

| Area | Detail |
| --- | --- |
| Symptoms | Manual `kubectl edit` changes disappear after a Helm upgrade, Helm reports unexpected diffs, or live resources no longer match chart values. |
| Likely causes | Operators edited Helm-managed objects directly, chart values changed without review, failed rollback left an unexpected revision active. |
| Diagnostics | `helm get values vdiforge --namespace vdiforge-system`; `helm get manifest vdiforge --namespace vdiforge-system`; `kubectl get <resource> -n <namespace> -o yaml`; compare the live object to `helm template` output. |
| Remediation | Make intended changes in Git through chart templates or values, run lint/render validation, upgrade the release, and use `helm rollback` only to return to a known previous revision. |
| Logs/metrics | Helm manifest, Helm revision history, Git diff, Kubernetes managed fields. |

## Helm Rollback Required

| Area | Detail |
| --- | --- |
| Symptoms | A Helm upgrade succeeds but causes incorrect foundation resource values, bad quotas, or unexpected NetworkPolicy behavior. |
| Likely causes | Incorrect local values, faulty chart template change, unsafe quota or policy adjustment. |
| Diagnostics | `helm history vdiforge --namespace vdiforge-system`; `helm status vdiforge --namespace vdiforge-system`; inspect the affected resources with `kubectl describe`. |
| Remediation | Identify the last known-good revision and run `helm rollback vdiforge <revision> --namespace vdiforge-system --force-conflicts --wait`. After rollback, rerun Phase 4 live validation and document the faulty change before attempting another upgrade. |
| Logs/metrics | Helm revision history, Kubernetes events, validation script output. |

## ResourceQuota or LimitRange Blocks a Future Phase

| Area | Detail |
| --- | --- |
| Symptoms | Future platform pods or VM resources fail to create with quota or limit errors. |
| Likely causes | Lab-safe Phase 4 quota too restrictive, missing explicit resource requests, desktop resource profile larger than the local lab can support. |
| Diagnostics | `kubectl describe resourcequota -n vdiforge-system`; `kubectl describe resourcequota -n vdiforge-desktops`; `kubectl describe limitrange -n vdiforge-system`; inspect scheduler events for the rejected object. |
| Remediation | Adjust `helm/vdiforge/values-local.yaml`, run Helm lint/template validation, perform a Helm upgrade, and avoid manual live edits that create drift. |
| Logs/metrics | Admission error messages, ResourceQuota usage, Kubernetes events, Helm values. |

## Helm-Managed NetworkPolicy Blocks Traffic

| Area | Detail |
| --- | --- |
| Symptoms | A future platform pod in `vdiforge-system` cannot resolve DNS or reach an explicitly required service. |
| Likely causes | Default-deny policy is active without a matching allow policy, pod labels do not match the intended policy selector, service port differs from the documented path. |
| Diagnostics | `kubectl get networkpolicy -n vdiforge-system`; `kubectl describe networkpolicy -n vdiforge-system`; run a temporary debug pod only if the phase allows it; inspect pod labels and service endpoints. |
| Remediation | Add a narrow explicit allow policy in the appropriate future phase, keep DNS egress enabled, update Helm values/templates, and validate with a targeted NetworkPolicy test. |
| Logs/metrics | Pod connectivity errors, CoreDNS logs, Calico status, Kubernetes events. |

## Phase 7 Container Image Build Failure

| Area | Detail |
| --- | --- |
| Symptoms | `scripts/phase7-build-load-image.sh` fails before the Helm deployment; `podman` or `buildah` is missing on `vdi-worker-01`; API pods later report `ImagePullBackOff`. |
| Likely causes | Phase 7 build tools were not installed on the platform worker, local image was not imported into containerd, temporary importer pod was blocked, or outbound image pull failed. |
| Diagnostics | On `vdi-worker-01`, run `command -v podman`, `podman --version`, `ctr --version`; from `vdi-control-01`, run `kubectl get pod -n vdiforge-desktops phase7-image-importer`; inspect `kubectl describe pod -n vdiforge-system -l app.kubernetes.io/component=api`. |
| Remediation | Prefer installing a persistent builder with `sudo apt-get update && sudo apt-get install -y podman` on `vdi-worker-01`. If Podman/Buildah is unavailable, rerun `scripts/phase7-build-load-image.sh` from `vdi-control-01`; it can use a temporary BuildKit validation pod and importer pod in `vdiforge-desktops`. Confirm API/provisioner images use the phase-selected `localhost/vdiforge-api` tag, restart the Deployments after same-tag image import, then rerun the relevant live validation. |
| Logs/metrics | Podman build output, importer pod logs, kubelet image pull events, containerd image list. |

## VDIForge API Unavailable

| Area | Detail |
| --- | --- |
| Symptoms | `https://api.vdiforge.local/api/v1/health` fails, API ingress returns 404/502, or API pod is not Ready. |
| Likely causes | API image not imported on `vdi-worker-01`, app PostgreSQL unavailable, migration failure, wrong TLS secret, Traefik route missing, NetworkPolicy denial, or bad Keycloak JWKS configuration. |
| Diagnostics | `kubectl -n vdiforge-system get deploy,svc,ingress,pod`; `kubectl -n vdiforge-system logs deploy/vdiforge-api`; `kubectl -n vdiforge-system describe ingress vdiforge-api`; `curl --cacert .local/phase5/tls/vdiforge-local-ca.crt --resolve api.vdiforge.local:443:192.168.56.11 https://api.vdiforge.local/api/v1/health`. |
| Remediation | Fix the failing dependency, rerun `scripts/phase7-create-local-secrets.sh`, rerun Helm upgrade with Phase 7 values, and validate health/readiness without using `curl -k` as final evidence. A brief 502 immediately after `kubectl rollout restart deployment/vdiforge-api` can be a normal ingress-to-pod transition; retry for a bounded period before treating it as a failure. |
| Logs/metrics | API logs, Traefik logs, Kubernetes events, readiness probe errors. |

## VDIForge App PostgreSQL Unavailable

| Area | Detail |
| --- | --- |
| Symptoms | `vdiforge-app-postgres-0` is not Ready; API readiness reports database failure; migration job fails to connect. |
| Likely causes | missing `vdiforge-app-secrets`, PVC not bound, local-path storage pressure, wrong database password key, accidental password rotation after PostgreSQL initialized, resource quota, or PostgreSQL image pull issue. |
| Diagnostics | `kubectl -n vdiforge-system get statefulset,pod,pvc,secret vdiforge-app-secrets`; `kubectl -n vdiforge-system logs statefulset/vdiforge-app-postgres`; `kubectl -n vdiforge-system logs job/vdiforge-api-migrations`; `kubectl -n vdiforge-system describe pod vdiforge-app-postgres-0`; `kubectl describe resourcequota -n vdiforge-system`. |
| Remediation | Preserve the existing app DB password when rerunning `scripts/phase7-create-local-secrets.sh`; if the Secret was accidentally rotated, restore it from the running PostgreSQL pod environment without printing the value, then rerun Helm upgrade. Restore local-path storage, fix quota or image pull issues, and do not delete the PostgreSQL PVC unless intentionally resetting application state. |
| Logs/metrics | PostgreSQL logs, PVC events, ResourceQuota usage, local-path provisioner logs. |

## VDIForge Migration Job Failure

| Area | Detail |
| --- | --- |
| Symptoms | Helm upgrade with `--wait-for-jobs` times out; `vdiforge-api-migrations` fails; API starts without expected tables. |
| Likely causes | database unavailable, wrong `VDIFORGE_DATABASE_URL`, Alembic migration error, read-only filesystem issue, image mismatch, or old failed Job still present. |
| Diagnostics | `kubectl -n vdiforge-system get job,pod -l app.kubernetes.io/component=migration`; `kubectl -n vdiforge-system logs job/vdiforge-api-migrations`; `helm status vdiforge -n vdiforge-system`; inspect `backend/alembic/versions`. |
| Remediation | Fix the migration or database issue, delete only the old `vdiforge-api-migrations` Job if Kubernetes job immutability blocks retry, rerun Helm upgrade, and verify `/api/v1/ready`. Do not delete application PostgreSQL data unless intentionally resetting the lab. |
| Logs/metrics | Migration job logs, PostgreSQL logs, Helm status/history. |

## VDIForge Provisioner Unavailable Or Denied

| Area | Detail |
| --- | --- |
| Symptoms | Desktop requests remain `REQUESTED` or `PROVISIONING`; provisioner logs show Kubernetes `403` errors. |
| Likely causes | provisioner Deployment down, ServiceAccount token not mounted, RBAC missing or too narrow, NetworkPolicy blocks Kubernetes API, source PVC unavailable, or KubeVirt/CDI failure. |
| Diagnostics | `kubectl -n vdiforge-system logs deploy/vdiforge-provisioner`; `bash scripts/phase7-rbac-test.sh`; `kubectl auth can-i create virtualmachines.kubevirt.io -n vdiforge-desktops --as=system:serviceaccount:vdiforge-system:vdiforge-provisioner`; `kubectl get dv,vm,vmi,pvc,svc -n vdiforge-desktops`. |
| Remediation | Restore the Helm-managed Role/RoleBinding, verify `vdiforge-system-provisioner-kubernetes-api` NetworkPolicy, restore the golden source PVC, and rerun live validation. Do not grant `cluster-admin` to bypass the failure. |
| Logs/metrics | Provisioner logs, Kubernetes events, audit events, DataVolume conditions. |

## Keycloak Unavailable

| Area | Detail |
| --- | --- |
| Symptoms | Login fails; OIDC discovery is unavailable; PKCE validation fails; future API readiness fails when it depends on issuer metadata. |
| Likely causes | Keycloak pod down, PostgreSQL unavailable, bad realm import, ingress/TLS issue, DNS problem, ResourceQuota pressure on `vdi-worker-01`. |
| Diagnostics | `kubectl -n keycloak get pods,svc,ingress,pvc`; `kubectl -n keycloak describe deployment/vdiforge-keycloak`; `kubectl -n keycloak logs deployment/vdiforge-keycloak`; `kubectl -n keycloak get events --sort-by=.lastTimestamp`; `curl --cacert .local/phase5/tls/vdiforge-local-ca.crt --resolve auth.vdiforge.local:443:192.168.56.11 https://auth.vdiforge.local/realms/vdiforge/.well-known/openid-configuration`. |
| Remediation | Wait for rollout, fix PostgreSQL, correct ingress/DNS/TLS, verify runtime secrets exist, rerun `scripts/phase5-configure-keycloak.sh`, or roll back the `vdiforge` Helm release. Do not delete the PostgreSQL PVC unless intentionally resetting identity state. |
| Logs/metrics | Keycloak logs, PostgreSQL logs, Traefik logs, Kubernetes events, `kubectl top pods -A`. |

## Keycloak PostgreSQL Unavailable

| Area | Detail |
| --- | --- |
| Symptoms | Keycloak startup fails or logs database connection errors; `vdiforge-keycloak-postgres-0` is not Ready. |
| Likely causes | PVC not bound, local-path storage issue, wrong secret key, ResourceQuota exhausted, PostgreSQL image pull failure. |
| Diagnostics | `kubectl -n keycloak get statefulset,pod,pvc`; `kubectl -n keycloak describe pod vdiforge-keycloak-postgres-0`; `kubectl -n keycloak logs statefulset/vdiforge-keycloak-postgres`; `kubectl describe resourcequota -n keycloak`; `kubectl get storageclass vdiforge-local-path`. |
| Remediation | Restore storage, fix the `vdiforge-keycloak-secrets` secret, free quota, rerun Helm upgrade, or rebuild only if the lab reset is intentional. |
| Logs/metrics | PostgreSQL logs, PVC events, local-path provisioner logs, quota events. |

## Authentication Failure

| Area | Detail |
| --- | --- |
| Symptoms | User cannot log in or API rejects token. |
| Likely causes | invalid credentials, expired token, wrong issuer, wrong audience, clock skew, Keycloak client misconfiguration, missing PKCE verifier. |
| Diagnostics | Run `python3 scripts/phase5-oidc-pkce-test.py --env .local/phase5/phase5.env --ca .local/phase5/tls/vdiforge-local-ca.crt --resolve-ip 192.168.56.11`; inspect OIDC discovery; compare system clocks; verify `vdiforge-frontend` client settings with `scripts/phase5-configure-keycloak.sh`. |
| Remediation | Reset demo credentials with `scripts/phase5-configure-keycloak.sh`, correct redirect URI/client settings in realm JSON, sync clocks, or refresh the browser session. Do not weaken PKCE or TLS validation to make login pass. |
| Logs/metrics | Keycloak login events, future API auth logs without raw tokens, Traefik access logs. |

## Authorization Failure

| Area | Detail |
| --- | --- |
| Symptoms | User is authenticated but cannot list image, launch desktop, connect, or delete. |
| Likely causes | missing role, wrong role mapper, ownership mismatch, quota denial, desktop in wrong state. |
| Diagnostics | Check user roles in Keycloak, run the Phase 5 RBAC claim test, inspect future API audit event, desktop owner in database, API error code. |
| Remediation | Correct role assignment in realm configuration, fix the role mapper, use an admin account for admin-only action, correct backend policy in Phase 7. |
| Logs/metrics | `AUTHORIZATION_DENIED` audit events, API logs, RBAC test evidence. |

## Guacamole Unavailable

| Area | Detail |
| --- | --- |
| Symptoms | `https://remote.vdiforge.local` fails, the API returns a Guacamole URL but the browser cannot load the gateway, or Guacamole returns a token/auth error. |
| Likely causes | Guacamole pod down, `guacd` pod down, missing `vdiforge-guacamole-json-secret`, wrong JSON auth key, TLS Secret missing, ingress or hosts-file issue, NetworkPolicy denial, or image pull failure. |
| Diagnostics | `kubectl -n guacamole get deploy,pod,svc,ingress,secret`; `kubectl -n guacamole logs deploy/vdiforge-guacamole`; `kubectl -n guacamole logs deploy/vdiforge-guacd`; `kubectl -n guacamole describe ingress vdiforge-guacamole`; `curl --cacert .local/phase5/tls/vdiforge-local-ca.crt --resolve remote.vdiforge.local:443:192.168.56.11 https://remote.vdiforge.local/`; inspect Traefik logs in `ingress-traefik`. |
| Remediation | Rerun `scripts/phase8-create-local-secrets.sh`, rerun the Helm upgrade with `values-phase8-local.yaml`, confirm Guacamole and `guacd` rollouts, verify `remote.vdiforge.local` maps to `192.168.56.11`, and rerun `scripts/phase8-networkpolicy-test.sh`. Do not switch to direct RDP exposure to bypass Guacamole. |
| Logs/metrics | Guacamole logs, `guacd` logs, Traefik logs, Kubernetes events, Phase 8 validation output. |

## Portal Unavailable

| Area | Detail |
| --- | --- |
| Symptoms | `https://vdiforge.local` fails, shows a TLS warning, or serves the wrong application. |
| Likely causes | missing Windows hosts entry, untrusted local CA, missing `vdiforge-portal-tls` Secret, frontend pod unavailable, stale frontend image, ingress misconfiguration, or Traefik issue. |
| Diagnostics | `kubectl -n vdiforge-system get deploy,pod,svc,ingress,secret vdiforge-frontend`; `kubectl -n vdiforge-system logs deploy/vdiforge-frontend`; `kubectl -n ingress-traefik logs deploy/traefik`; `curl --cacert ~/vdiforge-phase5-validation/.local/phase5/tls/vdiforge-local-ca.crt --resolve vdiforge.local:443:192.168.56.11 https://vdiforge.local/`; verify the Windows hosts entry maps `vdiforge.local` to `192.168.56.11`. |
| Remediation | Rerun `scripts/phase9-create-local-secrets.sh`, rebuild/load the frontend image with `scripts/phase9-build-load-frontend-image.sh`, rerun the Helm upgrade with `values-phase9-local.yaml`, refresh local DNS, and confirm the browser trusts the Phase 5 local CA. |
| Logs/metrics | Frontend pod logs, Traefik logs, ingress status, Phase 9 validation output. |

## Portal API or CORS Failure

| Area | Detail |
| --- | --- |
| Symptoms | The portal loads but image/desktop requests fail, browser dev tools show CORS errors, or the UI shows a safe API error. |
| Likely causes | API rollout unavailable, `VDIFORGE_CORS_ALLOWED_ORIGINS` missing `https://vdiforge.local`, Keycloak token invalid, local TLS trust issue, API NetworkPolicy issue, or stale Helm values. |
| Diagnostics | `kubectl -n vdiforge-system logs deploy/vdiforge-api`; `kubectl -n vdiforge-system get deploy vdiforge-api -o yaml | grep VDIFORGE_CORS_ALLOWED_ORIGINS`; browser network panel; `curl --cacert ~/vdiforge-phase5-validation/.local/phase5/tls/vdiforge-local-ca.crt --resolve api.vdiforge.local:443:192.168.56.11 -H 'Origin: https://vdiforge.local' -H 'Access-Control-Request-Method: GET' -X OPTIONS https://api.vdiforge.local/api/v1/images`. |
| Remediation | Reapply Phase 9 Helm values, restart `vdiforge-api` after config changes, verify Keycloak client redirect/web origin settings, and rerun `scripts/phase9-portal-e2e-test.py`. Do not bypass server-side authorization in the portal. |
| Logs/metrics | Browser network errors, API logs, Traefik logs, Keycloak logs, Phase 9 E2E output. |

## Portal Login Callback Failure

| Area | Detail |
| --- | --- |
| Symptoms | Login redirects loop, callback page fails, or Keycloak reports invalid redirect URI. |
| Likely causes | Keycloak client missing `https://vdiforge.local/oidc/callback`, stale realm import, browser session/cookie issue, wrong local hostname, or untrusted TLS certificate. |
| Diagnostics | Inspect `helm/vdiforge/files/keycloak/vdiforge-realm.json`; run `python3 scripts/phase5-oidc-pkce-test.py --env ~/vdiforge-phase5-validation/.local/phase5/phase5.env --ca ~/vdiforge-phase5-validation/.local/phase5/tls/vdiforge-local-ca.crt --resolve-ip 192.168.56.11`; check Keycloak logs. |
| Remediation | Rerun `scripts/phase5-configure-keycloak.sh`, clear the browser session for `vdiforge.local` and `auth.vdiforge.local`, verify hosts-file entries, and retry. Do not enable implicit flow or wildcard redirects to work around the issue. |
| Logs/metrics | Keycloak logs, browser console/network panel, Phase 5 and Phase 9 validation output. |

## VDI Connection Failure

| Area | Detail |
| --- | --- |
| Symptoms | Desktop is `READY` but Guacamole displays a connection failure, the Phase 8 E2E test cannot reach TCP 3389 from the `guacd` network position, or `/connect` returns `DESKTOP_NOT_READY`. |
| Likely causes | xrdp not running in the guest, image version missing Phase 8 remote prerequisites, per-desktop remote Secret missing, wrong Service selector, NetworkPolicy denial from `guacd` or the provisioner readiness probe, VMI not actually running, VM firewall, or stale connection token. |
| Diagnostics | `kubectl -n vdiforge-desktops get vm,vmi,dv,pvc,svc,secret`; `kubectl -n vdiforge-desktops describe svc <desktop-service>`; `kubectl -n vdiforge-desktops describe vmi <desktop-vmi>`; `kubectl -n vdiforge-system get networkpolicy vdiforge-system-provisioner-to-desktop-rdp`; `kubectl -n guacamole logs deploy/vdiforge-guacd`; run `python3 scripts/phase8-remote-desktop-e2e-test.py --env ~/vdiforge-phase5-validation/.local/phase5/phase5.env --ca ~/vdiforge-phase5-validation/.local/phase5/tls/vdiforge-local-ca.crt --resolve-ip 192.168.56.11`. |
| Remediation | Confirm the desktop uses `ubuntu-devops:1.2.0`, rebuild/import the source PVC if needed, restore the per-desktop Secret through provisioner reconciliation, fix the Service or the Helm-managed `guacd`/provisioner NetworkPolicies, stop/start the desktop through the API, and delete/relaunch failed test desktops through the API. |
| Logs/metrics | `guacd` logs, VMI conditions, VM boot logs, service endpoints, NetworkPolicy test results, API audit events. |

## API HPA Metrics Unknown

| Area | Detail |
| --- | --- |
| Symptoms | `kubectl -n vdiforge-system get hpa vdiforge-api` shows `<unknown>` for CPU, or Phase 10 validation fails before load starts. |
| Likely causes | Metrics Server unavailable, API pods missing CPU requests, HPA rendered against the wrong target, API pods not Ready long enough for metrics collection, or APIService aggregation issue. |
| Diagnostics | `kubectl top nodes`; `kubectl top pods -n vdiforge-system`; `kubectl describe hpa vdiforge-api -n vdiforge-system`; `kubectl describe apiservice v1beta1.metrics.k8s.io`; `kubectl -n kube-system logs deploy/metrics-server`; `kubectl -n vdiforge-system get deploy vdiforge-api -o yaml | grep -A8 resources`. |
| Remediation | Restore Metrics Server, keep API CPU requests in Helm values, reapply Phase 10 values, wait for new API pods to become Ready, and rerun `scripts/validate-phase10-live.sh`. Do not disable metrics validation or manually scale the Deployment as final evidence. |
| Logs/metrics | HPA conditions/events, Metrics Server logs, API pod resource specs, `kubectl top` output. |

## API Does Not Scale Up

| Area | Detail |
| --- | --- |
| Symptoms | The Phase 10 load generator is running but `vdiforge-api` remains at one replica and HPA desired replicas do not increase. |
| Likely causes | Load-test endpoint disabled, request authentication failing, load too light, CPU target too high for observed work, Metrics Server delay, or HPA not installed with Phase 10 values. |
| Diagnostics | `helm get values vdiforge -n vdiforge-system`; `kubectl -n vdiforge-system describe hpa vdiforge-api`; `kubectl -n vdiforge-system logs deploy/vdiforge-api`; inspect `/tmp/vdiforge-phase10-load.log`; run `kubectl top pods -n vdiforge-system -l app.kubernetes.io/component=api`. |
| Remediation | Confirm `values-phase10-local.yaml` is applied, verify bearer-token acquisition through the Phase 5 env file, rerun the load generator with documented duration/concurrency/iterations, and keep max replicas within platform-worker capacity. |
| Logs/metrics | Load-test output, HPA events, API logs, pod CPU metrics. |

## API Pods Pending During Scale-Out

| Area | Detail |
| --- | --- |
| Symptoms | HPA desired replicas increases but new `vdiforge-api` pods remain Pending. |
| Likely causes | `vdiforge-system` ResourceQuota pressure, insufficient CPU/memory on `vdi-worker-01`, missing `vdiforge.io/node-role=platform` label, image not loaded on the platform worker, or node pressure. |
| Diagnostics | `kubectl -n vdiforge-system get pods -l app.kubernetes.io/component=api -o wide`; `kubectl -n vdiforge-system describe pod <pending-api-pod>`; `kubectl describe resourcequota -n vdiforge-system`; `kubectl describe node vdi-worker-01`; `kubectl top node vdi-worker-01`. |
| Remediation | Free platform-worker capacity, restore the platform node label, load the `localhost/vdiforge-api:0.10.0` image on `vdi-worker-01`, tune max replicas conservatively, or add worker capacity in a future node-scaling architecture. HPA does not add worker nodes in the local lab. |
| Logs/metrics | Scheduler events, ResourceQuota usage, node CPU/memory, image pull errors. |

## API Scale-Down Slow

| Area | Detail |
| --- | --- |
| Symptoms | Load has stopped but `vdiforge-api` remains above the minimum replica count for several minutes. |
| Likely causes | HPA scale-down stabilization window, recent CPU samples still above target, continuing browser/API traffic, or failed load generator cleanup. |
| Diagnostics | `kubectl -n vdiforge-system describe hpa vdiforge-api`; `kubectl top pods -n vdiforge-system -l app.kubernetes.io/component=api`; `ps aux | grep load-test-api`; inspect `/tmp/vdiforge-phase10-load.log`. |
| Remediation | Wait for the configured stabilization window, stop stray load generators, verify CPU drops below target, and rerun validation. Do not manually scale down during final Phase 10 evidence capture. |
| Logs/metrics | HPA history/events, pod CPU metrics, load-test log. |

## Guacamole JSON Token Rejected

| Area | Detail |
| --- | --- |
| Symptoms | `/api/v1/desktops/{id}/connect` succeeds but Guacamole rejects the returned URL or `/api/tokens` does not return `authToken`. |
| Likely causes | API and Guacamole use different `JSON_SECRET_KEY` values, the key is not 32 hex characters, token expired, system clocks differ, or the URL was copied after its TTL. |
| Diagnostics | Confirm `vdiforge-guacamole-json-secret` exists in both `vdiforge-system` and `guacamole`; compare Secret checksums without printing secret values; inspect API and Guacamole logs; rerun `scripts/phase8-create-local-secrets.sh` if the secret is missing. |
| Remediation | Regenerate Phase 8 runtime secrets, restart `vdiforge-api` and `vdiforge-guacamole`, request a fresh connection URL, and avoid extending TTL unless a real demo need justifies it. |
| Logs/metrics | API logs, Guacamole logs, Kubernetes Secret metadata, Phase 8 E2E output. |

## Desktop Stuck PROVISIONING

| Area | Detail |
| --- | --- |
| Symptoms | Desktop remains `PROVISIONING` beyond expected time. |
| Likely causes | provisioner down, Kubernetes API denied request, NetworkPolicy blocking `10.96.0.1:443` or `192.168.56.10:6443`, selected source PVC unavailable, CDI clone pending, `WaitForFirstConsumer` has no schedulable VM consumer, storage quota exhausted, or image artifact import failure. |
| Diagnostics | `kubectl logs deploy/vdiforge-provisioner -n vdiforge-system`; `kubectl get dv,vm,vmi,pvc,svc -n vdiforge-desktops`; `kubectl describe datavolume <desktop-root-dv> -n vdiforge-desktops`; inspect audit and operation records. |
| Remediation | Restore the source PVC with `scripts/phase7-prepare-golden-source.sh` for `1.0.0` or `VDIFORGE_IMAGE_VERSION=1.2.0 bash scripts/phase8-prepare-remote-source.sh` for the current portal image, fix CDI/storage/RBAC, verify the `vdiforge-system-provisioner-kubernetes-api` egress endpoints, make sure the VM resource is created so local-path storage can bind, rerun the provisioner validation, and delete failed desktop resources through the API where possible. |
| Logs/metrics | Provisioner retries, KubeVirt events, DataVolume/PVC events. |

## Desktop Stuck BOOTING

| Area | Detail |
| --- | --- |
| Symptoms | VM exists but never reaches READY. |
| Likely causes | guest boot failure, remote desktop service not started, cloud-init issue, no `/dev/kvm`, insufficient resources, or NetworkPolicy blocking the provisioner readiness probe to TCP 3389. |
| Diagnostics | `kubectl get vmi -n vdiforge-desktops`; `kubectl describe vmi <name> -n vdiforge-desktops`; `virtctl console <name>` where available; VM serial console logs. |
| Remediation | Fix image, validate KVM/nested virtualization, increase resources, rebuild image, transition failed desktop after timeout. |
| Logs/metrics | VMI conditions, virt-launcher logs, guest logs, provisioning latency. |

## VM Boot Failure

| Area | Detail |
| --- | --- |
| Symptoms | VMI fails immediately or restarts. |
| Likely causes | invalid image, unsupported CPU mode, missing `/dev/kvm`, bad disk bus, cloud-init error. |
| Diagnostics | `kubectl describe vmi <name> -n vdiforge-desktops`; `kubectl logs <virt-launcher-pod> -n vdiforge-desktops`; KubeVirt operator logs. |
| Remediation | Enable nested virtualization, enable development emulation only as fallback, fix image definition, rebuild image. |
| Logs/metrics | virt-launcher logs, KubeVirt events, node KVM validation. |

## Image Unavailable

| Area | Detail |
| --- | --- |
| Symptoms | Launch request fails or DataVolume import fails. |
| Likely causes | missing artifact, bad URL, checksum mismatch, storage import failure, image marked blocked. |
| Diagnostics | Check image catalog row; inspect DataVolume events; verify artifact availability and checksum. |
| Remediation | Restore promoted artifact, promote previous known-good version, rebuild image. |
| Logs/metrics | Image pipeline logs, DataVolume status, `IMAGE_PROMOTED` audit events. |

## Provisioning Timeout

| Area | Detail |
| --- | --- |
| Symptoms | Desktop transitions to `FAILED` after retry window. |
| Likely causes | capacity issue, image issue, KubeVirt issue, unreachable remote service. |
| Diagnostics | Review ProvisioningOperation record, request ID logs, Kubernetes events, VMI conditions. |
| Remediation | Fix root cause, delete failed desktop, retry launch with same or corrected profile, promote fixed image. |
| Logs/metrics | Provisioning latency, retry count, failure reason metrics. |

## DNS Problems

| Area | Detail |
| --- | --- |
| Symptoms | Services cannot resolve Keycloak, API, database, or Guacamole. |
| Likely causes | CoreDNS down for cluster services; wrong Service name or namespace; Windows hosts file missing `auth.vdiforge.local`, `api.vdiforge.local`, or `remote.vdiforge.local`; future thin client lacks local DNS entry. |
| Diagnostics | `kubectl get pods -n kube-system -l k8s-app=kube-dns`; `kubectl logs -n kube-system deployment/coredns`; run `nslookup vdiforge-keycloak.keycloak.svc.cluster.local`, `nslookup vdiforge-api.vdiforge-system.svc.cluster.local`, or `nslookup vdiforge-guacamole.guacamole.svc.cluster.local` from a debug pod; on Windows run `Resolve-DnsName auth.vdiforge.local`, `Resolve-DnsName api.vdiforge.local`, and `Resolve-DnsName remote.vdiforge.local`. |
| Remediation | Restore CoreDNS for cluster DNS. For browser access, map `192.168.56.11 auth.vdiforge.local api.vdiforge.local remote.vdiforge.local vdiforge.local grafana.vdiforge.local` in the client hosts file or local DNS. Use `scripts/phase5-windows-hosts-and-trust.ps1` from an elevated PowerShell prompt on Windows. |
| Logs/metrics | CoreDNS logs, Traefik logs, browser DNS errors, future API dependency failures. |

## TLS Problems

| Area | Detail |
| --- | --- |
| Symptoms | Browser certificate warnings, OIDC redirect failure, API calls rejected, or `remote.vdiforge.local` certificate errors. |
| Likely causes | expired local certificate, wrong hostname/SAN, missing local CA trust, wrong Kubernetes TLS secret, Traefik ingress issue. |
| Diagnostics | `kubectl -n keycloak describe ingress vdiforge-keycloak`; `kubectl -n vdiforge-system describe ingress vdiforge-api`; `kubectl -n guacamole describe ingress vdiforge-guacamole`; `kubectl -n keycloak get secret vdiforge-keycloak-tls`; `kubectl -n vdiforge-system get secret vdiforge-api-tls`; `kubectl -n guacamole get secret vdiforge-guacamole-tls`; `openssl x509 -in .local/phase5/tls/auth.vdiforge.local.crt -noout -text`; `openssl x509 -in .local/phase7/tls/api.vdiforge.local.crt -noout -text`; `openssl x509 -in .local/phase8/tls/remote.vdiforge.local.crt -noout -text`; trusted `curl --resolve` checks for all browser-facing hosts. |
| Remediation | Regenerate identity TLS with `scripts/phase5-create-local-secrets.sh`, API TLS with `scripts/phase7-create-local-secrets.sh`, and Guacamole TLS with `scripts/phase8-create-local-secrets.sh`; refresh Kubernetes TLS Secrets, trust the local CA on the browser client, and rerun Phase 5/7/8 validation. Do not use `curl -k` as final validation evidence. |
| Logs/metrics | Ingress TLS errors, browser error, API request failures. |
