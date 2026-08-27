#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SECRET_DIR="${VDIFORGE_PHASE5_SECRET_DIR:-.local/phase5}"
TLS_DIR="${SECRET_DIR}/tls"
ENV_FILE="${SECRET_DIR}/phase5.env"
NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
SECRET_NAME="${KEYCLOAK_SECRET_NAME:-vdiforge-keycloak-secrets}"
TLS_SECRET_NAME="${KEYCLOAK_TLS_SECRET_NAME:-vdiforge-keycloak-tls}"
AUTH_HOST="${VDIFORGE_AUTH_HOST:-auth.vdiforge.local}"
INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

random_secret() {
  openssl rand -hex 24
}

require_tool kubectl
require_tool openssl

umask 077
mkdir -p "${TLS_DIR}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME:-local-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-$(random_secret)}"
KEYCLOAK_DB_PASSWORD="${KEYCLOAK_DB_PASSWORD:-$(random_secret)}"
DEMO_USER_PASSWORD="${DEMO_USER_PASSWORD:-$(random_secret)}"
DEMO_DEVELOPER_PASSWORD="${DEMO_DEVELOPER_PASSWORD:-$(random_secret)}"
DEMO_DEVOPS_PASSWORD="${DEMO_DEVOPS_PASSWORD:-$(random_secret)}"
DEMO_ADMIN_PASSWORD="${DEMO_ADMIN_PASSWORD:-$(random_secret)}"

cat > "${ENV_FILE}" <<EOF
KEYCLOAK_ADMIN_USERNAME=${KEYCLOAK_ADMIN_USERNAME}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
KEYCLOAK_DB_PASSWORD=${KEYCLOAK_DB_PASSWORD}
DEMO_USER_PASSWORD=${DEMO_USER_PASSWORD}
DEMO_DEVELOPER_PASSWORD=${DEMO_DEVELOPER_PASSWORD}
DEMO_DEVOPS_PASSWORD=${DEMO_DEVOPS_PASSWORD}
DEMO_ADMIN_PASSWORD=${DEMO_ADMIN_PASSWORD}
EOF
chmod 600 "${ENV_FILE}"

CA_KEY="${TLS_DIR}/vdiforge-local-ca.key"
CA_CERT="${TLS_DIR}/vdiforge-local-ca.crt"
CA_EXT="${TLS_DIR}/vdiforge-local-ca.openssl.cnf"
TLS_KEY="${TLS_DIR}/${AUTH_HOST}.key"
TLS_CSR="${TLS_DIR}/${AUTH_HOST}.csr"
TLS_CERT="${TLS_DIR}/${AUTH_HOST}.crt"
TLS_EXT="${TLS_DIR}/${AUTH_HOST}.openssl.cnf"

cat > "${CA_EXT}" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
CN = VDIForge Local Development CA

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
EOF

ca_cert_has_required_extensions() {
  [[ -f "${CA_CERT}" ]] || return 1
  openssl x509 -in "${CA_CERT}" -noout -text 2>/dev/null | grep -q "CA:TRUE" &&
    openssl x509 -in "${CA_CERT}" -noout -text 2>/dev/null | grep -q "Certificate Sign"
}

if ! ca_cert_has_required_extensions; then
  rm -f "${CA_CERT}" "${TLS_CERT}" "${TLS_CSR}" "${TLS_DIR}/vdiforge-local-ca.srl"
fi

if [[ ! -f "${CA_KEY}" || ! -f "${CA_CERT}" ]]; then
  openssl genrsa -out "${CA_KEY}" 4096 >/dev/null 2>&1
  openssl req -x509 -new -nodes \
    -key "${CA_KEY}" \
    -sha256 \
    -days 825 \
    -subj "/CN=VDIForge Local Development CA" \
    -config "${CA_EXT}" \
    -extensions v3_ca \
    -out "${CA_CERT}" >/dev/null 2>&1
fi

cat > "${TLS_EXT}" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
CN = ${AUTH_HOST}

[req_ext]
subjectAltName = @alt_names
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = ${AUTH_HOST}
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
    -CA "${CA_CERT}" \
    -CAkey "${CA_KEY}" \
    -CAcreateserial \
    -out "${TLS_CERT}" \
    -days 398 \
    -sha256 \
    -extensions req_ext \
    -extfile "${TLS_EXT}" >/dev/null 2>&1
fi

chmod 600 "${CA_KEY}" "${TLS_KEY}"
chmod 644 "${CA_CERT}" "${TLS_CERT}"

kubectl get namespace "${NAMESPACE}" >/dev/null

kubectl create secret generic "${SECRET_NAME}" \
  --namespace "${NAMESPACE}" \
  --from-literal=KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME}" \
  --from-literal=KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}" \
  --from-literal=KEYCLOAK_DB_PASSWORD="${KEYCLOAK_DB_PASSWORD}" \
  --from-literal=DEMO_USER_PASSWORD="${DEMO_USER_PASSWORD}" \
  --from-literal=DEMO_DEVELOPER_PASSWORD="${DEMO_DEVELOPER_PASSWORD}" \
  --from-literal=DEMO_DEVOPS_PASSWORD="${DEMO_DEVOPS_PASSWORD}" \
  --from-literal=DEMO_ADMIN_PASSWORD="${DEMO_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls "${TLS_SECRET_NAME}" \
  --namespace "${NAMESPACE}" \
  --cert "${TLS_CERT}" \
  --key "${TLS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Created or refreshed Kubernetes Secrets in namespace ${NAMESPACE}."
echo "Local CA certificate: ${CA_CERT}"
echo "Local secret values file: ${ENV_FILE}"
