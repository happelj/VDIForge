#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

IMAGE="${1:-}"
VERSION="${VDIFORGE_IMAGE_VERSION:-1.0.0}"
ARTIFACT_ROOT="${VDIFORGE_ARTIFACT_ROOT:-${ROOT_DIR}/artifacts/images}"
KEY_DIR="${ROOT_DIR}/.local/phase6"
KEY_PATH="${KEY_DIR}/packer_ed25519"
IMAGE_DISK_SIZE="${VDIFORGE_IMAGE_DISK_SIZE:-24G}"
IMAGE_MEMORY="${VDIFORGE_IMAGE_MEMORY:-3072}"
IMAGE_CPUS="${VDIFORGE_IMAGE_CPUS:-2}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

case "${IMAGE}" in
  ubuntu-base|ubuntu-developer|ubuntu-devops)
    ;;
  *)
    fail "Usage: $0 <ubuntu-base|ubuntu-developer|ubuntu-devops>"
    ;;
esac

command -v packer >/dev/null 2>&1 || fail "packer is not installed or not in PATH"
command -v qemu-system-x86_64 >/dev/null 2>&1 || fail "qemu-system-x86_64 is not installed"
command -v qemu-img >/dev/null 2>&1 || fail "qemu-img is not installed"
command -v virt-sysprep >/dev/null 2>&1 || fail "virt-sysprep is not installed"
command -v ansible-playbook >/dev/null 2>&1 || fail "ansible-playbook is not installed"

[[ -e /dev/kvm ]] || fail "/dev/kvm is missing"
[[ -r /dev/kvm && -w /dev/kvm ]] || fail "current user cannot read/write /dev/kvm"

mkdir -p "${KEY_DIR}" "${ARTIFACT_ROOT}"

if [[ ! -f "${KEY_PATH}" ]]; then
  ssh-keygen -t ed25519 -N "" -C "vdiforge-phase6-packer" -f "${KEY_PATH}" >/dev/null
fi

chmod 600 "${KEY_PATH}"
SSH_PUBLIC_KEY="$(tr -d '\r\n' <"${KEY_PATH}.pub")"
TEMPLATE_DIR="${ROOT_DIR}/packer/${IMAGE}"
VAR_FILE="${KEY_DIR}/${IMAGE}.pkrvars.hcl"
VALIDATE_VAR_FILE="${KEY_DIR}/${IMAGE}.validate.pkrvars.hcl"
VALIDATE_ARTIFACT_ROOT="${KEY_DIR}/validate-artifacts-${IMAGE}-$$"

cat >"${VAR_FILE}" <<EOF
image_version = "${VERSION}"
artifact_root = "${ARTIFACT_ROOT}"
ssh_private_key_file = "${KEY_PATH}"
ssh_public_key = "${SSH_PUBLIC_KEY}"
build_username = "packer"
disk_size = "${IMAGE_DISK_SIZE}"
memory = ${IMAGE_MEMORY}
cpus = ${IMAGE_CPUS}
EOF

cat >"${VALIDATE_VAR_FILE}" <<EOF
image_version = "${VERSION}"
artifact_root = "${VALIDATE_ARTIFACT_ROOT}"
ssh_private_key_file = "${KEY_PATH}"
ssh_public_key = "${SSH_PUBLIC_KEY}"
build_username = "packer"
disk_size = "${IMAGE_DISK_SIZE}"
memory = ${IMAGE_MEMORY}
cpus = ${IMAGE_CPUS}
EOF

export PATH="${HOME}/.local/bin:${PATH}"

packer init "${TEMPLATE_DIR}"
packer fmt -check "${TEMPLATE_DIR}"
packer validate -var-file="${VALIDATE_VAR_FILE}" "${TEMPLATE_DIR}"
packer build -force -var-file="${VAR_FILE}" "${TEMPLATE_DIR}"

ARTIFACT="${ARTIFACT_ROOT}/${IMAGE}/${VERSION}/${IMAGE}-${VERSION}-amd64.qcow2"
MANIFEST="${ARTIFACT_ROOT}/${IMAGE}/${VERSION}/${IMAGE}-${VERSION}.manifest.json"
CHECKSUM="${ARTIFACT_ROOT}/${IMAGE}/${VERSION}/${IMAGE}-${VERSION}.sha256"

[[ -f "${ARTIFACT}" ]] || fail "expected artifact missing: ${ARTIFACT}"
[[ -f "${MANIFEST}" ]] || fail "expected manifest missing: ${MANIFEST}"
[[ -f "${CHECKSUM}" ]] || fail "expected checksum missing: ${CHECKSUM}"

qemu-img info "${ARTIFACT}" | grep -q "file format: qcow2" || fail "artifact is not qcow2"
sha256sum -c "${CHECKSUM}"

echo "PASS: ${IMAGE}:${VERSION} build and artifact validation completed"
