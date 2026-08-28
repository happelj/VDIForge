#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <artifact.qcow2>" >&2
  exit 2
fi

ARTIFACT="$1"

if [[ ! -f "${ARTIFACT}" ]]; then
  echo "Image artifact not found: ${ARTIFACT}" >&2
  exit 1
fi

if ! command -v virt-sysprep >/dev/null 2>&1; then
  echo "virt-sysprep is required for offline image generalization." >&2
  exit 1
fi

virt-sysprep \
  -a "${ARTIFACT}" \
  --operations bash-history,logfiles,machine-id,ssh-hostkeys,tmp-files,udev-persistent-net \
  --run-command 'rm -f /etc/sudoers.d/90-cloud-init-users /etc/sudoers.d/99-vdiforge-packer /etc/sudoers.d/90-vdiforge-packer || true' \
  --run-command 'userdel -r packer 2>/dev/null || true' \
  --run-command 'rm -rf /home/packer /root/.ssh || true'

qemu-img info "${ARTIFACT}" >/dev/null
