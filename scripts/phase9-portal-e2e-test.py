#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import html
import json
import os
import re
import secrets
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

AUTH_HOST = "auth.vdiforge.local"
API_HOST = "api.vdiforge.local"
PORTAL_HOST = "vdiforge.local"
REMOTE_HOST = "remote.vdiforge.local"
REALM = "vdiforge"
CLIENT_ID = "vdiforge-frontend"
REDIRECT_URI = "https://vdiforge.local/oidc/callback"
ISSUER = f"https://{AUTH_HOST}/realms/{REALM}"
PASSWORD_ENV = {
    "demo-user": "DEMO_USER_PASSWORD",
    "demo-developer": "DEMO_DEVELOPER_PASSWORD",
    "demo-devops": "DEMO_DEVOPS_PASSWORD",
    "demo-admin": "DEMO_ADMIN_PASSWORD",
}


class RedirectSeen(Exception):
    def __init__(self, location: str) -> None:
        super().__init__(location)
        self.location = location


class CaptureRedirect(urllib.request.HTTPRedirectHandler):
    def http_error_302(self, req, fp, code, msg, headers):
        raise RedirectSeen(headers["Location"])

    http_error_301 = http_error_302
    http_error_303 = http_error_302
    http_error_307 = http_error_302
    http_error_308 = http_error_302


def b64url_no_padding(value: bytes) -> str:
    import hashlib

    return base64.urlsafe_b64encode(hashlib.sha256(value).digest()).decode("ascii").rstrip("=")


def load_env(path: str) -> dict[str, str]:
    values = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key] = value
    for key in PASSWORD_ENV.values():
        if key not in values:
            raise RuntimeError(f"{key} is missing from {path}")
    return values


def install_dns_override(hosts: set[str], ip: str) -> None:
    original_getaddrinfo = socket.getaddrinfo

    def getaddrinfo(name, *args, **kwargs):
        if name in hosts:
            return original_getaddrinfo(ip, *args, **kwargs)
        return original_getaddrinfo(name, *args, **kwargs)

    socket.getaddrinfo = getaddrinfo


def build_opener(ca_file: str) -> urllib.request.OpenerDirector:
    context = ssl.create_default_context(cafile=ca_file)
    cookie_processor = urllib.request.HTTPCookieProcessor()
    https_handler = urllib.request.HTTPSHandler(context=context)
    opener = urllib.request.build_opener(cookie_processor, CaptureRedirect, https_handler)
    opener.addheaders = [("User-Agent", "vdiforge-phase9-portal-e2e/1.0")]
    return opener


def read_text(opener: urllib.request.OpenerDirector, url: str) -> str:
    with opener.open(url, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace")


def parse_login_action(body: str) -> str:
    match = re.search(r'<form[^>]+(?:id="kc-form-login"|action="[^"]+")[^>]+action="([^"]+)"', body)
    if not match:
        match = re.search(r'<form[^>]+action="([^"]+)"', body)
    if not match:
        raise RuntimeError("Could not locate Keycloak login form action.")
    return html.unescape(match.group(1))


def auth_url(verifier: str) -> str:
    query = urllib.parse.urlencode(
        {
            "client_id": CLIENT_ID,
            "redirect_uri": REDIRECT_URI,
            "response_type": "code",
            "scope": "openid profile email",
            "state": secrets.token_urlsafe(16),
            "code_challenge": b64url_no_padding(verifier.encode("ascii")),
            "code_challenge_method": "S256",
        }
    )
    return f"{ISSUER}/protocol/openid-connect/auth?{query}"


def get_authorization_code(opener: urllib.request.OpenerDirector, username: str, password: str, verifier: str) -> str:
    login_page = read_text(opener, auth_url(verifier))
    payload = urllib.parse.urlencode(
        {"username": username, "password": password, "credentialId": "", "login": "Sign In"}
    ).encode("utf-8")
    request = urllib.request.Request(
        parse_login_action(login_page),
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with opener.open(request, timeout=30) as response:
            body = response.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"Login for {username} did not redirect; response length {len(body)}.")
    except RedirectSeen as redirect:
        parsed = urllib.parse.urlparse(redirect.location)
        params = urllib.parse.parse_qs(parsed.query)
        if "code" not in params:
            raise RuntimeError(f"Login redirect for {username} did not contain an authorization code.")
        return params["code"][0]


def exchange_code(opener: urllib.request.OpenerDirector, code: str, verifier: str) -> str:
    payload = urllib.parse.urlencode(
        {
            "grant_type": "authorization_code",
            "client_id": CLIENT_ID,
            "code": code,
            "redirect_uri": REDIRECT_URI,
            "code_verifier": verifier,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{ISSUER}/protocol/openid-connect/token",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with opener.open(request, timeout=30) as response:
        token_response = json.loads(response.read().decode("utf-8"))
    token = token_response.get("access_token")
    if not token:
        raise RuntimeError("No access token returned.")
    return token


def token_for(ca_file: str, env: dict[str, str], username: str) -> str:
    verifier = secrets.token_urlsafe(48)
    opener = build_opener(ca_file)
    code = get_authorization_code(opener, username, env[PASSWORD_ENV[username]], verifier)
    return exchange_code(opener, code, verifier)


def token_valid_for(token: str, seconds: int) -> bool:
    try:
        payload_segment = token.split(".")[1]
        padded = payload_segment + "=" * (-len(payload_segment) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded.encode("ascii")))
        return int(payload.get("exp", 0)) > int(time.time()) + seconds
    except (IndexError, ValueError, TypeError, json.JSONDecodeError):
        return False


class TokenCache:
    def __init__(self, ca_file: str, env: dict[str, str]) -> None:
        self.ca_file = ca_file
        self.env = env
        self._tokens: dict[str, str] = {}

    def __getitem__(self, username: str) -> str:
        token = self._tokens.get(username)
        if token and token_valid_for(token, 60):
            return token
        return self.refresh(username)

    def refresh(self, username: str) -> str:
        token = token_for(self.ca_file, self.env, username)
        self._tokens[username] = token
        return token

    def prefetch_all(self) -> None:
        for username in PASSWORD_ENV:
            self.refresh(username)


def request_json(
    opener: urllib.request.OpenerDirector,
    method: str,
    url: str,
    token: str | None = None,
    data: dict | None = None,
    headers: dict[str, str] | None = None,
) -> tuple[int, dict]:
    body = None if data is None else json.dumps(data).encode("utf-8")
    request_headers = {"Content-Type": "application/json"}
    if token:
        request_headers["Authorization"] = f"Bearer {token}"
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(url, data=body, headers=request_headers, method=method)
    try:
        with opener.open(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            return error.code, json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return error.code, {"raw": raw[:500]}


def api_request(
    opener: urllib.request.OpenerDirector,
    method: str,
    path: str,
    token: str | None = None,
    data: dict | None = None,
    headers: dict[str, str] | None = None,
) -> tuple[int, dict]:
    return request_json(opener, method, f"https://{API_HOST}{path}", token, data, headers)


def wait_desktop_state(
    opener: urllib.request.OpenerDirector,
    tokens: TokenCache,
    username: str,
    desktop_id: str,
    expected: set[str],
    timeout_seconds: int,
) -> dict:
    deadline = time.monotonic() + timeout_seconds
    last_payload = {}
    last_reported_state = ""
    while time.monotonic() < deadline:
        status, payload = api_request(opener, "GET", f"/api/v1/desktops/{desktop_id}", tokens[username])
        if status == 401:
            status, payload = api_request(
                opener,
                "GET",
                f"/api/v1/desktops/{desktop_id}",
                tokens.refresh(username),
            )
        if status != 200:
            raise RuntimeError(f"desktop status returned HTTP {status}: {payload}")
        last_payload = payload
        observed_state = str(payload["observed_state"])
        if observed_state != last_reported_state:
            print(f"WAIT: desktop {desktop_id} observed_state={observed_state}")
            last_reported_state = observed_state
        if observed_state in expected:
            return payload
        if observed_state == "FAILED":
            raise RuntimeError(f"desktop failed: {payload.get('failure_code')} {payload.get('failure_message')}")
        time.sleep(10)
    raise RuntimeError(f"timed out waiting for {expected}; last payload: {last_payload}")


def cleanup_previous_test_desktops(opener: urllib.request.OpenerDirector, tokens: TokenCache) -> None:
    status, payload = api_request(opener, "GET", "/api/v1/desktops", tokens["demo-devops"])
    if status != 200:
        raise RuntimeError(f"could not list existing demo-devops desktops: {status} {payload}")
    stale = [
        desktop
        for desktop in payload.get("desktops", [])
        if desktop.get("display_name") == "Phase 9 Portal Desktop Test"
        and desktop.get("observed_state") != "TERMINATED"
    ]
    for desktop in stale:
        status, delete_payload = api_request(opener, "DELETE", f"/api/v1/desktops/{desktop['id']}", tokens["demo-devops"])
        if status not in {200, 202}:
            raise RuntimeError(f"could not delete stale test desktop {desktop['id']}: {status} {delete_payload}")
        wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"TERMINATED"}, 900)
    if stale:
        print(f"PASS: cleaned up {len(stale)} previous Phase 9 test desktop(s)")


def write_browser_artifact(path: str, connection: dict, desktop: dict) -> None:
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(
            {
                "desktop_id": desktop["id"],
                "image_id": desktop["image_id"],
                "image_version": desktop["image_version"],
                "vm": desktop["kubevirt_vm_name"],
                "service": desktop["kubevirt_service_name"],
                "connection_url": connection["connection_url"],
                "expires_at": connection["expires_at"],
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    output.chmod(0o600)
    print(f"Browser connection artifact: {output}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Phase 9 portal/API/remote-desktop validation.")
    parser.add_argument("--env", default=".local/phase5/phase5.env")
    parser.add_argument("--ca", default=".local/phase5/tls/vdiforge-local-ca.crt")
    parser.add_argument("--resolve-ip", default=os.environ.get("VDIFORGE_INGRESS_IP", "192.168.56.11"))
    parser.add_argument("--keep-desktop", action="store_true", help="Leave the test desktop running for manual browser proof.")
    parser.add_argument("--cleanup-only", action="store_true", help="Delete previous Phase 9 test desktops and exit.")
    parser.add_argument("--browser-artifact", default=".local/phase9/browser-connection.json")
    args = parser.parse_args()

    install_dns_override({AUTH_HOST, API_HOST, PORTAL_HOST, REMOTE_HOST}, args.resolve_ip)
    env = load_env(args.env)
    opener = build_opener(args.ca)

    portal = read_text(opener, f"https://{PORTAL_HOST}/")
    if "VDIForge" not in portal:
        raise AssertionError("portal index does not contain the VDIForge app shell")
    print("PASS: portal index loads over trusted HTTPS")

    runtime_config = read_text(opener, f"https://{PORTAL_HOST}/runtime-config.js")
    for expected in [
        "https://api.vdiforge.local",
        "https://auth.vdiforge.local/realms/vdiforge",
        "vdiforge-frontend",
        "https://vdiforge.local/oidc/callback",
    ]:
        if expected not in runtime_config:
            raise AssertionError(f"runtime config missing {expected}")
    if re.search(r"password|client_secret|refresh_token|access_token", runtime_config, re.IGNORECASE):
        raise AssertionError("runtime config contains secret-like content")
    print("PASS: portal runtime config contains public endpoints only")

    status, health = api_request(opener, "GET", "/api/v1/health")
    if status != 200 or health.get("status") != "ok":
        raise AssertionError(f"API health failed: {status} {health}")
    print("PASS: API health")

    tokens = TokenCache(args.ca, env)
    tokens.prefetch_all()
    print("PASS: OIDC Authorization Code + PKCE tokens acquired")

    if args.cleanup_only:
        cleanup_previous_test_desktops(opener, tokens)
        print("Phase 9 cleanup-only validation: PASS")
        return 0

    role_images: dict[str, set[str]] = {}
    for username in PASSWORD_ENV:
        status, payload = api_request(opener, "GET", "/api/v1/images", tokens[username])
        if status != 200:
            raise AssertionError(f"image list failed for {username}: {status} {payload}")
        role_images[username] = {str(item.get("id")) for item in payload}
    if "ubuntu-devops" in role_images["demo-user"] or "ubuntu-devops" in role_images["demo-developer"]:
        raise AssertionError(f"lower-privileged users can see ubuntu-devops: {role_images}")
    if "ubuntu-devops" not in role_images["demo-devops"] or "ubuntu-devops" not in role_images["demo-admin"]:
        raise AssertionError(f"authorized roles cannot see ubuntu-devops: {role_images}")
    print("PASS: role-specific image visibility enforced through API responses")

    status, images = api_request(opener, "GET", "/api/v1/images", tokens["demo-devops"])
    if status != 200:
        raise AssertionError(f"authorized image list failed: {status} {images}")
    ubuntu_devops = next((item for item in images if item.get("id") == "ubuntu-devops"), None)
    if not ubuntu_devops or ubuntu_devops.get("default_version") != "1.2.0":
        raise AssertionError(f"ubuntu-devops:1.2.0 is not the default image: {images}")
    print("PASS: devops user sees ubuntu-devops:1.2.0")

    cleanup_previous_test_desktops(opener, tokens)

    status, denied = api_request(
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-user"],
        {"image_id": "ubuntu-devops", "resource_profile": "small", "display_name": "Phase 9 Portal Desktop Test"},
        {"Idempotency-Key": f"phase9-denied-{secrets.token_hex(4)}"},
    )
    if status != 403:
        raise AssertionError(f"unauthorized launch should be denied: {status} {denied}")
    print("PASS: unauthorized image launch denied")

    status, desktop = api_request(
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-devops"],
        {"image_id": "ubuntu-devops", "resource_profile": "small", "display_name": "Phase 9 Portal Desktop Test"},
        {"Idempotency-Key": f"phase9-launch-{int(time.time())}-{secrets.token_hex(4)}"},
    )
    if status != 202:
        raise AssertionError(f"desktop launch failed: {status} {desktop}")
    print("PASS: portal-equivalent desktop launch accepted asynchronously")

    ready = wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"READY"}, 1200)
    if ready["image_version"] != "1.2.0":
        raise AssertionError(f"expected ubuntu-devops:1.2.0, got {ready['image_version']}")
    print("PASS: default Phase 9 desktop reached READY")

    status, connection = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/connect", tokens["demo-devops"])
    if status != 200:
        raise AssertionError(f"owner connect failed: {status} {connection}")
    if not connection.get("connection_url", "").startswith(f"https://{REMOTE_HOST}/?data="):
        raise AssertionError(f"unexpected connection URL: {connection}")
    if "password" in json.dumps(connection).lower():
        raise AssertionError("connection API response exposed a password")
    print("PASS: Connect returns exact opaque Guacamole handoff URL without plaintext credentials")
    write_browser_artifact(args.browser_artifact, connection, ready)

    status, audit = api_request(opener, "GET", "/api/v1/audit-events", tokens["demo-admin"])
    if status != 200:
        raise AssertionError(f"admin audit endpoint failed: {status} {audit}")
    actions = {item["action"] for item in audit.get("audit_events", [])}
    if "DESKTOP_CONNECTION_REQUESTED" not in actions:
        raise AssertionError("connection audit event was not recorded")
    print("PASS: audit event visible to admin")

    if args.keep_desktop:
        print("Phase 9 validation paused with the desktop running for manual browser proof.")
        print(f"Open this URL in a browser: {connection['connection_url']}")
        return 0

    status, payload = api_request(opener, "DELETE", f"/api/v1/desktops/{desktop['id']}", tokens["demo-devops"])
    if status != 202:
        raise AssertionError(f"delete request failed: {status} {payload}")
    wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"TERMINATED"}, 900)
    print("PASS: desktop deleted after portal validation")

    print("Phase 9 portal E2E validation: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Phase 9 portal E2E validation: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
