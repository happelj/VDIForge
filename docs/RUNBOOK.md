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
| Diagnostics | `kubectl describe node <node>`; `kubectl get events -A --sort-by=.lastTimestamp`; `systemctl status kubelet`; `systemctl status containerd`; `journalctl -u kubelet -xe`. |
| Remediation | Restore host/network, restart failed services, clear disk pressure, verify CNI pods, cordon/drain only when safe. |
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
| Symptoms | Connect button fails; browser cannot load remote session. |
| Likely causes | Guacamole pod down, guacd down, database issue, ingress/WebSocket issue. |
| Diagnostics | `kubectl get pods -n guacamole`; `kubectl logs -n guacamole deploy/guacamole`; `kubectl logs -n guacamole deploy/guacd`; inspect ingress controller logs. |
| Remediation | Restart failed pods, fix database, correct WebSocket ingress settings, roll back chart values. |
| Logs/metrics | Guacamole logs, guacd logs, ingress logs, active remote sessions. |

## VDI Connection Failure

| Area | Detail |
| --- | --- |
| Symptoms | Desktop is READY but Guacamole cannot connect. |
| Likely causes | xrdp/VNC not running, wrong service selector, NetworkPolicy denial, VM firewall, stale connection target. |
| Diagnostics | `kubectl get svc,pod -n vdiforge-desktops`; `kubectl describe networkpolicy -n vdiforge-desktops`; VM console logs; Guacamole connection logs. |
| Remediation | Restart remote service in VM if policy allows, fix Service labels, correct NetworkPolicy, recreate connection context. |
| Logs/metrics | guacd logs, VM boot logs, service endpoints, network policy test results. |

## Desktop Stuck PROVISIONING

| Area | Detail |
| --- | --- |
| Symptoms | Desktop remains `PROVISIONING` beyond expected time. |
| Likely causes | provisioner down, Kubernetes API denied request, image unavailable, PVC pending. |
| Diagnostics | `kubectl logs deploy/vdiforge-provisioner -n vdiforge-system`; `kubectl get vm,pvc,dv -n vdiforge-desktops`; audit and operation records. |
| Remediation | Restart provisioner, fix RBAC, restore image, fix storage, mark operation failed after timeout. |
| Logs/metrics | Provisioner retries, KubeVirt events, DataVolume/PVC events. |

## Desktop Stuck BOOTING

| Area | Detail |
| --- | --- |
| Symptoms | VM exists but never reaches READY. |
| Likely causes | guest boot failure, remote desktop service not started, cloud-init issue, no `/dev/kvm`, insufficient resources. |
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
| Likely causes | CoreDNS down for cluster services; wrong Service name or namespace; Windows hosts file missing `auth.vdiforge.local`; future thin client lacks local DNS entry. |
| Diagnostics | `kubectl get pods -n kube-system -l k8s-app=kube-dns`; `kubectl logs -n kube-system deployment/coredns`; run `nslookup vdiforge-keycloak.keycloak.svc.cluster.local` from a debug pod; on Windows run `Resolve-DnsName auth.vdiforge.local`. |
| Remediation | Restore CoreDNS for cluster DNS. For browser access, map `192.168.56.11 auth.vdiforge.local vdiforge.local grafana.vdiforge.local` in the client hosts file or local DNS. Use `scripts/phase5-windows-hosts-and-trust.ps1` from an elevated PowerShell prompt on Windows. |
| Logs/metrics | CoreDNS logs, Traefik logs, browser DNS errors, future API dependency failures. |

## TLS Problems

| Area | Detail |
| --- | --- |
| Symptoms | Browser certificate warnings, OIDC redirect failure, API calls rejected. |
| Likely causes | expired local certificate, wrong hostname/SAN, missing local CA trust, wrong Kubernetes TLS secret, Traefik ingress issue. |
| Diagnostics | `kubectl -n keycloak describe ingress vdiforge-keycloak`; `kubectl -n keycloak get secret vdiforge-keycloak-tls`; `openssl x509 -in .local/phase5/tls/auth.vdiforge.local.crt -noout -text`; `curl --cacert .local/phase5/tls/vdiforge-local-ca.crt --resolve auth.vdiforge.local:443:192.168.56.11 https://auth.vdiforge.local/realms/vdiforge/.well-known/openid-configuration`. |
| Remediation | Regenerate local TLS with `scripts/phase5-create-local-secrets.sh`, refresh the Kubernetes TLS Secret, trust the local CA on the browser client, and rerun Phase 5 validation. Do not use `curl -k` as final validation evidence. |
| Logs/metrics | Ingress TLS errors, browser error, API request failures. |
