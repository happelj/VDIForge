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
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

AUTH_HOST = "auth.vdiforge.local"
API_HOST = "api.vdiforge.local"
REALM = "vdiforge"
CLIENT_ID = "vdiforge-frontend"
REDIRECT_URI = "https://vdiforge.local/oidc/callback"
ISSUER = f"https://{AUTH_HOST}/realms/{REALM}"
PASSWORD_ENV = {
    "demo-user": "DEMO_USER_PASSWORD",
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
    import base64
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
    opener.addheaders = [("User-Agent", "vdiforge-phase7-api-e2e/1.0")]
    return opener


def read_response(response) -> str:
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
            "scope": "openid",
            "state": secrets.token_urlsafe(16),
            "code_challenge": b64url_no_padding(verifier.encode("ascii")),
            "code_challenge_method": "S256",
        }
    )
    return f"{ISSUER}/protocol/openid-connect/auth?{query}"


def get_authorization_code(opener: urllib.request.OpenerDirector, username: str, password: str, verifier: str) -> str:
    with opener.open(auth_url(verifier), timeout=20) as response:
        login_page = read_response(response)

    action = parse_login_action(login_page)
    payload = urllib.parse.urlencode(
        {"username": username, "password": password, "credentialId": "", "login": "Sign In"}
    ).encode("utf-8")
    request = urllib.request.Request(
        action,
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with opener.open(request, timeout=20) as response:
            body = read_response(response)
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
    with opener.open(request, timeout=20) as response:
        token_response = json.loads(response.read().decode("utf-8"))
    token = token_response.get("access_token")
    if not token:
        raise RuntimeError(f"No access token returned for {code[:8]}.")
    return token


def token_for(opener: urllib.request.OpenerDirector, env: dict[str, str], username: str) -> str:
    verifier = secrets.token_urlsafe(48)
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
        token = token_for(build_opener(self.ca_file), self.env, username)
        self._tokens[username] = token
        return token

    def prefetch_all(self) -> None:
        for username in PASSWORD_ENV:
            self.refresh(username)


def api_request(
    opener: urllib.request.OpenerDirector,
    method: str,
    path: str,
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
    request = urllib.request.Request(
        f"https://{API_HOST}{path}",
        data=body,
        headers=request_headers,
        method=method,
    )
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


def wait_api_request(
    opener: urllib.request.OpenerDirector,
    method: str,
    path: str,
    token: str | None = None,
    timeout_seconds: int = 180,
) -> tuple[int, dict]:
    deadline = time.monotonic() + timeout_seconds
    last_status = 0
    last_payload: dict = {}
    while time.monotonic() < deadline:
        try:
            last_status, last_payload = api_request(opener, method, path, token)
        except (urllib.error.URLError, TimeoutError):
            last_status, last_payload = 0, {}
        if last_status < 500:
            return last_status, last_payload
        time.sleep(5)
    return last_status, last_payload


def kubectl_json(*args: str) -> dict:
    result = subprocess.run(["kubectl", *args, "-o", "json"], check=True, text=True, stdout=subprocess.PIPE)
    return json.loads(result.stdout)


def kubectl(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["kubectl", *args], check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


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
        if payload["observed_state"] in expected:
            return payload
        if payload["observed_state"] == "FAILED":
            raise RuntimeError(f"desktop failed: {payload.get('failure_code')} {payload.get('failure_message')}")
        time.sleep(10)
    raise RuntimeError(f"timed out waiting for {expected}; last payload: {last_payload}")


def verify_kubevirt(desktop: dict) -> None:
    vmi = kubectl_json("get", "vmi", desktop["kubevirt_vm_name"], "-n", "vdiforge-desktops")
    node = vmi.get("status", {}).get("nodeName")
    if node != "vdi-worker-02":
        raise AssertionError(f"VMI scheduled on {node}, expected vdi-worker-02")

    pods = kubectl_json(
        "get",
        "pods",
        "-n",
        "vdiforge-desktops",
        "-l",
        f"vdiforge.io/desktop-id={desktop['id']}",
    )
    launcher = next(
        (pod for pod in pods.get("items", []) if pod.get("metadata", {}).get("labels", {}).get("kubevirt.io") == "virt-launcher"),
        None,
    )
    if not launcher:
        raise AssertionError("virt-launcher pod was not found")
    request = "0"
    for container in launcher.get("spec", {}).get("containers", []):
        request = container.get("resources", {}).get("requests", {}).get("devices.kubevirt.io/kvm", request)
    if request == "0":
        raise AssertionError("virt-launcher pod did not request devices.kubevirt.io/kvm")
    print(f"PASS: KubeVirt VM scheduled on vdi-worker-02 with KVM request {request}")


def resources_deleted(desktop: dict) -> bool:
    names = [
        ("vm", desktop["kubevirt_vm_name"]),
        ("datavolume", desktop["kubevirt_data_volume_name"]),
        ("pvc", desktop["kubevirt_data_volume_name"]),
        ("svc", desktop["kubevirt_service_name"]),
    ]
    return all(kubectl("get", kind, name, "-n", "vdiforge-desktops", check=False).returncode != 0 for kind, name in names)


def cleanup_previous_test_desktops(
    opener: urllib.request.OpenerDirector,
    tokens: TokenCache,
    timeout_seconds: int = 900,
) -> None:
    status, payload = api_request(opener, "GET", "/api/v1/desktops", tokens["demo-devops"])
    if status != 200:
        raise RuntimeError(f"could not list existing demo-devops desktops: {status} {payload}")

    stale = [
        desktop
        for desktop in payload.get("desktops", [])
        if desktop.get("display_name") == "Phase 7 DevOps Test" and desktop.get("observed_state") != "TERMINATED"
    ]
    for desktop in stale:
        status, delete_payload = api_request(
            opener,
            "DELETE",
            f"/api/v1/desktops/{desktop['id']}",
            tokens["demo-devops"],
        )
        if status not in {200, 202}:
            raise RuntimeError(f"could not delete stale test desktop {desktop['id']}: {status} {delete_payload}")
        wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"TERMINATED"}, timeout_seconds)

    if stale:
        print(f"PASS: cleaned up {len(stale)} previous Phase 7 test desktop(s)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Phase 7 OIDC/API/KubeVirt lifecycle validation.")
    parser.add_argument("--env", default=".local/phase5/phase5.env")
    parser.add_argument("--ca", default=".local/phase5/tls/vdiforge-local-ca.crt")
    parser.add_argument("--resolve-ip", default=os.environ.get("VDIFORGE_INGRESS_IP", "192.168.56.11"))
    args = parser.parse_args()

    install_dns_override({AUTH_HOST, API_HOST}, args.resolve_ip)
    env = load_env(args.env)
    opener = build_opener(args.ca)

    status, payload = api_request(opener, "GET", "/api/v1/health")
    if status != 200 or payload.get("status") != "ok":
        raise AssertionError(f"health check failed: {status} {payload}")
    print("PASS: API health")

    status, payload = api_request(opener, "GET", "/api/v1/images")
    if status != 401 or payload.get("error", {}).get("code") != "AUTHENTICATION_REQUIRED":
        raise AssertionError("protected API did not reject missing bearer token")
    print("PASS: missing bearer token rejected")

    tokens = TokenCache(args.ca, env)
    tokens.prefetch_all()
    print("PASS: OIDC Authorization Code + PKCE tokens acquired")
    cleanup_previous_test_desktops(opener, tokens)

    status, payload = api_request(opener, "GET", "/api/v1/images", tokens["demo-user"])
    if status != 200 or payload:
        raise AssertionError(f"demo-user should not see ubuntu-devops: {status} {payload}")
    print("PASS: demo-user image catalog is filtered")

    status, payload = api_request(opener, "GET", "/api/v1/images", tokens["demo-devops"])
    if status != 200 or [item["id"] for item in payload] != ["ubuntu-devops"]:
        raise AssertionError(f"demo-devops image catalog mismatch: {status} {payload}")
    print("PASS: demo-devops sees authorized available image")

    status, payload = api_request(
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-user"],
        {"image_id": "ubuntu-devops", "resource_profile": "small"},
        {"Idempotency-Key": f"phase7-denied-{int(time.time())}"},
    )
    if status != 403:
        raise AssertionError(f"demo-user launch should be denied: {status} {payload}")
    print("PASS: unauthorized launch denied")

    status, payload = api_request(
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-devops"],
        {"image_id": "ubuntu-devops", "resource_profile": "small"},
    )
    if status != 400 or payload.get("error", {}).get("code") != "IDEMPOTENCY_KEY_REQUIRED":
        raise AssertionError("missing idempotency key was not rejected")
    print("PASS: missing idempotency key rejected")

    key = f"phase7-launch-{int(time.time())}-{secrets.token_hex(4)}"
    status, desktop = api_request(
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-devops"],
        {"image_id": "ubuntu-devops", "resource_profile": "small", "display_name": "Phase 7 DevOps Test"},
        {"Idempotency-Key": key},
    )
    if status != 202:
        raise AssertionError(f"desktop launch failed: {status} {desktop}")
    print("PASS: desktop launch accepted asynchronously")

    status, duplicate = api_request(
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-devops"],
        {"image_id": "ubuntu-devops", "resource_profile": "small", "display_name": "Phase 7 DevOps Test"},
        {"Idempotency-Key": key},
    )
    if status != 202 or duplicate["id"] != desktop["id"]:
        raise AssertionError("idempotent launch did not return the original desktop")
    print("PASS: idempotent launch replay returned original desktop")

    ready = wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"READY"}, 1200)
    print("PASS: provisioner reconciled desktop to READY")
    verify_kubevirt(ready)

    status, payload = api_request(
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-devops"],
        {"image_id": "ubuntu-devops", "resource_profile": "small"},
        {"Idempotency-Key": f"phase7-quota-{int(time.time())}"},
    )
    if status != 409 or payload.get("error", {}).get("code") != "DESKTOP_QUOTA_EXCEEDED":
        raise AssertionError("active desktop quota did not reject second launch")
    print("PASS: quota enforcement rejected second active desktop")

    status, payload = api_request(opener, "GET", f"/api/v1/desktops/{desktop['id']}", tokens["demo-user"])
    if status != 403:
        raise AssertionError("cross-user desktop read was not denied")
    print("PASS: cross-user desktop access denied")

    status, payload = api_request(opener, "GET", "/api/v1/desktops?all_users=true", tokens["demo-admin"])
    if status != 200 or not any(item["id"] == desktop["id"] for item in payload.get("desktops", [])):
        raise AssertionError("admin list-all did not include the launched desktop")
    print("PASS: admin can list all desktops")

    status, payload = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/stop", tokens["demo-devops"])
    if status != 200:
        raise AssertionError(f"stop request failed: {status} {payload}")
    wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"STOPPED"}, 600)
    print("PASS: desktop stop lifecycle")

    status, payload = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/start", tokens["demo-devops"])
    if status != 200:
        raise AssertionError(f"start request failed: {status} {payload}")
    ready = wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"READY"}, 900)
    verify_kubevirt(ready)
    print("PASS: desktop restart lifecycle")

    status, payload = api_request(opener, "DELETE", f"/api/v1/desktops/{desktop['id']}", tokens["demo-devops"])
    if status != 202:
        raise AssertionError(f"delete request failed: {status} {payload}")
    wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"TERMINATED"}, 600)
    if not resources_deleted(desktop):
        raise AssertionError("desktop Kubernetes resources were not cleaned up")
    print("PASS: desktop delete and Kubernetes cleanup")

    status, payload = api_request(opener, "GET", "/api/v1/audit-events", tokens["demo-admin"])
    if status != 200:
        raise AssertionError("admin audit endpoint failed")
    actions = {item["action"] for item in payload.get("audit_events", [])}
    expected_actions = {"DESKTOP_REQUESTED", "DESKTOP_CREATED", "DESKTOP_STOPPED", "DESKTOP_DELETED"}
    if not expected_actions.issubset(actions):
        raise AssertionError(f"audit events missing: {sorted(expected_actions - actions)}")
    print("PASS: audit events recorded")

    kubectl("rollout", "restart", "deployment/vdiforge-api", "-n", "vdiforge-system")
    kubectl("rollout", "status", "deployment/vdiforge-api", "-n", "vdiforge-system", "--timeout=300s")
    status, payload = wait_api_request(opener, "GET", "/api/v1/audit-events", tokens["demo-admin"])
    if status != 200 or not payload.get("audit_events"):
        raise AssertionError(f"audit events were not readable after API restart: {status} {payload}")
    print("PASS: database-backed state survives API pod restart")

    print("Phase 7 API/OIDC/KubeVirt E2E validation: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Phase 7 API/OIDC/KubeVirt E2E validation: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
