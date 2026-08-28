#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "Usage: $0 <image-name> <version> <artifact> <source-url> <source-checksum> <ubuntu-release> <architecture>" >&2
  exit 2
fi

IMAGE_NAME="$1"
IMAGE_VERSION="$2"
ARTIFACT="$3"
SOURCE_URL="$4"
SOURCE_CHECKSUM="$5"
UBUNTU_RELEASE="$6"
ARCHITECTURE="$7"

if [[ ! -f "${ARTIFACT}" ]]; then
  echo "Artifact not found: ${ARTIFACT}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to write image manifests." >&2
  exit 1
fi

ARTIFACT_SHA256="$(sha256sum "${ARTIFACT}" | awk '{print $1}')"
MANIFEST_PATH="$(dirname "${ARTIFACT}")/${IMAGE_NAME}-${IMAGE_VERSION}.manifest.json"
CHECKSUM_PATH="$(dirname "${ARTIFACT}")/${IMAGE_NAME}-${IMAGE_VERSION}.sha256"
PACKER_VERSION="$(packer version | head -n 1 | awk '{print $NF}')"
ANSIBLE_VERSION="$(ansible --version | head -n 1)"
GIT_COMMIT="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
BUILD_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

sha256sum "${ARTIFACT}" >"${CHECKSUM_PATH}"

jq -n \
  --arg imageName "${IMAGE_NAME}" \
  --arg imageVersion "${IMAGE_VERSION}" \
  --arg ubuntuRelease "${UBUNTU_RELEASE}" \
  --arg architecture "${ARCHITECTURE}" \
  --arg buildTimestamp "${BUILD_TIMESTAMP}" \
  --arg sourceUrl "${SOURCE_URL}" \
  --arg sourceChecksum "${SOURCE_CHECKSUM}" \
  --arg artifactPath "${ARTIFACT}" \
  --arg artifactSha256 "${ARTIFACT_SHA256}" \
  --arg artifactFormat "qcow2" \
  --arg packerVersion "${PACKER_VERSION}" \
  --arg ansibleVersion "${ANSIBLE_VERSION}" \
  --arg gitCommit "${GIT_COMMIT}" \
  '{
    schemaVersion: "vdiforge.io/image-manifest/v1alpha1",
    image: {
      id: $imageName,
      version: $imageVersion,
      ubuntuRelease: $ubuntuRelease,
      architecture: $architecture,
      buildTimestamp: $buildTimestamp
    },
    source: {
      url: $sourceUrl,
      checksum: ("sha256:" + $sourceChecksum)
    },
    artifact: {
      path: $artifactPath,
      format: $artifactFormat,
      sha256: $artifactSha256
    },
    build: {
      packerVersion: $packerVersion,
      ansibleVersion: $ansibleVersion,
      gitCommit: $gitCommit
    }
  }' >"${MANIFEST_PATH}"

echo "Wrote ${MANIFEST_PATH}"
echo "Wrote ${CHECKSUM_PATH}"
