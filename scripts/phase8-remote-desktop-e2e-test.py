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
from pathlib import Path

AUTH_HOST = "auth.vdiforge.local"
API_HOST = "api.vdiforge.local"
REMOTE_HOST = "remote.vdiforge.local"
REALM = "vdiforge"
CLIENT_ID = "vdiforge-frontend"
REDIRECT_URI = "https://vdiforge.local/oidc/callback"
ISSUER = f"https://{AUTH_HOST}/realms/{REALM}"
DESKTOP_NAMESPACE = "vdiforge-desktops"
GUACAMOLE_NAMESPACE = "guacamole"
AGNHOST_IMAGE = "registry.k8s.io/e2e-test-images/agnhost:2.40"
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
    opener.addheaders = [("User-Agent", "vdiforge-phase8-remote-desktop-e2e/1.0")]
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
        raise RuntimeError("No access token returned.")
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


def guacamole_post_token(opener: urllib.request.OpenerDirector, connection_url: str) -> dict:
    parsed = urllib.parse.urlparse(connection_url)
    data = urllib.parse.parse_qs(parsed.query).get("data", [""])[0]
    if not data:
        raise AssertionError("connection_url did not contain a Guacamole JSON data token")
    payload = urllib.parse.urlencode({"data": data}).encode("utf-8")
    request = urllib.request.Request(
        f"https://{REMOTE_HOST}/api/tokens",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with opener.open(request, timeout=30) as response:
        token_response = json.loads(response.read().decode("utf-8"))
    if "authToken" not in token_response:
        raise AssertionError(f"Guacamole did not return an auth token: {token_response}")
    return token_response


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
    last_reported_state = ""
    last_transient_status = 0
    while time.monotonic() < deadline:
        status, payload = api_request(opener, "GET", f"/api/v1/desktops/{desktop_id}", tokens[username])
        if status == 401:
            status, payload = api_request(
                opener,
                "GET",
                f"/api/v1/desktops/{desktop_id}",
                tokens.refresh(username),
            )
        if status in {502, 503, 504}:
            if status != last_transient_status:
                print(f"WAIT: desktop {desktop_id} API returned transient HTTP {status}; retrying")
                last_transient_status = status
            time.sleep(10)
            continue
        last_transient_status = 0
        if status != 200:
            raise RuntimeError(f"desktop status returned HTTP {status}: {payload}")
        last_payload = payload
        observed_state = str(payload["observed_state"])
        if observed_state != last_reported_state:
            print(f"WAIT: desktop {desktop_id} observed_state={observed_state}")
            last_reported_state = observed_state
        if payload["observed_state"] in expected:
            return payload
        if payload["observed_state"] == "FAILED":
            raise RuntimeError(f"desktop failed: {payload.get('failure_code')} {payload.get('failure_message')}")
        time.sleep(10)
    raise RuntimeError(f"timed out waiting for {expected}; last payload: {last_payload}")


def cleanup_probe_pods() -> None:
    kubectl("delete", "pod", "phase8-rdp-probe", "-n", GUACAMOLE_NAMESPACE, "--ignore-not-found=true", "--wait=true")


def cleanup_previous_test_desktops(opener: urllib.request.OpenerDirector, tokens: TokenCache) -> None:
    cleanup_probe_pods()
    status, payload = api_request(opener, "GET", "/api/v1/desktops", tokens["demo-devops"])
    if status != 200:
        raise RuntimeError(f"could not list existing demo-devops desktops: {status} {payload}")
    stale = [
        desktop
        for desktop in payload.get("desktops", [])
        if desktop.get("display_name") == "Phase 8 Remote Desktop Test" and desktop.get("observed_state") != "TERMINATED"
    ]
    for desktop in stale:
        status, delete_payload = api_request(opener, "DELETE", f"/api/v1/desktops/{desktop['id']}", tokens["demo-devops"])
        if status not in {200, 202}:
            raise RuntimeError(f"could not delete stale test desktop {desktop['id']}: {status} {delete_payload}")
        wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"TERMINATED"}, 900)
    if stale:
        print(f"PASS: cleaned up {len(stale)} previous Phase 8 test desktop(s)")


def verify_kubevirt(desktop: dict) -> None:
    vmi = kubectl_json("get", "vmi", desktop["kubevirt_vm_name"], "-n", DESKTOP_NAMESPACE)
    node = vmi.get("status", {}).get("nodeName")
    if node != "vdi-worker-02":
        raise AssertionError(f"VMI scheduled on {node}, expected vdi-worker-02")
    pods = kubectl_json("get", "pods", "-n", DESKTOP_NAMESPACE, "-l", f"vdiforge.io/desktop-id={desktop['id']}")
    launcher = next(
        (
            pod
            for pod in pods.get("items", [])
            if pod.get("metadata", {}).get("labels", {}).get("kubevirt.io") == "virt-launcher"
        ),
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


def verify_desktop_service(desktop: dict) -> None:
    service = kubectl_json("get", "svc", desktop["kubevirt_service_name"], "-n", DESKTOP_NAMESPACE)
    if service.get("spec", {}).get("type") != "ClusterIP":
        raise AssertionError("desktop RDP service is not ClusterIP")
    ports = {str(port.get("port")) for port in service.get("spec", {}).get("ports", [])}
    if "3389" not in ports:
        raise AssertionError("desktop Service does not expose internal RDP port 3389")
    print("PASS: desktop RDP service is internal ClusterIP")


def secret_exists(desktop: dict) -> bool:
    return kubectl("get", "secret", f"{desktop['kubevirt_vm_name']}-remote", "-n", DESKTOP_NAMESPACE, check=False).returncode == 0


def resources_deleted(desktop: dict) -> bool:
    names = [
        ("vm", desktop["kubevirt_vm_name"]),
        ("datavolume", desktop["kubevirt_data_volume_name"]),
        ("pvc", desktop["kubevirt_data_volume_name"]),
        ("svc", desktop["kubevirt_service_name"]),
        ("secret", f"{desktop['kubevirt_vm_name']}-remote"),
    ]
    return all(kubectl("get", kind, name, "-n", DESKTOP_NAMESPACE, check=False).returncode != 0 for kind, name in names)


def rdp_reachable_from_guacd(desktop: dict) -> None:
    pod = "phase8-rdp-probe"
    endpoint = f"{desktop['kubevirt_service_name']}.{DESKTOP_NAMESPACE}.svc.cluster.local:3389"
    pod_manifest = json.dumps(
        {
            "apiVersion": "v1",
            "kind": "Pod",
            "metadata": {
                "name": pod,
                "namespace": GUACAMOLE_NAMESPACE,
                "labels": {
                    "app.kubernetes.io/name": "vdiforge-guacd",
                    "app.kubernetes.io/instance": "vdiforge",
                    "app.kubernetes.io/component": "guacd",
                    "app.kubernetes.io/part-of": "vdiforge",
                },
            },
            "spec": {
                "automountServiceAccountToken": False,
                "restartPolicy": "Never",
                "securityContext": {"seccompProfile": {"type": "RuntimeDefault"}},
                "containers": [
                    {
                        "name": "agnhost",
                        "image": AGNHOST_IMAGE,
                        "command": ["/agnhost", "pause"],
                        "resources": {
                            "requests": {"cpu": "5m", "memory": "16Mi"},
                            "limits": {"cpu": "10m", "memory": "32Mi"},
                        },
                        "securityContext": {
                            "allowPrivilegeEscalation": False,
                            "runAsNonRoot": True,
                            "runAsUser": 65534,
                            "runAsGroup": 65534,
                            "capabilities": {"drop": ["ALL"]},
                        },
                    }
                ],
            },
        }
    )
    kubectl("delete", "pod", pod, "-n", GUACAMOLE_NAMESPACE, "--ignore-not-found=true", "--wait=true")
    try:
        subprocess.run(
            ["kubectl", "apply", "-f", "-"],
            input=pod_manifest,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        kubectl("wait", "pod", pod, "-n", GUACAMOLE_NAMESPACE, "--for=condition=Ready", "--timeout=180s")
        last_error = ""
        for attempt in range(1, 25):
            result = kubectl(
                "exec",
                "-n",
                GUACAMOLE_NAMESPACE,
                pod,
                "--",
                "/agnhost",
                "connect",
                endpoint,
                "--timeout=10s",
                check=False,
            )
            if result.returncode == 0:
                break
            last_error = result.stderr.strip() or result.stdout.strip()
            print(f"WAIT: RDP endpoint not reachable from guacd probe yet, attempt={attempt}")
            time.sleep(5)
        else:
            raise AssertionError(f"RDP endpoint not reachable from guacd probe: {last_error}")
    finally:
        kubectl("delete", "pod", pod, "-n", GUACAMOLE_NAMESPACE, "--ignore-not-found=true", "--wait=true")
    print("PASS: guacd network position can reach desktop RDP service")


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


def wait_api_health(opener: urllib.request.OpenerDirector) -> None:
    last_payload: object = None
    last_status = 0
    for attempt in range(1, 25):
        status, payload = api_request(opener, "GET", "/api/v1/health")
        if status == 200 and payload.get("status") == "ok":
            print("PASS: API health")
            return
        last_status = status
        last_payload = payload
        print(f"WAIT: API health not ready yet, attempt={attempt}, status={status}")
        time.sleep(5)
    raise AssertionError(f"API health check failed: {last_status} {last_payload}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Phase 8 Guacamole remote desktop validation.")
    parser.add_argument("--env", default=".local/phase5/phase5.env")
    parser.add_argument("--ca", default=".local/phase5/tls/vdiforge-local-ca.crt")
    parser.add_argument("--resolve-ip", default=os.environ.get("VDIFORGE_INGRESS_IP", "192.168.56.11"))
    parser.add_argument(
        "--expected-image-version",
        default=os.environ.get("VDIFORGE_EXPECTED_REMOTE_IMAGE_VERSION", "1.1.0"),
        help="Expected ubuntu-devops version for this regression run.",
    )
    parser.add_argument("--keep-desktop", action="store_true", help="Leave the test desktop running for manual browser proof.")
    parser.add_argument("--cleanup-only", action="store_true", help="Delete stale Phase 8 validation desktops and exit.")
    parser.add_argument("--browser-artifact", default=".local/phase8/browser-connection.json")
    args = parser.parse_args()

    install_dns_override({AUTH_HOST, API_HOST, REMOTE_HOST}, args.resolve_ip)
    env = load_env(args.env)
    opener = build_opener(args.ca)

    wait_api_health(opener)

    tokens = TokenCache(args.ca, env)
    tokens.prefetch_all()
    print("PASS: OIDC Authorization Code + PKCE tokens acquired")
    cleanup_previous_test_desktops(opener, tokens)
    if args.cleanup_only:
        print("Phase 8 previous test desktop cleanup: PASS")
        return 0

    key = f"phase8-launch-{int(time.time())}-{secrets.token_hex(4)}"
    status, desktop = api_request(
        opener,
        "POST",
        "/api/v1/desktops",
        tokens["demo-devops"],
        {"image_id": "ubuntu-devops", "resource_profile": "small", "display_name": "Phase 8 Remote Desktop Test"},
        {"Idempotency-Key": key},
    )
    if status != 202:
        raise AssertionError(f"desktop launch failed: {status} {desktop}")
    print("PASS: remote-enabled desktop launch accepted")

    ready = wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"READY"}, 1200)
    if ready["image_version"] != args.expected_image_version:
        raise AssertionError(f"expected ubuntu-devops:{args.expected_image_version}, got {ready['image_version']}")
    verify_kubevirt(ready)
    verify_desktop_service(ready)
    if not secret_exists(ready):
        raise AssertionError("per-desktop remote secret was not created")
    print("PASS: per-desktop remote credential Secret exists")
    rdp_reachable_from_guacd(ready)

    status, connection = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/connect", tokens["demo-devops"])
    if status != 200:
        raise AssertionError(f"owner connect failed: {status} {connection}")
    if "password" in json.dumps(connection).lower():
        raise AssertionError("connection API response exposed a password")
    if not connection.get("connection_url", "").startswith(f"https://{REMOTE_HOST}/?data="):
        raise AssertionError(f"unexpected connection URL: {connection}")
    print("PASS: owner received short-lived Guacamole connection URL without plaintext credential")

    guacamole_post_token(opener, connection["connection_url"])
    print("PASS: Guacamole JSON auth accepted the brokered connection")

    status, denied = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/connect", tokens["demo-user"])
    if status != 403:
        raise AssertionError(f"cross-user connect should be denied: {status} {denied}")
    print("PASS: cross-user connection request denied")

    status, missing = api_request(opener, "POST", f"/api/v1/desktops/{secrets.token_hex(16)}/connect", tokens["demo-user"])
    if status != 404:
        raise AssertionError(f"guessed desktop ID should not connect: {status} {missing}")
    print("PASS: guessed desktop ID denied")

    write_browser_artifact(args.browser_artifact, connection, ready)
    if args.keep_desktop:
        print("Phase 8 remote desktop validation paused with the desktop running for browser proof.")
        print(f"Open this URL in a browser: {connection['connection_url']}")
        return 0

    status, payload = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/stop", tokens["demo-devops"])
    if status != 200:
        raise AssertionError(f"stop request failed: {status} {payload}")
    wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"STOPPED"}, 600)
    status, stopped_connect = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/connect", tokens["demo-devops"])
    if status != 409:
        raise AssertionError(f"stopped desktop should not connect: {status} {stopped_connect}")
    print("PASS: stopped desktop connection denied")

    status, payload = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/start", tokens["demo-devops"])
    if status != 200:
        raise AssertionError(f"start request failed: {status} {payload}")
    ready = wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"READY"}, 900)
    verify_kubevirt(ready)
    status, connection = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/connect", tokens["demo-devops"])
    if status != 200:
        raise AssertionError(f"reconnect failed: {status} {connection}")
    guacamole_post_token(opener, connection["connection_url"])
    print("PASS: restarted desktop reconnects through Guacamole JSON auth")

    status, payload = api_request(opener, "DELETE", f"/api/v1/desktops/{desktop['id']}", tokens["demo-devops"])
    if status != 202:
        raise AssertionError(f"delete request failed: {status} {payload}")
    wait_desktop_state(opener, tokens, "demo-devops", desktop["id"], {"TERMINATED"}, 900)
    if not resources_deleted(desktop):
        raise AssertionError("desktop VM/DataVolume/PVC/Service/Secret resources were not cleaned up")
    print("PASS: desktop delete cleaned up KubeVirt, Service, PVC, and remote Secret resources")

    status, deleted_connect = api_request(opener, "POST", f"/api/v1/desktops/{desktop['id']}/connect", tokens["demo-devops"])
    if status != 409:
        raise AssertionError(f"deleted desktop should not create a new connection: {status} {deleted_connect}")
    print("PASS: deleted desktop connection denied")

    status, audit = api_request(opener, "GET", "/api/v1/audit-events", tokens["demo-admin"])
    if status != 200:
        raise AssertionError(f"admin audit endpoint failed: {status} {audit}")
    actions = {item["action"] for item in audit.get("audit_events", [])}
    expected = {"DESKTOP_CONNECTION_REQUESTED", "DESKTOP_CONNECTION_DENIED"}
    if not expected.issubset(actions):
        raise AssertionError(f"audit events missing: {sorted(expected - actions)}")
    if "password" in json.dumps(audit).lower():
        raise AssertionError("audit API response exposed a password")
    print("PASS: connection audit events recorded without credential leakage")

    print("Phase 8 remote desktop E2E validation: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Phase 8 remote desktop E2E validation: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
