#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${VDIFORGE_IMAGE_NAME:-}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command missing: $1"
}

require_package() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed" || fail "required package missing: $1"
}

[[ -n "${IMAGE_NAME}" ]] || fail "VDIFORGE_IMAGE_NAME is required"

grep -q "Ubuntu 26.04" /etc/os-release || fail "Ubuntu 26.04 release was not detected"
require_command ip
require_command cloud-init
require_command qemu-ga
require_package qemu-guest-agent
require_package openssh-server
require_package ca-certificates
require_package xfce4
require_package xrdp
require_package xorgxrdp

ip route get 1.1.1.1 >/dev/null || fail "network route validation failed"
systemctl is-enabled qemu-guest-agent >/dev/null || fail "qemu-guest-agent is not enabled"

if [[ "${IMAGE_NAME}" == "ubuntu-developer" || "${IMAGE_NAME}" == "ubuntu-devops" ]]; then
  require_command git
  require_command python3
  require_command gcc
  require_command make
  require_command geany
fi

if [[ "${IMAGE_NAME}" == "ubuntu-devops" ]]; then
  require_command terraform
  require_command ansible
  require_command kubectl
  require_command helm

  terraform version >/dev/null
  ansible --version >/dev/null
  kubectl version --client >/dev/null
  helm version >/dev/null
  python3 --version >/dev/null
  git --version >/dev/null
fi

find_cmd=(find /home /root -xdev -type f \( -name "id_rsa" -o -name "id_ed25519" -o -name "*.pem" -o -name "*.key" \) -print -quit)
if command -v sudo >/dev/null 2>&1; then
  sudo "${find_cmd[@]}" 2>/dev/null | grep -q . && fail "private key material found in user homes"
else
  "${find_cmd[@]}" 2>/dev/null | grep -q . && fail "private key material found in user homes"
fi

echo "PASS: ${IMAGE_NAME} in-guest image validation completed"
