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
MONITORING_RELEASE="${VDIFORGE_MONITORING_RELEASE:-vdiforge-monitoring}"
MONITORING_NAMESPACE="${VDIFORGE_MONITORING_NAMESPACE:-monitoring}"
TRAEFIK_RELEASE="${VDIFORGE_TRAEFIK_RELEASE:-traefik}"
TRAEFIK_NAMESPACE="${VDIFORGE_TRAEFIK_NAMESPACE:-ingress-traefik}"
TRAEFIK_CHART_VERSION="${VDIFORGE_TRAEFIK_CHART_VERSION:-41.2.0}"
KUBE_PROM_STACK_VERSION="${VDIFORGE_KUBE_PROMETHEUS_STACK_VERSION:-88.6.1}"
CHART_DIR="${HELM_CHART:-helm/vdiforge}"
TRAEFIK_VALUES="${VDIFORGE_TRAEFIK_VALUES:-helm/traefik/values-local.yaml}"
MONITORING_VALUES="${VDIFORGE_MONITORING_VALUES:-monitoring/kube-prometheus-stack-values-local.yaml}"
PHASE4_VALUES="${HELM_VALUES:-helm/vdiforge/values-local.yaml}"
PHASE5_VALUES="${HELM_PHASE5_VALUES:-helm/vdiforge/values-phase5-local.yaml}"
PHASE7_VALUES="${HELM_PHASE7_VALUES:-helm/vdiforge/values-phase7-local.yaml}"
PHASE8_VALUES="${HELM_PHASE8_VALUES:-helm/vdiforge/values-phase8-local.yaml}"
PHASE9_VALUES="${HELM_PHASE9_VALUES:-helm/vdiforge/values-phase9-local.yaml}"
PHASE10_VALUES="${HELM_PHASE10_VALUES:-helm/vdiforge/values-phase10-local.yaml}"
PHASE11_VALUES="${HELM_PHASE11_VALUES:-helm/vdiforge/values-phase11-local.yaml}"
PHASE12_VALUES="${HELM_PHASE12_VALUES:-helm/vdiforge/values-phase12-local.yaml}"
AUTH_HOST="${VDIFORGE_AUTH_HOST:-auth.vdiforge.local}"
API_HOST="${VDIFORGE_API_HOST:-api.vdiforge.local}"
REMOTE_HOST="${VDIFORGE_REMOTE_HOST:-remote.vdiforge.local}"
PORTAL_HOST="${VDIFORGE_PORTAL_HOST:-vdiforge.local}"
GRAFANA_HOST="${VDIFORGE_GRAFANA_HOST:-grafana.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
CA_KEY="${VDIFORGE_PHASE5_CA_KEY:-.local/phase5/tls/vdiforge-local-ca.key}"
ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"
PHASE11_ENV_FILE="${VDIFORGE_PHASE11_ENV_FILE:-.local/phase11/phase11.env}"
PHASE11_FALLBACK_DIR="${VDIFORGE_PHASE11_FALLBACK_DIR:-${HOME}/vdiforge-phase11-validation/.local/phase11}"
API_IMAGE="${PHASE12_API_IMAGE:-localhost/vdiforge-api:0.12.0}"
API_IMAGE_TAR="${PHASE12_API_IMAGE_TAR:-/tmp/vdiforge-api-0.12.0.tar}"
FRONTEND_IMAGE="${PHASE12_FRONTEND_IMAGE:-localhost/vdiforge-frontend:0.9.0}"
FRONTEND_IMAGE_TAR="${PHASE12_FRONTEND_IMAGE_TAR:-/tmp/vdiforge-frontend-0.9.0.tar}"
REMOTE_IMAGE_VERSION="${VDIFORGE_PHASE12_REMOTE_IMAGE_VERSION:-1.2.0}"
RENDERED_MANIFEST="${RENDERED_MANIFEST:-/tmp/vdiforge-phase12-rendered.yaml}"
BROWSER_ARTIFACT="${VDIFORGE_PHASE12_BROWSER_ARTIFACT:-.local/phase12/browser-connection.json}"

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

ensure_helm_client() {
  if command -v "${HELM_BIN}" >/dev/null 2>&1 || [[ -x "${HELM_BIN}" ]]; then
    return 0
  fi
  bash scripts/install-helm-client.sh >/dev/null
  HELM_BIN="${HOME}/.local/bin/helm"
  export HELM_BIN
  [[ -x "${HELM_BIN}" ]]
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
  if [[ ! -f "${PHASE11_ENV_FILE}" && -f "${PHASE11_FALLBACK_DIR}/phase11.env" ]]; then
    PHASE11_ENV_FILE="${PHASE11_FALLBACK_DIR}/phase11.env"
  fi

  export VDIFORGE_PHASE5_CA_CERT="${CA_CERT}"
  export VDIFORGE_PHASE5_CA_KEY="${CA_KEY}"
  export VDIFORGE_PHASE5_ENV_FILE="${ENV_FILE}"
}

phase5_runtime_exists() {
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
    --values "${PHASE10_VALUES}" \
    --values "${PHASE11_VALUES}" \
    --values "${PHASE12_VALUES}" >"${RENDERED_MANIFEST}"
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
    --values "${PHASE11_VALUES}" \
    --values "${PHASE12_VALUES}" \
    --take-ownership \
    --force-conflicts \
    --dry-run=server >/dev/null
}

install_traefik() {
  helm_cmd repo add traefik https://traefik.github.io/charts --force-update >/dev/null
  helm_cmd repo update >/dev/null
  helm_cmd upgrade --install "${TRAEFIK_RELEASE}" traefik/traefik \
    --namespace "${TRAEFIK_NAMESPACE}" \
    --version "${TRAEFIK_CHART_VERSION}" \
    --values "${TRAEFIK_VALUES}" \
    --wait \
    --timeout 600s
  kubectl get crd middlewares.traefik.io >/dev/null
}

build_and_load_api_image() {
  PHASE7_IMAGE="${API_IMAGE}" \
    PHASE7_IMAGE_TAR="${API_IMAGE_TAR}" \
    bash scripts/phase7-build-load-image.sh
}

build_and_load_frontend_image() {
  PHASE9_FRONTEND_IMAGE="${FRONTEND_IMAGE}" \
    PHASE9_FRONTEND_IMAGE_TAR="${FRONTEND_IMAGE_TAR}" \
    bash scripts/phase9-build-load-frontend-image.sh
}

create_runtime_secrets() {
  resolve_phase5_runtime
  [[ -f "${CA_CERT}" && -f "${CA_KEY}" && -f "${ENV_FILE}" ]] || return 1
  bash scripts/phase7-create-local-secrets.sh
  bash scripts/phase8-create-local-secrets.sh
  bash scripts/phase9-create-local-secrets.sh
  bash scripts/phase11-create-local-secrets.sh
}

remove_previous_migration_job() {
  kubectl delete job vdiforge-api-migrations -n "${RELEASE_NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null
}

install_vdiforge_phase12() {
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
    --take-ownership \
    --force-conflicts \
    --wait \
    --wait-for-jobs \
    --timeout 900s
}

install_monitoring_phase12() {
  helm_cmd repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
  helm_cmd repo update >/dev/null
  helm_cmd upgrade --install "${MONITORING_RELEASE}" prometheus-community/kube-prometheus-stack \
    --version "${KUBE_PROM_STACK_VERSION}" \
    --namespace "${MONITORING_NAMESPACE}" \
    --values "${MONITORING_VALUES}" \
    --wait \
    --timeout 1200s
}

release_deployed() {
  [[ "$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

monitoring_release_deployed() {
  [[ "$(helm_cmd status "${MONITORING_RELEASE}" --namespace "${MONITORING_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

middleware_resources_exist() {
  kubectl get middleware vdiforge-frontend-security-headers -n "${RELEASE_NAMESPACE}" >/dev/null
  kubectl get middleware vdiforge-api-security-headers -n "${RELEASE_NAMESPACE}" >/dev/null
  kubectl get middleware vdiforge-keycloak-security-headers -n keycloak >/dev/null
  kubectl get middleware vdiforge-guacamole-security-headers -n guacamole >/dev/null
  kubectl get middleware vdiforge-grafana-security-headers -n "${MONITORING_NAMESPACE}" >/dev/null
}

api_version_is_phase12() {
  local body
  body="$(curl -fsS --cacert "${CA_CERT}" --resolve "${API_HOST}:443:${INGRESS_IP}" "https://${API_HOST}/api/v1/health")"
  grep -q '"version":"0.12.0"' <<<"${body}"
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

metrics_are_non_sensitive() {
  local metrics
  metrics="$(curl -fsS --cacert "${CA_CERT}" --resolve "${API_HOST}:443:${INGRESS_IP}" "https://${API_HOST}/metrics")"
  ! grep -Eiq 'access_token|refresh_token|authorization|password|credential|secret|request_id|user_subject|username' <<<"${metrics}" &&
    ! grep -Eiq '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"${metrics}"
}

kubevirt_kvm_verified() {
  [[ "$(kubectl get node vdi-worker-02 -o json | jq -r '.status.allocatable["devices.kubevirt.io/kvm"] // "0"')" != "0" ]]
}

secret_metadata_inventory() {
  bash scripts/phase12-inventory.sh
}

direct_db_services_not_external() {
  local bad
  bad="$(kubectl get svc -A -o json |
    jq -r '.items[] | select(.metadata.name | test("postgres|database"; "i")) | select(.spec.type != "ClusterIP") | "\(.metadata.namespace)/\(.metadata.name) \(.spec.type)"')"
  if [[ -n "${bad}" ]]; then
    echo "${bad}" >&2
    return 1
  fi
}

direct_rdp_not_externally_exposed() {
  local bad
  bad="$(kubectl get svc -n vdiforge-desktops -o json |
    jq -r '.items[] | select([.spec.ports[]?.port] | index(3389)) | select(.spec.type != "ClusterIP") | "\(.metadata.name) \(.spec.type)"')"
  if [[ -n "${bad}" ]]; then
    echo "${bad}" >&2
    return 1
  fi
}

run_phase12_networkpolicy_with_desktop() {
  mkdir -p "$(dirname "${BROWSER_ARTIFACT}")"
  local create_rc=0
  local desktop_service=""
  local network_rc=0
  local cleanup_rc=0

  python3 scripts/phase8-remote-desktop-e2e-test.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --expected-image-version "${REMOTE_IMAGE_VERSION}" \
    --browser-artifact "${BROWSER_ARTIFACT}" \
    --keep-desktop || create_rc=$?

  if [[ "${create_rc}" -eq 0 && -f "${BROWSER_ARTIFACT}" ]]; then
    desktop_service="$(jq -r '.service // .desktop.service // empty' "${BROWSER_ARTIFACT}")"
  fi
  if [[ "${create_rc}" -ne 0 || -z "${desktop_service}" ]]; then
    network_rc=1
  else
    VDIFORGE_PHASE12_DESKTOP_SERVICE="${desktop_service}" bash scripts/phase12-networkpolicy-test.sh || network_rc=$?
  fi
  python3 scripts/phase8-remote-desktop-e2e-test.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --cleanup-only || cleanup_rc=$?
  [[ "${network_rc}" -eq 0 && "${cleanup_rc}" -eq 0 ]]
}

run_browser_vdi_regression() {
  python3 scripts/phase8-remote-desktop-e2e-test.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}" \
    --expected-image-version "${REMOTE_IMAGE_VERSION}"
}

run_security_scans() {
  PHASE12_API_IMAGE_TAR="${API_IMAGE_TAR}" \
    PHASE12_FRONTEND_IMAGE_TAR="${FRONTEND_IMAGE_TAR}" \
    bash scripts/phase12-dependency-scan.sh
}

apply_keycloak_hardening() {
  bash scripts/phase12-keycloak-hardening.sh
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

check_output "nodes before Phase 12" kubectl get nodes -o wide
check "all nodes Ready before Phase 12" all_nodes_ready
check "Calico available before Phase 12" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "CoreDNS rollout before Phase 12" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Metrics Server available before Phase 12" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "KubeVirt available before Phase 12" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before Phase 12" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "KubeVirt KVM resource remains on vdi-worker-02" kubevirt_kvm_verified
check_output "node metrics before Phase 12" kubectl top nodes
check_output "HPA state before Phase 12" kubectl get hpa -A

check "build and load Phase 12 API image" build_and_load_api_image
check "build and load frontend image for scanning/regression" build_and_load_frontend_image
check "create or refresh Phase 7/8/9/11 runtime secrets without committing values" create_runtime_secrets
resolve_phase5_runtime
check "install or upgrade Traefik with CRD middleware support" install_traefik

check "Helm lint with Phase 12 values" helm_cmd lint "${CHART_DIR}" --values "${PHASE4_VALUES}" --values "${PHASE5_VALUES}" --values "${PHASE7_VALUES}" --values "${PHASE8_VALUES}" --values "${PHASE9_VALUES}" --values "${PHASE10_VALUES}" --values "${PHASE11_VALUES}" --values "${PHASE12_VALUES}"
check "Helm template render with Phase 12 values" render_chart
check "rendered Phase 12 middleware exists" bash -c "grep -q 'kind: Middleware' '${RENDERED_MANIFEST}' && grep -q 'contentSecurityPolicy' '${RENDERED_MANIFEST}'"
check "rendered API rate limit env exists" bash -c "grep -q 'VDIFORGE_API_RATE_LIMIT_ENABLED' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no cluster-admin or ClusterRoleBinding" bash -c "! grep -Eq 'cluster-admin|ClusterRoleBinding' '${RENDERED_MANIFEST}'"
check "rendered manifests avoid direct nodeName scheduling" bash -c "! grep -Eq 'nodeName:' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no plaintext secret values" bash -c "! grep -Eiq 'KEYCLOAK_ADMIN_PASSWORD:|GRAFANA_ADMIN_PASSWORD:|VDIFORGE_APP_DB_PASSWORD:|JSON_SECRET_KEY:|password: [A-Za-z0-9_./+=-]{12,}' '${RENDERED_MANIFEST}'"
check "Helm server dry-run validation" helm_server_dry_run

check "remove previous migration job if present" remove_previous_migration_job
check "install or upgrade VDIForge Phase 12 release" install_vdiforge_phase12
check "VDIForge release deployed" release_deployed
check "Keycloak rollout" kubectl -n keycloak rollout status deployment/vdiforge-keycloak --timeout=600s
check "API rollout" kubectl -n "${RELEASE_NAMESPACE}" rollout status deployment/vdiforge-api --timeout=600s
check "provisioner rollout" kubectl -n "${RELEASE_NAMESPACE}" rollout status deployment/vdiforge-provisioner --timeout=600s
check "frontend rollout" kubectl -n "${RELEASE_NAMESPACE}" rollout status deployment/vdiforge-frontend --timeout=600s
check "Guacamole rollout" kubectl -n guacamole rollout status deployment/vdiforge-guacamole --timeout=600s
check "API reports version 0.12.0" api_version_is_phase12
check "Phase 12 security middleware resources exist" middleware_resources_exist
check "Keycloak Phase 12 hardening applied" apply_keycloak_hardening

check "install or upgrade monitoring with Grafana security settings" install_monitoring_phase12
check "monitoring release deployed" monitoring_release_deployed
check "Grafana rollout" kubectl -n "${MONITORING_NAMESPACE}" rollout status deployment/vdiforge-monitoring-grafana --timeout=600s
check "Prometheus StatefulSet ready" kubectl -n "${MONITORING_NAMESPACE}" rollout status statefulset/prometheus-vdiforge-monitoring-prometheus --timeout=600s
check "Grafana trusted HTTPS works" grafana_https_works

check "portal trusted HTTPS works" portal_https_works
check "RBAC least-privilege validation" bash scripts/phase12-rbac-test.sh
check "HTTP security headers and CORS validation" bash scripts/phase12-security-headers-test.sh
check "Phase 12 API/OIDC/audit security validation" python3 scripts/phase12-api-security-test.py --env "${ENV_FILE}" --ca "${CA_CERT}" --resolve-ip "${INGRESS_IP}"
check "secret metadata inventory and access review" secret_metadata_inventory
check "database Services are not externally exposed" direct_db_services_not_external
check "RDP desktop Services are ClusterIP only" direct_rdp_not_externally_exposed
check "Prometheus metrics contain no sensitive high-cardinality labels" metrics_are_non_sensitive
check "NetworkPolicy validation with a disposable desktop" run_phase12_networkpolicy_with_desktop
check "browser VDI stop/start/reconnect/delete regression" run_browser_vdi_regression
check "dependency and custom container scans" run_security_scans

check_output "nodes after Phase 12" kubectl get nodes -o wide
check_output "pods after Phase 12" kubectl get pods -A
check_output "KubeVirt status after Phase 12" kubectl get kubevirt -n kubevirt
check_output "CDI status after Phase 12" kubectl get cdi -n cdi
check_output "storage classes after Phase 12" kubectl get storageclass
check_output "node metrics after Phase 12" kubectl top nodes
check_output "pod metrics after Phase 12" kubectl top pods -A
check_output "HPA state after Phase 12" kubectl get hpa -A
check_output "Helm releases after Phase 12" helm_cmd list -A
check "all nodes Ready after Phase 12" all_nodes_ready
check "no unexpected failed pods after Phase 12" no_unexpected_pod_failures
check "KubeVirt KVM resource remains after Phase 12" kubevirt_kvm_verified

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 12 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

FINAL_REVISION="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.version')"
MONITORING_REVISION="$(helm_cmd status "${MONITORING_RELEASE}" --namespace "${MONITORING_NAMESPACE}" --output json | jq -r '.version')"
echo "KubeVirt hardware acceleration: KUBEVIRT_KVM_VERIFIED"
echo "Final VDIForge Helm revision: ${FINAL_REVISION}"
echo "Final monitoring Helm revision: ${MONITORING_REVISION}"
echo "Phase 12 live validation: PASS"
