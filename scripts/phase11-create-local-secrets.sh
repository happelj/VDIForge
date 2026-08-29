#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SECRET_DIR="${VDIFORGE_PHASE11_SECRET_DIR:-.local/phase11}"
TLS_DIR="${SECRET_DIR}/tls"
ENV_FILE="${SECRET_DIR}/phase11.env"
MONITORING_NAMESPACE="${VDIFORGE_MONITORING_NAMESPACE:-monitoring}"
GRAFANA_ADMIN_SECRET="${VDIFORGE_GRAFANA_ADMIN_SECRET:-vdiforge-grafana-admin}"
GRAFANA_TLS_SECRET="${VDIFORGE_GRAFANA_TLS_SECRET:-vdiforge-grafana-tls}"
GRAFANA_HOST="${VDIFORGE_GRAFANA_HOST:-grafana.vdiforge.local}"
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

GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '\n')}"

cat >"${ENV_FILE}" <<EOF
GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
GRAFANA_HOST=${GRAFANA_HOST}
EOF
chmod 600 "${ENV_FILE}"

TLS_KEY="${TLS_DIR}/${GRAFANA_HOST}.key"
TLS_CSR="${TLS_DIR}/${GRAFANA_HOST}.csr"
TLS_CERT="${TLS_DIR}/${GRAFANA_HOST}.crt"
TLS_EXT="${TLS_DIR}/${GRAFANA_HOST}.openssl.cnf"

cat >"${TLS_EXT}" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
CN = ${GRAFANA_HOST}

[req_ext]
subjectAltName = @alt_names
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = ${GRAFANA_HOST}
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

kubectl get namespace "${MONITORING_NAMESPACE}" >/dev/null

kubectl create secret generic "${GRAFANA_ADMIN_SECRET}" \
  --namespace "${MONITORING_NAMESPACE}" \
  --from-literal=admin-user="${GRAFANA_ADMIN_USER}" \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls "${GRAFANA_TLS_SECRET}" \
  --namespace "${MONITORING_NAMESPACE}" \
  --cert "${TLS_CERT}" \
  --key "${TLS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Created or refreshed Phase 11 Grafana Secrets."
echo "Grafana admin user: ${GRAFANA_ADMIN_USER}"
echo "Grafana password file: ${ENV_FILE}"
echo "Grafana TLS certificate: ${TLS_CERT}"
