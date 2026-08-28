#!/usr/bin/env bash
set -euo pipefail

NS="vdiforge-phase7-netpol-test"
POD="phase7-netpol-client"
IMAGE="${PHASE7_NETPOL_IMAGE:-registry.k8s.io/e2e-test-images/agnhost:2.57}"
DB_HOST="vdiforge-app-postgres.vdiforge-system.svc.cluster.local"
DB_PORT="5432"
API_HOST="vdiforge-api.vdiforge-system.svc.cluster.local"
API_PORT="8000"

cleanup() {
  kubectl delete namespace "${NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
}

fail() {
  echo "FAIL: $*" >&2
  cleanup
  exit 1
}

trap cleanup EXIT
cleanup
kubectl create namespace "${NS}" >/dev/null
kubectl run "${POD}" -n "${NS}" --image="${IMAGE}" --restart=Never --command -- sleep 3600 >/dev/null
kubectl wait pod "${POD}" -n "${NS}" --for=condition=Ready --timeout=180s >/dev/null

if kubectl exec -n "${NS}" "${POD}" -- /agnhost connect "${API_HOST}:${API_PORT}" --timeout=5s >/dev/null 2>&1; then
  fail "unauthorized namespace unexpectedly reached VDIForge API ClusterIP"
fi
echo "PASS: unauthorized namespace cannot reach VDIForge API ClusterIP"

if kubectl exec -n "${NS}" "${POD}" -- /agnhost connect "${DB_HOST}:${DB_PORT}" --timeout=5s >/dev/null 2>&1; then
  fail "unauthorized namespace unexpectedly reached VDIForge app PostgreSQL"
fi
echo "PASS: unauthorized namespace cannot reach VDIForge app PostgreSQL"

cleanup
trap - EXIT
echo "Phase 7 NetworkPolicy validation: PASS"
