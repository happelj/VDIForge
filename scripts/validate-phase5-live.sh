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
TRAEFIK_RELEASE="${TRAEFIK_RELEASE:-traefik}"
TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-ingress-traefik}"
TRAEFIK_CHART_VERSION="${TRAEFIK_CHART_VERSION:-41.2.0}"
TRAEFIK_VALUES="${TRAEFIK_VALUES:-helm/traefik/values-local.yaml}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_DEPLOYMENT="${KEYCLOAK_DEPLOYMENT:-vdiforge-keycloak}"
POSTGRES_STATEFULSET="${POSTGRES_STATEFULSET:-vdiforge-keycloak-postgres}"
AUTH_HOST="${VDIFORGE_AUTH_HOST:-auth.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
RENDERED_MANIFEST="${RENDERED_MANIFEST:-/tmp/vdiforge-phase5-rendered.yaml}"
EXPECTED_HELM_VERSION="${EXPECTED_HELM_VERSION:-v4.2.4}"
EXPECTED_KEYCLOAK_VERSION="${EXPECTED_KEYCLOAK_VERSION:-26.7.2}"
EXPECTED_POSTGRES_VERSION="${EXPECTED_POSTGRES_VERSION:-18.0-alpine}"

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

require_tool() {
  command -v "$1" >/dev/null 2>&1
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

render_chart() {
  helm_cmd template "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" >"${RENDERED_MANIFEST}"
}

helm_server_dry_run() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --set "platformConfig.validationMarker=phase5-keycloak" \
    --take-ownership \
    --force-conflicts \
    --dry-run=server >/dev/null
}

install_traefik() {
  kubectl create namespace "${TRAEFIK_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  helm_cmd repo add traefik https://traefik.github.io/charts --force-update >/dev/null
  helm_cmd repo update >/dev/null
  helm_cmd upgrade --install "${TRAEFIK_RELEASE}" traefik/traefik \
    --namespace "${TRAEFIK_NAMESPACE}" \
    --version "${TRAEFIK_CHART_VERSION}" \
    --values "${TRAEFIK_VALUES}" \
    --wait \
    --timeout 300s
}

install_vdiforge_identity() {
  helm_cmd upgrade --install "${RELEASE}" "${CHART_DIR}" \
    --namespace "${RELEASE_NAMESPACE}" \
    --values "${PHASE4_VALUES}" \
    --values "${PHASE5_VALUES}" \
    --set "platformConfig.validationMarker=phase5-keycloak" \
    --take-ownership \
    --force-conflicts \
    --wait \
    --timeout 600s
}

release_deployed() {
  [[ "$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.info.status')" == "deployed" ]]
}

expected_identity_resources_exist() {
  kubectl get secret vdiforge-keycloak-secrets -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get secret vdiforge-keycloak-tls -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get configmap vdiforge-keycloak-realm -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get deployment "${KEYCLOAK_DEPLOYMENT}" -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get statefulset "${POSTGRES_STATEFULSET}" -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get service vdiforge-keycloak -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get service vdiforge-keycloak-postgres -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get ingress vdiforge-keycloak -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get resourcequota vdiforge-identity-quota -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get networkpolicy keycloak-default-deny -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get networkpolicy keycloak-allow-ingress-controller -n "${KEYCLOAK_NAMESPACE}" >/dev/null
  kubectl get networkpolicy keycloak-allow-keycloak-to-postgres -n "${KEYCLOAK_NAMESPACE}" >/dev/null
}

identity_scheduled_on_platform_worker() {
  local bad_nodes
  bad_nodes="$(kubectl get pods -n "${KEYCLOAK_NAMESPACE}" \
    -l 'app.kubernetes.io/component in (identity,identity-database)' \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' |
    awk '$2 != "vdi-worker-01" { print }')"
  if [[ -n "${bad_nodes}" ]]; then
    echo "${bad_nodes}" >&2
    return 1
  fi
}

traefik_scheduled_on_platform_worker() {
  local bad_nodes
  bad_nodes="$(kubectl get pods -n "${TRAEFIK_NAMESPACE}" \
    -l app.kubernetes.io/name=traefik \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.nodeName}{"\n"}{end}' |
    awk '$2 != "vdi-worker-01" { print }')"
  if [[ -n "${bad_nodes}" ]]; then
    echo "${bad_nodes}" >&2
    return 1
  fi
}

trusted_https_discovery() {
  curl -fsS \
    --cacert "${CA_CERT}" \
    --resolve "${AUTH_HOST}:443:${INGRESS_IP}" \
    "https://${AUTH_HOST}/realms/vdiforge/.well-known/openid-configuration" |
    jq -e --arg issuer "https://${AUTH_HOST}/realms/vdiforge" '.issuer == $issuer' >/dev/null
}

trusted_https_jwks() {
  curl -fsS \
    --cacert "${CA_CERT}" \
    --resolve "${AUTH_HOST}:443:${INGRESS_IP}" \
    "https://${AUTH_HOST}/realms/vdiforge/protocol/openid-connect/certs" |
    jq -e '.keys | length > 0' >/dev/null
}

system_or_explicit_dns_resolution() {
  if getent hosts "${AUTH_HOST}" >/dev/null 2>&1; then
    getent hosts "${AUTH_HOST}"
    return 0
  fi
  echo "System resolver does not map ${AUTH_HOST}; validation uses explicit ${AUTH_HOST}:443:${INGRESS_IP} resolution."
  return 0
}

keycloak_objects() {
  bash scripts/phase5-configure-keycloak.sh >/dev/null
}

restart_keycloak_and_verify_persistence() {
  kubectl get pod -n "${KEYCLOAK_NAMESPACE}" -l "app.kubernetes.io/name=${KEYCLOAK_DEPLOYMENT}" -o name | grep -q .
  kubectl delete pod -n "${KEYCLOAK_NAMESPACE}" -l "app.kubernetes.io/name=${KEYCLOAK_DEPLOYMENT}" --wait=true >/dev/null
  kubectl -n "${KEYCLOAK_NAMESPACE}" rollout status "deployment/${KEYCLOAK_DEPLOYMENT}" --timeout=600s >/dev/null
  bash scripts/phase5-configure-keycloak.sh >/dev/null
}

keycloak_version_deployed() {
  kubectl get deployment "${KEYCLOAK_DEPLOYMENT}" -n "${KEYCLOAK_NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="keycloak")].image}' |
    grep -q ":${EXPECTED_KEYCLOAK_VERSION}$"
}

postgres_version_deployed() {
  kubectl get statefulset "${POSTGRES_STATEFULSET}" -n "${KEYCLOAK_NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="postgres")].image}' |
    grep -q ":${EXPECTED_POSTGRES_VERSION}$"
}

check "kubectl exists" require_tool kubectl
check "jq exists" require_tool jq
check "curl exists" require_tool curl
check "openssl exists" require_tool openssl
check "python3 exists" require_tool python3
check "Helm client exists" test -x "$(command -v "${HELM_BIN}" || echo "${HELM_BIN}")"
check "Helm version is pinned" bash -c "[[ \"$(current_helm_version)\" == \"${EXPECTED_HELM_VERSION}\" ]]"
check_output "Helm version" helm_cmd version

check "helm lint with Phase 5 values" helm_cmd lint "${CHART_DIR}" --values "${PHASE4_VALUES}" --values "${PHASE5_VALUES}"
check "helm template render with Phase 5 values" render_chart
check "rendered manifests contain no cluster-admin binding" bash -c "! grep -Eq 'cluster-admin|ClusterRoleBinding' '${RENDERED_MANIFEST}'"
check "rendered manifests contain no hardcoded node names" bash -c "! grep -Eq 'vdi-control-01|vdi-worker-01|vdi-worker-02' '${RENDERED_MANIFEST}'"

check "all nodes Ready before identity deployment" all_nodes_ready
check "KubeVirt available before identity deployment" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available before identity deployment" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s
check "Calico available before identity deployment" kubectl wait tigerastatus/calico --for=condition=Available --timeout=180s
check "Metrics Server available before identity deployment" kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
check "storage class available" kubectl get storageclass vdiforge-local-path

check "install Traefik ingress controller" install_traefik
check "Traefik rollout" kubectl -n "${TRAEFIK_NAMESPACE}" rollout status "deployment/${TRAEFIK_RELEASE}" --timeout=300s
check "Traefik scheduled on platform worker" traefik_scheduled_on_platform_worker

check "create runtime-only Keycloak secrets and TLS material" bash scripts/phase5-create-local-secrets.sh
check "Helm server dry-run validation" helm_server_dry_run
check "install VDIForge identity release" install_vdiforge_identity
check "VDIForge release deployed" release_deployed
check "expected identity resources exist" expected_identity_resources_exist
check "Keycloak rollout" kubectl -n "${KEYCLOAK_NAMESPACE}" rollout status "deployment/${KEYCLOAK_DEPLOYMENT}" --timeout=600s
check "PostgreSQL rollout" kubectl -n "${KEYCLOAK_NAMESPACE}" rollout status "statefulset/${POSTGRES_STATEFULSET}" --timeout=600s
check "Keycloak image version is pinned in live deployment" keycloak_version_deployed
check "PostgreSQL image version is pinned in live deployment" postgres_version_deployed
check "Keycloak and PostgreSQL scheduled on platform worker" identity_scheduled_on_platform_worker
check "realm, clients, roles, users, and demo passwords configured" keycloak_objects
check "system DNS or explicit local resolver mapping available" system_or_explicit_dns_resolution
check "trusted HTTPS OIDC discovery endpoint" trusted_https_discovery
check "trusted HTTPS JWKS endpoint" trusted_https_jwks
check "Authorization Code + PKCE, JWT, RBAC, and negative security tests" python3 scripts/phase5-oidc-pkce-test.py --env "${ENV_FILE}" --ca "${CA_CERT}" --resolve-ip "${INGRESS_IP}"
check "Keycloak persistence after pod recreation" restart_keycloak_and_verify_persistence
check "post-restart trusted HTTPS OIDC discovery endpoint" trusted_https_discovery
check "Keycloak NetworkPolicy enforcement" bash scripts/phase5-networkpolicy-test.sh
check "VDIForge Helm foundation resources remain healthy" bash scripts/validate-phase4-live.sh
check "restore VDIForge identity release after Phase 4 regression" install_vdiforge_identity
check "expected identity resources exist after regression" expected_identity_resources_exist
check "Keycloak rollout after regression" kubectl -n "${KEYCLOAK_NAMESPACE}" rollout status "deployment/${KEYCLOAK_DEPLOYMENT}" --timeout=600s
check "PostgreSQL rollout after regression" kubectl -n "${KEYCLOAK_NAMESPACE}" rollout status "statefulset/${POSTGRES_STATEFULSET}" --timeout=600s
check "post-regression realm, clients, roles, users, and demo passwords configured" keycloak_objects
check "post-regression trusted HTTPS OIDC discovery endpoint" trusted_https_discovery

check_output "nodes" kubectl get nodes -o wide
check_output "pods" kubectl get pods -A
check_output "helm releases" helm_cmd list -A
check_output "node metrics" kubectl top nodes
check_output "pod metrics" kubectl top pods -A
check "no unexpected failed pods after identity validation" no_unexpected_pod_failures
check "KubeVirt KVM resource remains on VDI worker" bash -c '[[ "$(kubectl get node vdi-worker-02 -o json | jq -r ".status.allocatable[\"devices.kubevirt.io/kvm\"] // \"0\"")" != "0" ]]'
check "KubeVirt available after identity validation" kubectl -n kubevirt wait kubevirt/kubevirt --for=condition=Available --timeout=180s
check "CDI available after identity validation" kubectl -n cdi wait cdi/cdi --for=condition=Available --timeout=180s

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 5 live validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

FINAL_REVISION="$(helm_cmd status "${RELEASE}" --namespace "${RELEASE_NAMESPACE}" --output json | jq -r '.version')"
KEYCLOAK_NODE="$(kubectl get pod -n "${KEYCLOAK_NAMESPACE}" -l app.kubernetes.io/name=vdiforge-keycloak -o jsonpath='{.items[0].spec.nodeName}')"
POSTGRES_NODE="$(kubectl get pod -n "${KEYCLOAK_NAMESPACE}" -l app.kubernetes.io/name=vdiforge-keycloak-postgres -o jsonpath='{.items[0].spec.nodeName}')"

echo "Final VDIForge Helm revision: ${FINAL_REVISION}"
echo "Keycloak node: ${KEYCLOAK_NODE}"
echo "PostgreSQL node: ${POSTGRES_NODE}"
echo "Identity endpoint: https://${AUTH_HOST}"
echo "Phase 5 live validation: PASS"
