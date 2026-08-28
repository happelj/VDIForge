#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

NS="${PHASE7_NAMESPACE:-vdiforge-desktops}"
SOURCE_DV="${PHASE7_SOURCE_DV:-vdiforge-golden-ubuntu-devops-1-0-0}"
SOURCE_PVC="${PHASE7_SOURCE_PVC:-${SOURCE_DV}}"
BUILD_HOST="${PHASE7_BUILD_HOST:-192.168.56.12}"
BUILD_HOST_USER="${PHASE7_BUILD_HOST_USER:-vdiadmin}"
BUILD_HOST_SSH_KEY="${PHASE7_BUILD_HOST_SSH_KEY:-${HOME}/.ssh/vdiforge_ansible}"
BUILD_WORKDIR="${PHASE7_BUILD_WORKDIR:-/home/vdiadmin/vdiforge-phase6-build}"
IMAGE_VERSION="${VDIFORGE_IMAGE_VERSION:-1.0.0}"
IMAGE_FILE="${PHASE7_IMAGE_FILE:-${BUILD_WORKDIR}/artifacts/images/ubuntu-devops/${IMAGE_VERSION}/ubuntu-devops-${IMAGE_VERSION}-amd64.qcow2}"
HTTP_PORT="${PHASE7_HTTP_PORT:-18081}"
STORAGE_SIZE="${PHASE7_STORAGE_SIZE:-32Gi}"
RENDERED="/tmp/vdiforge-phase7-golden-source.yaml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ssh_build_host() {
  ssh -o BatchMode=yes -i "${BUILD_HOST_SSH_KEY}" "${BUILD_HOST_USER}@${BUILD_HOST}" "$@"
}

cleanup_http() {
  ssh_build_host "if [[ -f /tmp/vdiforge-phase7-image-http.pid ]]; then kill \$(cat /tmp/vdiforge-phase7-image-http.pid) >/dev/null 2>&1 || true; rm -f /tmp/vdiforge-phase7-image-http.pid; fi; pkill -f 'python3 -m http.server ${HTTP_PORT} --bind ${BUILD_HOST}' >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
}

command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed"
command -v curl >/dev/null 2>&1 || fail "curl is not installed"

source_is_ready() {
  local pvc_phase
  pvc_phase="$(kubectl get pvc "${SOURCE_PVC}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${pvc_phase}" == "Bound" ]]
}

if source_is_ready; then
  echo "PASS: source PVC ${SOURCE_PVC} already exists and is Bound in ${NS}"
  exit 0
fi

if kubectl get datavolume "${SOURCE_DV}" -n "${NS}" >/dev/null 2>&1 ||
  kubectl get pvc "${SOURCE_PVC}" -n "${NS}" >/dev/null 2>&1; then
  echo "Removing incomplete source DataVolume/PVC ${SOURCE_PVC} before recreating it."
  kubectl delete datavolume "${SOURCE_DV}" -n "${NS}" --ignore-not-found=true --wait=true >/dev/null
  kubectl delete pvc "${SOURCE_PVC}" -n "${NS}" --ignore-not-found=true --wait=true >/dev/null
fi

ssh_build_host "test -f '${IMAGE_FILE}'" || fail "image artifact not found on build host: ${IMAGE_FILE}"

IMAGE_SHA256="$(ssh_build_host "sha256sum '${IMAGE_FILE}' | awk '{print \$1}'")"
IMAGE_BASENAME="$(basename "${IMAGE_FILE}")"
IMAGE_URL="http://${BUILD_HOST}:${HTTP_PORT}/${IMAGE_BASENAME}"

cleanup_http
trap cleanup_http EXIT

ssh_build_host "cd '$(dirname "${IMAGE_FILE}")' || exit 1; nohup python3 -m http.server '${HTTP_PORT}' --bind '${BUILD_HOST}' >/tmp/vdiforge-phase7-image-http.log 2>&1 </dev/null & echo \$! >/tmp/vdiforge-phase7-image-http.pid"
sleep 3
curl -fsI "${IMAGE_URL}" >/dev/null || fail "image artifact HTTP endpoint is not reachable: ${IMAGE_URL}"

cat >"${RENDERED}" <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${SOURCE_DV}
  namespace: ${NS}
  annotations:
    cdi.kubevirt.io/storage.bind.immediate.requested: "true"
  labels:
    app.kubernetes.io/name: vdiforge-golden-source
    app.kubernetes.io/part-of: vdiforge
    app.kubernetes.io/component: golden-image-source
    vdiforge.io/image-id: ubuntu-devops
    vdiforge.io/image-version: "${IMAGE_VERSION}"
    vdiforge.io/phase: "7"
spec:
  source:
    http:
      url: "${IMAGE_URL}"
      checksum: "sha256:${IMAGE_SHA256}"
  storage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: ${STORAGE_SIZE}
    storageClassName: vdiforge-local-path
EOF

kubectl apply -f "${RENDERED}" >/dev/null
kubectl wait "datavolume/${SOURCE_DV}" -n "${NS}" --for=condition=Ready --timeout=1200s >/dev/null
kubectl get pvc "${SOURCE_PVC}" -n "${NS}" >/dev/null
trap - EXIT
cleanup_http

echo "PASS: source PVC ${SOURCE_PVC} is ready for ubuntu-devops:${IMAGE_VERSION}"
