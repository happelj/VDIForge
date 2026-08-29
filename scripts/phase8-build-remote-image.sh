#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

export VDIFORGE_IMAGE_VERSION="${VDIFORGE_IMAGE_VERSION:-1.1.0}"
export VDIFORGE_IMAGE_DISK_SIZE="${VDIFORGE_IMAGE_DISK_SIZE:-15G}"
IMAGE_DIR="${PHASE8_IMAGE_DIR:-artifacts/images/ubuntu-devops/${VDIFORGE_IMAGE_VERSION}}"
IMAGE_FILE="${IMAGE_DIR}/ubuntu-devops-${VDIFORGE_IMAGE_VERSION}-amd64.qcow2"
CHECKSUM_FILE="${IMAGE_DIR}/ubuntu-devops-${VDIFORGE_IMAGE_VERSION}.sha256"

desired_virtual_bytes() {
  case "${VDIFORGE_IMAGE_DISK_SIZE}" in
    *G) echo "$((${VDIFORGE_IMAGE_DISK_SIZE%G} * 1024 * 1024 * 1024))" ;;
    *M) echo "$((${VDIFORGE_IMAGE_DISK_SIZE%M} * 1024 * 1024))" ;;
    *) echo "${VDIFORGE_IMAGE_DISK_SIZE}" ;;
  esac
}

if [[ -f "${IMAGE_FILE}" && -f "${CHECKSUM_FILE}" ]]; then
  if (cd "${IMAGE_DIR}" && sha256sum -c "$(basename "${CHECKSUM_FILE}")" >/dev/null); then
    if command -v qemu-img >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      VIRTUAL_SIZE="$(qemu-img info --output=json "${IMAGE_FILE}" | jq -r '."virtual-size"')"
      if [[ "${VIRTUAL_SIZE}" == "$(desired_virtual_bytes)" ]]; then
        echo "PASS: ubuntu-devops:${VDIFORGE_IMAGE_VERSION} remote-enabled image artifact already exists, passed checksum validation, and has ${VDIFORGE_IMAGE_DISK_SIZE} virtual size"
        exit 0
      fi
      echo "Existing ubuntu-devops:${VDIFORGE_IMAGE_VERSION} artifact virtual size is ${VIRTUAL_SIZE} bytes; rebuilding with ${VDIFORGE_IMAGE_DISK_SIZE} for Phase 8."
    else
      echo "qemu-img or jq is unavailable for artifact size inspection; rebuilding ubuntu-devops:${VDIFORGE_IMAGE_VERSION}."
    fi
  fi
fi

bash scripts/phase6-build-image.sh ubuntu-devops

echo "PASS: ubuntu-devops:${VDIFORGE_IMAGE_VERSION} remote-enabled image build completed"
