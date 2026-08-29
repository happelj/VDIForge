#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import importlib.util
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from uuid import uuid4

PHASE8_HELPER = Path(__file__).with_name("phase8-remote-desktop-e2e-test.py")
API_HOST = "api.vdiforge.local"


def load_phase8_helpers():
    spec = importlib.util.spec_from_file_location("phase8_remote_desktop_helpers", PHASE8_HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load helper script: {PHASE8_HELPER}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def token_for_username(phase8, ca_file: str, env: dict[str, str], username: str) -> str:
    password_keys = {
        "demo-user": "DEMO_USER_PASSWORD",
        "demo-developer": "DEMO_DEVELOPER_PASSWORD",
        "demo-devops": "DEMO_DEVOPS_PASSWORD",
        "demo-admin": "DEMO_ADMIN_PASSWORD",
    }
    verifier = secrets.token_urlsafe(48)
    opener = phase8.build_opener(ca_file)
    code = phase8.get_authorization_code(opener, username, env[password_keys[username]], verifier)
    return phase8.exchange_code(opener, code, verifier)


def expect_status(label: str, actual: int, expected: set[int]) -> None:
    if actual not in expected:
        raise AssertionError(f"{label}: expected {sorted(expected)}, got HTTP {actual}")
    print(f"PASS: {label}")


def tamper_jwt_payload(token: str) -> str:
    header, payload, signature = token.split(".", 2)
    padded_payload = payload + ("=" * (-len(payload) % 4))
    decoded_payload = base64.urlsafe_b64decode(padded_payload.encode("ascii"))
    claims = json.loads(decoded_payload.decode("utf-8"))
    claims["sub"] = f"tampered-{claims.get('sub', 'subject')}"
    tampered_payload = base64.urlsafe_b64encode(
        json.dumps(claims, separators=(",", ":"), sort_keys=True).encode("utf-8")
    ).decode("ascii").rstrip("=")
    return ".".join([header, tampered_payload, signature])


def request_raw(
    phase8,
    opener,
    method: str,
    path: str,
    token: str | None = None,
    data: dict | None = None,
    headers: dict[str, str] | None = None,
) -> tuple[int, str, dict[str, str]]:
    body = None if data is None else json.dumps(data).encode("utf-8")
    request_headers = {"Content-Type": "application/json"}
    if token:
        request_headers["Authorization"] = f"Bearer {token}"
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(
        f"https://{API_HOST}{path}",
        data=body,
        headers=request_headers,
        method=method,
    )
    try:
        with opener.open(request, timeout=30) as response:
            return response.status, response.read().decode("utf-8"), dict(response.headers)
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", errors="replace"), dict(error.headers)


def assert_no_sensitive_text(label: str, text: str) -> None:
    lowered = text.lower()
    forbidden = [
        "access_token",
        "refresh_token",
        "authorization:",
        "bearer ",
        "password",
        "xrdp_password",
        "json_secret_key",
        "keycloak_admin_password",
        "keycloak_db_password",
        "vdiforge_app_db_password",
    ]
    found = [item for item in forbidden if item in lowered]
    if found:
        raise AssertionError(f"{label} contained sensitive terms: {', '.join(found)}")
    print(f"PASS: {label} contains no obvious secrets")


def cleanup_previous_phase12_desktops(phase8, opener, tokens) -> None:
    status, payload = phase8.api_request(opener, "GET", "/api/v1/desktops", tokens["demo-devops"])
    if status != 200:
        raise RuntimeError(f"could not list existing demo-devops desktops: {status} {payload}")
    stale = [
        desktop
        for desktop in payload.get("desktops", [])
        if desktop.get("display_name") in {"Phase 12 Security Test", "Phase 12 VDI Workflow Test"}
        and desktop.get("observed_state") != "TERMINATED"
    ]
    for desktop in stale:
        status, delete_payload = phase8.api_request(
            opener, "DELETE", f"/api/v1/desktops/{desktop['id']}", tokens["demo-devops"]
        )
        if status not in {200, 202}:
            raise RuntimeError(f"could not delete stale Phase 12 desktop {desktop['id']}: {status} {delete_payload}")
        phase8.wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"TERMINATED"}, 900)
    if stale:
        print(f"PASS: cleaned up {len(stale)} previous Phase 12 test desktop(s)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Phase 12 live API security validation.")
    parser.add_argument("--env", default=".local/phase5/phase5.env")
    parser.add_argument("--ca", default=".local/phase5/tls/vdiforge-local-ca.crt")
    parser.add_argument("--resolve-ip", default=os.environ.get("VDIFORGE_INGRESS_IP", "192.168.56.11"))
    parser.add_argument("--audit-export", default=".local/phase12/audit-export.jsonl")
    args = parser.parse_args()

    phase8 = load_phase8_helpers()
    phase8.install_dns_override({phase8.AUTH_HOST, phase8.API_HOST, phase8.REMOTE_HOST}, args.resolve_ip)
    env = phase8.load_env(args.env)
    opener = phase8.build_opener(args.ca)
    phase8.wait_api_health(opener)

    tokens = phase8.TokenCache(args.ca, env)
    tokens.prefetch_all()
    developer_token = token_for_username(phase8, args.ca, env, "demo-developer")
    print("PASS: OIDC Authorization Code + PKCE tokens acquired")

    cleanup_previous_phase12_desktops(phase8, opener, tokens)

    status, _body, _headers = request_raw(phase8, opener, "GET", "/api/v1/images")
    expect_status("unauthenticated API call denied", status, {401})

    tampered = tamper_jwt_payload(tokens["demo-devops"])
    status, _body, _headers = request_raw(phase8, opener, "GET", "/api/v1/images", tampered)
    expect_status("tampered bearer token denied", status, {401})

    status, _body, _headers = request_raw(
        phase8,
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-devops"],
        {"image_id": "../ubuntu-devops", "resource_profile": "small"},
        {"Idempotency-Key": f"phase12-bad-image-{int(time.time())}"},
    )
    expect_status("unsafe image ID rejected", status, {422})

    status, _body, _headers = request_raw(
        phase8,
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-devops"],
        {"image_id": "ubuntu-devops", "resource_profile": "small", "display_name": "bad\nname"},
        {"Idempotency-Key": f"phase12-bad-display-{int(time.time())}"},
    )
    expect_status("unsafe display name rejected", status, {422})

    status, _body, _headers = request_raw(
        phase8,
        opener,
        "POST",
        "/api/v1/desktops/not-a-valid-uuid/connect",
        tokens["demo-devops"],
    )
    expect_status("malformed desktop ID rejected", status, {422})

    status, _body, _headers = request_raw(
        phase8,
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-user"],
        {"image_id": "ubuntu-devops", "resource_profile": "small", "display_name": "Unauthorized"},
        {"Idempotency-Key": f"phase12-user-denied-{int(time.time())}"},
    )
    expect_status("unauthorized image launch denied", status, {403})

    key = f"phase12-security-{int(time.time())}-{secrets.token_hex(4)}"
    status, desktop = phase8.api_request(
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-devops"],
        {"image_id": "ubuntu-devops", "resource_profile": "small", "display_name": "Phase 12 Security Test"},
        {"Idempotency-Key": key},
    )
    if status != 202:
        raise AssertionError(f"desktop launch for security test failed: {status} {desktop}")
    print("PASS: security-test desktop launch accepted")

    status, _payload = phase8.api_request(opener, "GET", f"/api/v1/desktops/{desktop['id']}", tokens["demo-user"])
    expect_status("cross-user desktop read denied", status, {403})

    status, _payload = phase8.api_request(
        opener, "POST", f"/api/v1/desktops/{desktop['id']}/connect", tokens["demo-user"]
    )
    expect_status("cross-user connect denied", status, {403})

    status, _payload = phase8.api_request(opener, "GET", f"/api/v1/desktops/{uuid4()}", tokens["demo-user"])
    expect_status("guessed desktop ID denied", status, {404})

    for username, token in [
        ("demo-user", tokens["demo-user"]),
        ("demo-developer", developer_token),
        ("demo-devops", tokens["demo-devops"]),
    ]:
        status, _payload = phase8.api_request(opener, "GET", "/api/v1/audit-events", token)
        expect_status(f"{username} denied audit admin endpoint", status, {403})

    status, audit = phase8.api_request(opener, "GET", "/api/v1/audit-events?limit=20", tokens["demo-admin"])
    if status != 200:
        raise AssertionError(f"demo-admin audit endpoint failed: {status} {audit}")
    print("PASS: demo-admin can read audit events")
    assert_no_sensitive_text("audit JSON response", json.dumps(audit))
    if not any(item.get("event_hash") for item in audit.get("audit_events", [])):
        raise AssertionError("audit endpoint did not return event hashes")
    print("PASS: audit endpoint returns hash-chain metadata")

    status, export_body, _headers = request_raw(
        phase8, opener, "GET", "/api/v1/audit-events/export?limit=50", tokens["demo-admin"]
    )
    if status != 200:
        raise AssertionError(f"demo-admin audit export failed: HTTP {status} {export_body[:200]}")
    assert_no_sensitive_text("audit export", export_body)
    lines = [json.loads(line) for line in export_body.splitlines() if line.strip()]
    if not lines or not lines[0].get("event_hash"):
        raise AssertionError("audit export did not include hash-chain metadata")
    export_path = Path(args.audit_export)
    export_path.parent.mkdir(parents=True, exist_ok=True)
    export_path.write_text(export_body, encoding="utf-8")
    export_path.chmod(0o600)
    print(f"PASS: audit export written to {export_path}")

    status, payload = phase8.api_request(opener, "DELETE", f"/api/v1/desktops/{desktop['id']}", tokens["demo-devops"])
    if status not in {200, 202}:
        raise AssertionError(f"desktop cleanup failed: {status} {payload}")
    phase8.wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"TERMINATED"}, 900)
    print("PASS: security-test desktop cleaned up")

    print("Phase 12 live API security validation: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Phase 12 live API security validation: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
