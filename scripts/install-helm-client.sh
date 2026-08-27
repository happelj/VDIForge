#!/usr/bin/env bash
set -euo pipefail

HELM_VERSION="${HELM_VERSION:-v4.2.4}"
HELM_PLATFORM="${HELM_PLATFORM:-linux-amd64}"
HELM_BIN_DIR="${HELM_BIN_DIR:-${HOME}/.local/bin}"
ARCHIVE="helm-${HELM_VERSION}-${HELM_PLATFORM}.tar.gz"
BASE_URL="https://get.helm.sh"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT

mkdir -p "${HELM_BIN_DIR}"
cd "${WORK_DIR}"

curl -fsSLO "${BASE_URL}/${ARCHIVE}"
curl -fsSLO "${BASE_URL}/${ARCHIVE}.sha256sum"
sha256sum -c "${ARCHIVE}.sha256sum"

tar -xzf "${ARCHIVE}"
install -m 0755 "${HELM_PLATFORM}/helm" "${HELM_BIN_DIR}/helm"

"${HELM_BIN_DIR}/helm" version
