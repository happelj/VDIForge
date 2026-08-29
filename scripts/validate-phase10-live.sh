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
AUTH_HOST="${VDIFORGE_AUTH_HOST:-auth.vdiforge.local}"
API_HOST="${VDIFORGE_API_HOST:-api.vdiforge.local}"
PORTAL_HOST="${VDIFORGE_PORTAL_HOST:-vdiforge.local}"
REMOTE_HOST="${VDIFORGE_REMOTE_HOST:-remote.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
CA_KEY="${VDIFORGE_PHASE5_CA_KEY:-.local/phase5/tls/vdiforge-local-ca.key}"
ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"
API_IMAGE="${PHASE10_API_IMAGE:-localhost/vdiforge-api:0.10.0}"
API_IMAGE_TAR="${PHASE10_API_IMAGE_TAR:-/tmp/vdiforge-api-0.10.0.tar}"
RENDERED_MANIFEST="${RENDERED_MANIFEST:-/tmp/vdiforge-phase10-rendered.yaml}"
LOAD_LOG="${PHASE10_LOAD_LOG:-/tmp/vdiforge-phase10-load.log}"
LOAD_DURATION="${PHASE10_LOAD_DURATION:-180}"
LOAD_CONCURRENCY="${PHASE10_LOAD_CONCURRENCY:-20}"
LOAD_ITERATIONS="${PHASE10_LOAD_ITERATIONS:-150000}"
SCALE_UP_TIMEOUT="${PHASE10_SCALE_UP_TIMEOUT:-360}"
SCALE_DOWN_TIMEOUT="${PHASE10_SCALE_DOWN_TIMEOUT:-600}"
MIN_EXPECTED_REPLICAS="${PHASE10_MIN_EXPECTED_REPLICAS:-1}"
MAX_EXPECTED_REPLICAS="${PHASE10_MAX_EXPECTED_REPLICAS:-3}"
CPU_TARGET="${PHASE10_CPU_TARGET:-50}"
PLATFORM_NODE="${PHASE10_PLATFORM_NODE:-vdi-worker-01}"

FAILURES=0
LOAD_PID=""
PLATFORM_WORKER_BASELINE=""
PLATFORM_WORKER_PEAK_CPU_M=0
PLATFORM_WORKER_PEAK_MEMORY_MI=0

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

cleanup() {
  if [[ -n "${LOAD_PID}" ]] && kill -0 "${LOAD_PID}" >/dev/null 2>&1; then
    kill "${LOAD_PID}" >/dev/null 2>&1 || true
    wait "${LOAD_PID}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

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
    grep -E 'Pending|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|Evicted|Error'
}

resolve_phase5_runtime() {
  if [[ ! -f "${CA_CERT}" && -f "${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt" ]]; then
    CA_CERT="${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt"
  fi
  if [[ ! -f "${CA_KEY}" && -f "${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.key" ]]; then
    CA_KEY="${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.key"
  fi
  if [[ ! -f "${ENV_FILE}" && -f "${PHASE5_FALLBACK_DIR}/phase5.env" ]]; then
    ENV_FILE="${PHASE5_FALLBACK_DIR}/phase5.env"
  fi

  export VDIFORGE_PHASE5_CA_CERT="${CA_CERT}"
  export VDIFORGE_PHASE5_CA_KEY="${CA_KEY}"
  export VDIFORGE_PHASE5_ENV_FILE="${ENV_FILE}"
}

ensure_phase5_runtime() {
  resolve_phase5_runtime
  if [[ -f "${CA_CERT}" && -f "${CA_KEY}" && -f "${ENV_FILE}" ]]; then
    return 0
  fi
  bash scripts/phase5-create-local-secrets.sh >/dev/null
  resolve_phase5_runtime
  [[ -f "${CA_CERT}" && -f "${CA_KEY}" && -f "${ENV_FILE}" ]]
}

render_chart() {
  helm_cmd template "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --values "${PHASE9_VALUES}" \
    --values "${PHASE10_VALUES}" >"${RENDERED_MANIFEST}"
}

helm_server_dry_run() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --values "${PHASE9_VALUES}" \
    --values "${PHASE10_VALUES}" \
    --take-ownership \
    --force-conflicts \
    --dry-run=server >/dev/null
}

remove_previous_migration_job() {
  kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true >/dev/null
}

build_and_load_api_image() {
  PHASE7_IMAGE="${API_IMAGE}" \
    PHASE7_IMAGE_TAR="${API_IMAGE_TAR}" \
    bash scripts/phase7-build-load-image.sh
}

install_phase10_release() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --values "${PHASE9_VALUES}" \
    --values "${PHASE10_VALUES}" \
    --take-ownership \
    --force-conflicts \
    --wait \
    --wait-for-jobs \
    --timeout 900s
}

release_deployed() {
  [[ "$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

hpa_json() {
  kubectl get hpa vdiforge-api -n vdiforge-system -o json
}

hpa_desired() {
  hpa_json | jq -r '.status.desiredReplicas // 0'
}

hpa_current() {
  hpa_json | jq -r '.status.currentReplicas // 0'
}

hpa_cpu_utilization() {
  hpa_json | jq -r '.status.currentMetrics[]? | select(.type == "Resource" and .resource.name == "cpu") | .resource.current.averageUtilization // empty'
}

api_ready_replicas() {
  kubectl get deployment vdiforge-api -n vdiforge-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true
}

api_endpoint_count() {
  kubectl get endpointslice -n vdiforge-system \
    -l kubernetes.io/service-name=vdiforge-api \
    -o json |
    jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length'
}

api_pod_cpu_millicores() {
  kubectl top pods -n vdiforge-system -l app.kubernetes.io/component=api --no-headers 2>/dev/null |
    awk '{gsub(/m/, "", $2); sum += $2} END {print sum + 0}'
}

cpu_to_millicores() {
  local cpu="$1"
  if [[ "${cpu}" == *m ]]; then
    echo "${cpu%m}"
  else
    awk -v value="${cpu}" 'BEGIN { printf "%d", value * 1000 }'
  fi
}

memory_to_mib() {
  local memory="$1"
  case "${memory}" in
    *Ki) awk -v value="${memory%Ki}" 'BEGIN { printf "%d", value / 1024 }' ;;
    *Mi) echo "${memory%Mi}" ;;
    *Gi) awk -v value="${memory%Gi}" 'BEGIN { printf "%d", value * 1024 }' ;;
    *) echo "${memory}" | sed 's/[^0-9].*$//' ;;
  esac
}

update_platform_worker_peak() {
  local row cpu memory cpu_m memory_mi
  row="$(kubectl top node "${PLATFORM_NODE}" --no-headers 2>/dev/null || true)"
  [[ -n "${row}" ]] || return 0
  cpu="$(awk '{print $2}' <<<"${row}")"
  memory="$(awk '{print $4}' <<<"${row}")"
  cpu_m="$(cpu_to_millicores "${cpu}")"
  memory_mi="$(memory_to_mib "${memory}")"
  if [[ "${cpu_m}" =~ ^[0-9]+$ && "${cpu_m}" -gt "${PLATFORM_WORKER_PEAK_CPU_M}" ]]; then
    PLATFORM_WORKER_PEAK_CPU_M="${cpu_m}"
  fi
  if [[ "${memory_mi}" =~ ^[0-9]+$ && "${memory_mi}" -gt "${PLATFORM_WORKER_PEAK_MEMORY_MI}" ]]; then
    PLATFORM_WORKER_PEAK_MEMORY_MI="${memory_mi}"
  fi
}

desktop_vm_count() {
  kubectl get vm -n vdiforge-desktops --no-headers 2>/dev/null | wc -l | tr -d ' '
}

wait_for_hpa_metrics() {
  for _ in $(seq 1 36); do
    local cpu
    cpu="$(hpa_cpu_utilization || true)"
    if [[ "${cpu}" =~ ^[0-9]+$ ]]; then
      echo "${cpu}"
      return 0
    fi
    kubectl get hpa vdiforge-api -n vdiforge-system || true
    sleep 10
  done
  kubectl describe hpa vdiforge-api -n vdiforge-system >&2
  return 1
}

start_load() {
  rm -f "${LOAD_LOG}"
  python3 scripts/load-test-api.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --duration "${LOAD_DURATION}" \
    --concurrency "${LOAD_CONCURRENCY}" \
    --iterations "${LOAD_ITERATIONS}" >"${LOAD_LOG}" 2>&1 &
  LOAD_PID="$!"
}

wait_load() {
  set +e
  wait "${LOAD_PID}"
  local result=$?
  set -e
  LOAD_PID=""
  cat "${LOAD_LOG}"
  return "${result}"
}

wait_for_scale_up() {
  local started now elapsed ready desired cpu pod_cpu endpoints
  started="$(date +%s)"
  PEAK_REPLICAS="${BASELINE_REPLICAS}"
  PEAK_CPU="${BASELINE_CPU}"
  THRESHOLD_CROSSED="false"
  SCALE_UP_SECONDS=""

  while true; do
    now="$(date +%s)"
    elapsed=$((now - started))
    ready="$(api_ready_replicas)"
    [[ -n "${ready}" ]] || ready=0
    desired="$(hpa_desired)"
    cpu="$(hpa_cpu_utilization || true)"
    pod_cpu="$(api_pod_cpu_millicores)"
    endpoints="$(api_endpoint_count)"
    update_platform_worker_peak
    echo "HPA watch: elapsed=${elapsed}s desired=${desired} current=$(hpa_current) ready=${ready} endpoints=${endpoints} hpa_cpu=${cpu:-unknown}% pod_cpu=${pod_cpu}m"

    if [[ "${ready}" =~ ^[0-9]+$ && "${ready}" -gt "${PEAK_REPLICAS}" ]]; then
      PEAK_REPLICAS="${ready}"
    fi
    if [[ "${cpu}" =~ ^[0-9]+$ && "${cpu}" -gt "${PEAK_CPU}" ]]; then
      PEAK_CPU="${cpu}"
    fi
    if [[ "${cpu}" =~ ^[0-9]+$ && "${cpu}" -gt "${CPU_TARGET}" ]]; then
      THRESHOLD_CROSSED="true"
    fi
    if [[ "${ready}" =~ ^[0-9]+$ && "${ready}" -ge 2 && "${desired}" =~ ^[0-9]+$ && "${desired}" -ge 2 ]]; then
      SCALE_UP_SECONDS="${elapsed}"
      return 0
    fi
    if [[ "${elapsed}" -ge "${SCALE_UP_TIMEOUT}" ]]; then
      return 1
    fi
    sleep 10
  done
}

wait_for_scale_down() {
  local started now elapsed ready desired
  started="$(date +%s)"
  while true; do
    now="$(date +%s)"
    elapsed=$((now - started))
    ready="$(api_ready_replicas)"
    [[ -n "${ready}" ]] || ready=0
    desired="$(hpa_desired)"
    update_platform_worker_peak
    echo "HPA scale-down watch: elapsed=${elapsed}s desired=${desired} current=$(hpa_current) ready=${ready}"
    if [[ "${ready}" =~ ^[0-9]+$ && "${desired}" =~ ^[0-9]+$ && "${ready}" -le "${MIN_EXPECTED_REPLICAS}" && "${desired}" -le "${MIN_EXPECTED_REPLICAS}" ]]; then
      SCALE_DOWN_RESULT="PASS"
      SCALE_DOWN_SECONDS="${elapsed}"
      FINAL_REPLICAS="${ready}"
      return 0
    fi
    if [[ "${elapsed}" -ge "${SCALE_DOWN_TIMEOUT}" ]]; then
      SCALE_DOWN_RESULT="FAIL"
      FINAL_REPLICAS="${ready}"
      return 1
    fi
    sleep 15
  done
}

curl_with_resolve() {
  local url="$1"
  curl -fsS \
    --cacert "${CA_CERT}" \
    --resolve "${AUTH_HOST}:443:${INGRESS_IP}" \
    --resolve "${API_HOST}:443:${INGRESS_IP}" \
    --resolve "${REMOTE_HOST}:443:${INGRESS_IP}" \
    --resolve "${PORTAL_HOST}:443:${INGRESS_IP}" \
    "${url}"
}

portal_https_works() {
  local body
  body="$(curl_with_resolve "https://${PORTAL_HOST}/")"
  grep -q "VDIForge" <<<"${body}"
}

run_auth_consistency_checks() {
  python3 scripts/load-test-api.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --path /api/v1/images \
    --duration 15 \
    --concurrency 4 \
    --iterations "${LOAD_ITERATIONS}"
  python3 scripts/load-test-api.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --path /api/v1/desktops \
    --duration 15 \
    --concurrency 4 \
    --iterations "${LOAD_ITERATIONS}"
}

api_hpa_shape_valid() {
  local api_version min_replicas max_replicas target
  api_version="$(kubectl get hpa vdiforge-api -n vdiforge-system -o jsonpath='{.apiVersion}')"
  min_replicas="$(kubectl get hpa vdiforge-api -n vdiforge-system -o jsonpath='{.spec.minReplicas}')"
  max_replicas="$(kubectl get hpa vdiforge-api -n vdiforge-system -o jsonpath='{.spec.maxReplicas}')"
  target="$(hpa_json | jq -r '.spec.metrics[] | select(.resource.name == "cpu") | .resource.target.averageUtilization')"
  [[ "${api_version}" == "autoscaling/v2" && "${min_replicas}" == "${MIN_EXPECTED_REPLICAS}" && "${max_replicas}" == "${MAX_EXPECTED_REPLICAS}" && "${target}" == "${CPU_TARGET}" ]]
}

check "kubectl exists" command -v kubectl
check "jq exists" command -v jq
check "curl exists" command -v curl
check "python3 exists" command -v python3
check "Helm client exists" command -v "${HELM_BIN}"
check_output "Helm version" helm_cmd version

check_output "nodes before Phase 10" kubectl get nodes -o wide
check "all nodes Ready before Phase 10" all_nodes_ready
check "Calico available before Phase 10" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "CoreDNS rollout before Phase 10" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Metrics Server available before Phase 10" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "KubeVirt available before Phase 10" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before Phase 10" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "KubeVirt KVM resource remains on VDI worker" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'
check_output "node metrics before Phase 10" kubectl top nodes
check_output "pod metrics before Phase 10" kubectl top pods -A

check "Phase 5 runtime env and CA available" ensure_phase5_runtime
check "build and load Phase 10 API image" build_and_load_api_image
check "Helm lint with Phase 10 values" helm_cmd lint "${CHART_DIR}" --values "${PHASE4_VALUES}" --values "${PHASE5_VALUES}" --values "${PHASE7_VALUES}" --values "${PHASE8_VALUES}" --values "${PHASE9_VALUES}" --values "${PHASE10_VALUES}"
check "Helm template render with Phase 10 values" render_chart
check "rendered HPA uses autoscaling/v2" bash -c "grep -q 'apiVersion: autoscaling/v2' '${RENDERED_MANIFEST}' && grep -q 'kind: HorizontalPodAutoscaler' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no cluster-admin binding" bash -c "! grep -Eq 'cluster-admin|ClusterRoleBinding' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no hardcoded node names" bash -c "! grep -Eq 'vdi-control-01|vdi-worker-01|vdi-worker-02' '${RENDERED_MANIFEST}'"
check "Helm server dry-run validation" helm_server_dry_run

check "remove previous migration job if present" remove_previous_migration_job
check "install VDIForge Phase 10 release" install_phase10_release
check "VDIForge release deployed" release_deployed
check "API rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-api --timeout=300s
check "provisioner rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-provisioner --timeout=300s
check "frontend rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-frontend --timeout=300s
check "Guacamole rollout" kubectl -n guacamole rollout status deployment/vdiforge-guacamole --timeout=300s
check "API HPA exists with expected shape" api_hpa_shape_valid
check_output "HPA baseline" kubectl get hpa vdiforge-api -n vdiforge-system
check "HPA metrics resolve before load" wait_for_hpa_metrics
check "portal HTTPS remains functional before load" portal_https_works

BASELINE_REPLICAS="$(api_ready_replicas)"
[[ -n "${BASELINE_REPLICAS}" ]] || BASELINE_REPLICAS=0
BASELINE_CPU="$(hpa_cpu_utilization || true)"
[[ "${BASELINE_CPU}" =~ ^[0-9]+$ ]] || BASELINE_CPU=0
BASELINE_POD_CPU="$(api_pod_cpu_millicores)"
PLATFORM_WORKER_BASELINE="$(kubectl top node "${PLATFORM_NODE}" --no-headers 2>/dev/null || true)"
update_platform_worker_peak
DESKTOP_COUNT_BEFORE="$(desktop_vm_count)"

echo "Starting safe authenticated API load: duration=${LOAD_DURATION}s concurrency=${LOAD_CONCURRENCY} iterations=${LOAD_ITERATIONS}"
start_load
check "HPA scales API replicas up automatically" wait_for_scale_up
check "safe API load completed successfully" wait_load
check "CPU utilization crossed HPA threshold" bash -c "[[ '${THRESHOLD_CROSSED:-false}' == 'true' ]]"
check "new API replicas are represented in Service endpoints" bash -c "[[ \"$(api_endpoint_count)\" -ge 2 ]]"
check "authenticated API reads remain consistent after scale-up" run_auth_consistency_checks
check "portal HTTPS remains functional during/after scaling" portal_https_works
DESKTOP_COUNT_AFTER_LOAD="$(desktop_vm_count)"
check "load test did not create desktops" bash -c "[[ '${DESKTOP_COUNT_AFTER_LOAD}' == '${DESKTOP_COUNT_BEFORE}' ]]"

check "HPA scales API replicas down automatically" wait_for_scale_down
DESKTOP_COUNT_AFTER="$(desktop_vm_count)"
check "desktop count remains unchanged after scale-down" bash -c "[[ '${DESKTOP_COUNT_AFTER}' == '${DESKTOP_COUNT_BEFORE}' ]]"
update_platform_worker_peak

check_output "HPA final" kubectl get hpa vdiforge-api -n vdiforge-system
check_output "API deployment final" kubectl get deployment vdiforge-api -n vdiforge-system
check_output "node metrics after Phase 10" kubectl top nodes
check_output "pod metrics after Phase 10" kubectl top pods -A
check_output "helm releases after Phase 10" helm_cmd list -A
check_output "pods after Phase 10" kubectl get pods -A
check "all nodes Ready after Phase 10" all_nodes_ready
check "no unexpected failed pods after Phase 10" no_unexpected_pod_failures
check "KubeVirt available after Phase 10" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available after Phase 10" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 10 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

FINAL_REVISION="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.version')"
echo "Phase 10 autoscaling evidence:"
echo "baseline_replicas=${BASELINE_REPLICAS}"
echo "peak_replicas=${PEAK_REPLICAS}"
echo "baseline_cpu=${BASELINE_CPU}%"
echo "baseline_pod_cpu=${BASELINE_POD_CPU}m"
echo "peak_cpu=${PEAK_CPU}%"
echo "target_cpu=${CPU_TARGET}%"
echo "scale_up_seconds=${SCALE_UP_SECONDS}"
echo "scale_down_result=${SCALE_DOWN_RESULT}"
echo "scale_down_seconds=${SCALE_DOWN_SECONDS}"
echo "final_replicas=${FINAL_REPLICAS}"
echo "desktop_count_before=${DESKTOP_COUNT_BEFORE}"
echo "desktop_count_after=${DESKTOP_COUNT_AFTER}"
echo "platform_worker=${PLATFORM_NODE}"
echo "platform_worker_baseline=${PLATFORM_WORKER_BASELINE}"
echo "platform_worker_peak_cpu=${PLATFORM_WORKER_PEAK_CPU_M}m"
echo "platform_worker_peak_memory=${PLATFORM_WORKER_PEAK_MEMORY_MI}Mi"
echo "final_helm_revision=${FINAL_REVISION}"
echo "Phase 10 live validation: PASS"
