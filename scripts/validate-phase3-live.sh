#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

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

check "ansible syntax for Phase 3 playbook" bash -c 'cd ansible && ANSIBLE_ROLES_PATH="${PWD}/roles" ansible-playbook -i inventory/local/hosts.yml playbooks/phase3.yml --syntax-check'
check "ansible-lint for Phase 3 Ansible content" bash -c 'cd ansible && ANSIBLE_ROLES_PATH="${PWD}/roles" ansible-lint playbooks roles'

check "expected Kubernetes node count" bash -c '[[ "$(kubectl get nodes --no-headers | wc -l)" -eq 3 ]]'
check "all nodes Ready" bash -c '[[ "$(kubectl get nodes --no-headers | awk '\''$2 != "Ready" { print }'\'' | wc -l)" -eq 0 ]]'
check "control-plane node exists" kubectl get node vdi-control-01
check "platform worker label" bash -c '[[ "$(kubectl get node vdi-worker-01 -o json | jq -r '\''.metadata.labels["vdiforge.io/node-role"] // ""'\'')" == "platform" ]]'
check "VDI worker label" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r '\''.metadata.labels["vdiforge.io/node-role"] // ""'\'')" == "vdi" ]]'

check_output "node status" kubectl get nodes -o wide
check_output "node labels" kubectl get nodes --show-labels
check_output "cluster pods" kubectl get pods -A
check "no unexpected Pending pods" bash -c '! kubectl get pods -A --no-headers | awk "{print \$4}" | grep -E "Pending|CrashLoopBackOff|ImagePullBackOff|ErrImagePull"'

check "CoreDNS rollout" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Calico tigerastatus available" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "Metrics Server rollout" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "node metrics available" kubectl top nodes
check "pod metrics available" kubectl top pods -A

check "storage class exists" kubectl get storageclass vdiforge-local-path
check "KubeVirt available" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "KubeVirt KVM resource on VDI worker" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'

check "NetworkPolicy enforcement" bash scripts/phase3-networkpolicy-test.sh
check "KubeVirt disposable test VM lifecycle" bash scripts/phase3-kubevirt-test-vm.sh

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 3 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

echo "Phase 3 live validation: PASS"
