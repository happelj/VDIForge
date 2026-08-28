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
AUTH_HOST="${VDIFORGE_AUTH_HOST:-auth.vdiforge.local}"
API_HOST="${VDIFORGE_API_HOST:-api.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
CA_KEY="${VDIFORGE_PHASE5_CA_KEY:-.local/phase5/tls/vdiforge-local-ca.key}"
ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"
RENDERED_MANIFEST="${RENDERED_MANIFEST:-/tmp/vdiforge-phase7-rendered.yaml}"

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

  if [[ -f "${CA_CERT}" && -f "${CA_KEY}" && -f "${ENV_FILE}" ]] &&
    kubectl get secret vdiforge-keycloak-secrets -n keycloak >/dev/null &&
    kubectl get secret vdiforge-keycloak-tls -n keycloak >/dev/null; then
    echo "Using existing Phase 5 Keycloak runtime secrets and local CA."
    return 0
  fi

  bash scripts/phase5-create-local-secrets.sh
  resolve_phase5_runtime
  [[ -f "${CA_CERT}" && -f "${CA_KEY}" && -f "${ENV_FILE}" ]]
}

render_chart() {
  helm_cmd template "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" >"${RENDERED_MANIFEST}"
}

helm_server_dry_run() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --take-ownership \
    --dry-run=server >/dev/null
}

install_vdiforge_phase7() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --take-ownership \
    --wait \
    --wait-for-jobs \
    --timeout 900s
}

restart_phase7_deployments_for_local_image() {
  kubectl rollout restart deployment/vdiforge-api deployment/vdiforge-provisioner -n vdiforge-system
}

remove_previous_migration_job() {
  kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true >/dev/null
}

release_deployed() {
  [[ "$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

app_resources_exist() {
  kubectl get statefulset vdiforge-app-postgres -n vdiforge-system >/dev/null
  kubectl get service vdiforge-app-postgres -n vdiforge-system >/dev/null
  kubectl get deployment vdiforge-api -n vdiforge-system >/dev/null
  kubectl get deployment vdiforge-provisioner -n vdiforge-system >/dev/null
  kubectl get service vdiforge-api -n vdiforge-system >/dev/null
  kubectl get ingress vdiforge-api -n vdiforge-system >/dev/null
  kubectl get secret vdiforge-app-secrets -n vdiforge-system >/dev/null
  kubectl get secret vdiforge-api-tls -n vdiforge-system >/dev/null
  kubectl get secret vdiforge-api-keycloak-ca -n vdiforge-system >/dev/null
  kubectl get networkpolicy vdiforge-system-app-to-app-postgres -n vdiforge-system >/dev/null
  kubectl get networkpolicy vdiforge-system-app-postgres-ingress -n vdiforge-system >/dev/null
  kubectl get networkpolicy vdiforge-system-api-to-keycloak -n vdiforge-system >/dev/null
  kubectl get networkpolicy vdiforge-system-allow-api-ingress -n vdiforge-system >/dev/null
}

phase7_scheduled_on_platform_worker() {
  local bad_nodes
  bad_nodes="$(kubectl get pods -n vdiforge-system \
    -l 'app.kubernetes.io/component in (api,provisioner,app-database)' \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' |
    awk '$2 != "vdi-worker-01" { print }')"
  if [[ -n "${bad_nodes}" ]]; then
    echo "${bad_nodes}" >&2
    return 1
  fi
}

curl_json_with_retry() {
  local url="$1"
  local attempt
  for attempt in $(seq 1 24); do
    if curl -fsS \
      --cacert "${CA_CERT}" \
      --resolve "${API_HOST}:443:${INGRESS_IP}" \
      "${url}"; then
      return 0
    fi
    sleep 5
  done
  return 1
}

trusted_api_health() {
  local response
  response="$(curl_json_with_retry "https://${API_HOST}/api/v1/health")" || return 1
  jq -e '.status == "ok"' <<<"${response}" >/dev/null
}

trusted_api_ready() {
  local response
  response="$(curl_json_with_retry "https://${API_HOST}/api/v1/ready")" || return 1
  jq -e '.status == "ok" and .database == "ok" and .image_catalog == "ok"' <<<"${response}" >/dev/null
}

check "kubectl exists" command -v kubectl
check "jq exists" command -v jq
check "curl exists" command -v curl
check "python3 exists" command -v python3
check "Helm client exists" test -x "$(command -v "${HELM_BIN}" || echo "${HELM_BIN}")"
check_output "Helm version" helm_cmd version

check_output "nodes before Phase 7" kubectl get nodes -o wide
check "all nodes Ready before Phase 7" all_nodes_ready
check "Calico available before Phase 7" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "CoreDNS rollout before Phase 7" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Metrics Server available before Phase 7" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "KubeVirt available before Phase 7" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before Phase 7" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "KubeVirt KVM resource remains on VDI worker" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'
check_output "node metrics before Phase 7" kubectl top nodes

check "image catalog validation" python3 scripts/validate-image-catalog.py
check "Helm lint with Phase 7 values" helm_cmd lint "${CHART_DIR}" --values "${PHASE4_VALUES}" --values "${PHASE5_VALUES}" --values "${PHASE7_VALUES}"
check "Helm template render with Phase 7 values" render_chart
check "rendered manifests contain no cluster-admin binding" bash -c "! grep -Eq 'cluster-admin|ClusterRoleBinding' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no hardcoded node names" bash -c "! grep -Eq 'vdi-control-01|vdi-worker-01|vdi-worker-02' '${RENDERED_MANIFEST}'"
check "Helm server dry-run validation" helm_server_dry_run

check "Phase 5 Keycloak runtime secrets and local CA available" ensure_phase5_runtime
check "create Phase 7 app secrets and API TLS" bash scripts/phase7-create-local-secrets.sh
check "prepare ubuntu-devops golden source PVC" bash scripts/phase7-prepare-golden-source.sh
check "build and load Phase 7 API image" bash scripts/phase7-build-load-image.sh
check "remove previous Phase 7 migration job if present" remove_previous_migration_job
check "install VDIForge Phase 7 release" install_vdiforge_phase7
check "VDIForge release deployed" release_deployed
check "expected Phase 7 resources exist" app_resources_exist
check "restart Phase 7 deployments after local image import" restart_phase7_deployments_for_local_image
check "app PostgreSQL rollout" kubectl -n vdiforge-system rollout status statefulset/vdiforge-app-postgres --timeout=300s
check "API rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-api --timeout=300s
check "provisioner rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-provisioner --timeout=300s
check "Phase 7 pods scheduled on platform worker" phase7_scheduled_on_platform_worker
check "trusted HTTPS API health endpoint" trusted_api_health
check "trusted HTTPS API readiness endpoint" trusted_api_ready
check "Kubernetes RBAC least-privilege validation" bash scripts/phase7-rbac-test.sh
check "NetworkPolicy validation" bash scripts/phase7-networkpolicy-test.sh
check "OIDC/API/KubeVirt desktop lifecycle validation" python3 scripts/phase7-api-e2e-test.py --env "${ENV_FILE}" --ca "${CA_CERT}" --resolve-ip "${INGRESS_IP}"

check_output "nodes after Phase 7" kubectl get nodes -o wide
check_output "pods after Phase 7" kubectl get pods -A
check_output "KubeVirt status after Phase 7" kubectl get kubevirt -n kubevirt
check_output "storage classes after Phase 7" kubectl get storageclass
check_output "node metrics after Phase 7" kubectl top nodes
check_output "pod metrics after Phase 7" kubectl top pods -A
check_output "helm releases after Phase 7" helm_cmd list -A
check "all nodes Ready after Phase 7" all_nodes_ready
check "no unexpected failed pods after Phase 7" no_unexpected_pod_failures
check "KubeVirt KVM resource remains on VDI worker after Phase 7" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 7 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

FINAL_REVISION="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.version')"
echo "Final VDIForge Helm revision: ${FINAL_REVISION}"
echo "KubeVirt hardware acceleration: KUBEVIRT_KVM_VERIFIED"
echo "Phase 7 live validation: PASS"
