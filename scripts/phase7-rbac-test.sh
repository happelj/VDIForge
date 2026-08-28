#!/usr/bin/env bash
set -euo pipefail

SA="system:serviceaccount:vdiforge-system:vdiforge-provisioner"

expect_yes() {
  local description="$1"
  shift
  if [[ "$(kubectl auth can-i "$@" --as="${SA}")" != "yes" ]]; then
    echo "FAIL: expected allowed: ${description}" >&2
    exit 1
  fi
  echo "PASS: allowed: ${description}"
}

expect_no() {
  local description="$1"
  shift
  if [[ "$(kubectl auth can-i "$@" --as="${SA}")" != "no" ]]; then
    echo "FAIL: expected denied: ${description}" >&2
    exit 1
  fi
  echo "PASS: denied: ${description}"
}

expect_yes "create KubeVirt VMs in vdiforge-desktops" create virtualmachines.kubevirt.io -n vdiforge-desktops
expect_yes "create CDI DataVolumes in vdiforge-desktops" create datavolumes.cdi.kubevirt.io -n vdiforge-desktops
expect_yes "create Services in vdiforge-desktops" create services -n vdiforge-desktops
expect_no "cluster-admin equivalent ClusterRoleBinding creation" create clusterrolebindings.rbac.authorization.k8s.io
expect_no "read Keycloak secrets" get secrets -n keycloak
expect_no "read app database secrets" get secrets -n vdiforge-system
expect_no "delete KubeVirt namespace pods" delete pods -n kubevirt

echo "Phase 7 RBAC validation: PASS"
