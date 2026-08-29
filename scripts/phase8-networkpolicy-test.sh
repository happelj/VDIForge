#!/usr/bin/env bash
set -euo pipefail

GUAC_NS="${VDIFORGE_GUACAMOLE_NAMESPACE:-guacamole}"
INGRESS_NS="${VDIFORGE_INGRESS_NAMESPACE:-ingress-traefik}"
DENY_NS="${VDIFORGE_PHASE8_DENY_NAMESPACE:-vdiforge-phase8-netpol-deny}"
AGNHOST_IMAGE="${VDIFORGE_AGNHOST_IMAGE:-registry.k8s.io/e2e-test-images/agnhost:2.40}"
GUAC_SERVICE="${VDIFORGE_GUACAMOLE_SERVICE:-vdiforge-guacamole}"
GUACD_SERVICE="${VDIFORGE_GUACD_SERVICE:-vdiforge-guacd}"

cleanup() {
  kubectl delete pod phase8-ingress-probe -n "${INGRESS_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl delete pod phase8-guac-web-probe -n "${GUAC_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl delete pod phase8-guac-deny-probe -n "${GUAC_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl delete pod phase8-deny-probe -n "${DENY_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl delete namespace "${DENY_NS}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
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

trap cleanup EXIT
cleanup

kubectl create namespace "${DENY_NS}" >/dev/null
kubectl label namespace "${DENY_NS}" kubernetes.io/metadata.name="${DENY_NS}" --overwrite >/dev/null

run_probe "${INGRESS_NS}" phase8-ingress-probe "app.kubernetes.io/name=traefik,app.kubernetes.io/component=validation"
run_probe "${GUAC_NS}" phase8-guac-web-probe "app.kubernetes.io/name=vdiforge-guacamole,app.kubernetes.io/instance=vdiforge,app.kubernetes.io/component=remote-access,app.kubernetes.io/part-of=vdiforge"
run_probe "${GUAC_NS}" phase8-guac-deny-probe "app.kubernetes.io/name=phase8-guac-deny,app.kubernetes.io/component=validation"
run_probe "${DENY_NS}" phase8-deny-probe "app.kubernetes.io/name=phase8-deny,app.kubernetes.io/component=validation"

connect_from "${INGRESS_NS}" phase8-ingress-probe "${GUAC_SERVICE}.${GUAC_NS}.svc.cluster.local:8080" ||
  { echo "FAIL: allowed ingress-controller to Guacamole path did not connect" >&2; exit 1; }

connect_from "${GUAC_NS}" phase8-guac-web-probe "${GUACD_SERVICE}.${GUAC_NS}.svc.cluster.local:4822" ||
  { echo "FAIL: allowed Guacamole web to guacd path did not connect" >&2; exit 1; }

if connect_from "${GUAC_NS}" phase8-guac-deny-probe "${GUACD_SERVICE}.${GUAC_NS}.svc.cluster.local:4822"; then
  echo "FAIL: unlabeled Guacamole namespace pod reached guacd" >&2
  exit 1
fi

if connect_from "${DENY_NS}" phase8-deny-probe "${GUAC_SERVICE}.${GUAC_NS}.svc.cluster.local:8080"; then
  echo "FAIL: unauthorized namespace reached Guacamole web" >&2
  exit 1
fi

cleanup
trap - EXIT

echo "Phase 8 NetworkPolicy validation: PASS"
