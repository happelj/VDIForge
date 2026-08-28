#!/usr/bin/env bash
set -euo pipefail

if [[ "$(hostname)" != "vdi-worker-01" ]]; then
  echo "Run this helper on vdi-worker-01. Current host: $(hostname)" >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y podman

podman --version
ctr --version

echo "PASS: Phase 7 container build tools are installed on vdi-worker-01"
