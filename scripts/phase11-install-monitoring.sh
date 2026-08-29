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
MONITORING_VALUES="${VDIFORGE_MONITORING_VALUES:-monitoring/kube-prometheus-stack-values-local.yaml}"
KUBE_PROM_STACK_VERSION="${VDIFORGE_KUBE_PROMETHEUS_STACK_VERSION:-88.6.1}"
PHASE4_VALUES="${HELM_VALUES:-helm/vdiforge/values-local.yaml}"
PHASE5_VALUES="${HELM_PHASE5_VALUES:-helm/vdiforge/values-phase5-local.yaml}"
PHASE7_VALUES="${HELM_PHASE7_VALUES:-helm/vdiforge/values-phase7-local.yaml}"
PHASE8_VALUES="${HELM_PHASE8_VALUES:-helm/vdiforge/values-phase8-local.yaml}"
PHASE9_VALUES="${HELM_PHASE9_VALUES:-helm/vdiforge/values-phase9-local.yaml}"
PHASE10_VALUES="${HELM_PHASE10_VALUES:-helm/vdiforge/values-phase10-local.yaml}"
PHASE11_VALUES="${HELM_PHASE11_VALUES:-helm/vdiforge/values-phase11-local.yaml}"
API_IMAGE="${PHASE11_API_IMAGE:-localhost/vdiforge-api:0.11.0}"
API_IMAGE_TAR="${PHASE11_API_IMAGE_TAR:-/tmp/vdiforge-api-0.11.0.tar}"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

helm_cmd() {
  "${HELM_BIN}" "$@"
}

helm_release_status() {
  helm_cmd status "$1" --namespace "$2" --output json 2>/dev/null | jq -r '.info.status // empty' 2>/dev/null || true
}

last_deployed_revision() {
  helm_cmd history "$1" --namespace "$2" --output json 2>/dev/null |
    jq -r '[.[] | select(.status == "deployed")] | last | .revision // empty' 2>/dev/null || true
}

recover_pending_release_by_rollback() {
  local release="$1"
  local namespace="$2"
  local status
  local revision

  status="$(helm_release_status "${release}" "${namespace}")"
  case "${status}" in
    pending-install|pending-upgrade|pending-rollback)
      revision="$(last_deployed_revision "${release}" "${namespace}")"
      if [[ -z "${revision}" ]]; then
        echo "Release ${release} is ${status}, but no deployed revision is available for rollback." >&2
        exit 1
      fi
      echo "Rolling back pending Helm release ${release} in ${namespace} to deployed revision ${revision} before retrying."
      kubectl delete job vdiforge-api-migrations -n "${namespace}" --ignore-not-found=true --wait=true >/dev/null
      helm_cmd rollback "${release}" "${revision}" --namespace "${namespace}" --timeout 300s
      ;;
  esac
}

require_tool kubectl
require_tool bash
require_tool jq
if ! command -v "${HELM_BIN}" >/dev/null 2>&1 && [[ ! -x "${HELM_BIN}" ]]; then
  bash scripts/install-helm-client.sh >/dev/null
  HELM_BIN="${HOME}/.local/bin/helm"
fi

bash scripts/phase11-create-local-secrets.sh

helm_cmd repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm_cmd repo add grafana-community https://grafana-community.github.io/helm-charts --force-update >/dev/null
helm_cmd repo update >/dev/null

MONITORING_STATUS="$(helm_release_status "${MONITORING_RELEASE}" "${MONITORING_NAMESPACE}")"
case "${MONITORING_STATUS}" in
  pending-install|pending-upgrade|pending-rollback)
    echo "Removing pending Helm operation for ${MONITORING_RELEASE} before retrying."
    helm_cmd uninstall "${MONITORING_RELEASE}" --namespace "${MONITORING_NAMESPACE}" --wait --timeout 300s >/dev/null || true
    ;;
esac

helm_cmd upgrade --install "${MONITORING_RELEASE}" prometheus-community/kube-prometheus-stack \
  --version "${KUBE_PROM_STACK_VERSION}" \
  --namespace "${MONITORING_NAMESPACE}" \
  --values "${MONITORING_VALUES}" \
  --wait \
  --timeout 1200s

PROMETHEUS_SERVICE_ACCOUNT="$(kubectl get serviceaccount -n "${MONITORING_NAMESPACE}" \
  -l app.kubernetes.io/name=prometheus \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
PROMETHEUS_SERVICE_ACCOUNT="${PROMETHEUS_SERVICE_ACCOUNT:-vdiforge-monitoring-prometheus}"

kubectl patch kubevirt kubevirt -n kubevirt --type merge \
  -p "{\"spec\":{\"monitorNamespace\":\"${MONITORING_NAMESPACE}\",\"monitorAccount\":\"${PROMETHEUS_SERVICE_ACCOUNT}\",\"serviceMonitorNamespace\":\"${MONITORING_NAMESPACE}\"}}" >/dev/null
kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=300s >/dev/null

PHASE7_IMAGE="${API_IMAGE}" \
  PHASE7_IMAGE_TAR="${API_IMAGE_TAR}" \
  bash scripts/phase7-build-load-image.sh

recover_pending_release_by_rollback "${VDIFORGE_RELEASE}" "${VDIFORGE_NAMESPACE}"
kubectl delete job vdiforge-api-migrations -n "${VDIFORGE_NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null

helm_cmd upgrade --install "${VDIFORGE_RELEASE}" "${CHART_DIR}" \
  --namespace "${VDIFORGE_NAMESPACE}" \
  --values "${PHASE4_VALUES}" \
  --values "${PHASE5_VALUES}" \
  --values "${PHASE7_VALUES}" \
  --values "${PHASE8_VALUES}" \
  --values "${PHASE9_VALUES}" \
  --values "${PHASE10_VALUES}" \
  --values "${PHASE11_VALUES}" \
  --take-ownership \
  --force-conflicts \
  --timeout 900s

kubectl -n "${VDIFORGE_NAMESPACE}" wait job/vdiforge-api-migrations --for=condition=complete --timeout=300s
kubectl -n keycloak rollout status deployment/vdiforge-keycloak --timeout=300s
kubectl -n "${VDIFORGE_NAMESPACE}" rollout status deployment/vdiforge-api --timeout=300s
kubectl -n "${VDIFORGE_NAMESPACE}" rollout status deployment/vdiforge-provisioner --timeout=300s
kubectl -n "${MONITORING_NAMESPACE}" rollout status deployment/"${MONITORING_RELEASE}"-operator --timeout=300s >/dev/null || true

echo "Phase 11 monitoring stack installed or upgraded."
echo "Monitoring release: ${MONITORING_RELEASE}"
echo "VDIForge release: ${VDIFORGE_RELEASE}"
