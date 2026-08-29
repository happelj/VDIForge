#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import html
import json
import re
import secrets
import socket
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

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


class LoadStats:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.requests = 0
        self.successes = 0
        self.errors = 0
        self.latencies: list[float] = []
        self.first_errors: list[str] = []

    def record(self, status: int, latency: float, error: str | None = None) -> None:
        with self.lock:
            self.requests += 1
            self.latencies.append(latency)
            if 200 <= status < 300:
                self.successes += 1
            else:
                self.errors += 1
                if error and len(self.first_errors) < 5:
                    self.first_errors.append(error)


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


def build_opener(ca_file: str | None) -> urllib.request.OpenerDirector:
    context = ssl.create_default_context(cafile=ca_file) if ca_file else ssl.create_default_context()
    cookie_processor = urllib.request.HTTPCookieProcessor()
    https_handler = urllib.request.HTTPSHandler(context=context)
    opener = urllib.request.build_opener(cookie_processor, CaptureRedirect, https_handler)
    opener.addheaders = [("User-Agent", "vdiforge-phase10-load-test/1.0")]
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


def token_for(ca_file: str | None, env: dict[str, str], username: str) -> str:
    password_key = PASSWORD_ENV[username]
    if password_key not in env:
        raise RuntimeError(f"{password_key} is missing from the selected environment file.")
    verifier = secrets.token_urlsafe(48)
    opener = build_opener(ca_file)
    code = get_authorization_code(opener, username, env[password_key], verifier)
    return exchange_code(opener, code, verifier)


def request_once(url: str, token: str | None, ca_file: str | None, timeout: int) -> tuple[int, str | None]:
    headers = {"Accept": "application/json", "X-Request-ID": f"phase10-load-{secrets.token_hex(8)}"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers, method="GET")
    opener = build_opener(ca_file)
    try:
        with opener.open(request, timeout=timeout) as response:
            response.read()
            return response.status, None
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        return error.code, raw[:200]
    except (OSError, TimeoutError, urllib.error.URLError) as exc:
        return 0, str(exc)


def build_url(base_url: str, path: str, iterations: int | None) -> str:
    if path.startswith(("http://", "https://")):
        url = path
    else:
        url = f"{base_url.rstrip('/')}/{path.lstrip('/')}"
    if iterations is None or "load-test" not in url:
        return url
    separator = "&" if urllib.parse.urlparse(url).query else "?"
    return f"{url}{separator}iterations={iterations}"


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, round((pct / 100) * (len(ordered) - 1)))
    return ordered[index]


def run_load(url: str, token: str | None, ca_file: str | None, duration: int, concurrency: int, timeout: int) -> LoadStats:
    stats = LoadStats()
    deadline = time.monotonic() + duration

    def worker() -> None:
        while time.monotonic() < deadline:
            started = time.monotonic()
            status, error = request_once(url, token, ca_file, timeout)
            stats.record(status, time.monotonic() - started, error)

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        for _ in range(concurrency):
            executor.submit(worker)
    return stats


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate safe authenticated API load for VDIForge HPA validation.")
    parser.add_argument("--base-url", default=f"https://{API_HOST}", help="API base URL.")
    parser.add_argument("--path", default="/api/v1/health/load-test", help="GET path or full URL to exercise.")
    parser.add_argument("--duration", type=int, default=120, help="Load duration in seconds.")
    parser.add_argument("--concurrency", type=int, default=12, help="Number of concurrent request workers.")
    parser.add_argument("--iterations", type=int, default=150_000, help="Load-test endpoint iterations per request.")
    parser.add_argument("--timeout", type=int, default=30, help="Per-request timeout in seconds.")
    parser.add_argument("--token", default=None, help="Optional bearer token. The token is never printed.")
    parser.add_argument("--env", default=None, help="Optional Phase 5 env file used to acquire a demo-user token.")
    parser.add_argument("--username", default="demo-devops", choices=sorted(PASSWORD_ENV), help="Demo identity for PKCE.")
    parser.add_argument("--ca", default=None, help="Optional local CA certificate.")
    parser.add_argument("--resolve-ip", default=None, help="Resolve VDIForge local hostnames to this IP.")
    parser.add_argument("--max-error-rate", type=float, default=0.02, help="Allowed non-2xx response rate.")
    args = parser.parse_args()

    if args.duration < 1 or args.concurrency < 1:
        raise RuntimeError("duration and concurrency must be positive.")

    if args.resolve_ip:
        install_dns_override({AUTH_HOST, API_HOST, PORTAL_HOST, REMOTE_HOST}, args.resolve_ip)

    token = args.token
    if token is None and args.env:
        token = token_for(args.ca, load_env(args.env), args.username)
    if token is None:
        raise RuntimeError("Provide --token or --env so the safe load test uses authenticated API requests.")

    url = build_url(args.base_url, args.path, args.iterations)
    started = time.monotonic()
    stats = run_load(url, token, args.ca, args.duration, args.concurrency, args.timeout)
    elapsed = time.monotonic() - started
    error_rate = stats.errors / stats.requests if stats.requests else 1.0

    print("VDIForge Phase 10 API load test summary")
    print(f"endpoint: {urllib.parse.urlparse(url).scheme}://{urllib.parse.urlparse(url).netloc}{urllib.parse.urlparse(url).path}")
    print(f"duration_seconds: {elapsed:.1f}")
    print(f"concurrency: {args.concurrency}")
    print(f"requests: {stats.requests}")
    print(f"successes: {stats.successes}")
    print(f"errors: {stats.errors}")
    print(f"error_rate: {error_rate:.4f}")
    print(f"p50_latency_seconds: {percentile(stats.latencies, 50):.3f}")
    print(f"p95_latency_seconds: {percentile(stats.latencies, 95):.3f}")
    if stats.first_errors:
        print("first_errors:")
        for error in stats.first_errors:
            print(f"- {error}")

    if stats.requests == 0 or error_rate > args.max_error_rate:
        print("Phase 10 API load test: FAIL", file=sys.stderr)
        return 1

    print("Phase 10 API load test: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, TimeoutError, urllib.error.URLError, ValueError) as exc:
        print(f"Phase 10 API load test: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
