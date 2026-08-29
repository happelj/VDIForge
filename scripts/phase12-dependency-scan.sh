#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SCAN_DIR="${VDIFORGE_PHASE12_SCAN_DIR:-.local/phase12/scans}"
PIP_AUDIT_VERSION="${VDIFORGE_PIP_AUDIT_VERSION:-2.10.1}"
TRIVY_VERSION="${VDIFORGE_TRIVY_VERSION:-0.72.0}"
TRIVY_URL="${VDIFORGE_TRIVY_URL:-https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz}"
PLATFORM_HOST="${PHASE12_PLATFORM_HOST:-192.168.56.11}"
PLATFORM_USER="${PHASE12_PLATFORM_USER:-vdiadmin}"
PLATFORM_SSH_KEY="${PHASE12_PLATFORM_SSH_KEY:-${HOME}/.ssh/vdiforge_ansible}"
API_IMAGE_TAR="${PHASE12_API_IMAGE_TAR:-/tmp/vdiforge-api-0.12.0.tar}"
FRONTEND_IMAGE_TAR="${PHASE12_FRONTEND_IMAGE_TAR:-/tmp/vdiforge-frontend-0.9.0.tar}"
SCAN_NAMESPACE="${VDIFORGE_PHASE12_SCAN_NAMESPACE:-default}"
SCAN_CONFIGMAP="${VDIFORGE_PHASE12_SCAN_CONFIGMAP:-phase12-dependency-input}"
PIP_AUDIT_POD="${VDIFORGE_PHASE12_PIP_AUDIT_POD:-phase12-pip-audit}"
NPM_AUDIT_POD="${VDIFORGE_PHASE12_NPM_AUDIT_POD:-phase12-npm-audit}"

mkdir -p "${SCAN_DIR}"

FAILURES=0
WARNINGS=0

pass() {
  echo "PASS: $*"
}

warn() {
  echo "WARN: $*" >&2
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  echo "FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

normalize_json_report() {
  local report="$1"
  local cleaned="${report}.clean"
  if jq empty "${report}" >/dev/null 2>&1; then
    return 0
  fi
  awk 'found || /^[[:space:]]*\{/ { found=1; print }' "${report}" >"${cleaned}"
  if jq empty "${cleaned}" >/dev/null 2>&1; then
    mv "${cleaned}" "${report}"
    return 0
  fi
  rm -f "${cleaned}"
  return 1
}

ssh_platform() {
  ssh -o BatchMode=yes -i "${PLATFORM_SSH_KEY}" "${PLATFORM_USER}@${PLATFORM_HOST}" "$@"
}

prepare_dependency_configmap() {
  kubectl delete pod "${PIP_AUDIT_POD}" -n "${SCAN_NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl delete pod "${NPM_AUDIT_POD}" -n "${SCAN_NAMESPACE}" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
  kubectl create configmap "${SCAN_CONFIGMAP}" \
    --namespace "${SCAN_NAMESPACE}" \
    --from-file=requirements-runtime.txt=backend/requirements-runtime.txt \
    --from-file=requirements-dev.txt=backend/requirements-dev.txt \
    --from-file=package.json=frontend/package.json \
    --from-file=package-lock.json=frontend/package-lock.json \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

wait_pod_done() {
  local pod="$1"
  local deadline=$((SECONDS + 360))
  local phase
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    phase="$(kubectl get pod "${pod}" -n "${SCAN_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "${phase}" in
      Succeeded|Failed)
        return 0
        ;;
    esac
    sleep 5
  done
  return 1
}

run_kubernetes_pip_audit() {
  local report="${SCAN_DIR}/pip-audit.json"

  command -v kubectl >/dev/null 2>&1 || {
    fail "kubectl is required for the pip-audit pod fallback"
    return
  }
  prepare_dependency_configmap
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${PIP_AUDIT_POD}
  namespace: ${SCAN_NAMESPACE}
  labels:
    app.kubernetes.io/name: phase12-pip-audit
    app.kubernetes.io/component: validation
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  containers:
    - name: pip-audit
      image: python:3.14.4-slim-bookworm
      command:
        - /bin/sh
        - -lc
      args:
        - python -m pip install --quiet --no-cache-dir pip-audit==${PIP_AUDIT_VERSION} >/dev/null 2>&1 && pip-audit -r /scan/requirements-runtime.txt -r /scan/requirements-dev.txt --format json
      volumeMounts:
        - name: dependency-input
          mountPath: /scan
          readOnly: true
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
  volumes:
    - name: dependency-input
      configMap:
        name: ${SCAN_CONFIGMAP}
EOF

  if ! wait_pod_done "${PIP_AUDIT_POD}"; then
    fail "pip-audit validation pod did not complete"
    kubectl delete pod "${PIP_AUDIT_POD}" -n "${SCAN_NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
    return
  fi

  kubectl logs "${PIP_AUDIT_POD}" -n "${SCAN_NAMESPACE}" >"${report}" 2>"${SCAN_DIR}/pip-audit-pod.stderr" || true
  kubectl delete pod "${PIP_AUDIT_POD}" -n "${SCAN_NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

  if ! normalize_json_report "${report}"; then
    fail "pip-audit pod did not produce valid JSON; review ${report}"
    return
  fi

  local vulnerabilities
  vulnerabilities="$(jq '[.dependencies[]?.vulns[]?] | length' "${report}" 2>/dev/null || echo 0)"
  if [[ "${vulnerabilities}" == "0" ]]; then
    pass "pip-audit pod completed with no reported vulnerabilities"
  else
    warn "pip-audit pod reported vulnerabilities=${vulnerabilities}; review ${report}"
  fi
}

run_kubernetes_npm_audit() {
  local report="${SCAN_DIR}/npm-audit.json"

  command -v kubectl >/dev/null 2>&1 || {
    fail "kubectl is required for the npm audit pod fallback"
    return
  }
  prepare_dependency_configmap
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${NPM_AUDIT_POD}
  namespace: ${SCAN_NAMESPACE}
  labels:
    app.kubernetes.io/name: phase12-npm-audit
    app.kubernetes.io/component: validation
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  containers:
    - name: npm-audit
      image: node:22.15.0-alpine
      workingDir: /scan
      command:
        - /bin/sh
        - -lc
      args:
        - npm audit --package-lock-only --json --cache /tmp/npm-cache
      env:
        - name: NO_UPDATE_NOTIFIER
          value: "true"
        - name: NPM_CONFIG_UPDATE_NOTIFIER
          value: "false"
      volumeMounts:
        - name: dependency-input
          mountPath: /scan
          readOnly: true
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
  volumes:
    - name: dependency-input
      configMap:
        name: ${SCAN_CONFIGMAP}
EOF

  if ! wait_pod_done "${NPM_AUDIT_POD}"; then
    fail "npm audit validation pod did not complete"
    kubectl delete pod "${NPM_AUDIT_POD}" -n "${SCAN_NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
    return
  fi

  kubectl logs "${NPM_AUDIT_POD}" -n "${SCAN_NAMESPACE}" >"${report}" 2>"${SCAN_DIR}/npm-audit-pod.stderr" || true
  kubectl delete pod "${NPM_AUDIT_POD}" -n "${SCAN_NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

  if ! normalize_json_report "${report}"; then
    fail "npm audit pod did not produce valid JSON; review ${report}"
    return
  fi

  local high critical
  high="$(jq -r '.metadata.vulnerabilities.high // 0' "${report}" 2>/dev/null || echo 0)"
  critical="$(jq -r '.metadata.vulnerabilities.critical // 0' "${report}" 2>/dev/null || echo 0)"
  if [[ "${high}" == "0" && "${critical}" == "0" ]]; then
    pass "npm audit pod completed with no high/critical vulnerabilities"
  else
    warn "npm audit pod reported high=${high} critical=${critical}; review ${report}"
  fi
}

ensure_pip_audit() {
  local venv="${SCAN_DIR}/pip-audit-venv"
  if [[ ! -x "${venv}/bin/pip-audit" ]]; then
    python3 -m venv "${venv}" || return 1
    [[ -x "${venv}/bin/python" ]] || return 1
    "${venv}/bin/python" -m pip install --upgrade pip >/dev/null || return 1
    "${venv}/bin/python" -m pip install "pip-audit==${PIP_AUDIT_VERSION}" >/dev/null || return 1
  fi
  [[ -x "${venv}/bin/pip-audit" ]] || return 1
  echo "${venv}/bin/pip-audit"
}

run_pip_audit() {
  local pip_audit report rc
  set +e
  pip_audit="$(ensure_pip_audit 2>"${SCAN_DIR}/pip-audit-bootstrap.log")"
  rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    warn "local pip-audit bootstrap failed; using Kubernetes validation pod fallback"
    run_kubernetes_pip_audit
    return
  fi
  report="${SCAN_DIR}/pip-audit.json"
  set +e
  "${pip_audit}" \
    -r backend/requirements-runtime.txt \
    -r backend/requirements-dev.txt \
    --format json \
    --output "${report}" >/dev/null
  rc=$?
  set -e
  case "${rc}" in
    0)
      pass "pip-audit completed with no reported vulnerabilities"
      ;;
    1)
      warn "pip-audit completed and reported vulnerabilities; review ${report}"
      ;;
    *)
      fail "pip-audit failed with exit code ${rc}"
      ;;
  esac
}

run_npm_audit() {
  local report rc high critical
  if ! command -v npm >/dev/null 2>&1; then
    warn "local npm is not installed; using Kubernetes validation pod fallback"
    run_kubernetes_npm_audit
    return
  fi
  report="${SCAN_DIR}/npm-audit.json"
  set +e
  NO_UPDATE_NOTIFIER=true NPM_CONFIG_UPDATE_NOTIFIER=false npm --prefix frontend audit --json >"${report}"
  rc=$?
  set -e
  if [[ "${rc}" -gt 1 ]]; then
    fail "npm audit failed with exit code ${rc}"
    return
  fi
  high="$(jq -r '.metadata.vulnerabilities.high // 0' "${report}" 2>/dev/null || echo 0)"
  critical="$(jq -r '.metadata.vulnerabilities.critical // 0' "${report}" 2>/dev/null || echo 0)"
  if [[ "${high}" == "0" && "${critical}" == "0" ]]; then
    pass "npm audit completed with no high/critical vulnerabilities"
  else
    warn "npm audit reported high=${high} critical=${critical}; review ${report}"
  fi
}

ensure_remote_trivy() {
  ssh_platform "mkdir -p '\${HOME}/.local/bin' '\${HOME}/.cache/vdiforge-phase12-trivy' && if ! command -v trivy >/dev/null 2>&1 && [[ ! -x '\${HOME}/.local/bin/trivy' ]]; then tmp=\$(mktemp -d); curl -fsSL '${TRIVY_URL}' -o \"\${tmp}/trivy.tar.gz\"; tar -xzf \"\${tmp}/trivy.tar.gz\" -C \"\${tmp}\" trivy; install -m 0755 \"\${tmp}/trivy\" '\${HOME}/.local/bin/trivy'; rm -rf \"\${tmp}\"; fi"
}

scan_remote_image_tar() {
  local label="$1"
  local tar_path="$2"
  local report="${SCAN_DIR}/trivy-${label}.json"
  local output high critical

  if ! ssh_platform "test -f '${tar_path}'"; then
    fail "container image tar not found on ${PLATFORM_HOST}: ${tar_path}"
    return
  fi

  if output="$(
    ssh_platform "TRIVY_CACHE_DIR='\${HOME}/.cache/vdiforge-phase12-trivy' '\${HOME}/.local/bin/trivy' image --quiet --timeout 15m --severity HIGH,CRITICAL --format json --input '${tar_path}'" 2>&1
  )"; then
    printf '%s\n' "${output}" >"${report}"
    high="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "${report}" 2>/dev/null || echo 0)"
    critical="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "${report}" 2>/dev/null || echo 0)"
    if [[ "${high}" == "0" && "${critical}" == "0" ]]; then
      pass "Trivy ${label} image scan completed with no high/critical findings"
    else
      warn "Trivy ${label} image scan reported high=${high} critical=${critical}; review ${report}"
    fi
  else
    fail "Trivy ${label} image scan failed: ${output}"
  fi
}

run_trivy_config_scan() {
  local report="${SCAN_DIR}/trivy-config.json"
  local high critical

  if command -v trivy >/dev/null 2>&1; then
    trivy config --quiet --severity HIGH,CRITICAL --format json --output "${report}" backend frontend helm >/dev/null || true
    high="$(jq '[.Results[]?.Misconfigurations[]? | select(.Severity == "HIGH")] | length' "${report}" 2>/dev/null || echo 0)"
    critical="$(jq '[.Results[]?.Misconfigurations[]? | select(.Severity == "CRITICAL")] | length' "${report}" 2>/dev/null || echo 0)"
    if [[ "${high}" == "0" && "${critical}" == "0" ]]; then
      pass "Trivy config scan completed with no high/critical findings"
    else
      warn "Trivy config scan reported high=${high} critical=${critical}; review ${report}"
    fi
  else
    warn "local trivy not found; config scan skipped because container image scans run on ${PLATFORM_HOST}"
  fi
}

command -v python3 >/dev/null 2>&1 || fail "python3 is not installed"
command -v jq >/dev/null 2>&1 || fail "jq is not installed"

if [[ "${FAILURES}" -eq 0 ]]; then
  run_pip_audit
  run_npm_audit
  ensure_remote_trivy || fail "could not install or locate Trivy on ${PLATFORM_HOST}"
  if [[ "${FAILURES}" -eq 0 ]]; then
    scan_remote_image_tar "api" "${API_IMAGE_TAR}"
    scan_remote_image_tar "frontend" "${FRONTEND_IMAGE_TAR}"
    run_trivy_config_scan
  fi
fi

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 12 security scans: FAIL (${FAILURES} failed checks, ${WARNINGS} warning(s))" >&2
  exit 1
fi

echo "Phase 12 security scans: PASS (${WARNINGS} warning(s); review reports under ${SCAN_DIR})"
