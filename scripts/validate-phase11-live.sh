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

VDIFORGE_RELEASE="${HELM_RELEASE:-vdiforge}"
VDIFORGE_NAMESPACE="${HELM_NAMESPACE:-vdiforge-system}"
MONITORING_RELEASE="${VDIFORGE_MONITORING_RELEASE:-vdiforge-monitoring}"
MONITORING_NAMESPACE="${VDIFORGE_MONITORING_NAMESPACE:-monitoring}"
CHART_DIR="${HELM_CHART:-helm/vdiforge}"
PHASE4_VALUES="${HELM_VALUES:-helm/vdiforge/values-local.yaml}"
PHASE5_VALUES="${HELM_PHASE5_VALUES:-helm/vdiforge/values-phase5-local.yaml}"
PHASE7_VALUES="${HELM_PHASE7_VALUES:-helm/vdiforge/values-phase7-local.yaml}"
PHASE8_VALUES="${HELM_PHASE8_VALUES:-helm/vdiforge/values-phase8-local.yaml}"
PHASE9_VALUES="${HELM_PHASE9_VALUES:-helm/vdiforge/values-phase9-local.yaml}"
PHASE10_VALUES="${HELM_PHASE10_VALUES:-helm/vdiforge/values-phase10-local.yaml}"
PHASE11_VALUES="${HELM_PHASE11_VALUES:-helm/vdiforge/values-phase11-local.yaml}"
AUTH_HOST="${VDIFORGE_AUTH_HOST:-auth.vdiforge.local}"
API_HOST="${VDIFORGE_API_HOST:-api.vdiforge.local}"
REMOTE_HOST="${VDIFORGE_REMOTE_HOST:-remote.vdiforge.local}"
PORTAL_HOST="${VDIFORGE_PORTAL_HOST:-vdiforge.local}"
GRAFANA_HOST="${VDIFORGE_GRAFANA_HOST:-grafana.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"
PHASE11_ENV_FILE="${VDIFORGE_PHASE11_ENV_FILE:-.local/phase11/phase11.env}"
PHASE11_FALLBACK_DIR="${VDIFORGE_PHASE11_FALLBACK_DIR:-${HOME}/vdiforge-phase11-validation/.local/phase11}"
REMOTE_REGRESSION_IMAGE_VERSION="${VDIFORGE_PHASE11_REMOTE_IMAGE_VERSION:-1.2.0}"
PROM_PORT="${VDIFORGE_PROMETHEUS_LOCAL_PORT:-19090}"
LOAD_LOG="${PHASE11_LOAD_LOG:-/tmp/vdiforge-phase11-load.log}"
RENDERED_MANIFEST="${RENDERED_MANIFEST:-/tmp/vdiforge-phase11-rendered.yaml}"

FAILURES=0
PROM_PID=""

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
  kubectl delete prometheusrule phase11-alert-validation -n "${MONITORING_NAMESPACE}" --ignore-not-found=true >/dev/null 2>&1 || true
  if [[ -n "${PROM_PID}" ]] && kill -0 "${PROM_PID}" >/dev/null 2>&1; then
    kill "${PROM_PID}" >/dev/null 2>&1 || true
    wait "${PROM_PID}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

helm_cmd() {
  "${HELM_BIN}" "$@"
}

ensure_helm_client() {
  if command -v "${HELM_BIN}" >/dev/null 2>&1 || [[ -x "${HELM_BIN}" ]]; then
    return 0
  fi
  bash scripts/install-helm-client.sh >/dev/null
  HELM_BIN="${HOME}/.local/bin/helm"
  command -v "${HELM_BIN}" >/dev/null 2>&1 || [[ -x "${HELM_BIN}" ]]
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

resolve_phase_runtime() {
  if [[ ! -f "${CA_CERT}" && -f "${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt" ]]; then
    CA_CERT="${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt"
  fi
  if [[ ! -f "${ENV_FILE}" && -f "${PHASE5_FALLBACK_DIR}/phase5.env" ]]; then
    ENV_FILE="${PHASE5_FALLBACK_DIR}/phase5.env"
  fi
  if [[ ! -f "${PHASE11_ENV_FILE}" && -f "${PHASE11_FALLBACK_DIR}/phase11.env" ]]; then
    PHASE11_ENV_FILE="${PHASE11_FALLBACK_DIR}/phase11.env"
  fi
}

render_phase11_chart() {
  helm_cmd template "${VDIFORGE_RELEASE}" "${CHART_DIR}" \
    --namespace "${VDIFORGE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --values "${PHASE9_VALUES}" \
    --values "${PHASE10_VALUES}" \
    --values "${PHASE11_VALUES}" >"${RENDERED_MANIFEST}"
}

curl_with_resolve() {
  local url="$1"
  curl -fsS \
    --cacert "${CA_CERT}" \
    --resolve "${AUTH_HOST}:443:${INGRESS_IP}" \
    --resolve "${API_HOST}:443:${INGRESS_IP}" \
    --resolve "${REMOTE_HOST}:443:${INGRESS_IP}" \
    --resolve "${PORTAL_HOST}:443:${INGRESS_IP}" \
    --resolve "${GRAFANA_HOST}:443:${INGRESS_IP}" \
    "${url}"
}

api_metrics_available() {
  local body
  body="$(curl_with_resolve "https://${API_HOST}/metrics")"
  grep -q "vdiforge_api_requests_total" <<<"${body}" &&
    grep -q "vdiforge_desktops_by_state" <<<"${body}"
}

api_health_available() {
  for _ in $(seq 1 18); do
    if curl_with_resolve "https://${API_HOST}/api/v1/health" >/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}

start_prometheus_port_forward() {
  local service
  service="$(kubectl get svc -n "${MONITORING_NAMESPACE}" "${MONITORING_RELEASE}-prometheus" \
    -o jsonpath='{.metadata.name}' 2>/dev/null || true)"
  if [[ -z "${service}" ]]; then
    service="$(kubectl get svc -n "${MONITORING_NAMESPACE}" \
      -l operated-prometheus=true \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  [[ -n "${service}" ]] || {
    echo "No Prometheus service found in namespace ${MONITORING_NAMESPACE}." >&2
    return 1
  }
  kubectl -n "${MONITORING_NAMESPACE}" port-forward "svc/${service}" "${PROM_PORT}:9090" >/tmp/vdiforge-phase11-prometheus-portforward.log 2>&1 &
  PROM_PID="$!"
  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${PROM_PORT}/-/ready" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  cat /tmp/vdiforge-phase11-prometheus-portforward.log >&2 || true
  return 1
}

prom_query() {
  local query="$1"
  curl -fsSG "http://127.0.0.1:${PROM_PORT}/api/v1/query" --data-urlencode "query=${query}"
}

prometheus_has_series() {
  local query="$1"
  prom_query "${query}" | jq -e '.status == "success" and (.data.result | length) > 0' >/dev/null
}

vdiforge_release_deployed() {
  [[ "$(helm_cmd status "${VDIFORGE_RELEASE}" --namespace "${VDIFORGE_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

monitoring_release_deployed() {
  [[ "$(helm_cmd status "${MONITORING_RELEASE}" --namespace "${MONITORING_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

grafana_dashboard_available() {
  # shellcheck disable=SC1090
  source "${PHASE11_ENV_FILE}"
  curl -fsS \
    --cacert "${CA_CERT}" \
    --resolve "${GRAFANA_HOST}:443:${INGRESS_IP}" \
    -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "https://${GRAFANA_HOST}/api/search?query=VDIForge" |
    jq -e '.[] | select(.title == "VDIForge Overview")' >/dev/null
}

temporary_alert_fires() {
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: phase11-alert-validation
  namespace: ${MONITORING_NAMESPACE}
  labels:
    app.kubernetes.io/part-of: vdiforge
    vdiforge.io/phase: "11"
spec:
  groups:
    - name: vdiforge.phase11.validation
      rules:
        - alert: VDIForgePhase11ValidationAlert
          expr: vector(1)
          for: 0s
          labels:
            severity: info
          annotations:
            summary: temporary Phase 11 alert validation
EOF
  for _ in $(seq 1 60); do
    if prometheus_has_series 'ALERTS{alertname="VDIForgePhase11ValidationAlert",alertstate="firing"}'; then
      kubectl delete prometheusrule phase11-alert-validation -n "${MONITORING_NAMESPACE}" >/dev/null
      return 0
    fi
    sleep 5
  done
  kubectl delete prometheusrule phase11-alert-validation -n "${MONITORING_NAMESPACE}" --ignore-not-found=true >/dev/null
  return 1
}

run_safe_hpa_load() {
  rm -f "${LOAD_LOG}"
  python3 scripts/load-test-api.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --duration 60 \
    --concurrency 8 \
    --iterations 150000 >"${LOAD_LOG}" 2>&1
  local status=$?
  cat "${LOAD_LOG}"
  return "${status}"
}

run_desktop_lifecycle() {
  python3 scripts/phase8-remote-desktop-e2e-test.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --expected-image-version "${REMOTE_REGRESSION_IMAGE_VERSION}"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    return 1
  }
}

check "kubectl exists" require_tool kubectl
check "jq exists" require_tool jq
check "curl exists" require_tool curl
check "python3 exists" require_tool python3
check "Helm client available or installed" ensure_helm_client

resolve_phase_runtime
check "Phase 5 runtime env and CA available" bash -c "[[ -f '${ENV_FILE}' && -f '${CA_CERT}' ]]"

check_output "nodes before Phase 11" kubectl get nodes -o wide
check "all nodes Ready before Phase 11" all_nodes_ready
check "Calico available before Phase 11" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "CoreDNS rollout before Phase 11" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Metrics Server available before Phase 11" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "KubeVirt available before Phase 11" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before Phase 11" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "KubeVirt KVM resource remains on VDI worker" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'
check_output "node metrics before Phase 11" kubectl top nodes

check "install or upgrade Phase 11 monitoring stack" bash scripts/phase11-install-monitoring.sh
resolve_phase_runtime

check "Helm lint with Phase 11 values" helm_cmd lint "${CHART_DIR}" --values "${PHASE4_VALUES}" --values "${PHASE5_VALUES}" --values "${PHASE7_VALUES}" --values "${PHASE8_VALUES}" --values "${PHASE9_VALUES}" --values "${PHASE10_VALUES}" --values "${PHASE11_VALUES}"
check "Helm template render with Phase 11 values" render_phase11_chart
check "rendered ServiceMonitor resources exist" bash -c "grep -q 'kind: ServiceMonitor' '${RENDERED_MANIFEST}'"
check "rendered PrometheusRule exists" bash -c "grep -q 'kind: PrometheusRule' '${RENDERED_MANIFEST}'"
check "rendered Grafana dashboard ConfigMap exists" bash -c "grep -q 'VDIForge Overview' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no cluster-admin" bash -c "! grep -Eq 'cluster-admin|ClusterRoleBinding' '${RENDERED_MANIFEST}'"
check "rendered manifests avoid direct nodeName scheduling" bash -c "! grep -Eq 'nodeName:' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no plaintext Grafana password" bash -c "! grep -Eiq 'admin-password:|GRAFANA_ADMIN_PASSWORD=' '${RENDERED_MANIFEST}'"

check "VDIForge release deployed" vdiforge_release_deployed
check "monitoring release deployed" monitoring_release_deployed
check "Keycloak rollout" kubectl -n keycloak rollout status deployment/vdiforge-keycloak --timeout=300s
check "API rollout" kubectl -n "${VDIFORGE_NAMESPACE}" rollout status deployment/vdiforge-api --timeout=300s
check "provisioner rollout" kubectl -n "${VDIFORGE_NAMESPACE}" rollout status deployment/vdiforge-provisioner --timeout=300s
check "Prometheus StatefulSet ready" kubectl -n "${MONITORING_NAMESPACE}" rollout status statefulset/prometheus-vdiforge-monitoring-prometheus --timeout=600s
check "Alertmanager StatefulSet ready" kubectl -n "${MONITORING_NAMESPACE}" rollout status statefulset/alertmanager-vdiforge-monitoring-alertmanager --timeout=600s
check "Grafana Deployment ready" kubectl -n "${MONITORING_NAMESPACE}" rollout status deployment/vdiforge-monitoring-grafana --timeout=600s
check "VDIForge ServiceMonitors exist" bash -c "kubectl get servicemonitor -n '${MONITORING_NAMESPACE}' vdiforge-api vdiforge-provisioner >/dev/null"
check "VDIForge alert rules exist" kubectl get prometheusrule -n "${MONITORING_NAMESPACE}" vdiforge-alerts
check "VDIForge Grafana dashboard ConfigMap exists" kubectl get configmap -n "${MONITORING_NAMESPACE}" vdiforge-overview-dashboard
check "API metrics endpoint exports VDIForge metrics" api_metrics_available

check "Prometheus port-forward available" start_prometheus_port_forward
check "Prometheus sees VDIForge API target" prometheus_has_series 'up{namespace="vdiforge-system",service="vdiforge-api"}'
check "Prometheus sees VDIForge API request metric" prometheus_has_series 'vdiforge_api_requests_total'
check "Prometheus sees desktop state metric" prometheus_has_series 'vdiforge_desktops_by_state'
check "Prometheus sees HPA desired/current metrics" prometheus_has_series 'kube_horizontalpodautoscaler_status_desired_replicas{namespace="vdiforge-system",horizontalpodautoscaler="vdiforge-api"}'
check "Prometheus sees KubeVirt metrics" prometheus_has_series '{__name__=~"kubevirt_vmi.*"}'
check "Grafana HTTPS and dashboard search work" grafana_dashboard_available
check "temporary alert rule fires and is cleaned up" temporary_alert_fires
check "safe Phase 10 API load still passes" run_safe_hpa_load
check "Prometheus observes API load after test" prometheus_has_series 'rate(vdiforge_api_requests_total[5m])'
check "API rollout after load test" kubectl -n "${VDIFORGE_NAMESPACE}" rollout status deployment/vdiforge-api --timeout=300s
check "API health after load test" api_health_available
check "controlled desktop lifecycle still passes" run_desktop_lifecycle
check "Prometheus observes provisioning metrics after desktop lifecycle" prometheus_has_series 'vdiforge_desktop_provision_requests_total{result="accepted"}'
check "Prometheus observes active session metric" prometheus_has_series 'vdiforge_remote_sessions_active'

check_output "nodes after Phase 11" kubectl get nodes -o wide
check_output "pods after Phase 11" kubectl get pods -A
check_output "KubeVirt status after Phase 11" kubectl get kubevirt -n kubevirt
check_output "node metrics after Phase 11" kubectl top nodes
check_output "pod metrics after Phase 11" kubectl top pods -A
check_output "Helm releases after Phase 11" helm_cmd list -A
check "all nodes Ready after Phase 11" all_nodes_ready
check "no unexpected failed pods after Phase 11" no_unexpected_pod_failures
check "KubeVirt KVM resource remains after Phase 11" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 11 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

echo "KubeVirt hardware acceleration: KUBEVIRT_KVM_VERIFIED"
echo "Phase 11 live validation: PASS"
