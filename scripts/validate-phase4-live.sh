#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

HELM_BIN="${HELM_BIN:-${HOME}/.local/bin/helm}"
RELEASE="${HELM_RELEASE:-vdiforge}"
RELEASE_NAMESPACE="${HELM_NAMESPACE:-vdiforge-system}"
CHART_DIR="${HELM_CHART:-helm/vdiforge}"
VALUES_FILE="${HELM_VALUES:-helm/vdiforge/values-local.yaml}"
RENDERED_MANIFEST="${RENDERED_MANIFEST:-/tmp/vdiforge-phase4-rendered.yaml}"
BASELINE_MARKER="${BASELINE_MARKER:-phase4-baseline}"
UPGRADE_MARKER="${UPGRADE_MARKER:-phase4-upgrade}"
EXPECTED_HELM_VERSION="${EXPECTED_HELM_VERSION:-v4.2.4}"

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

helm_cmd() {
  "${HELM_BIN}" "$@"
}

current_helm_version() {
  helm_cmd version --template '{{ .Version }}'
}

config_marker() {
  kubectl get configmap "${RELEASE}-platform-config" \
    -n "${RELEASE_NAMESPACE}" \
    -o jsonpath='{.data.validationMarker}'
}

release_deployed() {
  [[ "$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

all_nodes_ready() {
  local not_ready
  not_ready="$(kubectl get nodes --no-headers | awk '$2 != "Ready" { print }')"
  if [[ -n "${not_ready}" ]]; then
    echo "${not_ready}" >&2
    return 1
  fi
}

expected_resources_exist() {
  kubectl get serviceaccount vdiforge-api -n vdiforge-system >/dev/null
  kubectl get serviceaccount vdiforge-provisioner -n vdiforge-system >/dev/null
  kubectl get role vdiforge-provisioner-vdi-manager -n vdiforge-desktops >/dev/null
  kubectl get rolebinding vdiforge-provisioner-vdi-manager -n vdiforge-desktops >/dev/null
  kubectl get configmap "${RELEASE}-platform-config" -n vdiforge-system >/dev/null
  kubectl get resourcequota vdiforge-system-quota -n vdiforge-system >/dev/null
  kubectl get resourcequota vdiforge-desktops-quota -n vdiforge-desktops >/dev/null
  kubectl get limitrange vdiforge-system-defaults -n vdiforge-system >/dev/null
  kubectl get networkpolicy vdiforge-system-default-deny -n vdiforge-system >/dev/null
  kubectl get networkpolicy vdiforge-system-allow-dns -n vdiforge-system >/dev/null
  kubectl get networkpolicy vdiforge-system-provisioner-kubernetes-api -n vdiforge-system >/dev/null
}

no_unexpected_pod_failures() {
  ! kubectl get pods -A --no-headers |
    awk '{print $4}' |
    grep -E 'Pending|CrashLoopBackOff|ImagePullBackOff|ErrImagePull'
}

render_chart() {
  helm_cmd template "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${VALUES_FILE}" >"${RENDERED_MANIFEST}"
}

helm_server_dry_run() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${VALUES_FILE}" \
    --set "platformConfig.validationMarker=${BASELINE_MARKER}" \
    --take-ownership \
    --force-conflicts \
    --dry-run=server >/dev/null
}

install_baseline() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${VALUES_FILE}" \
    --set "platformConfig.validationMarker=${BASELINE_MARKER}" \
    --take-ownership \
    --force-conflicts \
    --wait \
    --timeout 180s
}

upgrade_marker() {
  helm_cmd upgrade "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${VALUES_FILE}" \
    --set "platformConfig.validationMarker=${UPGRADE_MARKER}" \
    --take-ownership \
    --force-conflicts \
    --wait \
    --timeout 180s
}

check "Helm client exists" test -x "${HELM_BIN}"
check "Helm version is pinned" bash -c "[[ \"$(current_helm_version)\" == \"${EXPECTED_HELM_VERSION}\" ]]"
check_output "Helm version" helm_cmd version

check "helm lint" helm_cmd lint "${CHART_DIR}"
check "helm template render" render_chart
check "rendered manifests include recommended labels" bash -c "grep -q 'app.kubernetes.io/managed-by' '${RENDERED_MANIFEST}' && grep -q 'helm.sh/chart' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no cluster-admin binding" bash -c "! grep -Eq 'cluster-admin|ClusterRoleBinding' '${RENDERED_MANIFEST}'"
check "Helm server dry-run validation" helm_server_dry_run

check "all nodes Ready before Helm lifecycle" all_nodes_ready
check "KubeVirt available before Helm lifecycle" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before Helm lifecycle" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "Calico available before Helm lifecycle" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "Metrics Server available before Helm lifecycle" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s

check "Helm install baseline" install_baseline
BASELINE_REVISION="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.version')"
check "Helm release deployed after install" release_deployed
check "baseline marker applied" bash -c "[[ \"$(config_marker)\" == \"${BASELINE_MARKER}\" ]]"
check "expected foundation resources exist after install" expected_resources_exist
check_output "helm list" helm_cmd list --all-namespaces
check_output "helm status" helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}"

check "Helm upgrade marker" upgrade_marker
check "Helm release deployed after upgrade" release_deployed
check "upgrade marker applied" bash -c "[[ \"$(config_marker)\" == \"${UPGRADE_MARKER}\" ]]"
check "expected foundation resources exist after upgrade" expected_resources_exist

check "Helm repeated upgrade" upgrade_marker
check "Helm release deployed after repeated upgrade" release_deployed
check "repeated upgrade keeps expected marker" bash -c "[[ \"$(config_marker)\" == \"${UPGRADE_MARKER}\" ]]"
check "expected foundation resources exist after repeated upgrade" expected_resources_exist

check_output "helm history" helm_cmd history "${RELEASE}" --namespace "${RELEASE_NAMESPACE}"
check "Helm rollback to baseline revision" helm_cmd rollback "${RELEASE}" "${BASELINE_REVISION}" --namespace "${RELEASE_NAMESPACE}" --force-conflicts --wait --timeout 180s
check "Helm release deployed after rollback" release_deployed
check "rollback restored baseline marker" bash -c "[[ \"$(config_marker)\" == \"${BASELINE_MARKER}\" ]]"
check "expected foundation resources exist after rollback" expected_resources_exist

check_output "post-lifecycle node status" kubectl get nodes -o wide
check_output "post-lifecycle pods" kubectl get pods -A
check "no unexpected failed pods after Helm lifecycle" no_unexpected_pod_failures
check "CoreDNS rollout after Helm lifecycle" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Metrics Server node metrics after Helm lifecycle" kubectl top nodes
check "KubeVirt KVM resource remains on VDI worker" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'
check "KubeVirt available after Helm lifecycle" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available after Helm lifecycle" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 4 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

FINAL_REVISION="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.version')"
echo "Final Helm revision: ${FINAL_REVISION}"
echo "Phase 4 live validation: PASS"
