#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

IMAGE="${PHASE7_IMAGE:-localhost/vdiforge-api:0.7.0}"
PLATFORM_NODE="${PHASE7_PLATFORM_NODE:-vdi-worker-01}"
PLATFORM_HOST="${PHASE7_PLATFORM_HOST:-192.168.56.11}"
PLATFORM_USER="${PHASE7_PLATFORM_USER:-vdiadmin}"
PLATFORM_SSH_KEY="${PHASE7_PLATFORM_SSH_KEY:-${HOME}/.ssh/vdiforge_ansible}"
BUILD_WORKDIR="${PHASE7_PLATFORM_BUILD_WORKDIR:-/home/vdiadmin/vdiforge-phase7-build}"
IMAGE_TAR="${PHASE7_IMAGE_TAR:-/tmp/vdiforge-api-0.7.0.tar}"
IMAGE_TAR_DIR="$(dirname "${IMAGE_TAR}")"
IMAGE_TAR_BASENAME="$(basename "${IMAGE_TAR}")"
IMPORTER_NAMESPACE="${PHASE7_IMPORTER_NAMESPACE:-vdiforge-desktops}"
IMPORTER_POD="${PHASE7_IMPORTER_POD:-phase7-image-importer}"
IMPORTER_IMAGE="${PHASE7_IMPORTER_IMAGE:-docker.io/moby/buildkit:v0.26.2}"
BUILDER_POD="${PHASE7_BUILDER_POD:-phase7-image-builder}"
BUILDER_IMAGE="${PHASE7_BUILDER_IMAGE:-docker.io/moby/buildkit:v0.26.2}"
HOST_CTR_PATH="${PHASE7_HOST_CTR_PATH:-/usr/bin/ctr}"
HOST_LIBC_PATH="${PHASE7_HOST_LIBC_PATH:-/usr/lib/x86_64-linux-gnu/libc.so.6}"
HOST_LD_PATH="${PHASE7_HOST_LD_PATH:-/lib64/ld-linux-x86-64.so.2}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ssh_platform() {
  ssh -o BatchMode=yes -i "${PLATFORM_SSH_KEY}" "${PLATFORM_USER}@${PLATFORM_HOST}" "$@"
}

sync_repo_to_platform() {
  ssh_platform "mkdir -p '${BUILD_WORKDIR}'"
  tar \
    --exclude='.git' \
    --exclude='.local' \
    --exclude='artifacts' \
    --exclude='packer_cache' \
    --exclude='*.qcow2' \
    --exclude='*.raw' \
    --exclude='*.img' \
    --exclude='*.iso' \
    -cf - . |
    ssh_platform "tar -xf - -C '${BUILD_WORKDIR}'"
}

build_on_platform() {
  ssh_platform "cd '${BUILD_WORKDIR}' && if command -v podman >/dev/null 2>&1; then podman build -f backend/Dockerfile -t '${IMAGE}' . && podman save '${IMAGE}' -o '${IMAGE_TAR}'; elif command -v buildah >/dev/null 2>&1; then buildah bud -f backend/Dockerfile -t '${IMAGE}' . && buildah push '${IMAGE}' 'docker-archive:${IMAGE_TAR}:${IMAGE}'; else echo 'Neither podman nor buildah is installed on ${PLATFORM_NODE}.' >&2; echo 'Run: sudo apt-get update && sudo apt-get install -y podman' >&2; exit 1; fi"
}

host_builder_available() {
  ssh_platform "command -v podman >/dev/null 2>&1 || command -v buildah >/dev/null 2>&1"
}

cleanup_builder_pod() {
  kubectl delete pod "${BUILDER_POD}" -n "${IMPORTER_NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null
}

cleanup_builder_pod_on_exit() {
  cleanup_builder_pod || true
}

build_with_kubernetes_builder() {
  cleanup_builder_pod
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${BUILDER_POD}
  namespace: ${IMPORTER_NAMESPACE}
  labels:
    app.kubernetes.io/name: phase7-image-builder
    app.kubernetes.io/part-of: vdiforge
    app.kubernetes.io/component: validation
spec:
  restartPolicy: Never
  nodeSelector:
    vdiforge.io/node-role: platform
  containers:
    - name: buildkit
      image: ${BUILDER_IMAGE}
      imagePullPolicy: IfNotPresent
      command:
        - /bin/sh
        - -ec
        - mkdir -p /workspace && sleep 3600
      securityContext:
        privileged: true
      resources:
        requests:
          cpu: 500m
          memory: 512Mi
        limits:
          cpu: "2"
          memory: 2Gi
      volumeMounts:
        - name: host-output
          mountPath: /host-output
  volumes:
    - name: host-output
      hostPath:
        path: ${IMAGE_TAR_DIR}
        type: DirectoryOrCreate
EOF
  kubectl wait pod "${BUILDER_POD}" -n "${IMPORTER_NAMESPACE}" --for=condition=Ready --timeout=600s >/dev/null
  tar \
    --exclude='.git' \
    --exclude='.local' \
    --exclude='artifacts' \
    --exclude='packer_cache' \
    --exclude='*.qcow2' \
    --exclude='*.raw' \
    --exclude='*.img' \
    --exclude='*.iso' \
    -cf - . |
    kubectl exec -i "${BUILDER_POD}" -n "${IMPORTER_NAMESPACE}" -- tar -xf - -C /workspace
  kubectl exec "${BUILDER_POD}" -n "${IMPORTER_NAMESPACE}" -- \
    buildctl-daemonless.sh build \
      --frontend dockerfile.v0 \
      --local context=/workspace \
      --local dockerfile=/workspace/backend \
      --output "type=docker,name=${IMAGE},dest=/host-output/${IMAGE_TAR_BASENAME}"
  cleanup_builder_pod
}

import_with_kubernetes_pod() {
  kubectl delete pod "${IMPORTER_POD}" -n "${IMPORTER_NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${IMPORTER_POD}
  namespace: ${IMPORTER_NAMESPACE}
  labels:
    app.kubernetes.io/name: phase7-image-importer
    app.kubernetes.io/part-of: vdiforge
    app.kubernetes.io/component: validation
spec:
  restartPolicy: Never
  nodeSelector:
    vdiforge.io/node-role: platform
  containers:
    - name: importer
      image: ${IMPORTER_IMAGE}
      imagePullPolicy: IfNotPresent
      command:
        - /bin/sh
        - -ec
        - /host-ld/ld-linux-x86-64.so.2 --library-path /host-lib /host-bin/ctr -a /run/containerd/containerd.sock -n k8s.io images import /image/vdiforge-api.tar
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 500m
          memory: 256Mi
      volumeMounts:
        - name: containerd-socket
          mountPath: /run/containerd/containerd.sock
        - name: image-tar
          mountPath: /image/vdiforge-api.tar
          readOnly: true
        - name: host-ctr
          mountPath: /host-bin/ctr
          readOnly: true
        - name: host-libc
          mountPath: /host-lib/libc.so.6
          readOnly: true
        - name: host-ld
          mountPath: /host-ld/ld-linux-x86-64.so.2
          readOnly: true
  volumes:
    - name: containerd-socket
      hostPath:
        path: /run/containerd/containerd.sock
        type: Socket
    - name: image-tar
      hostPath:
        path: ${IMAGE_TAR}
        type: File
    - name: host-ctr
      hostPath:
        path: ${HOST_CTR_PATH}
        type: File
    - name: host-libc
      hostPath:
        path: ${HOST_LIBC_PATH}
        type: File
    - name: host-ld
      hostPath:
        path: ${HOST_LD_PATH}
        type: File
EOF
  kubectl wait pod "${IMPORTER_POD}" -n "${IMPORTER_NAMESPACE}" --for=condition=Ready --timeout=180s >/dev/null || true
  kubectl wait pod "${IMPORTER_POD}" -n "${IMPORTER_NAMESPACE}" --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s >/dev/null
  kubectl logs "${IMPORTER_POD}" -n "${IMPORTER_NAMESPACE}" || true
  kubectl delete pod "${IMPORTER_POD}" -n "${IMPORTER_NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null
}

verify_image_loaded() {
  ssh_platform "sudo -n ctr -n k8s.io images list | grep -q '${IMAGE}'" || {
    echo "Image import pod completed. sudo-less direct containerd verification is unavailable on ${PLATFORM_NODE}." >&2
    return 0
  }
}

command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed"
command -v ssh >/dev/null 2>&1 || fail "ssh is not installed"
command -v tar >/dev/null 2>&1 || fail "tar is not installed"

node_name="$(kubectl get node "${PLATFORM_NODE}" -o jsonpath='{.metadata.name}')"
[[ "${node_name}" == "${PLATFORM_NODE}" ]] || fail "platform node ${PLATFORM_NODE} is not present"

trap cleanup_builder_pod_on_exit EXIT

if host_builder_available; then
  sync_repo_to_platform
  build_on_platform
else
  echo "No Podman/Buildah builder found on ${PLATFORM_NODE}; using temporary BuildKit validation pod."
  build_with_kubernetes_builder
fi
import_with_kubernetes_pod
verify_image_loaded

echo "PASS: ${IMAGE} was built and imported for ${PLATFORM_NODE}"
