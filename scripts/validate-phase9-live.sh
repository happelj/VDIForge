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
AUTH_HOST="${VDIFORGE_AUTH_HOST:-auth.vdiforge.local}"
API_HOST="${VDIFORGE_API_HOST:-api.vdiforge.local}"
REMOTE_HOST="${VDIFORGE_REMOTE_HOST:-remote.vdiforge.local}"
PORTAL_HOST="${VDIFORGE_PORTAL_HOST:-vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
CA_KEY="${VDIFORGE_PHASE5_CA_KEY:-.local/phase5/tls/vdiforge-local-ca.key}"
ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"
IMAGE_VERSION="${VDIFORGE_IMAGE_VERSION:-1.2.0}"
IMAGE_VERSION_DASHED="${IMAGE_VERSION//./-}"
API_IMAGE="${PHASE9_API_IMAGE:-localhost/vdiforge-api:0.9.0}"
FRONTEND_IMAGE="${PHASE9_FRONTEND_IMAGE:-localhost/vdiforge-frontend:0.9.0}"
BUILD_HOST="${PHASE8_BUILD_HOST:-192.168.56.12}"
BUILD_HOST_USER="${PHASE8_BUILD_HOST_USER:-vdiadmin}"
BUILD_HOST_SSH_KEY="${PHASE8_BUILD_HOST_SSH_KEY:-${HOME}/.ssh/vdiforge_ansible}"
BUILD_WORKDIR="${PHASE8_BUILD_WORKDIR:-/home/vdiadmin/vdiforge-phase6-build}"
RENDERED_MANIFEST="${RENDERED_MANIFEST:-/tmp/vdiforge-phase9-rendered.yaml}"

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

ssh_build_host() {
  ssh -o BatchMode=yes -i "${BUILD_HOST_SSH_KEY}" "${BUILD_HOST_USER}@${BUILD_HOST}" "$@"
}

sync_repo_to_build_host() {
  ssh_build_host "mkdir -p '${BUILD_WORKDIR}'"
  tar \
    --exclude='.git' \
    --exclude='.local' \
    --exclude='artifacts' \
    --exclude='packer_cache' \
    --exclude='node_modules' \
    --exclude='frontend/dist' \
    --exclude='*.qcow2' \
    --exclude='*.raw' \
    --exclude='*.img' \
    --exclude='*.iso' \
    -cf - . |
    ssh_build_host "tar -xf - -C '${BUILD_WORKDIR}'"
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

phase9_source_is_ready() {
  local source_name="vdiforge-golden-ubuntu-devops-${IMAGE_VERSION_DASHED}"
  local dv_phase
  local pvc_phase
  dv_phase="$(kubectl get datavolume "${source_name}" -n vdiforge-desktops -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  pvc_phase="$(kubectl get pvc "${source_name}" -n vdiforge-desktops -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${dv_phase}" == "Succeeded" && "${pvc_phase}" == "Bound" ]]
}

vdi_worker_disk_pressure_clear() {
  local condition
  local taints
  condition="$(kubectl get node vdi-worker-02 -o jsonpath='{range .status.conditions[?(@.type=="DiskPressure")]}{.status}{end}' 2>/dev/null || true)"
  taints="$(kubectl get node vdi-worker-02 -o jsonpath='{.spec.taints}' 2>/dev/null || true)"
  [[ "${condition}" == "False" && "${taints}" != *"node.kubernetes.io/disk-pressure"* ]]
}

wait_for_vdi_worker_disk_pressure_clear() {
  for _ in $(seq 1 60); do
    if vdi_worker_disk_pressure_clear; then
      return 0
    fi
    sleep 5
  done
  kubectl describe node vdi-worker-02 | sed -n '/Conditions:/,/Addresses:/p' >&2
  kubectl get node vdi-worker-02 -o jsonpath='{.spec.taints}' >&2
  echo >&2
  return 1
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
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --values "${PHASE9_VALUES}" >"${RENDERED_MANIFEST}"
}

helm_server_dry_run() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --values "${PHASE9_VALUES}" \
    --take-ownership \
    --force-conflicts \
    --dry-run=server >/dev/null
}

install_phase9_release() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --values "${PHASE9_VALUES}" \
    --take-ownership \
    --force-conflicts \
    --wait \
    --wait-for-jobs \
    --timeout 900s
}

remove_previous_migration_job() {
  kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true >/dev/null
}

build_and_load_api_image() {
  PHASE7_IMAGE="${API_IMAGE}" \
    PHASE7_IMAGE_TAR="/tmp/vdiforge-api-0.9.0.tar" \
    bash scripts/phase7-build-load-image.sh
}

build_remote_image() {
  if phase9_source_is_ready; then
    echo "PASS: ubuntu-devops:${IMAGE_VERSION} source PVC already exists; skipping rebuild."
    return 0
  fi
  sync_repo_to_build_host
  ssh_build_host "cd '${BUILD_WORKDIR}' && export PATH=\"\$HOME/.local/bin:\$PATH\" && VDIFORGE_IMAGE_VERSION='${IMAGE_VERSION}' bash scripts/phase8-build-remote-image.sh"
}

prepare_remote_source() {
  VDIFORGE_IMAGE_VERSION="${IMAGE_VERSION}" bash scripts/phase8-prepare-remote-source.sh
}

remove_imported_build_artifact() {
  if ! phase9_source_is_ready; then
    echo "Source PVC for ubuntu-devops:${IMAGE_VERSION} is not ready; refusing to remove the build artifact." >&2
    return 1
  fi
  local artifact_dir="${BUILD_WORKDIR}/artifacts/images/ubuntu-devops/${IMAGE_VERSION}"
  ssh_build_host "rm -f '${artifact_dir}/ubuntu-devops-${IMAGE_VERSION}-amd64.qcow2' && df -h /"
  wait_for_vdi_worker_disk_pressure_clear
}

build_and_load_frontend_image() {
  PHASE9_FRONTEND_IMAGE="${FRONTEND_IMAGE}" bash scripts/phase9-build-load-frontend-image.sh
}

release_deployed() {
  [[ "$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

phase9_resources_exist() {
  kubectl get serviceaccount vdiforge-frontend -n vdiforge-system >/dev/null
  kubectl get configmap vdiforge-frontend-runtime-config -n vdiforge-system >/dev/null
  kubectl get deployment vdiforge-frontend -n vdiforge-system >/dev/null
  kubectl get service vdiforge-frontend -n vdiforge-system >/dev/null
  kubectl get ingress vdiforge-frontend -n vdiforge-system >/dev/null
  kubectl get secret vdiforge-portal-tls -n vdiforge-system >/dev/null
  kubectl get networkpolicy vdiforge-system-allow-frontend-ingress -n vdiforge-system >/dev/null
}

frontend_scheduled_on_platform_worker() {
  local bad_nodes
  bad_nodes="$(kubectl get pods -n vdiforge-system \
    -l app.kubernetes.io/component=frontend \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' |
    awk '$2 != "vdi-worker-01" { print }')"
  if [[ -n "${bad_nodes}" ]]; then
    echo "${bad_nodes}" >&2
    return 1
  fi
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

runtime_config_public_only() {
  local body
  body="$(curl_with_resolve "https://${PORTAL_HOST}/runtime-config.js")"
  grep -q "https://api.vdiforge.local" <<<"${body}" &&
    grep -q "https://auth.vdiforge.local/realms/vdiforge" <<<"${body}" &&
    ! grep -Eiq "password|client_secret|refresh_token|access_token" <<<"${body}"
}

api_cors_allows_portal() {
  local headers
  headers="$(curl -fsS -D - -o /dev/null \
    --cacert "${CA_CERT}" \
    --resolve "${API_HOST}:443:${INGRESS_IP}" \
    -X OPTIONS \
    -H "Origin: https://${PORTAL_HOST}" \
    -H "Access-Control-Request-Method: GET" \
    "https://${API_HOST}/api/v1/images")"
  grep -iq "access-control-allow-origin: https://${PORTAL_HOST}" <<<"${headers}"
}

keycloak_frontend_client_allows_portal() {
  curl_with_resolve "https://${AUTH_HOST}/realms/vdiforge/.well-known/openid-configuration" >/dev/null
}

run_phase9_portal_e2e() {
  python3 scripts/phase9-portal-e2e-test.py \
    --env "${ENV_FILE}" \
    --ca "${CA_CERT}" \
    --resolve-ip "${INGRESS_IP}"
}

check "kubectl exists" command -v kubectl
check "jq exists" command -v jq
check "curl exists" command -v curl
check "python3 exists" command -v python3
check "ssh exists" command -v ssh
check "Helm client available or installable" ensure_helm_client
check_output "Helm version" helm_cmd version

check_output "nodes before Phase 9" kubectl get nodes -o wide
check "all nodes Ready before Phase 9" all_nodes_ready
check "Calico available before Phase 9" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "CoreDNS rollout before Phase 9" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Metrics Server available before Phase 9" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "KubeVirt available before Phase 9" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before Phase 9" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "KubeVirt KVM resource remains on VDI worker" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'
check_output "node metrics before Phase 9" kubectl top nodes

check "Phase 5 runtime secrets and local CA available" ensure_phase5_runtime
check "create Phase 7 app/API secrets" bash scripts/phase7-create-local-secrets.sh
check "create Phase 8 Guacamole secrets" bash scripts/phase8-create-local-secrets.sh
check "create Phase 9 portal TLS secret" bash scripts/phase9-create-local-secrets.sh
check "image catalog validation" python3 scripts/validate-image-catalog.py
check "ubuntu-devops:${IMAGE_VERSION} remote-enabled image artifact" build_remote_image
check "prepare ubuntu-devops:${IMAGE_VERSION} source PVC" prepare_remote_source
check "remove imported ubuntu-devops:${IMAGE_VERSION} build-host QCOW2 artifact" remove_imported_build_artifact
check "build and load Phase 9 API image" build_and_load_api_image
check "build and load Phase 9 frontend image" build_and_load_frontend_image

check "Helm lint with Phase 9 values" helm_cmd lint "${CHART_DIR}" --values "${PHASE4_VALUES}" --values "${PHASE5_VALUES}" --values "${PHASE7_VALUES}" --values "${PHASE8_VALUES}" --values "${PHASE9_VALUES}"
check "Helm template render with Phase 9 values" render_chart
check "rendered manifests contain no cluster-admin binding" bash -c "! grep -Eq 'cluster-admin|ClusterRoleBinding' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no hardcoded node names" bash -c "! grep -Eq 'vdi-control-01|vdi-worker-01|vdi-worker-02' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no plaintext password values" bash -c "! grep -Eiq 'password:|client_secret:|VDIFORGE_.*PASSWORD=[^$]|JSON_SECRET_KEY: [a-f0-9]{32}' '${RENDERED_MANIFEST}'"
check "Helm server dry-run validation" helm_server_dry_run

check "remove previous migration job if present" remove_previous_migration_job
check "install VDIForge Phase 9 release" install_phase9_release
check "VDIForge release deployed" release_deployed
check "expected Phase 9 resources exist" phase9_resources_exist
check "frontend rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-frontend --timeout=300s
check "API rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-api --timeout=300s
check "provisioner rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-provisioner --timeout=300s
check "Guacamole rollout" kubectl -n guacamole rollout status deployment/vdiforge-guacamole --timeout=300s
check "frontend pod scheduled on platform worker" frontend_scheduled_on_platform_worker
check "portal trusted HTTPS endpoint" portal_https_works
check "portal runtime config public only" runtime_config_public_only
check "API CORS accepts portal origin" api_cors_allows_portal
check "Keycloak OIDC discovery still reachable" keycloak_frontend_client_allows_portal
check "Phase 9 portal/API/remote-desktop validation" run_phase9_portal_e2e

check_output "nodes after Phase 9" kubectl get nodes -o wide
check_output "pods after Phase 9" kubectl get pods -A
check_output "KubeVirt status after Phase 9" kubectl get kubevirt -n kubevirt
check_output "storage classes after Phase 9" kubectl get storageclass
check_output "node metrics after Phase 9" kubectl top nodes
check_output "pod metrics after Phase 9" kubectl top pods -A
check_output "helm releases after Phase 9" helm_cmd list -A
check "all nodes Ready after Phase 9" all_nodes_ready
check "no unexpected failed pods after Phase 9" no_unexpected_pod_failures
check "KubeVirt KVM resource remains on VDI worker after Phase 9" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 9 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

FINAL_REVISION="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.version')"
echo "Final VDIForge Helm revision: ${FINAL_REVISION}"
echo "KubeVirt hardware acceleration: KUBEVIRT_KVM_VERIFIED"
echo "Phase 9 live validation: PASS"
