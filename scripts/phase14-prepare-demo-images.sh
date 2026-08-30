#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

NS="${PHASE14_NAMESPACE:-vdiforge-desktops}"
BUILD_HOST="${PHASE14_BUILD_HOST:-192.168.56.12}"
BUILD_HOST_USER="${PHASE14_BUILD_HOST_USER:-vdiadmin}"
BUILD_HOST_SSH_KEY="${PHASE14_BUILD_HOST_SSH_KEY:-${HOME}/.ssh/vdiforge_ansible}"
BUILD_WORKDIR="${PHASE14_BUILD_WORKDIR:-/home/vdiadmin/vdiforge-phase6-build}"
HTTP_BIND="${PHASE14_HTTP_BIND:-${BUILD_HOST}}"
STORAGE_CLASS="${PHASE14_STORAGE_CLASS:-vdiforge-local-path}"
SCRATCH_STORAGE_CLASS="${PHASE14_SCRATCH_STORAGE_CLASS:-vdiforge-local-path}"
CLEANUP_SUPERSEDED_DEVOPS="${PHASE14_CLEANUP_SUPERSEDED_DEVOPS:-false}"
CLEANUP_SUPERSEDED_DEVOPS_ARTIFACTS="${PHASE14_CLEANUP_SUPERSEDED_DEVOPS_ARTIFACTS:-${CLEANUP_SUPERSEDED_DEVOPS}}"

IMAGE_DEFINITIONS=(
  "ubuntu-base|1.0.0|vdiforge-golden-ubuntu-base-1-0-0|24Gi|18083"
  "ubuntu-developer|1.0.0|vdiforge-golden-ubuntu-developer-1-0-0|28Gi|18084"
)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ssh_build_host() {
  ssh -o BatchMode=yes -i "${BUILD_HOST_SSH_KEY}" "${BUILD_HOST_USER}@${BUILD_HOST}" "$@"
}

command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed"
command -v curl >/dev/null 2>&1 || fail "curl is not installed"
command -v ssh >/dev/null 2>&1 || fail "ssh is not installed"

ensure_cdi_scratch_storage() {
  local current
  if ! kubectl get cdi cdi -n cdi >/dev/null 2>&1; then
    fail "CDI is not installed; cannot prepare source DataVolumes"
  fi

  current="$(kubectl get cdiconfig config -o jsonpath='{.status.scratchSpaceStorageClass}' 2>/dev/null || true)"
  if [[ "${current}" == "${SCRATCH_STORAGE_CLASS}" ]]; then
    echo "PASS: CDI scratch storage class is ${SCRATCH_STORAGE_CLASS}"
    return 0
  fi

  echo "Configuring CDI scratch storage class as ${SCRATCH_STORAGE_CLASS}."
  kubectl patch cdi cdi -n cdi \
    --type merge \
    --patch "{\"spec\":{\"config\":{\"scratchSpaceStorageClass\":\"${SCRATCH_STORAGE_CLASS}\"}}}" >/dev/null

  for _ in $(seq 1 60); do
    current="$(kubectl get cdiconfig config -o jsonpath='{.status.scratchSpaceStorageClass}' 2>/dev/null || true)"
    if [[ "${current}" == "${SCRATCH_STORAGE_CLASS}" ]]; then
      echo "PASS: CDI scratch storage class configured as ${SCRATCH_STORAGE_CLASS}"
      return 0
    fi
    sleep 2
  done

  fail "CDI scratch storage class did not converge to ${SCRATCH_STORAGE_CLASS}"
}

source_is_ready() {
  local name="$1"
  local dv_phase
  local pvc_phase
  dv_phase="$(kubectl get datavolume "${name}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  pvc_phase="$(kubectl get pvc "${name}" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${dv_phase}" == "Succeeded" && "${pvc_phase}" == "Bound" ]]
}

cleanup_http() {
  local label="$1"
  local port="$2"
  ssh_build_host "if [[ -f /tmp/${label}.pid ]]; then kill \$(cat /tmp/${label}.pid) >/dev/null 2>&1 || true; rm -f /tmp/${label}.pid; fi; pkill -f 'python3 -m http.server ${port} --bind ${HTTP_BIND}' >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
}

cleanup_superseded_devops_sources() {
  [[ "${CLEANUP_SUPERSEDED_DEVOPS}" == "true" ]] || return 0

  for name in vdiforge-golden-ubuntu-devops-1-0-0 vdiforge-golden-ubuntu-devops-1-1-0; do
    echo "Deleting superseded DevOps source DataVolume/PVC ${name}; ubuntu-devops:1.2.0 is preserved."
    kubectl delete datavolume "${name}" -n "${NS}" --ignore-not-found=true --wait=true >/dev/null
    kubectl delete pvc "${name}" -n "${NS}" --ignore-not-found=true --wait=true >/dev/null
  done
}

cleanup_superseded_devops_artifacts() {
  [[ "${CLEANUP_SUPERSEDED_DEVOPS_ARTIFACTS}" == "true" ]] || return 0

  local artifact_root="${BUILD_WORKDIR}/artifacts/images/ubuntu-devops"
  local version
  local artifact_dir

  for version in 1.0.0 1.1.0; do
    artifact_dir="${artifact_root}/${version}"
    case "${artifact_dir}" in
      "${BUILD_WORKDIR}/artifacts/images/ubuntu-devops/"*) ;;
      *) fail "refusing to delete unexpected artifact path: ${artifact_dir}" ;;
    esac
    echo "Deleting superseded generated DevOps image artifact ${artifact_dir}; it can be rebuilt from Packer if needed."
    ssh_build_host "rm -rf -- '${artifact_dir}'"
  done
}

prepare_source() {
  local image_id="$1"
  local version="$2"
  local source_name="$3"
  local storage_size="$4"
  local http_port="$5"
  local image_file="${BUILD_WORKDIR}/artifacts/images/${image_id}/${version}/${image_id}-${version}-amd64.qcow2"
  local image_basename="${image_id}-${version}-amd64.qcow2"
  local image_url="http://${HTTP_BIND}:${http_port}/${image_basename}"
  local image_sha256
  local label="vdiforge-phase14-${image_id}-${version}-http"

  if source_is_ready "${source_name}"; then
    echo "PASS: ${source_name} DataVolume is Succeeded and PVC is Bound"
    return 0
  fi

  if kubectl get datavolume "${source_name}" -n "${NS}" >/dev/null 2>&1 ||
    kubectl get pvc "${source_name}" -n "${NS}" >/dev/null 2>&1; then
    echo "Removing incomplete source DataVolume/PVC ${source_name} before recreating it."
    kubectl delete datavolume "${source_name}" -n "${NS}" --ignore-not-found=true --wait=true >/dev/null
    kubectl delete pvc "${source_name}" -n "${NS}" --ignore-not-found=true --wait=true >/dev/null
  fi

  ssh_build_host "test -f '${image_file}'" || fail "image artifact not found on build host: ${image_file}"
  image_sha256="$(ssh_build_host "sha256sum '${image_file}' | awk '{print \$1}'")"

  cleanup_http "${label}" "${http_port}"
  trap "cleanup_http '${label}' '${http_port}'" EXIT

  ssh_build_host "cd '$(dirname "${image_file}")' || exit 1; nohup python3 -m http.server '${http_port}' --bind '${HTTP_BIND}' >/tmp/${label}.log 2>&1 </dev/null & echo \$! >/tmp/${label}.pid"
  sleep 3
  curl -fsI "${image_url}" >/dev/null || fail "image artifact HTTP endpoint is not reachable: ${image_url}"

  kubectl apply -f - >/dev/null <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${source_name}
  namespace: ${NS}
  annotations:
    cdi.kubevirt.io/storage.bind.immediate.requested: "true"
  labels:
    app.kubernetes.io/name: vdiforge-golden-source
    app.kubernetes.io/part-of: vdiforge
    app.kubernetes.io/component: golden-image-source
    vdiforge.io/image-id: ${image_id}
    vdiforge.io/image-version: "${version}"
    vdiforge.io/phase: "14"
spec:
  source:
    http:
      url: "${image_url}"
      checksum: "sha256:${image_sha256}"
  storage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: ${storage_size}
    storageClassName: ${STORAGE_CLASS}
EOF

  kubectl wait "datavolume/${source_name}" -n "${NS}" --for=condition=Ready --timeout=1200s >/dev/null
  kubectl get pvc "${source_name}" -n "${NS}" >/dev/null
  trap - EXIT
  cleanup_http "${label}" "${http_port}"

  echo "PASS: source PVC ${source_name} is ready for ${image_id}:${version}"
}

ensure_cdi_scratch_storage
cleanup_superseded_devops_sources
cleanup_superseded_devops_artifacts

for definition in "${IMAGE_DEFINITIONS[@]}"; do
  IFS="|" read -r image_id version source_name storage_size http_port <<<"${definition}"
  prepare_source "${image_id}" "${version}" "${source_name}" "${storage_size}" "${http_port}"
done

if ! source_is_ready "vdiforge-golden-ubuntu-devops-1-2-0"; then
  fail "ubuntu-devops:1.2.0 source PVC is not ready; Phase 14 preserves this as the final remote desktop demo image"
fi

kubectl get datavolume,pvc -n "${NS}" \
  -l app.kubernetes.io/component=golden-image-source \
  -o wide

echo "Phase 14 demo image source preparation: PASS"
