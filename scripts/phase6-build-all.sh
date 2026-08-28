#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

for image in ubuntu-base ubuntu-developer ubuntu-devops; do
  bash scripts/phase6-build-image.sh "${image}"
done

echo "PASS: all Phase 6 golden image builds completed"
