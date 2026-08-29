#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SECRET_DIR="${VDIFORGE_PHASE8_SECRET_DIR:-.local/phase8}"
TLS_DIR="${SECRET_DIR}/tls"
ENV_FILE="${SECRET_DIR}/phase8.env"
SYSTEM_NAMESPACE="${VDIFORGE_SYSTEM_NAMESPACE:-vdiforge-system}"
GUACAMOLE_NAMESPACE="${VDIFORGE_GUACAMOLE_NAMESPACE:-guacamole}"
JSON_SECRET_NAME="${VDIFORGE_GUACAMOLE_JSON_SECRET_NAME:-vdiforge-guacamole-json-secret}"
TLS_SECRET_NAME="${VDIFORGE_GUACAMOLE_TLS_SECRET_NAME:-vdiforge-guacamole-tls}"
REMOTE_HOST="${VDIFORGE_REMOTE_HOST:-remote.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"
PHASE5_CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
PHASE5_CA_KEY="${VDIFORGE_PHASE5_CA_KEY:-.local/phase5/tls/vdiforge-local-ca.key}"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

resolve_phase5_ca() {
  if [[ ! -f "${PHASE5_CA_CERT}" && -f "${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt" ]]; then
    PHASE5_CA_CERT="${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt"
  fi
  if [[ ! -f "${PHASE5_CA_KEY}" && -f "${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.key" ]]; then
    PHASE5_CA_KEY="${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.key"
  fi
}

require_tool kubectl
require_tool openssl

resolve_phase5_ca
if [[ ! -f "${PHASE5_CA_CERT}" || ! -f "${PHASE5_CA_KEY}" ]]; then
  echo "Missing Phase 5 local CA. Run scripts/phase5-create-local-secrets.sh first." >&2
  exit 1
fi

umask 077
mkdir -p "${TLS_DIR}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

JSON_SECRET_KEY="${JSON_SECRET_KEY:-$(openssl rand -hex 16)}"

cat >"${ENV_FILE}" <<EOF
JSON_SECRET_KEY=${JSON_SECRET_KEY}
EOF
chmod 600 "${ENV_FILE}"

TLS_KEY="${TLS_DIR}/${REMOTE_HOST}.key"
TLS_CSR="${TLS_DIR}/${REMOTE_HOST}.csr"
TLS_CERT="${TLS_DIR}/${REMOTE_HOST}.crt"
TLS_EXT="${TLS_DIR}/${REMOTE_HOST}.openssl.cnf"

cat >"${TLS_EXT}" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
CN = ${REMOTE_HOST}

[req_ext]
subjectAltName = @alt_names
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = ${REMOTE_HOST}
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
kubectl get namespace "${GUACAMOLE_NAMESPACE}" >/dev/null

for namespace in "${SYSTEM_NAMESPACE}" "${GUACAMOLE_NAMESPACE}"; do
  kubectl create secret generic "${JSON_SECRET_NAME}" \
    --namespace "${namespace}" \
    --from-literal=JSON_SECRET_KEY="${JSON_SECRET_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

kubectl create secret tls "${TLS_SECRET_NAME}" \
  --namespace "${GUACAMOLE_NAMESPACE}" \
  --cert "${TLS_CERT}" \
  --key "${TLS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Created or refreshed Phase 8 Guacamole Secrets."
echo "Guacamole TLS certificate: ${TLS_CERT}"
echo "Local Phase 8 secret values file: ${ENV_FILE}"
