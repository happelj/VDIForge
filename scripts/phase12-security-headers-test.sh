#!/usr/bin/env bash
set -euo pipefail

INGRESS_IP="${VDIFORGE_INGRESS_IP:-192.168.56.11}"
CA_CERT="${VDIFORGE_PHASE5_CA_CERT:-.local/phase5/tls/vdiforge-local-ca.crt}"
PHASE5_FALLBACK_DIR="${VDIFORGE_PHASE5_FALLBACK_DIR:-${HOME}/vdiforge-phase5-validation/.local/phase5}"

if [[ ! -f "${CA_CERT}" && -f "${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt" ]]; then
  CA_CERT="${PHASE5_FALLBACK_DIR}/tls/vdiforge-local-ca.crt"
fi

FAILURES=0

check_header() {
  local host="$1"
  local path="$2"
  local header_pattern="$3"
  local description="$4"
  local headers

  headers="$(curl -sS --cacert "${CA_CERT}" --resolve "${host}:443:${INGRESS_IP}" -D - -o /dev/null "https://${host}${path}")"
  if grep -Eiq "${header_pattern}" <<<"${headers}"; then
    echo "PASS: ${description}"
  else
    echo "FAIL: ${description}" >&2
    echo "${headers}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

check_no_header_value() {
  local host="$1"
  local path="$2"
  local header_pattern="$3"
  local description="$4"
  local headers

  headers="$(curl -sS --cacert "${CA_CERT}" --resolve "${host}:443:${INGRESS_IP}" -D - -o /dev/null "https://${host}${path}")"
  if grep -Eiq "${header_pattern}" <<<"${headers}"; then
    echo "FAIL: ${description}" >&2
    echo "${headers}" >&2
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: ${description}"
  fi
}

[[ -f "${CA_CERT}" ]] || {
  echo "FAIL: CA certificate not found: ${CA_CERT}" >&2
  exit 1
}

check_header "vdiforge.local" "/" '^x-content-type-options:\s*nosniff' "portal sends X-Content-Type-Options"
check_header "vdiforge.local" "/" '^strict-transport-security:\s*max-age=' "portal sends HSTS"
check_header "vdiforge.local" "/" '^referrer-policy:\s*strict-origin-when-cross-origin' "portal sends Referrer-Policy"
check_header "vdiforge.local" "/" '^content-security-policy:\s*' "portal sends CSP"

check_header "api.vdiforge.local" "/api/v1/health" '^x-content-type-options:\s*nosniff' "API sends X-Content-Type-Options"
check_header "api.vdiforge.local" "/api/v1/health" '^content-security-policy:\s*default-src '\''none'\''' "API sends strict CSP"
check_header "auth.vdiforge.local" "/realms/vdiforge/.well-known/openid-configuration" '^x-content-type-options:\s*nosniff' "Keycloak sends X-Content-Type-Options"
check_header "remote.vdiforge.local" "/" '^x-content-type-options:\s*nosniff' "Guacamole sends X-Content-Type-Options"
check_header "grafana.vdiforge.local" "/login" '^x-content-type-options:\s*nosniff' "Grafana sends X-Content-Type-Options"

cors_headers="$(
  curl -sS --cacert "${CA_CERT}" \
    --resolve "api.vdiforge.local:443:${INGRESS_IP}" \
    -X OPTIONS \
    -H "Origin: https://evil.example" \
    -H "Access-Control-Request-Method: GET" \
    -D - -o /dev/null \
    "https://api.vdiforge.local/api/v1/images"
)"
if grep -Eiq '^access-control-allow-origin:\s*https://evil\.example' <<<"${cors_headers}"; then
  echo "FAIL: unauthorized CORS origin was allowed" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: unauthorized CORS origin denied"
fi

allowed_cors_headers="$(
  curl -sS --cacert "${CA_CERT}" \
    --resolve "api.vdiforge.local:443:${INGRESS_IP}" \
    -X OPTIONS \
    -H "Origin: https://vdiforge.local" \
    -H "Access-Control-Request-Method: GET" \
    -D - -o /dev/null \
    "https://api.vdiforge.local/api/v1/images"
)"
if grep -Eiq '^access-control-allow-origin:\s*https://vdiforge\.local' <<<"${allowed_cors_headers}"; then
  echo "PASS: approved portal CORS origin allowed"
else
  echo "FAIL: approved portal CORS origin was not allowed" >&2
  FAILURES=$((FAILURES + 1))
fi

check_no_header_value "api.vdiforge.local" "/api/v1/health" '^access-control-allow-origin:\s*\*' "API does not return wildcard CORS"

if [[ "${FAILURES}" -ne 0 ]]; then
  echo "Phase 12 HTTP security validation: FAIL (${FAILURES} failed checks)" >&2
  exit 1
fi

echo "Phase 12 HTTP security validation: PASS"
