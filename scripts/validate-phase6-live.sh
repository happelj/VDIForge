#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ -z "${HELM_BIN:-}" ]]; then
  if [[ -x "${HOME}/.local/bin/helm" ]]; then
    HELM_BIN="${HOME}/.local/bin/helm"
  else
    HELM_BIN="helm"
  fi
fi

BUILD_HOST="${PHASE6_BUILD_HOST:-192.168.56.12}"
BUILD_HOST_USER="${PHASE6_BUILD_HOST_USER:-vdiadmin}"
BUILD_HOST_SSH_KEY="${PHASE6_BUILD_HOST_SSH_KEY:-${HOME}/.ssh/vdiforge_ansible}"
BUILD_WORKDIR="${PHASE6_BUILD_WORKDIR:-/home/vdiadmin/vdiforge-phase6-build}"
EXPECTED_PACKER_VERSION="${EXPECTED_PACKER_VERSION:-1.16.0}"
EXPECTED_QEMU_PLUGIN_VERSION="${EXPECTED_QEMU_PLUGIN_VERSION:-1.1.6}"
EXPECTED_ANSIBLE_PLUGIN_VERSION="${EXPECTED_ANSIBLE_PLUGIN_VERSION:-1.1.6}"
EXPECTED_NODE="${PHASE6_EXPECTED_NODE:-vdi-worker-02}"

FAILURES=0

check() {
  local name="$1"
  shift
  echo "CHECK: ${name}"
  if "$@"; then
    echo "PASS: ${name}"
  else
    echo "FAIL: ${name}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

check_output() {
  local name="$1"
  shift
  echo "CHECK: ${name}"
  if output="$("$@" 2>&1)"; then
    echo "${output}"
    echo "PASS: ${name}"
  else
    echo "${output}" >&2
    echo "FAIL: ${name}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

ssh_build_host() {
  ssh -o BatchMode=yes -i "${BUILD_HOST_SSH_KEY}" "${BUILD_HOST_USER}@${BUILD_HOST}" "$@"
}

helm_cmd() {
  "${HELM_BIN}" "$@"
}

all_nodes_ready() {
  local not_ready
  not_ready="$(kubectl get nodes --no-headers | awk '$2 != "Ready" { print }')"
  if [[ -n "${not_ready}" ]]; then
    echo "${not_ready}" >&2
    return 1
  fi
}

no_unexpected_pod_failures() {
  ! kubectl get pods -A --no-headers |
    awk '{print $4}' |
    grep -E 'Pending|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError'
}

build_host_toolchain_ready() {
  ssh_build_host "export PATH=\"\$HOME/.local/bin:\$PATH\"; kernel_image=\"/boot/vmlinuz-\$(uname -r)\"; command -v packer >/dev/null && packer version | grep -Eq 'v?${EXPECTED_PACKER_VERSION}' && command -v qemu-system-x86_64 >/dev/null && command -v qemu-img >/dev/null && command -v virt-sysprep >/dev/null && command -v ansible-playbook >/dev/null && command -v ansible-lint >/dev/null && test -r /dev/kvm && test -w /dev/kvm && test -r \"\$kernel_image\""
}

print_build_host_help() {
  cat >&2 <<EOF
The Phase 6 build host is not ready.
Run this once on vdi-worker-02 with interactive sudo, then start a new SSH session:

  cd ${BUILD_WORKDIR}
  sudo bash scripts/phase6-install-build-tools.sh

If ${BUILD_WORKDIR} does not exist yet, copy or clone this repository there first.
EOF
}

sync_repo_to_build_host() {
  ssh_build_host "mkdir -p '${BUILD_WORKDIR}'"
  tar \
    --exclude='.git' \
    --exclude='.local' \
    --exclude='artifacts' \
    --exclude='packer_cache' \
    --exclude='*.qcow2' \
    --exclude='*.raw' \
    --exclude='*.img' \
    --exclude='*.iso' \
    -cf - . |
    ssh_build_host "tar -xf - -C '${BUILD_WORKDIR}'"
}

image_ansible_validation() {
  ssh_build_host "cd '${BUILD_WORKDIR}/ansible' && ansible-playbook -i localhost, playbooks/image-ubuntu-base.yml --syntax-check && ansible-playbook -i localhost, playbooks/image-ubuntu-developer.yml --syntax-check && ansible-playbook -i localhost, playbooks/image-ubuntu-devops.yml --syntax-check && ansible-lint playbooks/image-ubuntu-base.yml playbooks/image-ubuntu-developer.yml playbooks/image-ubuntu-devops.yml"
}

packer_static_validation() {
  ssh_build_host "cd '${BUILD_WORKDIR}' && export PATH=\"\$HOME/.local/bin:\$PATH\"; mkdir -p .local/phase6; if [ ! -f .local/phase6/packer_ed25519 ]; then ssh-keygen -t ed25519 -N '' -C 'vdiforge-phase6-packer' -f .local/phase6/packer_ed25519 >/dev/null; fi; pub_key=\$(tr -d '\r\n' < .local/phase6/packer_ed25519.pub); for dir in packer/ubuntu-base packer/ubuntu-developer packer/ubuntu-devops; do image_name=\$(basename \"\$dir\"); printf 'image_version = \"1.0.0\"\nartifact_root = \"%s\"\nssh_private_key_file = \"%s\"\nssh_public_key = \"%s\"\nbuild_username = \"packer\"\n' '${BUILD_WORKDIR}/.local/phase6/static-validation-artifacts'\"\$image_name-\$\$\" '${BUILD_WORKDIR}/.local/phase6/packer_ed25519' \"\$pub_key\" > .local/phase6/static-validation-\"\$image_name\".pkrvars.hcl; packer init \"\$dir\" && packer fmt -check \"\$dir\" && packer validate -var-file=.local/phase6/static-validation-\"\$image_name\".pkrvars.hcl \"\$dir\"; done"
}

build_all_images() {
  ssh_build_host "cd '${BUILD_WORKDIR}' && export PATH=\"\$HOME/.local/bin:\$PATH\"; bash scripts/phase6-build-all.sh"
}

phase6_artifacts_exist() {
  ssh_build_host "test -f '${BUILD_WORKDIR}/artifacts/images/ubuntu-base/1.0.0/ubuntu-base-1.0.0-amd64.qcow2' && test -f '${BUILD_WORKDIR}/artifacts/images/ubuntu-developer/1.0.0/ubuntu-developer-1.0.0-amd64.qcow2' && test -f '${BUILD_WORKDIR}/artifacts/images/ubuntu-devops/1.0.0/ubuntu-devops-1.0.0-amd64.qcow2'"
}

phase6_manifests_exist() {
  ssh_build_host "test -f '${BUILD_WORKDIR}/artifacts/images/ubuntu-base/1.0.0/ubuntu-base-1.0.0.manifest.json' && test -f '${BUILD_WORKDIR}/artifacts/images/ubuntu-developer/1.0.0/ubuntu-developer-1.0.0.manifest.json' && test -f '${BUILD_WORKDIR}/artifacts/images/ubuntu-devops/1.0.0/ubuntu-devops-1.0.0.manifest.json'"
}

phase6_checksums_pass() {
  ssh_build_host "cd '${BUILD_WORKDIR}' && sha256sum -c artifacts/images/ubuntu-base/1.0.0/ubuntu-base-1.0.0.sha256 && sha256sum -c artifacts/images/ubuntu-developer/1.0.0/ubuntu-developer-1.0.0.sha256 && sha256sum -c artifacts/images/ubuntu-devops/1.0.0/ubuntu-devops-1.0.0.sha256"
}

tracked_artifact_scan() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ! git ls-files | grep -E '\.(qcow2|raw|img|iso|vdi|vmdk|ova|box)$|packer_cache|output-'
  else
    ! find . \
      \( -path './.git' -o -path './.local' -o -path './artifacts' -o -path './packer_cache' \) -prune -o \
      -type f \( -name '*.qcow2' -o -name '*.raw' -o -name '*.img' -o -name '*.iso' -o -name '*.vdi' -o -name '*.vmdk' -o -name '*.ova' -o -name '*.box' \) \
      -print | grep -q .
  fi
}

source_checksum_present() {
  grep -R "8196be9d7958059cb56c6c75c80fdf6cee8a8885bc149ea791d7db1c7ef93035" packer/ubuntu-*/variables.pkr.hcl >/dev/null
}

packer_plugins_pinned() {
  grep -R "source  = \"github.com/hashicorp/qemu\"" packer/ubuntu-*/*.pkr.hcl >/dev/null &&
    grep -R "source  = \"github.com/hashicorp/ansible\"" packer/ubuntu-*/*.pkr.hcl >/dev/null &&
    grep -R "version = \"${EXPECTED_QEMU_PLUGIN_VERSION}\"" packer/ubuntu-*/*.pkr.hcl >/dev/null &&
    grep -R "version = \"${EXPECTED_ANSIBLE_PLUGIN_VERSION}\"" packer/ubuntu-*/*.pkr.hcl >/dev/null
}

check_output "nodes before Phase 6 build" kubectl get nodes -o wide
check "all nodes Ready before Phase 6 build" all_nodes_ready
check "Calico available before Phase 6 build" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "CoreDNS rollout before Phase 6 build" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Metrics Server available before Phase 6 build" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "KubeVirt available before Phase 6 build" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before Phase 6 build" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "VDI worker exposes KubeVirt KVM resource" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'
check "StorageClass vdiforge-local-path exists" kubectl get storageclass vdiforge-local-path
check_output "node utilization before Phase 6 build" kubectl top nodes
check_output "Helm releases before Phase 6 build" helm_cmd list -A

check "image catalog validation" python3 scripts/validate-image-catalog.py
check "no generated image artifacts tracked by Git" tracked_artifact_scan
check "Ubuntu source checksum is pinned" source_checksum_present
check "Packer QEMU and Ansible plugins are pinned" packer_plugins_pinned
check "sync repository to Phase 6 build host" sync_repo_to_build_host

if ! build_host_toolchain_ready; then
  print_build_host_help
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: Phase 6 build host toolchain is ready"
  check_output "build host tool versions" ssh_build_host "export PATH=\"\$HOME/.local/bin:\$PATH\"; packer version; qemu-system-x86_64 --version | head -n 1; virt-sysprep --version; ansible --version | head -n 1; ansible-lint --version"
  check "Ansible image syntax and lint" image_ansible_validation
  check "Packer fmt and validate" packer_static_validation
  check "build base, developer, and devops images" build_all_images
  check "Phase 6 image artifacts exist" phase6_artifacts_exist
  check "Phase 6 image manifests exist" phase6_manifests_exist
  check "Phase 6 artifact checksums pass" phase6_checksums_pass
  check "ubuntu-devops CDI import and KubeVirt boot validation" bash scripts/phase6-cdi-kubevirt-test.sh
fi

check_output "nodes after Phase 6 validation" kubectl get nodes -o wide
check_output "pods after Phase 6 validation" kubectl get pods -A
check_output "KubeVirt status after Phase 6 validation" kubectl get kubevirt -n kubevirt
check_output "storage classes after Phase 6 validation" kubectl get storageclass
check_output "node utilization after Phase 6 validation" kubectl top nodes
check "all nodes Ready after Phase 6 validation" all_nodes_ready
check "no unexpected failed pods after Phase 6 validation" no_unexpected_pod_failures
check "KubeVirt KVM resource remains on VDI worker" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 6 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

echo "KubeVirt hardware acceleration: KUBEVIRT_KVM_VERIFIED"
echo "Phase 6 live validation: PASS"
