#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SECRET_DIR="${VDIFORGE_PHASE7_SECRET_DIR:-.local/phase7}"
TLS_DIR="${SECRET_DIR}/tls"
ENV_FILE="${SECRET_DIR}/phase7.env"
SYSTEM_NAMESPACE="${VDIFORGE_SYSTEM_NAMESPACE:-vdiforge-system}"
APP_SECRET_NAME="${VDIFORGE_APP_SECRET_NAME:-vdiforge-app-secrets}"
API_TLS_SECRET_NAME="${VDIFORGE_API_TLS_SECRET_NAME:-vdiforge-api-tls}"
KEYCLOAK_CA_SECRET_NAME="${VDIFORGE_KEYCLOAK_CA_SECRET_NAME:-vdiforge-api-keycloak-ca}"
API_HOST="${VDIFORGE_API_HOST:-api.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
PHASE5_CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
PHASE5_CA_KEY="${VDIFORGE_PHASE5_CA_KEY:-.local/phase5/tls/vdiforge-local-ca.key}"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

random_secret() {
  openssl rand -hex 24
}

existing_kubernetes_app_db_password() {
  kubectl get secret "${APP_SECRET_NAME}" \
    --namespace "${SYSTEM_NAMESPACE}" \
    -o jsonpath='{.data.VDIFORGE_APP_DB_PASSWORD}' 2>/dev/null |
    base64 -d 2>/dev/null || true
}

require_tool kubectl
require_tool openssl

if [[ ! -f "${PHASE5_CA_CERT}" || ! -f "${PHASE5_CA_KEY}" ]]; then
  echo "Missing Phase 5 local CA. Run scripts/phase5-create-local-secrets.sh first." >&2
  exit 1
fi

umask 077
mkdir -p "${TLS_DIR}"

EXPLICIT_APP_DB_PASSWORD="${VDIFORGE_APP_DB_PASSWORD:-}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

EXISTING_APP_DB_PASSWORD="$(existing_kubernetes_app_db_password)"

if [[ -n "${EXPLICIT_APP_DB_PASSWORD}" ]]; then
  VDIFORGE_APP_DB_PASSWORD="${EXPLICIT_APP_DB_PASSWORD}"
elif [[ -n "${EXISTING_APP_DB_PASSWORD}" ]]; then
  VDIFORGE_APP_DB_PASSWORD="${EXISTING_APP_DB_PASSWORD}"
else
  VDIFORGE_APP_DB_PASSWORD="${VDIFORGE_APP_DB_PASSWORD:-$(random_secret)}"
fi

cat >"${ENV_FILE}" <<EOF
VDIFORGE_APP_DB_PASSWORD=${VDIFORGE_APP_DB_PASSWORD}
EOF
chmod 600 "${ENV_FILE}"

TLS_KEY="${TLS_DIR}/${API_HOST}.key"
TLS_CSR="${TLS_DIR}/${API_HOST}.csr"
TLS_CERT="${TLS_DIR}/${API_HOST}.crt"
TLS_EXT="${TLS_DIR}/${API_HOST}.openssl.cnf"

cat >"${TLS_EXT}" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
CN = ${API_HOST}

[req_ext]
subjectAltName = @alt_names
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = ${API_HOST}
IP.1 = ${INGRESS_IP}
EOF

if [[ ! -f "${TLS_KEY}" || ! -f "${TLS_CERT}" ]]; then
  openssl genrsa -out "${TLS_KEY}" 2048 >/dev/null 2>&1
  openssl req -new \
    -key "${TLS_KEY}" \
    -out "${TLS_CSR}" \
    -config "${TLS_EXT}" >/dev/null 2>&1
  openssl x509 -req \
    -in "${TLS_CSR}" \
    -CA "${PHASE5_CA_CERT}" \
    -CAkey "${PHASE5_CA_KEY}" \
    -CAcreateserial \
    -out "${TLS_CERT}" \
    -days 398 \
    -sha256 \
    -extensions req_ext \
    -extfile "${TLS_EXT}" >/dev/null 2>&1
fi

chmod 600 "${TLS_KEY}"
chmod 644 "${TLS_CERT}"

kubectl get namespace "${SYSTEM_NAMESPACE}" >/dev/null

kubectl create secret generic "${APP_SECRET_NAME}" \
  --namespace "${SYSTEM_NAMESPACE}" \
  --from-literal=VDIFORGE_APP_DB_PASSWORD="${VDIFORGE_APP_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls "${API_TLS_SECRET_NAME}" \
  --namespace "${SYSTEM_NAMESPACE}" \
  --cert "${TLS_CERT}" \
  --key "${TLS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "${KEYCLOAK_CA_SECRET_NAME}" \
  --namespace "${SYSTEM_NAMESPACE}" \
  --from-file=vdiforge-local-ca.crt="${PHASE5_CA_CERT}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Created or refreshed Phase 7 Kubernetes Secrets in namespace ${SYSTEM_NAMESPACE}."
echo "API TLS certificate: ${TLS_CERT}"
echo "Local secret values file: ${ENV_FILE}"
