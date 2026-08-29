#!/usr/bin/env bash
set -euo pipefail

NAMESPACES=(
  "${VDIFORGE_SYSTEM_NAMESPACE:-vdiforge-system}"
  "${VDIFORGE_DESKTOP_NAMESPACE:-vdiforge-desktops}"
  "${VDIFORGE_IDENTITY_NAMESPACE:-keycloak}"
  "${VDIFORGE_REMOTE_NAMESPACE:-guacamole}"
  "${VDIFORGE_MONITORING_NAMESPACE:-monitoring}"
)

echo "VDIForge Phase 12 Kubernetes Secret inventory"
echo "Only metadata and key names are shown. Secret values are intentionally not decoded."

for namespace in "${NAMESPACES[@]}"; do
  echo
  echo "Namespace: ${namespace}"
  kubectl get secrets -n "${namespace}" -o json |
    jq -r '
      .items[]
      | {
          name: .metadata.name,
          type: .type,
          keys: ((.data // {}) | keys)
        }
      | "- \(.name) type=\(.type) keys=\(.keys | join(","))"
    '
done

echo
echo "ServiceAccount Secret access summary"
bash "$(dirname "${BASH_SOURCE[0]}")/phase12-rbac-test.sh"
