#!/usr/bin/env bash
set -euo pipefail

PACKER_VERSION="${PACKER_VERSION:-1.16.0}"
PACKER_SHA256="${PACKER_SHA256:-5edcd14ab59b535040c512dbecd6ec9ef976a000b073c19d93e4c431c948581e}"
PACKER_URL="https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip"

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required to install QEMU/libguestfs build dependencies." >&2
  exit 1
fi

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ansible \
  ansible-lint \
  cloud-image-utils \
  curl \
  git \
  jq \
  libguestfs-tools \
  openssh-client \
  python3 \
  python3-yaml \
  qemu-system-x86 \
  qemu-utils \
  unzip \
  xorriso

sudo usermod -aG kvm "${USER}"

kernel_image="/boot/vmlinuz-$(uname -r)"
if [[ -f "${kernel_image}" ]]; then
  sudo chmod 0644 "${kernel_image}"
fi

mkdir -p "${HOME}/.local/bin"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

curl -fsSLo "${tmp_dir}/packer.zip" "${PACKER_URL}"
echo "${PACKER_SHA256}  ${tmp_dir}/packer.zip" | sha256sum -c -
unzip -oq "${tmp_dir}/packer.zip" -d "${tmp_dir}/packer"
install -m 0755 "${tmp_dir}/packer/packer" "${HOME}/.local/bin/packer"

if ! grep -q '\.local/bin' "${HOME}/.profile" 2>/dev/null; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"${HOME}/.profile"
fi

export PATH="${HOME}/.local/bin:${PATH}"

packer version
qemu-system-x86_64 --version | head -n 1
qemu-img --version | head -n 1
virt-sysprep --version
ansible --version | head -n 1
ansible-lint --version
ls -l "${kernel_image}" 2>/dev/null || true

if [[ ! -e /dev/kvm ]]; then
  echo "/dev/kvm is missing. Phase 6 builds require a KVM-capable Linux build environment." >&2
  exit 1
fi

if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  echo "Current shell cannot read/write /dev/kvm yet."
  echo "Log out and back in, or start a new SSH session, after kvm group membership is updated."
fi

if [[ -f "${kernel_image}" && ! -r "${kernel_image}" ]]; then
  echo "${kernel_image} is not readable by ${USER}; libguestfs/virt-sysprep will fail." >&2
  exit 1
fi

echo "Phase 6 build tooling installed."
