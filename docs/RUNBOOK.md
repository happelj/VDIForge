# Operations Runbook

This runbook defines troubleshooting procedures for the VDIForge local lab and planned platform. Kubernetes commands apply to later phases and may require namespace adjustment.

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

## Kubernetes Node NotReady

| Area | Detail |
| --- | --- |
| Symptoms | `kubectl get nodes` shows `NotReady`; pods evicted or stuck; desktops unavailable on affected node. |
| Likely causes | kubelet down, containerd down, network outage, disk pressure, host reboot, CNI failure. |
| Diagnostics | `kubectl describe node <node>`; `kubectl get events -A --sort-by=.lastTimestamp`; `systemctl status kubelet`; `systemctl status containerd`; `journalctl -u kubelet -xe`. |
| Remediation | Restore host/network, restart failed services, clear disk pressure, verify CNI pods, cordon/drain only when safe. |
| Logs/metrics | Node conditions, kubelet logs, containerd logs, Calico pod logs, node CPU/memory/disk metrics. |

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

## Keycloak Unavailable

| Area | Detail |
| --- | --- |
| Symptoms | Login fails; API readiness fails; token validation metadata unavailable. |
| Likely causes | Keycloak pod down, database unavailable, ingress/TLS issue, DNS problem. |
| Diagnostics | `kubectl get pods -n keycloak`; `kubectl logs deploy/keycloak -n keycloak`; `kubectl get ingress -n keycloak`; `curl -k https://<keycloak-host>/realms/vdiforge/.well-known/openid-configuration`. |
| Remediation | Restore Keycloak pod, fix database, correct ingress/DNS/TLS, roll back failed Keycloak configuration. |
| Logs/metrics | Keycloak logs, API auth errors, ingress logs, readiness metrics. |

## Authentication Failure

| Area | Detail |
| --- | --- |
| Symptoms | User cannot log in or API rejects token. |
| Likely causes | expired token, wrong issuer, wrong audience, clock skew, Keycloak client misconfiguration. |
| Diagnostics | Inspect API auth error code; verify OIDC discovery URL; compare system clocks; test with demo identity. |
| Remediation | Fix client settings, correct issuer/audience config, sync clocks, refresh session. |
| Logs/metrics | API auth logs without raw tokens, Keycloak login events, authorization failure counts. |

## Authorization Failure

| Area | Detail |
| --- | --- |
| Symptoms | User is authenticated but cannot list image, launch desktop, connect, or delete. |
| Likely causes | missing role, wrong role mapper, ownership mismatch, quota denial, desktop in wrong state. |
| Diagnostics | Check user roles in Keycloak, API audit event, desktop owner in database, API error code. |
| Remediation | Correct role assignment, fix role mapper, use admin account for admin action, correct backend policy. |
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
| Likely causes | CoreDNS down, wrong service name, namespace error, host DNS misconfiguration. |
| Diagnostics | `kubectl get pods -n kube-system -l k8s-app=kube-dns`; `kubectl logs -n kube-system deploy/coredns`; run `nslookup` from a debug pod. |
| Remediation | Restart CoreDNS, fix Service names, correct namespace references, fix host DNS. |
| Logs/metrics | CoreDNS logs, API dependency errors, readiness failures. |

## TLS Problems

| Area | Detail |
| --- | --- |
| Symptoms | Browser certificate warnings, OIDC redirect failure, API calls rejected. |
| Likely causes | expired certificate, wrong hostname, missing CA trust, ingress misconfiguration. |
| Diagnostics | Inspect certificate dates and SANs; `kubectl describe ingress`; ingress controller logs; browser dev tools. |
| Remediation | Renew certificate, correct hostname, install local CA trust for lab, fix ingress TLS secret. |
| Logs/metrics | Ingress TLS errors, browser error, API request failures. |
