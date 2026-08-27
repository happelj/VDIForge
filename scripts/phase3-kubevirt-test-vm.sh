#!/usr/bin/env bash
set -euo pipefail

NS="vdiforge-desktops"
VM="phase3-cirros"
MANIFEST="kubernetes/kubevirt/phase3-test-vm.yaml"
EXPECTED_NODE="vdi-worker-02"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cleanup_vm() {
  virtctl stop "${VM}" -n "${NS}" >/dev/null 2>&1 || true
  kubectl delete vm "${VM}" -n "${NS}" --ignore-not-found=true --wait=true --timeout=180s >/dev/null 2>&1 || true
  kubectl delete datavolume "${VM}-dv" -n "${NS}" --ignore-not-found=true --wait=true --timeout=180s >/dev/null 2>&1 || true
  kubectl delete pvc "${VM}-dv" -n "${NS}" --ignore-not-found=true --wait=true --timeout=180s >/dev/null 2>&1 || true
}

wait_for_datavolume() {
  local attempts=60
  local attempt

  for attempt in $(seq 1 "${attempts}"); do
    if kubectl get "datavolume/${VM}-dv" -n "${NS}" >/dev/null 2>&1; then
      kubectl wait "datavolume/${VM}-dv" -n "${NS}" --for=condition=Ready --timeout=600s >/dev/null
      return 0
    fi
    sleep 5
  done

  fail "DataVolume ${VM}-dv was not created"
}

wait_vmi_ready() {
  kubectl wait "vmi/${VM}" -n "${NS}" --for=condition=Ready --timeout=300s >/dev/null
  local phase
  phase="$(kubectl get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.phase}')"
  [[ "${phase}" == "Running" ]] || fail "VMI phase is ${phase}, expected Running"
}

validate_running_vm() {
  local node launcher launcher_node kvm_allocatable launcher_kvm_request guest_ip

  node="$(kubectl get vmi "${VM}" -n "${NS}" -o jsonpath='{.status.nodeName}')"
  [[ "${node}" == "${EXPECTED_NODE}" ]] || fail "VMI scheduled on ${node}, expected ${EXPECTED_NODE}"

  launcher="$(kubectl get pod -n "${NS}" -l "kubevirt.io=virt-launcher,app.kubernetes.io/name=${VM}" -o json | jq -r '.items[0].metadata.name // ""')"
  if [[ -z "${launcher}" ]]; then
    kubectl get pod -n "${NS}" -o wide --show-labels >&2 || true
    fail "virt-launcher pod was not found"
  fi

  launcher_node="$(kubectl get pod "${launcher}" -n "${NS}" -o jsonpath='{.spec.nodeName}')"
  [[ "${launcher_node}" == "${EXPECTED_NODE}" ]] || fail "virt-launcher scheduled on ${launcher_node}, expected ${EXPECTED_NODE}"

  kvm_allocatable="$(kubectl get node "${EXPECTED_NODE}" -o json | jq -r '.status.allocatable["devices.kubevirt.io/kvm"] // "0"')"
  [[ "${kvm_allocatable}" != "0" ]] || fail "KubeVirt KVM device is not allocatable on ${EXPECTED_NODE}"

  launcher_kvm_request="$(kubectl get pod "${launcher}" -n "${NS}" -o json | jq -r '[.spec.containers[].resources.requests["devices.kubevirt.io/kvm"] // empty] | first // "0"')"
  [[ "${launcher_kvm_request}" != "0" ]] || fail "virt-launcher pod did not request devices.kubevirt.io/kvm"

  guest_ip="$(kubectl get vmi "${VM}" -n "${NS}" -o json | jq -r '.status.interfaces[0].ipAddress // ""')"
  [[ -n "${guest_ip}" ]] || fail "VMI did not report a pod-network interface IP"

  echo "PASS: ${VM} Running on ${EXPECTED_NODE} with KubeVirt KVM request ${launcher_kvm_request} and guest IP ${guest_ip}"
}

if [[ "${1:-}" == "--cleanup-only" ]]; then
  cleanup_vm
  exit 0
fi

command -v virtctl >/dev/null || fail "virtctl is not installed"
command -v jq >/dev/null || fail "jq is not installed"

cleanup_vm
trap cleanup_vm EXIT

kubectl apply -f "${MANIFEST}" >/dev/null
virtctl start "${VM}" -n "${NS}" >/dev/null

wait_for_datavolume
wait_vmi_ready
validate_running_vm

virtctl stop "${VM}" -n "${NS}" >/dev/null
kubectl wait "vmi/${VM}" -n "${NS}" --for=delete --timeout=300s >/dev/null

virtctl start "${VM}" -n "${NS}" >/dev/null
wait_vmi_ready
validate_running_vm

cleanup_vm
trap - EXIT

if kubectl get vm "${VM}" -n "${NS}" >/dev/null 2>&1 || kubectl get datavolume "${VM}-dv" -n "${NS}" >/dev/null 2>&1; then
  fail "disposable VM resources were not cleaned up"
fi

echo "PASS: KubeVirt test VM create, boot, stop, restart, delete, and cleanup verified"
