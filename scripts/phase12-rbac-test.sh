#!/usr/bin/env bash
set -euo pipefail

SYSTEM_NS="${VDIFORGE_SYSTEM_NAMESPACE:-vdiforge-system}"
DESKTOP_NS="${VDIFORGE_DESKTOP_NAMESPACE:-vdiforge-desktops}"
IDENTITY_NS="${VDIFORGE_IDENTITY_NAMESPACE:-keycloak}"
MONITORING_NS="${VDIFORGE_MONITORING_NAMESPACE:-monitoring}"
REMOTE_NS="${VDIFORGE_REMOTE_NAMESPACE:-guacamole}"

API_SA="system:serviceaccount:${SYSTEM_NS}:vdiforge-api"
FRONTEND_SA="system:serviceaccount:${SYSTEM_NS}:vdiforge-frontend"
PROVISIONER_SA="system:serviceaccount:${SYSTEM_NS}:vdiforge-provisioner"

FAILURES=0

expect_yes() {
  local description="$1"
  shift
  local answer rc
  set +e
  answer="$(kubectl auth can-i "$@" --as="${PROVISIONER_SA}")"
  rc=$?
  set -e
  if [[ "${answer}" == "yes" && "${rc}" -eq 0 ]]; then
    echo "PASS: provisioner allowed: ${description}"
  else
    echo "FAIL: provisioner should be allowed: ${description}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

expect_no_as() {
  local subject="$1"
  local description="$2"
  shift 2
  local answer rc
  set +e
  answer="$(kubectl auth can-i "$@" --as="${subject}")"
  rc=$?
  set -e
  if [[ "${answer}" == "no" ]]; then
    echo "PASS: denied: ${description}"
  else
    echo "FAIL: expected denial for ${description}, got ${answer:-<empty>} (rc=${rc})" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

expect_yes "create KubeVirt VMs in ${DESKTOP_NS}" create virtualmachines.kubevirt.io -n "${DESKTOP_NS}"
expect_yes "patch KubeVirt VMs in ${DESKTOP_NS}" patch virtualmachines.kubevirt.io -n "${DESKTOP_NS}"
expect_yes "create CDI DataVolumes in ${DESKTOP_NS}" create datavolumes.cdi.kubevirt.io -n "${DESKTOP_NS}"
expect_yes "create desktop Services in ${DESKTOP_NS}" create services -n "${DESKTOP_NS}"
expect_yes "create per-desktop credential Secrets in ${DESKTOP_NS}" create secrets -n "${DESKTOP_NS}"
expect_yes "delete per-desktop credential Secrets in ${DESKTOP_NS}" delete secrets -n "${DESKTOP_NS}"

expect_no_as "${FRONTEND_SA}" "frontend cannot get Secrets in ${DESKTOP_NS}" get secrets -n "${DESKTOP_NS}"
expect_no_as "${FRONTEND_SA}" "frontend cannot list Secrets in ${SYSTEM_NS}" list secrets -n "${SYSTEM_NS}"
expect_no_as "${FRONTEND_SA}" "frontend cannot create pods" create pods -n "${SYSTEM_NS}"

expect_no_as "${API_SA}" "API cannot list desktop Secrets" list secrets -n "${DESKTOP_NS}"
expect_no_as "${API_SA}" "API cannot delete desktop Secrets" delete secrets -n "${DESKTOP_NS}"
expect_no_as "${API_SA}" "API cannot create pods" create pods -n "${SYSTEM_NS}"
expect_no_as "${API_SA}" "API cannot modify nodes" patch nodes
expect_no_as "${API_SA}" "API cannot create ClusterRoleBindings" create clusterrolebindings.rbac.authorization.k8s.io

expect_no_as "${PROVISIONER_SA}" "provisioner cannot list desktop Secrets" list secrets -n "${DESKTOP_NS}"
expect_no_as "${PROVISIONER_SA}" "provisioner cannot read identity Secrets" get secrets -n "${IDENTITY_NS}"
expect_no_as "${PROVISIONER_SA}" "provisioner cannot read monitoring Secrets" get secrets -n "${MONITORING_NS}"
expect_no_as "${PROVISIONER_SA}" "provisioner cannot read remote-access Secrets" get secrets -n "${REMOTE_NS}"
expect_no_as "${PROVISIONER_SA}" "provisioner cannot modify nodes" patch nodes
expect_no_as "${PROVISIONER_SA}" "provisioner cannot create namespaces" create namespaces
expect_no_as "${PROVISIONER_SA}" "provisioner cannot create ClusterRoleBindings" create clusterrolebindings.rbac.authorization.k8s.io

if kubectl get clusterrolebinding -o yaml | grep -A20 -E 'name: .*vdiforge' | grep -q 'cluster-admin'; then
  echo "FAIL: VDIForge ClusterRoleBinding grants cluster-admin" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: no VDIForge ClusterRoleBinding grants cluster-admin"
fi

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 12 RBAC validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

echo "Phase 12 RBAC validation: PASS"
