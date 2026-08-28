#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

NS="${PHASE6_NAMESPACE:-vdiforge-desktops}"
VM="${PHASE6_VM_NAME:-phase6-ubuntu-devops}"
DV="${PHASE6_DATAVOLUME_NAME:-phase6-ubuntu-devops-test-dv}"
EXPECTED_NODE="${PHASE6_EXPECTED_NODE:-vdi-worker-02}"
BUILD_HOST="${PHASE6_BUILD_HOST:-192.168.56.12}"
BUILD_HOST_USER="${PHASE6_BUILD_HOST_USER:-vdiadmin}"
BUILD_HOST_SSH_KEY="${PHASE6_BUILD_HOST_SSH_KEY:-${HOME}/.ssh/vdiforge_ansible}"
BUILD_WORKDIR="${PHASE6_BUILD_WORKDIR:-/home/vdiadmin/vdiforge-phase6-build}"
IMAGE_VERSION="${VDIFORGE_IMAGE_VERSION:-1.0.0}"
IMAGE_FILE="${PHASE6_IMAGE_FILE:-${BUILD_WORKDIR}/artifacts/images/ubuntu-devops/${IMAGE_VERSION}/ubuntu-devops-${IMAGE_VERSION}-amd64.qcow2}"
HTTP_PORT="${PHASE6_HTTP_PORT:-18080}"
STORAGE_SIZE="${PHASE6_STORAGE_SIZE:-32Gi}"
TEST_USER="${PHASE6_TEST_USER:-vdiforge}"
TEST_KEY_DIR="${ROOT_DIR}/.local/phase6"
TEST_KEY="${TEST_KEY_DIR}/kubevirt_test_ed25519"
TEMPLATE="${ROOT_DIR}/kubernetes/kubevirt/phase6-ubuntu-devops-vm.template.yaml"
RENDERED="/tmp/vdiforge-phase6-ubuntu-devops-vm.yaml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ssh_build_host() {
  ssh -o BatchMode=yes -i "${BUILD_HOST_SSH_KEY}" "${BUILD_HOST_USER}@${BUILD_HOST}" "$@"
}

cleanup() {
  virtctl stop "${VM}" -n "${NS}" >/dev/null 2>&1 || true
  kubectl delete vm "${VM}" -n "${NS}" --ignore-not-found=true --wait=true --timeout=180s >/dev/null 2>&1 || true
  kubectl delete datavolume "${DV}" -n "${NS}" --ignore-not-found=true --wait=true --timeout=180s >/dev/null 2>&1 || true
  kubectl delete pvc "${DV}" -n "${NS}" --ignore-not-found=true --wait=true --timeout=180s >/dev/null 2>&1 || true
  ssh_build_host "if [[ -f /tmp/vdiforge-phase6-image-http.pid ]]; then kill \$(cat /tmp/vdiforge-phase6-image-http.pid) >/dev/null 2>&1 || true; rm -f /tmp/vdiforge-phase6-image-http.pid; fi; pkill -f 'python3 -m http.server ${HTTP_PORT} --bind ${BUILD_HOST}' >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
}

wait_for_datavolume() {
  kubectl wait "datavolume/${DV}" -n "${NS}" --for=condition=Ready --timeout=1200s >/dev/null
}

wait_vmi_ready() {
  kubectl wait "vmi/${VM}" -n "${NS}" --for=condition=Ready --timeout=900s >/dev/null
  local phase
  phase="$(kubectl get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.phase}')"
  [[ "${phase}" == "Running" ]] || fail "VMI phase is ${phase}, expected Running"
}

virt_ssh() {
  virtctl ssh \
    --namespace="${NS}" \
    --identity-file="${TEST_KEY}" \
    --known-hosts=/dev/null \
    --local-ssh-opts="-o StrictHostKeyChecking=no" \
    --local-ssh-opts="-o UserKnownHostsFile=/dev/null" \
    "$@"
}

wait_guest_ssh() {
  local attempt
  for attempt in $(seq 1 90); do
    if virt_ssh --command "echo ready" "${TEST_USER}@vm/${VM}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
  done
  fail "guest SSH did not become ready"
}

validate_running_vm() {
  local node launcher launcher_node kvm_allocatable launcher_kvm_request guest_ip

  node="$(kubectl get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.nodeName}')"
  [[ "${node}" == "${EXPECTED_NODE}" ]] || fail "VMI scheduled on ${node}, expected ${EXPECTED_NODE}"

  launcher="$(kubectl get pod -n "${NS}" -l "kubevirt.io=virt-launcher,app.kubernetes.io/name=phase6-ubuntu-devops" -o json | jq -r '.items[0].metadata.name // ""')"
  [[ -n "${launcher}" ]] || fail "virt-launcher pod was not found"

  launcher_node="$(kubectl get pod "${launcher}" -n "${NS}" -o jsonpath='{.spec.nodeName}')"
  [[ "${launcher_node}" == "${EXPECTED_NODE}" ]] || fail "virt-launcher scheduled on ${launcher_node}, expected ${EXPECTED_NODE}"

  kvm_allocatable="$(kubectl get node "${EXPECTED_NODE}" -o json | jq -r '.status.allocatable["devices.kubevirt.io/kvm"] // "0"')"
  [[ "${kvm_allocatable}" != "0" ]] || fail "KubeVirt KVM device is not allocatable on ${EXPECTED_NODE}"

  launcher_kvm_request="$(kubectl get pod "${launcher}" -n "${NS}" -o json | jq -r '[.spec.containers[].resources.requests["devices.kubevirt.io/kvm"] // empty] | first // "0"')"
  [[ "${launcher_kvm_request}" != "0" ]] || fail "virt-launcher pod did not request devices.kubevirt.io/kvm"

  guest_ip="$(kubectl get vmi "${VM}" -n "${NS}" -o json | jq -r '.status.interfaces[0].ipAddress // ""')"
  [[ -n "${guest_ip}" ]] || fail "VMI did not report a pod-network interface IP"

  echo "PASS: ${VM} Running on ${node}; KVM request ${launcher_kvm_request}; guest IP ${guest_ip}"
}

validate_guest_tools() {
  virt_ssh --command "hostname && ip route get 1.1.1.1 && terraform version && ansible --version | head -n 1 && kubectl version --client && helm version && python3 --version && git --version" "${TEST_USER}@vm/${VM}"
}

if [[ "${1:-}" == "--cleanup-only" ]]; then
  cleanup
  exit 0
fi

command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed"
command -v virtctl >/dev/null 2>&1 || fail "virtctl is not installed"
command -v jq >/dev/null 2>&1 || fail "jq is not installed"
command -v ssh-keygen >/dev/null 2>&1 || fail "ssh-keygen is not installed"

ssh_build_host "test -f '${IMAGE_FILE}'" || fail "image artifact not found on build host: ${IMAGE_FILE}"
IMAGE_SHA256="$(ssh_build_host "sha256sum '${IMAGE_FILE}' | awk '{print \$1}'")"
IMAGE_BASENAME="$(basename "${IMAGE_FILE}")"
IMAGE_URL="http://${BUILD_HOST}:${HTTP_PORT}/${IMAGE_BASENAME}"

mkdir -p "${TEST_KEY_DIR}"
if [[ ! -f "${TEST_KEY}" ]]; then
  ssh-keygen -t ed25519 -N "" -C "vdiforge-phase6-kubevirt-test" -f "${TEST_KEY}" >/dev/null
fi
chmod 600 "${TEST_KEY}"
SSH_PUBLIC_KEY="$(tr -d '\r\n' <"${TEST_KEY}.pub")"

cleanup
trap cleanup EXIT

ssh_build_host "cd '$(dirname "${IMAGE_FILE}")' || exit 1; nohup python3 -m http.server '${HTTP_PORT}' --bind '${BUILD_HOST}' >/tmp/vdiforge-phase6-image-http.log 2>&1 </dev/null & echo \$! >/tmp/vdiforge-phase6-image-http.pid"
sleep 3
curl -fsI "${IMAGE_URL}" >/dev/null || fail "image artifact HTTP endpoint is not reachable: ${IMAGE_URL}"

sed \
  -e "s|__DATAVOLUME_NAME__|${DV}|g" \
  -e "s|__IMAGE_URL__|${IMAGE_URL}|g" \
  -e "s|__IMAGE_SHA256__|${IMAGE_SHA256}|g" \
  -e "s|__STORAGE_SIZE__|${STORAGE_SIZE}|g" \
  -e "s|__VM_NAME__|${VM}|g" \
  -e "s|__TEST_USER__|${TEST_USER}|g" \
  -e "s|__SSH_PUBLIC_KEY__|${SSH_PUBLIC_KEY}|g" \
  "${TEMPLATE}" >"${RENDERED}"

kubectl apply -f "${RENDERED}" >/dev/null
virtctl start "${VM}" -n "${NS}" >/dev/null
wait_for_datavolume
wait_vmi_ready
validate_running_vm
wait_guest_ssh
validate_guest_tools

virtctl stop "${VM}" -n "${NS}" >/dev/null
kubectl wait "vmi/${VM}" -n "${NS}" --for=delete --timeout=300s >/dev/null

virtctl start "${VM}" -n "${NS}" >/dev/null
wait_vmi_ready
validate_running_vm
wait_guest_ssh
validate_guest_tools

cleanup
trap - EXIT

if kubectl get vm "${VM}" -n "${NS}" >/dev/null 2>&1 || kubectl get datavolume "${DV}" -n "${NS}" >/dev/null 2>&1 || kubectl get pvc "${DV}" -n "${NS}" >/dev/null 2>&1; then
  fail "disposable Phase 6 VM resources were not cleaned up"
fi

echo "PASS: ubuntu-devops:${IMAGE_VERSION} CDI import, KubeVirt KVM boot, tool validation, stop, restart, delete, and cleanup verified"
