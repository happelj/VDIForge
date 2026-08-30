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

RELEASE="${HELM_RELEASE:-vdiforge}"
RELEASE_NAMESPACE="${HELM_NAMESPACE:-vdiforge-system}"
CHART_DIR="${HELM_CHART:-helm/vdiforge}"
PHASE4_VALUES="${HELM_VALUES:-helm/vdiforge/values-local.yaml}"
PHASE5_VALUES="${HELM_PHASE5_VALUES:-helm/vdiforge/values-phase5-local.yaml}"
PHASE7_VALUES="${HELM_PHASE7_VALUES:-helm/vdiforge/values-phase7-local.yaml}"
PHASE8_VALUES="${HELM_PHASE8_VALUES:-helm/vdiforge/values-phase8-local.yaml}"
PHASE9_VALUES="${HELM_PHASE9_VALUES:-helm/vdiforge/values-phase9-local.yaml}"
PHASE10_VALUES="${HELM_PHASE10_VALUES:-helm/vdiforge/values-phase10-local.yaml}"
PHASE11_VALUES="${HELM_PHASE11_VALUES:-helm/vdiforge/values-phase11-local.yaml}"
PHASE12_VALUES="${HELM_PHASE12_VALUES:-helm/vdiforge/values-phase12-local.yaml}"
PHASE14_VALUES="${HELM_PHASE14_VALUES:-helm/vdiforge/values-phase14-local.yaml}"
MONITORING_NAMESPACE="${VDIFORGE_MONITORING_NAMESPACE:-monitoring}"
AUTH_HOST="${VDIFORGE_AUTH_HOST:-auth.vdiforge.local}"
API_HOST="${VDIFORGE_API_HOST:-api.vdiforge.local}"
PORTAL_HOST="${VDIFORGE_PORTAL_HOST:-vdiforge.local}"
REMOTE_HOST="${VDIFORGE_REMOTE_HOST:-remote.vdiforge.local}"
GRAFANA_HOST="${VDIFORGE_GRAFANA_HOST:-grafana.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"
API_IMAGE="${PHASE14_API_IMAGE:-localhost/vdiforge-api:0.14.0}"
API_IMAGE_TAR="${PHASE14_API_IMAGE_TAR:-/tmp/vdiforge-api-0.14.0.tar}"
REMOTE_IMAGE_VERSION="${VDIFORGE_PHASE14_REMOTE_IMAGE_VERSION:-1.2.0}"
RENDERED_MANIFEST="${RENDERED_MANIFEST:-/tmp/vdiforge-phase14-rendered.yaml}"
LOAD_DURATION="${VDIFORGE_PHASE14_LOAD_DURATION:-45}"
LOAD_CONCURRENCY="${VDIFORGE_PHASE14_LOAD_CONCURRENCY:-8}"
LOAD_ITERATIONS="${VDIFORGE_PHASE14_LOAD_ITERATIONS:-150000}"
BROWSER_ARTIFACT="${VDIFORGE_PHASE14_BROWSER_ARTIFACT:-.local/phase14/browser-connection.json}"

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
  local output
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

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    return 1
  }
}

phase14_static_if_available() {
  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -File ./scripts/validate-phase14.ps1
    return
  fi

  echo "pwsh is not installed on this Linux control node; run ./scripts/validate-phase14.ps1 from Windows or CI for static validation."
  return 0
}

ensure_helm_client() {
  if command -v "${HELM_BIN}" >/dev/null 2>&1 || [[ -x "${HELM_BIN}" ]]; then
    return 0
  fi
  bash scripts/install-helm-client.sh >/dev/null
  HELM_BIN="${HOME}/.local/bin/helm"
  export HELM_BIN
  [[ -x "${HELM_BIN}" ]]
}

resolve_phase5_runtime() {
  if [[ ! -f "${CA_CERT}" && -f "${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt" ]]; then
    CA_CERT="${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt"
  fi
  if [[ ! -f "${ENV_FILE}" && -f "${PHASE5_FALLBACK_DIR}/phase5.env" ]]; then
    ENV_FILE="${PHASE5_FALLBACK_DIR}/phase5.env"
  fi
  export VDIFORGE_PHASE5_CA_CERT="${CA_CERT}"
  export VDIFORGE_PHASE5_ENV_FILE="${ENV_FILE}"
}

phase5_runtime_exists() {
  resolve_phase5_runtime
  [[ -f "${CA_CERT}" && -f "${ENV_FILE}" ]]
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
    grep -E 'Pending|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|Evicted|Error'
}

kubevirt_kvm_verified() {
  [[ "$(kubectl get node vdi-worker-02 -o json | jq -r '.status.allocatable["devices.kubevirt.io/kvm"] // "0"')" != "0" ]]
}

render_chart() {
  helm_cmd template "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --values "${PHASE9_VALUES}" \
    --values "${PHASE10_VALUES}" \
    --values "${PHASE11_VALUES}" \
    --values "${PHASE12_VALUES}" \
    --values "${PHASE14_VALUES}" >"${RENDERED_MANIFEST}"
}

api_version_is_phase14() {
  local body
  body="$(curl -fsS --cacert "${CA_CERT}" --resolve "${API_HOST}:443:${INGRESS_IP}" "https://${API_HOST}/api/v1/health")"
  python3 - "${body}" <<'PY'
import json
import sys

version = tuple(int(part) for part in json.loads(sys.argv[1])["version"].split("."))
raise SystemExit(0 if version >= (0, 14, 0) else 1)
PY
}

build_and_load_api_image() {
  PHASE7_IMAGE="${API_IMAGE}" \
    PHASE7_IMAGE_TAR="${API_IMAGE_TAR}" \
    bash scripts/phase7-build-load-image.sh
}

remove_previous_migration_job() {
  kubectl delete job vdiforge-api-migrations -n "${RELEASE_NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null
}

install_vdiforge_phase14() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --values "${PHASE9_VALUES}" \
    --values "${PHASE10_VALUES}" \
    --values "${PHASE11_VALUES}" \
    --values "${PHASE12_VALUES}" \
    --values "${PHASE14_VALUES}" \
    --take-ownership \
    --force-conflicts \
    --wait \
    --wait-for-jobs \
    --timeout 900s
}

release_deployed() {
  [[ "$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

portal_https_works() {
  curl -fsS \
    --cacert "${CA_CERT}" \
    --resolve "${PORTAL_HOST}:443:${INGRESS_IP}" \
    "https://${PORTAL_HOST}/" |
    grep -q "VDIForge"
}

grafana_https_works() {
  curl -fsS \
    --cacert "${CA_CERT}" \
    --resolve "${GRAFANA_HOST}:443:${INGRESS_IP}" \
    "https://${GRAFANA_HOST}/login" >/dev/null
}

prometheus_query_works() {
  kubectl -n "${MONITORING_NAMESPACE}" port-forward svc/vdiforge-monitoring-prometheus 19090:9090 >/tmp/vdiforge-phase14-prometheus-port-forward.log 2>&1 &
  local pf_pid=$!
  trap "kill ${pf_pid} >/dev/null 2>&1 || true" RETURN
  sleep 5
  curl -fsS --get "http://127.0.0.1:19090/api/v1/query" --data-urlencode "query=up" | jq -e '.status == "success"' >/dev/null
  kill "${pf_pid}" >/dev/null 2>&1 || true
}

source_pvcs_ready() {
  local name
  for name in \
    vdiforge-golden-ubuntu-base-1-0-0 \
    vdiforge-golden-ubuntu-developer-1-0-0 \
    vdiforge-golden-ubuntu-devops-1-2-0; do
    [[ "$(kubectl get datavolume "${name}" -n vdiforge-desktops -o jsonpath='{.status.phase}' 2>/dev/null || true)" == "Succeeded" ]] || return 1
    [[ "$(kubectl get pvc "${name}" -n vdiforge-desktops -o jsonpath='{.status.phase}' 2>/dev/null || true)" == "Bound" ]] || return 1
  done
}

run_role_image_validation() {
  python3 scripts/phase14-role-image-test.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}"
}

run_portal_regression() {
  python3 scripts/phase9-portal-e2e-test.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}"
}

run_browser_vdi_regression() {
  mkdir -p "$(dirname "${BROWSER_ARTIFACT}")"
  python3 scripts/phase8-remote-desktop-e2e-test.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --expected-image-version "${REMOTE_IMAGE_VERSION}" \
    --browser-artifact "${BROWSER_ARTIFACT}"
}

run_hpa_load_regression() {
  python3 scripts/load-test-api.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --duration "${LOAD_DURATION}" \
    --concurrency "${LOAD_CONCURRENCY}" \
    --iterations "${LOAD_ITERATIONS}"
}

audit_export_works() {
  python3 scripts/phase12-api-security-test.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}"
}

check "kubectl exists" require_tool kubectl
check "jq exists" require_tool jq
check "curl exists" require_tool curl
check "python3 exists" require_tool python3
check "ssh exists" require_tool ssh
check "tar exists" require_tool tar
check "Helm client available or installable" ensure_helm_client
check_output "Helm version" helm_cmd version

resolve_phase5_runtime
check "Phase 5 runtime env and CA are available" phase5_runtime_exists

check_output "nodes before Phase 14" kubectl get nodes -o wide
check "all nodes Ready before Phase 14" all_nodes_ready
check "Calico available before Phase 14" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "CoreDNS rollout before Phase 14" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Metrics Server available before Phase 14" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "KubeVirt available before Phase 14" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before Phase 14" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "KubeVirt KVM resource remains on vdi-worker-02" kubevirt_kvm_verified
check_output "node metrics before Phase 14" kubectl top nodes
check_output "HPA state before Phase 14" kubectl get hpa -A

check "Phase 14 static validator on control node when pwsh is available" phase14_static_if_available
check "build and load Phase 14 API image" build_and_load_api_image
check "prepare all final-demo source image PVCs" bash scripts/phase14-prepare-demo-images.sh

check "Helm lint with Phase 14 values" helm_cmd lint "${CHART_DIR}" --values "${PHASE4_VALUES}" --values "${PHASE5_VALUES}" --values "${PHASE7_VALUES}" --values "${PHASE8_VALUES}" --values "${PHASE9_VALUES}" --values "${PHASE10_VALUES}" --values "${PHASE11_VALUES}" --values "${PHASE12_VALUES}" --values "${PHASE14_VALUES}"
check "Helm template render with Phase 14 values" render_chart
check "rendered manifests contain no cluster-admin or ClusterRoleBinding" bash -c "! grep -Eq 'cluster-admin|ClusterRoleBinding' '${RENDERED_MANIFEST}'"
check "rendered manifests avoid direct nodeName scheduling" bash -c "! grep -Eq 'nodeName:' '${RENDERED_MANIFEST}'"
check "remove previous migration job if present" remove_previous_migration_job
check "install or upgrade VDIForge Phase 14 release" install_vdiforge_phase14
check "VDIForge release deployed" release_deployed

check "Keycloak rollout" kubectl -n keycloak rollout status deployment/vdiforge-keycloak --timeout=600s
check "API rollout" kubectl -n "${RELEASE_NAMESPACE}" rollout status deployment/vdiforge-api --timeout=600s
check "provisioner rollout" kubectl -n "${RELEASE_NAMESPACE}" rollout status deployment/vdiforge-provisioner --timeout=600s
check "frontend rollout" kubectl -n "${RELEASE_NAMESPACE}" rollout status deployment/vdiforge-frontend --timeout=600s
check "Guacamole rollout" kubectl -n guacamole rollout status deployment/vdiforge-guacamole --timeout=600s
check "Grafana rollout" kubectl -n "${MONITORING_NAMESPACE}" rollout status deployment/vdiforge-monitoring-grafana --timeout=600s
check "Prometheus StatefulSet ready" kubectl -n "${MONITORING_NAMESPACE}" rollout status statefulset/prometheus-vdiforge-monitoring-prometheus --timeout=600s
check "API reports at least the Phase 14 API version" api_version_is_phase14
check "portal trusted HTTPS works" portal_https_works
check "Grafana trusted HTTPS works" grafana_https_works
check "Prometheus query API works through port-forward" prometheus_query_works
check "all final-demo source image PVCs are ready" source_pvcs_ready
check "role-specific final image catalog validation" run_role_image_validation
check "React portal API regression" run_portal_regression
check "DevOps browser VDI stop/start/reconnect/delete regression" run_browser_vdi_regression
check "safe HPA/load regression" run_hpa_load_regression
check "audit/security export regression" audit_export_works

check_output "nodes after Phase 14" kubectl get nodes -o wide
check_output "pods after Phase 14" kubectl get pods -A
check_output "KubeVirt status after Phase 14" kubectl get kubevirt -n kubevirt
check_output "CDI status after Phase 14" kubectl get cdi -n cdi
check_output "source image DataVolumes after Phase 14" kubectl -n vdiforge-desktops get datavolume,pvc
check_output "node labels after Phase 14" kubectl get nodes --show-labels
check_output "node metrics after Phase 14" kubectl top nodes
check_output "pod metrics after Phase 14" kubectl top pods -A
check_output "HPA state after Phase 14" kubectl get hpa -A
check_output "Helm releases after Phase 14" helm_cmd list -A
check "all nodes Ready after Phase 14" all_nodes_ready
check "no unexpected failed pods after Phase 14" no_unexpected_pod_failures
check "KubeVirt KVM resource remains after Phase 14" kubevirt_kvm_verified

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 14 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

FINAL_REVISION="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.version')"
echo "KubeVirt hardware acceleration: KUBEVIRT_KVM_VERIFIED"
echo "Final VDIForge Helm revision: ${FINAL_REVISION}"
echo "Manual browser proof remains the operator-facing demo check: open https://vdiforge.local, login as demo-devops, launch Ubuntu DevOps, connect through Guacamole, and run the documented remote commands."
echo "Phase 14 live validation: PASS"
