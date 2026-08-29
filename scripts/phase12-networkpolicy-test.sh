#!/usr/bin/env bash
set -euo pipefail

SYSTEM_NS="${VDIFORGE_SYSTEM_NAMESPACE:-vdiforge-system}"
DESKTOP_NS="${VDIFORGE_DESKTOP_NAMESPACE:-vdiforge-desktops}"
IDENTITY_NS="${VDIFORGE_IDENTITY_NAMESPACE:-keycloak}"
REMOTE_NS="${VDIFORGE_REMOTE_NAMESPACE:-guacamole}"
AGNHOST_IMAGE="${VDIFORGE_AGNHOST_IMAGE:-registry.k8s.io/e2e-test-images/agnhost:2.40}"
DESKTOP_SERVICE="${VDIFORGE_PHASE12_DESKTOP_SERVICE:-}"

FAILURES=0

cleanup() {
  kubectl delete pod phase12-system-deny-probe -n "${SYSTEM_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl delete pod phase12-identity-deny-probe -n "${IDENTITY_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl delete pod phase12-guac-deny-probe -n "${REMOTE_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl delete pod phase12-guacd-allow-probe -n "${REMOTE_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
}

label_yaml() {
  local labels="$1"
  local old_ifs="${IFS}"
  IFS=','
  for label in ${labels}; do
    local key="${label%%=*}"
    local value="${label#*=}"
    printf '    "%s": "%s"\n' "${key}" "${value}"
  done
  IFS="${old_ifs}"
}

run_probe() {
  local namespace="$1"
  local pod="$2"
  local labels="$3"
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${pod}
  namespace: ${namespace}
  labels:
$(label_yaml "${labels}")
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: agnhost
      image: ${AGNHOST_IMAGE}
      command:
        - /agnhost
        - pause
      resources:
        requests:
          cpu: 5m
          memory: 16Mi
        limits:
          cpu: 10m
          memory: 32Mi
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
        capabilities:
          drop:
            - ALL
EOF
  kubectl wait pod "${pod}" -n "${namespace}" --for=condition=Ready --timeout=180s >/dev/null
}

connect_from() {
  local namespace="$1"
  local pod="$2"
  local endpoint="$3"
  kubectl exec -n "${namespace}" "${pod}" -- /agnhost connect "${endpoint}" --timeout=5s >/dev/null 2>&1
}

expect_connect() {
  local namespace="$1"
  local pod="$2"
  local endpoint="$3"
  local description="$4"
  if connect_from "${namespace}" "${pod}" "${endpoint}"; then
    echo "PASS: allowed path works: ${description}"
  else
    echo "FAIL: allowed path failed: ${description}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

expect_deny() {
  local namespace="$1"
  local pod="$2"
  local endpoint="$3"
  local description="$4"
  if connect_from "${namespace}" "${pod}" "${endpoint}"; then
    echo "FAIL: denied path connected: ${description}" >&2
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: denied path blocked: ${description}"
  fi
}

trap cleanup EXIT
cleanup

run_probe "${SYSTEM_NS}" phase12-system-deny-probe "app.kubernetes.io/name=phase12-system-deny,app.kubernetes.io/component=validation"
run_probe "${IDENTITY_NS}" phase12-identity-deny-probe "app.kubernetes.io/name=phase12-identity-deny,app.kubernetes.io/component=validation"
run_probe "${REMOTE_NS}" phase12-guac-deny-probe "app.kubernetes.io/name=phase12-guac-deny,app.kubernetes.io/component=validation"

expect_deny "${SYSTEM_NS}" phase12-system-deny-probe "vdiforge-app-postgres.${SYSTEM_NS}.svc.cluster.local:5432" "unlabeled platform pod to VDIForge app PostgreSQL"
expect_deny "${SYSTEM_NS}" phase12-system-deny-probe "vdiforge-keycloak-postgres.${IDENTITY_NS}.svc.cluster.local:5432" "unlabeled platform pod to Keycloak PostgreSQL"
expect_deny "${SYSTEM_NS}" phase12-system-deny-probe "vdiforge-keycloak.${IDENTITY_NS}.svc.cluster.local:8080" "unlabeled platform pod to Keycloak web"
expect_deny "${IDENTITY_NS}" phase12-identity-deny-probe "vdiforge-keycloak-postgres.${IDENTITY_NS}.svc.cluster.local:5432" "unlabeled identity pod to Keycloak PostgreSQL"
expect_deny "${REMOTE_NS}" phase12-guac-deny-probe "vdiforge-guacd.${REMOTE_NS}.svc.cluster.local:4822" "unlabeled Guacamole pod to guacd"

if [[ -n "${DESKTOP_SERVICE}" ]]; then
  run_probe "${REMOTE_NS}" phase12-guacd-allow-probe "app.kubernetes.io/name=vdiforge-guacd,app.kubernetes.io/instance=vdiforge,app.kubernetes.io/component=guacd,app.kubernetes.io/part-of=vdiforge"
  expect_connect "${REMOTE_NS}" phase12-guacd-allow-probe "${DESKTOP_SERVICE}.${DESKTOP_NS}.svc.cluster.local:3389" "guacd-position pod to desktop RDP service"
  expect_deny "${SYSTEM_NS}" phase12-system-deny-probe "${DESKTOP_SERVICE}.${DESKTOP_NS}.svc.cluster.local:3389" "unlabeled platform pod to desktop RDP service"
else
  echo "WARN: VDIFORGE_PHASE12_DESKTOP_SERVICE not set; skipping live desktop RDP NetworkPolicy check"
fi

cleanup
trap - EXIT

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 12 NetworkPolicy validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

echo "Phase 12 NetworkPolicy validation: PASS"
