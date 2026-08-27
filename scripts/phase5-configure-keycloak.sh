#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

ENV_FILE="${VDIFORGE_PHASE5_ENV_FILE:-.local/phase5/phase5.env}"
NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
DEPLOYMENT="${KEYCLOAK_DEPLOYMENT:-vdiforge-keycloak}"
REALM="${KEYCLOAK_REALM:-vdiforge}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Run scripts/phase5-create-local-secrets.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

require_tool kubectl
require_tool jq

kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" --timeout=600s

kcadm() {
  kubectl -n "${NAMESPACE}" exec "deployment/${DEPLOYMENT}" -- /opt/keycloak/bin/kcadm.sh "$@"
}

kcadm_stdin() {
  kubectl -n "${NAMESPACE}" exec -i "deployment/${DEPLOYMENT}" -- /opt/keycloak/bin/kcadm.sh "$@"
}

echo "Configuring Keycloak realm credentials and validating realm objects."
kcadm config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "${KEYCLOAK_ADMIN_USERNAME}" \
  --password "${KEYCLOAK_ADMIN_PASSWORD}" >/dev/null

kcadm get "realms/${REALM}" >/dev/null

for role in vdi-user vdi-developer vdi-devops vdi-admin; do
  kcadm get "roles/${role}" -r "${REALM}" >/dev/null
done

for client in vdiforge-frontend vdiforge-api; do
  client_count="$(kcadm get clients -r "${REALM}" -q "clientId=${client}" --fields id --format csv --noquotes | grep -c . || true)"
  if [[ "${client_count}" -ne 1 ]]; then
    echo "Expected one client named ${client}; found ${client_count}." >&2
    exit 1
  fi
done

frontend_client_id="$(kcadm get clients -r "${REALM}" -q "clientId=vdiforge-frontend" --fields id --format csv --noquotes | head -n 1)"

ensure_frontend_role_scope_mapping() {
  local role="$1"

  if kcadm get "clients/${frontend_client_id}/scope-mappings/realm" -r "${REALM}" |
    jq -e --arg role "${role}" '.[]? | select(.name == $role)' >/dev/null; then
    return
  fi

  role_json="$(kcadm get "roles/${role}" -r "${REALM}")"
  printf '[%s]' "${role_json}" |
    kcadm_stdin create "clients/${frontend_client_id}/scope-mappings/realm" -r "${REALM}" -f - >/dev/null
}

for role in vdi-user vdi-developer vdi-devops vdi-admin; do
  ensure_frontend_role_scope_mapping "${role}"
done

declare -A PASSWORDS=(
  [demo-user]="${DEMO_USER_PASSWORD}"
  [demo-developer]="${DEMO_DEVELOPER_PASSWORD}"
  [demo-devops]="${DEMO_DEVOPS_PASSWORD}"
  [demo-admin]="${DEMO_ADMIN_PASSWORD}"
)

for username in "${!PASSWORDS[@]}"; do
  user_count="$(kcadm get users -r "${REALM}" -q "username=${username}" --fields id --format csv --noquotes | grep -c . || true)"
  if [[ "${user_count}" -ne 1 ]]; then
    echo "Expected one user named ${username}; found ${user_count}." >&2
    exit 1
  fi
  kcadm set-password -r "${REALM}" --username "${username}" --new-password "${PASSWORDS[${username}]}" >/dev/null
done

echo "Keycloak realm, clients, roles, users, and local demo passwords are configured."
