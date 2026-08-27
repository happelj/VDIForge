#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
ALLOWED_NS="${INGRESS_NAMESPACE:-ingress-traefik}"
DENIED_NS="${PHASE5_NETPOL_DENIED_NS:-vdiforge-phase5-netpol-test}"
KEYCLOAK_URL="http://vdiforge-keycloak.${NAMESPACE}.svc.cluster.local:8080/realms/vdiforge/.well-known/openid-configuration"
POSTGRES_HOST="vdiforge-keycloak-postgres.${NAMESPACE}.svc.cluster.local"

cleanup() {
  kubectl delete pod phase5-allowed-keycloak -n "${ALLOWED_NS}" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete namespace "${DENIED_NS}" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl create namespace "${DENIED_NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl run phase5-allowed-keycloak \
  --namespace "${ALLOWED_NS}" \
  --image=curlimages/curl:8.11.1 \
  --labels="app.kubernetes.io/name=traefik,phase=phase5-netpol" \
  --command -- sleep 600 >/dev/null
kubectl wait pod phase5-allowed-keycloak -n "${ALLOWED_NS}" --for=condition=Ready --timeout=120s >/dev/null

kubectl exec -n "${ALLOWED_NS}" phase5-allowed-keycloak -- \
  curl -fsS --max-time 10 "${KEYCLOAK_URL}" >/dev/null

kubectl run phase5-denied \
  --namespace "${DENIED_NS}" \
  --image=busybox:1.36.1 \
  --command -- sleep 600 >/dev/null
kubectl wait pod phase5-denied -n "${DENIED_NS}" --for=condition=Ready --timeout=120s >/dev/null

if kubectl exec -n "${DENIED_NS}" phase5-denied -- \
  wget -q -T 5 -O - "${KEYCLOAK_URL}" >/dev/null 2>&1; then
  echo "Unexpected access from denied namespace to Keycloak." >&2
  exit 1
fi

if kubectl exec -n "${DENIED_NS}" phase5-denied -- \
  nc -z -w 5 "${POSTGRES_HOST}" 5432 >/dev/null 2>&1; then
  echo "Unexpected access from denied namespace to PostgreSQL." >&2
  exit 1
fi

echo "PASS: Keycloak NetworkPolicy allows ingress controller traffic and denies unauthorized Keycloak/PostgreSQL access."
