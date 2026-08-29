#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${VDIFORGE_IDENTITY_NAMESPACE:-keycloak}"
DEPLOYMENT="${VDIFORGE_KEYCLOAK_DEPLOYMENT:-vdiforge-keycloak}"
ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"

if [[ ! -f "${ENV_FILE}" && -f "${PHASE5_FALLBACK_DIR}/phase5.env" ]]; then
  ENV_FILE="${PHASE5_FALLBACK_DIR}/phase5.env"
fi

[[ -f "${ENV_FILE}" ]] || {
  echo "FAIL: Phase 5 environment file not found: ${ENV_FILE}" >&2
  exit 1
}

set -a
source "${ENV_FILE}"
set +a

: "${KEYCLOAK_ADMIN_USERNAME:?KEYCLOAK_ADMIN_USERNAME is required in ${ENV_FILE}}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD is required in ${ENV_FILE}}"

pod="$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/component=identity -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${pod}" ]] || {
  echo "FAIL: Keycloak pod was not found" >&2
  exit 1
}

kubectl -n "${NAMESPACE}" exec "${pod}" -- /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "${KEYCLOAK_ADMIN_USERNAME}" \
  --password "${KEYCLOAK_ADMIN_PASSWORD}" >/dev/null

kubectl -n "${NAMESPACE}" exec "${pod}" -- /opt/keycloak/bin/kcadm.sh update realms/vdiforge \
  -s bruteForceProtected=true \
  -s permanentLockout=false \
  -s failureFactor=5 \
  -s waitIncrementSeconds=60 \
  -s quickLoginCheckMilliSeconds=1000 \
  -s minimumQuickLoginWaitSeconds=60 \
  -s maxFailureWaitSeconds=900 \
  -s maxDeltaTimeSeconds=43200 >/dev/null

realm="$(
  kubectl -n "${NAMESPACE}" exec "${pod}" -- /opt/keycloak/bin/kcadm.sh get realms/vdiforge \
    --fields bruteForceProtected,permanentLockout,failureFactor,accessTokenLifespan,ssoSessionIdleTimeout,ssoSessionMaxLifespan
)"

if jq -e '.bruteForceProtected == true and .failureFactor == 5 and .accessTokenLifespan == 300' <<<"${realm}" >/dev/null; then
  echo "PASS: Keycloak brute-force protection and token lifetime settings verified"
else
  echo "FAIL: Keycloak hardening settings did not verify" >&2
  echo "${realm}" >&2
  exit 1
fi

echo "Phase 12 Keycloak hardening validation: PASS"
