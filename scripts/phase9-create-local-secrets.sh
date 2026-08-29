#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SECRET_DIR="${VDIFORGE_PHASE9_SECRET_DIR:-.local/phase9}"
TLS_DIR="${SECRET_DIR}/tls"
NAMESPACE="${VDIFORGE_SYSTEM_NAMESPACE:-vdiforge-system}"
TLS_SECRET_NAME="${VDIFORGE_PORTAL_TLS_SECRET_NAME:-vdiforge-portal-tls}"
PORTAL_HOST="${VDIFORGE_PORTAL_HOST:-vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
CA_KEY="${VDIFORGE_PHASE5_CA_KEY:-.local/phase5/tls/vdiforge-local-ca.key}"

if [[ ! -f "${CA_CERT}" && -f "${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt" ]]; then
  CA_CERT="${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt"
fi
if [[ ! -f "${CA_KEY}" && -f "${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.key" ]]; then
  CA_KEY="${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.key"
fi

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

require_tool kubectl
require_tool openssl

[[ -f "${CA_CERT}" ]] || {
  echo "Missing local CA certificate: ${CA_CERT}" >&2
  exit 1
}
[[ -f "${CA_KEY}" ]] || {
  echo "Missing local CA private key: ${CA_KEY}" >&2
  exit 1
}

umask 077
mkdir -p "${TLS_DIR}"

TLS_KEY="${TLS_DIR}/${PORTAL_HOST}.key"
TLS_CSR="${TLS_DIR}/${PORTAL_HOST}.csr"
TLS_CERT="${TLS_DIR}/${PORTAL_HOST}.crt"
TLS_EXT="${TLS_DIR}/${PORTAL_HOST}.openssl.cnf"

cat >"${TLS_EXT}" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
CN = ${PORTAL_HOST}

[req_ext]
subjectAltName = @alt_names
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = ${PORTAL_HOST}
IP.1 = ${INGRESS_IP}
EOF

openssl genrsa -out "${TLS_KEY}" 2048 >/dev/null 2>&1
openssl req -new \
  -key "${TLS_KEY}" \
  -out "${TLS_CSR}" \
  -config "${TLS_EXT}" >/dev/null 2>&1
openssl x509 -req \
  -in "${TLS_CSR}" \
  -CA "${CA_CERT}" \
  -CAkey "${CA_KEY}" \
  -CAcreateserial \
  -out "${TLS_CERT}" \
  -days 398 \
  -sha256 \
  -extensions req_ext \
  -extfile "${TLS_EXT}" >/dev/null 2>&1

chmod 600 "${TLS_KEY}"
chmod 644 "${TLS_CERT}"

kubectl get namespace "${NAMESPACE}" >/dev/null
kubectl create secret tls "${TLS_SECRET_NAME}" \
  --namespace "${NAMESPACE}" \
  --cert "${TLS_CERT}" \
  --key "${TLS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Created or refreshed ${TLS_SECRET_NAME} in namespace ${NAMESPACE}."
echo "Portal certificate: ${TLS_CERT}"
