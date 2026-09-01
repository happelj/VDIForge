# VDIForge Quickstart

This quickstart walks through the proven local install path for VDIForge: a three-node Ubuntu Server lab running on VirtualBox, followed by Kubernetes, KubeVirt, Keycloak, the VDIForge API, Guacamole, the React portal, autoscaling, observability, security hardening, CI-safe validation, and the final portfolio demo.

This is not a one-click installer. The current local lab intentionally uses manually created VirtualBox VMs because the project avoided abandoned Terraform VirtualBox providers. Terraform is still used for infrastructure specification and validation, but VirtualBox VM creation is manual in this supported path.

## 1. What You Will Build

The supported local path creates this environment:

| Layer | Result |
| --- | --- |
| Host | Windows 10 Pro or Windows 11 Pro with Oracle VirtualBox |
| VM platform | Three Ubuntu Server 26.04 LTS VirtualBox VMs |
| Kubernetes | kubeadm cluster with one control-plane node and two workers |
| Runtime | containerd |
| Networking | Calico CNI with NetworkPolicy support |
| VM orchestration | KubeVirt with CDI and local-path storage |
| Identity | Keycloak realm `vdiforge` with demo users and OIDC/PKCE |
| VDI control plane | FastAPI API, PostgreSQL state, asynchronous provisioner |
| Remote desktop | Apache Guacamole and xrdp/RDP into Ubuntu VMs |
| Portal | React self-service portal at `https://vdiforge.local` |
| Autoscaling | Kubernetes HPA for the API |
| Observability | Prometheus, Grafana, Alertmanager, VDIForge dashboard |
| Security | Hardened headers, CORS, RBAC, NetworkPolicy, audit export |
| Demo | Final role/image catalog and browser-based Ubuntu DevOps desktop |

The VDI desktop runs remotely inside Kubernetes/KubeVirt. The client browser does not download or boot Ubuntu locally. The browser receives the remote graphical session through Apache Guacamole and sends keyboard/mouse input back to the remote VM.

## 2. Expected Time And Host Capacity

Plan on this taking several hours the first time, longer if you need to troubleshoot VirtualBox networking, nested virtualization, or image builds.

Recommended minimum host capacity:

| Resource | Recommendation |
| --- | --- |
| CPU | 8 or more logical CPUs |
| RAM | 32 GiB strongly preferred |
| Free disk | 180 GiB or more across VM disks and generated QCOW2 images |
| Virtualization | AMD-V or Intel VT-x enabled in BIOS/UEFI |
| Cost | No paid cloud resources or commercial VDI licensing required |

If your host has less RAM or disk, the lab may still run, but VM boot times, image builds, and desktop launches will be slower and less reliable.

## 3. Required Host Tools

Install these on the Windows host:

1. Git for Windows.
2. Oracle VirtualBox 7.2.16 or a compatible current VirtualBox 7.x release.
3. Windows OpenSSH client, normally included with Windows 10/11.
4. A browser such as Chrome or Edge.
5. Terraform, optional for validating the infrastructure specification from Windows.
6. PowerShell, either Windows PowerShell or PowerShell 7.

Download an Ubuntu Server 26.04 LTS ISO and keep it somewhere easy to find.

## 4. Clone The Repository On Windows

Open PowerShell and run:

```powershell
git clone https://github.com/happelj/VDIForge.git
cd VDIForge
git status
```

Expected result:

```text
On branch main
nothing to commit, working tree clean
```

Optional static validation from Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-phase14.ps1
```

## 5. Create The Three VirtualBox VMs

Create exactly these VMs unless you intentionally adjust resources for your host.

| VM name | Hostname | Role | CPU | RAM | Disk | Static IP |
| --- | --- | --- | ---: | ---: | ---: | --- |
| `vdi-control-01` | `vdi-control-01` | Kubernetes control plane | 4 vCPU | 6144 MiB | 40 GiB | `192.168.56.10` |
| `vdi-worker-01` | `vdi-worker-01` | Platform worker | 2 vCPU | 6144 MiB | 50 GiB | `192.168.56.11` |
| `vdi-worker-02` | `vdi-worker-02` | VDI/KubeVirt worker | 4 vCPU | 8192 MiB | 60 GiB | `192.168.56.12` |

Use these VirtualBox settings for all three VMs:

1. Type: Linux.
2. Version: Ubuntu 64-bit.
3. Disk type: VDI.
4. Disk allocation: dynamically allocated is acceptable.
5. EFI: leave unchecked unless your local Ubuntu ISO/VirtualBox combination requires EFI.
6. Network Adapter 1: NAT.
7. Network Adapter 2: Host-only Adapter.
8. Host-only network: VirtualBox host-only network using `192.168.56.0/24`.
9. Username inside Ubuntu: `vdiadmin`.

For `vdi-worker-02`, also enable:

1. System -> Processor -> Nested VT-x/AMD-V.
2. System -> Processor -> PAE/NX, if the setting is visible.

Do not continue to Kubernetes until `vdi-worker-02` can expose `/dev/kvm`.

## 6. Install Ubuntu Server On Each VM

Install Ubuntu Server 26.04 LTS on all three VMs.

Use these values during installation:

| Field | Value |
| --- | --- |
| Username | `vdiadmin` |
| Hostname | Match the VM name |
| OpenSSH server | Install/enable |
| Password | Choose a local lab password and do not commit it |
| Storage | Use the full VM disk |

After each VM boots, log in at the console as `vdiadmin`.

## 7. Configure Static Host-Only IP Addresses

On each VM, identify the interface names:

```bash
ip -br addr
```

The expected pattern is:

```text
enp0s3  NAT/DHCP
enp0s8  host-only
```

If your names differ, use your actual interface names in the netplan file.

On `vdi-control-01`, create the static network config:

```bash
sudo tee /etc/netplan/01-vdiforge.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.10/24
EOF
sudo netplan apply
ip -br addr
```

On `vdi-worker-01`, use `192.168.56.11/24`:

```bash
sudo tee /etc/netplan/01-vdiforge.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.11/24
EOF
sudo netplan apply
ip -br addr
```

On `vdi-worker-02`, use `192.168.56.12/24`:

```bash
sudo tee /etc/netplan/01-vdiforge.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.12/24
EOF
sudo netplan apply
ip -br addr
```

From each node, verify outbound Internet access:

```bash
curl -I https://ubuntu.com
```

From the Windows host, verify host-to-node reachability:

```powershell
ping 192.168.56.10
ping 192.168.56.11
ping 192.168.56.12
```

## 8. Verify Nested Virtualization On `vdi-worker-02`

Run this on `vdi-worker-02`:

```bash
grep -E -m 5 '(vmx|svm)' /proc/cpuinfo
ls -l /dev/kvm
test -r /dev/kvm -a -w /dev/kvm && echo KVM_READ_WRITE_OK
```

Expected result:

1. The CPU flags command prints either `vmx` for Intel or `svm` for AMD.
2. `/dev/kvm` exists.
3. `KVM_READ_WRITE_OK` prints for `vdiadmin`.

If `/dev/kvm` is missing, stop here and fix VirtualBox nested virtualization before continuing.

## 9. Prepare SSH From The Control Node

Log in to `vdi-control-01` and create an Ansible SSH key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vdiforge_ansible -C "vdiforge-ansible"
```

Press Enter for no passphrase unless you intentionally want to manage one.

Copy the public key to all three nodes:

```bash
ssh-copy-id -i ~/.ssh/vdiforge_ansible.pub vdiadmin@192.168.56.10
ssh-copy-id -i ~/.ssh/vdiforge_ansible.pub vdiadmin@192.168.56.11
ssh-copy-id -i ~/.ssh/vdiforge_ansible.pub vdiadmin@192.168.56.12
```

Test SSH:

```bash
ssh -i ~/.ssh/vdiforge_ansible vdiadmin@192.168.56.10 hostname
ssh -i ~/.ssh/vdiforge_ansible vdiadmin@192.168.56.11 hostname
ssh -i ~/.ssh/vdiforge_ansible vdiadmin@192.168.56.12 hostname
```

Expected output:

```text
vdi-control-01
vdi-worker-01
vdi-worker-02
```

## 10. Clone The Repository On `vdi-control-01`

Run this on `vdi-control-01`:

```bash
sudo apt-get update
sudo apt-get install -y git curl jq python3 python3-venv python3-pip openssh-client tar
git clone https://github.com/happelj/VDIForge.git ~/vdiforge
cd ~/vdiforge
git status
```

Install Ansible tools:

```bash
sudo apt-get install -y ansible ansible-lint
ansible --version
ansible-lint --version
```

## 11. Validate The Terraform Specification

Terraform does not create the VirtualBox VMs in the current supported lab. It validates and documents the intended local infrastructure model.

Run from `~/vdiforge` on `vdi-control-01`, or from the Windows clone if Terraform is installed there:

```bash
terraform -chdir=terraform/environments/local init
terraform -chdir=terraform/environments/local fmt -check -recursive
terraform -chdir=terraform/environments/local validate
terraform -chdir=terraform/environments/local plan
terraform -chdir=terraform/environments/local output
```

Terraform state files are intentionally ignored by Git.

## 12. Run The Phase 2 Host Baseline

From `vdi-control-01`:

```bash
cd ~/vdiforge
ansible all -i ansible/inventory/local/hosts.yml -m ping --private-key ~/.ssh/vdiforge_ansible
```

If that passes, run the baseline:

```bash
ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/baseline.yml --private-key ~/.ssh/vdiforge_ansible --ask-become-pass
```

If your terminal times out waiting for the sudo prompt, use this lab-only temporary sudo approach.

Run this once on each node from that node's console:

```bash
echo 'vdiadmin ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-vdiforge-temp
sudo chmod 0440 /etc/sudoers.d/90-vdiforge-temp
sudo visudo -cf /etc/sudoers.d/90-vdiforge-temp
```

Then rerun the baseline without `--ask-become-pass`:

```bash
cd ~/vdiforge
ansible all -i ansible/inventory/local/hosts.yml -m command -a "sudo -n true" --private-key ~/.ssh/vdiforge_ansible
ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/baseline.yml --private-key ~/.ssh/vdiforge_ansible
ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/baseline.yml --private-key ~/.ssh/vdiforge_ansible
```

The second baseline run should be mostly `ok` with no failures.

## 13. Bootstrap Kubernetes And KubeVirt

From `vdi-control-01`:

```bash
cd ~/vdiforge
ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/phase3.yml --private-key ~/.ssh/vdiforge_ansible
ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/phase3.yml --private-key ~/.ssh/vdiforge_ansible
```

Validate the cluster:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl top nodes
kubectl get storageclass
kubectl get kubevirt -n kubevirt
kubectl get cdi -n cdi
kubectl get nodes --show-labels
kubectl get node vdi-worker-02 -o jsonpath='{.status.allocatable.devices\.kubevirt\.io/kvm}{"\n"}'
```

Expected result:

1. All three nodes are `Ready`.
2. `vdi-worker-01` has `vdiforge.io/node-role=platform`.
3. `vdi-worker-02` has `vdiforge.io/node-role=vdi`.
4. Metrics Server responds to `kubectl top nodes`.
5. KubeVirt and CDI are available.
6. The KVM allocatable value on `vdi-worker-02` is nonzero.

After Kubernetes is stable, remove the temporary passwordless sudo rule if you created it:

```bash
ansible-playbook -i ansible/inventory/local/hosts.yml ansible/playbooks/remove-temporary-sudo.yml --private-key ~/.ssh/vdiforge_ansible
```

## 14. Install Helm And The Identity Foundation

From `vdi-control-01`:

```bash
cd ~/vdiforge
bash scripts/install-helm-client.sh
export PATH="$HOME/.local/bin:$PATH"
helm version
bash scripts/validate-phase5-live.sh
```

This installs or validates:

1. Helm client.
2. Traefik ingress.
3. VDIForge Helm foundation.
4. Keycloak.
5. Keycloak PostgreSQL.
6. Local TLS material.
7. Demo users and roles.
8. OIDC/PKCE validation.

The demo credentials are stored locally on `vdi-control-01`:

```bash
cat ~/vdiforge/.local/phase5/phase5.env
```

Do not commit `.local/` files.

## 15. Configure Windows Hosts And Trust The Local CA

On the Windows host, open PowerShell in the Windows clone:

```powershell
cd VDIForge
New-Item -ItemType Directory -Force .local\phase5\tls
scp vdiadmin@192.168.56.10:/home/vdiadmin/vdiforge/.local/phase5/tls/vdiforge-local-ca.crt .local\phase5\tls\
```

Then open PowerShell as Administrator and run:

```powershell
cd VDIForge
powershell -ExecutionPolicy Bypass -File .\scripts\phase5-windows-hosts-and-trust.ps1
```

This configures the Windows host to resolve these names to the ingress worker at `192.168.56.11`:

```text
vdiforge.local
api.vdiforge.local
auth.vdiforge.local
remote.vdiforge.local
grafana.vdiforge.local
```

Validate from Windows:

```powershell
Resolve-DnsName vdiforge.local
Resolve-DnsName auth.vdiforge.local
Resolve-DnsName remote.vdiforge.local
Resolve-DnsName grafana.vdiforge.local
```

Each should resolve to `192.168.56.11`.

## 16. Build The Golden Images On `vdi-worker-02`

The full QCOW2 image builds are local/manual because they require KVM and produce large artifacts. They are intentionally not committed to Git.

From `vdi-control-01`, clone the repository onto the VDI worker build path:

```bash
ssh -i ~/.ssh/vdiforge_ansible vdiadmin@192.168.56.12 'rm -rf ~/vdiforge-phase6-build && git clone https://github.com/happelj/VDIForge.git ~/vdiforge-phase6-build'
```

Log in to `vdi-worker-02`:

```bash
ssh -i ~/.ssh/vdiforge_ansible vdiadmin@192.168.56.12
cd ~/vdiforge-phase6-build
sudo bash scripts/phase6-install-build-tools.sh
export PATH="$HOME/.local/bin:$PATH"
packer version
```

Build the final demo image set:

```bash
VDIFORGE_IMAGE_VERSION=1.0.0 bash scripts/phase6-build-image.sh ubuntu-base
VDIFORGE_IMAGE_VERSION=1.0.0 bash scripts/phase6-build-image.sh ubuntu-developer
VDIFORGE_IMAGE_VERSION=1.2.0 bash scripts/phase6-build-image.sh ubuntu-devops
```

Expected artifacts:

```text
~/vdiforge-phase6-build/artifacts/images/ubuntu-base/1.0.0/
~/vdiforge-phase6-build/artifacts/images/ubuntu-developer/1.0.0/
~/vdiforge-phase6-build/artifacts/images/ubuntu-devops/1.2.0/
```

Exit back to `vdi-control-01`:

```bash
exit
```

## 17. Import The Golden Images Into CDI

From `vdi-control-01`:

```bash
cd ~/vdiforge
VDIFORGE_IMAGE_VERSION=1.2.0 bash scripts/phase8-prepare-remote-source.sh
bash scripts/phase14-prepare-demo-images.sh
kubectl -n vdiforge-desktops get datavolume,pvc
```

Expected source image PVCs:

```text
vdiforge-golden-ubuntu-base-1-0-0
vdiforge-golden-ubuntu-developer-1-0-0
vdiforge-golden-ubuntu-devops-1-2-0
```

All three DataVolumes should be `Succeeded`, and all three PVCs should be `Bound`.

## 18. Create Runtime Secrets And Build Local Container Images

From `vdi-control-01`:

```bash
cd ~/vdiforge
bash scripts/phase7-create-local-secrets.sh
bash scripts/phase8-create-local-secrets.sh
bash scripts/phase9-create-local-secrets.sh
bash scripts/phase9-build-load-frontend-image.sh
```

These scripts create local-only Kubernetes Secrets and build/load the frontend image onto the platform worker.

No real secret values are committed to Git.

## 19. Install Monitoring And The Full Final Stack

From `vdi-control-01`:

```bash
cd ~/vdiforge
bash scripts/phase11-install-monitoring.sh
bash scripts/validate-phase14-live.sh
```

The Phase 14 live validator performs the final install/upgrade and validates the complete local platform, including:

1. Cluster health.
2. KVM exposure through KubeVirt.
3. API image build/load for `localhost/vdiforge-api:0.14.0`.
4. Helm render and release status.
5. Keycloak, API, provisioner, frontend, Guacamole, Prometheus, and Grafana rollouts.
6. Final three-image catalog.
7. Browser VDI regression through Guacamole.
8. HPA/load regression.
9. Audit/security export regression.
10. No unexpected failed pods.

Expected final line:

```text
Phase 14 live validation: PASS
```

## 20. Open The Local Portal

On the Windows host, open:

```text
https://vdiforge.local
```

Use the demo password from `~/vdiforge/.local/phase5/phase5.env` on `vdi-control-01`.

Recommended first login:

| Username | What it demonstrates |
| --- | --- |
| `demo-user` | Sees Ubuntu Base only |
| `demo-developer` | Sees Ubuntu Base and Ubuntu Developer |
| `demo-devops` | Sees Ubuntu Base, Ubuntu Developer, and Ubuntu DevOps |
| `demo-admin` | Sees all images and admin-capable behavior |

For the main remote desktop proof, use:

```text
demo-devops
```

Then:

1. Open the image catalog.
2. Launch Ubuntu DevOps.
3. Wait for the desktop to reach `Ready`.
4. Click Connect.
5. Open the Guacamole handoff URL.
6. Connect to the remote Ubuntu desktop.

Inside the remote desktop, open a terminal and run:

```bash
hostname
terraform version
helm version
kubectl version --client
python3 --version
git --version
```

This proves the tools are running inside the remote Ubuntu VDI VM, not on the thin client or browser machine.

## 21. Open Grafana

On the Windows host, open:

```text
https://grafana.vdiforge.local
```

Get the local Grafana password from `vdi-control-01`:

```bash
cat ~/vdiforge/.local/phase11/phase11.env
```

The username is normally:

```text
admin
```

Open:

```text
Dashboards -> VDIForge Overview
```

Use a longer time range such as `Last 24 hours` if panels show `No data` after the system has been idle.

## 22. Run The Final Manual Demo

The detailed portfolio demo is documented in [docs/DEMO.md](docs/DEMO.md).

The short version:

1. Show the three VirtualBox VMs.
2. Show `kubectl get nodes -o wide`.
3. Show KubeVirt and CDI health.
4. Open `https://vdiforge.local`.
5. Log in as `demo-devops`.
6. Show the authorized image catalog.
7. Launch Ubuntu DevOps.
8. Watch the VM/VMI appear:

   ```bash
   watch -n 2 'kubectl -n vdiforge-desktops get vm,vmi,dv,pvc,svc'
   ```

9. Wait for the desktop to become `Ready`.
10. Connect through Guacamole.
11. Run the remote terminal proof commands.
12. Show the Grafana `VDIForge Overview` dashboard.
13. Show an audit export:

   ```bash
   cd ~/vdiforge
   python3 scripts/phase12-api-security-test.py \
     --env .local/phase5/phase5.env \
     --ca .local/phase5/tls/vdiforge-local-ca.crt \
     --resolve-ip 192.168.56.11
   ```

14. Delete the desktop from the portal.
15. Verify Kubernetes cleanup.

## 23. Useful Health Checks

Run these from `vdi-control-01`:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl top nodes
kubectl get hpa -A
kubectl get kubevirt -n kubevirt
kubectl get cdi -n cdi
kubectl -n vdiforge-system get pods
kubectl -n vdiforge-desktops get vm,vmi,dv,pvc,svc
helm list -A
```

Run these from Windows:

```powershell
Resolve-DnsName vdiforge.local
Resolve-DnsName api.vdiforge.local
Resolve-DnsName auth.vdiforge.local
Resolve-DnsName remote.vdiforge.local
Resolve-DnsName grafana.vdiforge.local
```

## 24. Troubleshooting

| Problem | Most likely cause | First fix |
| --- | --- | --- |
| No `192.168.56.x` address in Ubuntu | Host-only adapter missing or netplan interface mismatch | Verify Adapter 2 is Host-only, run `ip -br addr`, update netplan interface names |
| `/dev/kvm` missing on `vdi-worker-02` | Nested virtualization not enabled or blocked by host settings | Power off VM, enable Nested VT-x/AMD-V, verify BIOS virtualization |
| `helm: command not found` | Helm only installed under `~/.local/bin` | Run `export PATH="$HOME/.local/bin:$PATH"` or `bash scripts/install-helm-client.sh` |
| Browser cannot resolve `vdiforge.local` | Windows hosts file missing entry | Rerun `scripts/phase5-windows-hosts-and-trust.ps1` as Administrator |
| Browser TLS warning | Local CA not trusted by Windows/browser | Copy the CA cert from `vdi-control-01` and rerun the Windows trust script |
| Grafana shows `No data` | Time range too short or system idle | Set Grafana to `Last 24 hours` and generate activity through the portal |
| Guacamole login page appears | Expired/invalid handoff URL or stale browser session | Generate a fresh Connect URL from the portal |
| Desktop quota exceeded | Too many non-terminal desktop records for the user | Delete active/ready desktops from the portal, then rerun the test |
| Migration job timed out | Previous Helm migration job or pending release state | Delete the old `vdiforge-api-migrations` job and rerun the install script |
| Pod stuck `Pending` | CPU/RAM/storage pressure | Check `kubectl describe pod`, node capacity, PVC status, and quotas |

## 25. Teardown

These commands are destructive. Run them only when you intentionally want to remove the lab services or VMs.

Remove the VDIForge application release:

```bash
helm uninstall vdiforge -n vdiforge-system
```

Remove monitoring:

```bash
helm uninstall vdiforge-monitoring -n monitoring
```

Remove disposable desktop resources:

```bash
kubectl -n vdiforge-desktops delete vm,vmi,dv,pvc,svc \
  -l app.kubernetes.io/part-of=vdiforge \
  --ignore-not-found=true
```

To remove the entire lab, power off and delete the three VirtualBox VMs from VirtualBox Manager. If you delete VM files, make sure you are deleting only the intended `vdi-control-01`, `vdi-worker-01`, and `vdi-worker-02` VM folders.

## 26. What Is Not Automated Yet

The repository is designed to be reproducible, but these parts are still intentionally manual or local-only:

1. Creating the three VirtualBox VMs.
2. Installing Ubuntu Server inside those VMs.
3. Building full QCOW2 golden images.
4. Trusting the local CA on each browser client.
5. Running the full browser/Guacamole/KubeVirt demo.

GitHub Actions validates code, manifests, scans, and container builds. It does not boot the home lab, build large golden images, or connect to the local VirtualBox cluster.

## 27. Next Documentation

Read these next:

1. [docs/LOCAL-INFRASTRUCTURE.md](docs/LOCAL-INFRASTRUCTURE.md)
2. [docs/KUBERNETES-KUBEVIRT.md](docs/KUBERNETES-KUBEVIRT.md)
3. [docs/KEYCLOAK-OIDC.md](docs/KEYCLOAK-OIDC.md)
4. [docs/GOLDEN-IMAGES.md](docs/GOLDEN-IMAGES.md)
5. [docs/API-CONTROL-PLANE.md](docs/API-CONTROL-PLANE.md)
6. [docs/REMOTE-DESKTOP.md](docs/REMOTE-DESKTOP.md)
7. [docs/WEB-PORTAL.md](docs/WEB-PORTAL.md)
8. [docs/PROMETHEUS-GRAFANA.md](docs/PROMETHEUS-GRAFANA.md)
9. [docs/SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md)
10. [docs/CI-CD.md](docs/CI-CD.md)
11. [docs/DEMO.md](docs/DEMO.md)
12. [docs/PORTFOLIO-SUMMARY.md](docs/PORTFOLIO-SUMMARY.md)
