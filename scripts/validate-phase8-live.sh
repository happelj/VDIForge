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
AUTH_HOST="${VDIFORGE_AUTH_HOST:-auth.vdiforge.local}"
API_HOST="${VDIFORGE_API_HOST:-api.vdiforge.local}"
REMOTE_HOST="${VDIFORGE_REMOTE_HOST:-remote.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
CA_KEY="${VDIFORGE_PHASE5_CA_KEY:-.local/phase5/tls/vdiforge-local-ca.key}"
ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"
BUILD_HOST="${PHASE8_BUILD_HOST:-192.168.56.12}"
BUILD_HOST_USER="${PHASE8_BUILD_HOST_USER:-vdiadmin}"
BUILD_HOST_SSH_KEY="${PHASE8_BUILD_HOST_SSH_KEY:-${HOME}/.ssh/vdiforge_ansible}"
BUILD_WORKDIR="${PHASE8_BUILD_WORKDIR:-/home/vdiadmin/vdiforge-phase6-build}"
IMAGE_VERSION="${VDIFORGE_IMAGE_VERSION:-1.1.0}"
API_IMAGE="${PHASE8_API_IMAGE:-localhost/vdiforge-api:0.8.0}"
RENDERED_MANIFEST="${RENDERED_MANIFEST:-/tmp/vdiforge-phase8-rendered.yaml}"

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

ssh_build_host() {
  ssh -o BatchMode=yes -i "${BUILD_HOST_SSH_KEY}" "${BUILD_HOST_USER}@${BUILD_HOST}" "$@"
}

helm_cmd() {
  "${HELM_BIN}" "$@"
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
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" >"${RENDERED_MANIFEST}"
}

helm_server_dry_run() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --take-ownership \
    --force-conflicts \
    --dry-run=server >/dev/null
}

install_phase8_release() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --values "${PHASE7_VALUES}" \
    --values "${PHASE8_VALUES}" \
    --take-ownership \
    --force-conflicts \
    --wait \
    --wait-for-jobs \
    --timeout 900s
}

remove_previous_migration_job() {
  kubectl delete job vdiforge-api-migrations -n vdiforge-system --ignore-not-found=true --wait=true >/dev/null
}

recover_pending_helm_release() {
  local status history last_deployed

  if ! helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  status="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" -o json | jq -r '.info.status // ""')"
  case "${status}" in
    pending-install|pending-upgrade|pending-rollback)
      echo "Helm release ${RELEASE} is ${status}; rolling back to the last deployed revision."
      ;;
    *)
      return 0
      ;;
  esac

  history="$(helm_cmd history "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" -o json)"
  last_deployed="$(jq -r '[.[] | select(.status == "deployed")] | last | .revision // empty' <<<"${history}")"
  [[ -n "${last_deployed}" ]] || return 1

  remove_previous_migration_job
  helm_cmd rollback "${RELEASE}" "${last_deployed}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --force-conflicts \
    --wait \
    --timeout 300s
}

sync_repo_to_build_host() {
  ssh_build_host "mkdir -p '${BUILD_WORKDIR}'"
  tar \
    --exclude='.git' \
    --exclude='.local' \
    --exclude='artifacts' \
    --exclude='packer_cache' \
    --exclude='*.qcow2' \
    --exclude='*.raw' \
    --exclude='*.img' \
    --exclude='*.iso' \
    -cf - . |
    ssh_build_host "tar -xf - -C '${BUILD_WORKDIR}'"
}

remote_image_exists() {
  ssh_build_host "test -f '${BUILD_WORKDIR}/artifacts/images/ubuntu-devops/${IMAGE_VERSION}/ubuntu-devops-${IMAGE_VERSION}-amd64.qcow2'"
}

build_remote_image() {
  sync_repo_to_build_host
  ssh_build_host "cd '${BUILD_WORKDIR}' && export PATH=\"\$HOME/.local/bin:\$PATH\"; VDIFORGE_IMAGE_VERSION='${IMAGE_VERSION}' bash scripts/phase8-build-remote-image.sh"
}

build_remote_image_if_needed() {
  build_remote_image
}

build_and_load_api_image() {
  PHASE7_IMAGE="${API_IMAGE}" \
    PHASE7_IMAGE_TAR="/tmp/vdiforge-api-0.8.0.tar" \
    bash scripts/phase7-build-load-image.sh
}

release_deployed() {
  [[ "$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

phase8_resources_exist() {
  kubectl get deployment vdiforge-guacamole -n guacamole >/dev/null
  kubectl get deployment vdiforge-guacd -n guacamole >/dev/null
  kubectl get service vdiforge-guacamole -n guacamole >/dev/null
  kubectl get service vdiforge-guacd -n guacamole >/dev/null
  kubectl get ingress vdiforge-guacamole -n guacamole >/dev/null
  kubectl get secret vdiforge-guacamole-json-secret -n guacamole >/dev/null
  kubectl get secret vdiforge-guacamole-json-secret -n vdiforge-system >/dev/null
  kubectl get secret vdiforge-guacamole-tls -n guacamole >/dev/null
  kubectl get role vdiforge-api-remote-session-reader -n vdiforge-desktops >/dev/null
  kubectl get rolebinding vdiforge-api-remote-session-reader -n vdiforge-desktops >/dev/null
  kubectl get networkpolicy vdiforge-system-provisioner-to-desktop-rdp -n vdiforge-system >/dev/null
  kubectl get networkpolicy guacamole-default-deny -n guacamole >/dev/null
  kubectl get networkpolicy guacamole-guacd-to-vdi-rdp -n guacamole >/dev/null
}

phase8_scheduled_on_platform_worker() {
  local bad_nodes
  bad_nodes="$(kubectl get pods -n guacamole \
    -l 'app.kubernetes.io/component in (remote-access,guacd)' \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' |
    awk '$1 !~ /^phase8-/ && $2 != "vdi-worker-01" { print }')"
  if [[ -n "${bad_nodes}" ]]; then
    echo "${bad_nodes}" >&2
    return 1
  fi
}

curl_with_retry() {
  local url="$1"
  local attempt
  for attempt in $(seq 1 24); do
    if curl -fsS \
      --cacert "${CA_CERT}" \
      --resolve "${REMOTE_HOST}:443:${INGRESS_IP}" \
      --resolve "${API_HOST}:443:${INGRESS_IP}" \
      --resolve "${AUTH_HOST}:443:${INGRESS_IP}" \
      "${url}" >/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}

restart_guacamole() {
  kubectl rollout restart deployment/vdiforge-guacd -n guacamole
  kubectl rollout status deployment/vdiforge-guacd -n guacamole --timeout=600s
  kubectl rollout restart deployment/vdiforge-guacamole -n guacamole
  kubectl rollout status deployment/vdiforge-guacamole -n guacamole --timeout=600s
  kubectl wait deployment/vdiforge-guacamole -n guacamole --for=condition=Available --timeout=600s
}

restart_application_deployments() {
  kubectl rollout restart deployment/vdiforge-api deployment/vdiforge-provisioner -n vdiforge-system
  kubectl rollout status deployment/vdiforge-api -n vdiforge-system --timeout=300s
  kubectl rollout status deployment/vdiforge-provisioner -n vdiforge-system --timeout=300s
}

check "kubectl exists" command -v kubectl
check "jq exists" command -v jq
check "curl exists" command -v curl
check "python3 exists" command -v python3
check "Helm client available or installable" ensure_helm_client
check_output "Helm version" helm_cmd version

check_output "nodes before Phase 8" kubectl get nodes -o wide
check "all nodes Ready before Phase 8" all_nodes_ready
check "Calico available before Phase 8" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "CoreDNS rollout before Phase 8" kubectl -n kube-system rollout status deployment/coredns --timeout=180s
check "Metrics Server available before Phase 8" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "KubeVirt available before Phase 8" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before Phase 8" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "KubeVirt KVM resource remains on VDI worker" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'
check_output "node metrics before Phase 8" kubectl top nodes

check "Phase 5 runtime secrets and local CA available" ensure_phase5_runtime
check "create Phase 7 app/API secrets" bash scripts/phase7-create-local-secrets.sh
check "create Phase 8 Guacamole secrets" bash scripts/phase8-create-local-secrets.sh
check "image catalog validation" python3 scripts/validate-image-catalog.py
check "ubuntu-devops:${IMAGE_VERSION} remote-enabled image artifact" build_remote_image_if_needed
check "build and load Phase 8 API image" build_and_load_api_image

check "Helm lint with Phase 8 values" helm_cmd lint "${CHART_DIR}" --values "${PHASE4_VALUES}" --values "${PHASE5_VALUES}" --values "${PHASE7_VALUES}" --values "${PHASE8_VALUES}"
check "Helm template render with Phase 8 values" render_chart
check "rendered manifests contain no cluster-admin binding" bash -c "! grep -Eq 'cluster-admin|ClusterRoleBinding' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no hardcoded node names" bash -c "! grep -Eq 'vdi-control-01|vdi-worker-01|vdi-worker-02' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no plaintext password values" bash -c "! grep -Eiq 'password:|VDIFORGE_.*PASSWORD=[^$]|JSON_SECRET_KEY: [a-f0-9]{32}' '${RENDERED_MANIFEST}'"
check "recover pending Helm release if required" recover_pending_helm_release
check "Helm server dry-run validation" helm_server_dry_run

check "remove previous migration job if present" remove_previous_migration_job
check "install VDIForge Phase 8 release" install_phase8_release
check "VDIForge release deployed" release_deployed
check "restart API and provisioner after same-tag image import" restart_application_deployments
check "expected Phase 8 resources exist" phase8_resources_exist
check "app PostgreSQL rollout" kubectl -n vdiforge-system rollout status statefulset/vdiforge-app-postgres --timeout=300s
check "API rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-api --timeout=300s
check "provisioner rollout" kubectl -n vdiforge-system rollout status deployment/vdiforge-provisioner --timeout=300s
check "guacd rollout" kubectl -n guacamole rollout status deployment/vdiforge-guacd --timeout=300s
check "Guacamole rollout" kubectl -n guacamole rollout status deployment/vdiforge-guacamole --timeout=300s
check "clean up stale Phase 8 validation desktops" python3 scripts/phase8-remote-desktop-e2e-test.py --env "${ENV_FILE}" --ca "${CA_CERT}" --resolve-ip "${INGRESS_IP}" --cleanup-only
check "prepare ubuntu-devops:${IMAGE_VERSION} source PVC" bash scripts/phase8-prepare-remote-source.sh
check "Guacamole pods scheduled on platform worker" phase8_scheduled_on_platform_worker
check "Guacamole trusted HTTPS endpoint" curl_with_retry "https://${REMOTE_HOST}/"
check "Guacamole restart persistence" restart_guacamole
check "Guacamole trusted HTTPS endpoint after restart" curl_with_retry "https://${REMOTE_HOST}/"
check "Phase 8 NetworkPolicy validation" bash scripts/phase8-networkpolicy-test.sh
check "Phase 8 API/Guacamole remote desktop validation" python3 scripts/phase8-remote-desktop-e2e-test.py --env "${ENV_FILE}" --ca "${CA_CERT}" --resolve-ip "${INGRESS_IP}"

check_output "nodes after Phase 8" kubectl get nodes -o wide
check_output "pods after Phase 8" kubectl get pods -A
check_output "KubeVirt status after Phase 8" kubectl get kubevirt -n kubevirt
check_output "storage classes after Phase 8" kubectl get storageclass
check_output "node metrics after Phase 8" kubectl top nodes
check_output "pod metrics after Phase 8" kubectl top pods -A
check_output "helm releases after Phase 8" helm_cmd list -A
check "all nodes Ready after Phase 8" all_nodes_ready
check "no unexpected failed pods after Phase 8" no_unexpected_pod_failures
check "KubeVirt KVM resource remains on VDI worker after Phase 8" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 8 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

FINAL_REVISION="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.version')"
echo "Final VDIForge Helm revision: ${FINAL_REVISION}"
echo "KubeVirt hardware acceleration: KUBEVIRT_KVM_VERIFIED"
echo "Phase 8 live validation: PASS"
