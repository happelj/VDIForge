#!/usr/bin/env python3
import argparse
import base64
import hashlib
import html
import json
import os
import re
import secrets
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


AUTH_HOST = "auth.vdiforge.local"
REALM = "vdiforge"
CLIENT_ID = "vdiforge-frontend"
REDIRECT_URI = "https://vdiforge.local/oidc/callback"
EXPECTED_AUDIENCE = "vdiforge-api"
EXPECTED_ISSUER = f"https://{AUTH_HOST}/realms/{REALM}"
EXPECTED_ROLES = {
    "demo-user": {"required": {"vdi-user"}, "forbidden": {"vdi-developer", "vdi-devops", "vdi-admin"}},
    "demo-developer": {"required": {"vdi-user", "vdi-developer"}, "forbidden": {"vdi-devops", "vdi-admin"}},
    "demo-devops": {"required": {"vdi-user", "vdi-developer", "vdi-devops"}, "forbidden": {"vdi-admin"}},
    "demo-admin": {"required": {"vdi-user", "vdi-developer", "vdi-devops", "vdi-admin"}, "forbidden": set()},
}
PASSWORD_ENV = {
    "demo-user": "DEMO_USER_PASSWORD",
    "demo-developer": "DEMO_DEVELOPER_PASSWORD",
    "demo-devops": "DEMO_DEVOPS_PASSWORD",
    "demo-admin": "DEMO_ADMIN_PASSWORD",
}


class RedirectSeen(Exception):
    def __init__(self, location):
        super().__init__(location)
        self.location = location


class CaptureRedirect(urllib.request.HTTPRedirectHandler):
    def http_error_302(self, req, fp, code, msg, headers):
        raise RedirectSeen(headers["Location"])

    http_error_301 = http_error_302
    http_error_303 = http_error_302
    http_error_307 = http_error_302
    http_error_308 = http_error_302


def b64url_decode(value):
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def b64url_no_padding(value):
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def load_env(path):
    values = {}
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key] = value
    return values


def install_dns_override(host, ip):
    if not ip:
        return

    original_getaddrinfo = socket.getaddrinfo

    def getaddrinfo(name, *args, **kwargs):
        if name == host:
            return original_getaddrinfo(ip, *args, **kwargs)
        return original_getaddrinfo(name, *args, **kwargs)

    socket.getaddrinfo = getaddrinfo


def build_opener(ca_file):
    context = ssl.create_default_context(cafile=ca_file)
    cookie_processor = urllib.request.HTTPCookieProcessor()
    opener = urllib.request.build_opener(cookie_processor, CaptureRedirect)
    opener.addheaders = [("User-Agent", "vdiforge-phase5-oidc-test/1.0")]
    opener._context = context

    https_handler = urllib.request.HTTPSHandler(context=context)
    opener = urllib.request.build_opener(cookie_processor, CaptureRedirect, https_handler)
    opener.addheaders = [("User-Agent", "vdiforge-phase5-oidc-test/1.0")]
    return opener


def http_get_json(opener, url):
    with opener.open(url, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def read_response(response):
    return response.read().decode("utf-8", errors="replace")


def parse_login_action(body):
    match = re.search(r'<form[^>]+(?:id="kc-form-login"|action="[^"]+")[^>]+action="([^"]+)"', body)
    if not match:
        match = re.search(r'<form[^>]+action="([^"]+)"', body)
    if not match:
        raise RuntimeError("Could not locate Keycloak login form action.")
    return html.unescape(match.group(1))


def auth_url(verifier, redirect_uri=REDIRECT_URI):
    challenge = b64url_no_padding(hashlib.sha256(verifier.encode("ascii")).digest())
    query = urllib.parse.urlencode(
        {
            "client_id": CLIENT_ID,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": "openid",
            "state": secrets.token_urlsafe(16),
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        }
    )
    return f"{EXPECTED_ISSUER}/protocol/openid-connect/auth?{query}"


def get_authorization_code(opener, username, password, verifier):
    with opener.open(auth_url(verifier), timeout=20) as response:
        login_page = read_response(response)

    action = parse_login_action(login_page)
    payload = urllib.parse.urlencode(
        {
            "username": username,
            "password": password,
            "credentialId": "",
            "login": "Sign In",
        }
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


def exchange_code(opener, code, verifier):
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
        f"{EXPECTED_ISSUER}/protocol/openid-connect/token",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with opener.open(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def expect_http_failure(label, func):
    try:
        func()
    except urllib.error.HTTPError as error:
        if error.code not in (400, 401, 403):
            raise
        print(f"PASS: {label}")
        return
    raise AssertionError(f"{label} unexpectedly succeeded.")


def expect_assertion_failure(label, func):
    try:
        func()
    except AssertionError:
        print(f"PASS: {label}")
        return
    raise AssertionError(f"{label} unexpectedly succeeded.")


def jwk_public_key_pem(jwk):
    x5c = jwk.get("x5c")
    if not x5c:
        raise RuntimeError("JWKS key does not include x5c certificate material.")
    cert = "-----BEGIN CERTIFICATE-----\n"
    cert += "\n".join(re.findall(".{1,64}", x5c[0]))
    cert += "\n-----END CERTIFICATE-----\n"
    with tempfile.TemporaryDirectory() as tmp:
        cert_path = os.path.join(tmp, "cert.pem")
        key_path = os.path.join(tmp, "pubkey.pem")
        with open(cert_path, "w", encoding="utf-8") as handle:
            handle.write(cert)
        result = subprocess.run(
            ["openssl", "x509", "-pubkey", "-noout", "-in", cert_path],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        with open(key_path, "w", encoding="utf-8") as handle:
            handle.write(result.stdout)
        with open(key_path, "r", encoding="utf-8") as handle:
            return handle.read()


def verify_rs256(token, jwks):
    parts = token.split(".")
    if len(parts) != 3:
        raise AssertionError("JWT does not have three sections.")
    header = json.loads(b64url_decode(parts[0]).decode("utf-8"))
    if header.get("alg") != "RS256":
        raise AssertionError(f"Unexpected JWT alg: {header.get('alg')}")
    kid = header.get("kid")
    jwk = next((key for key in jwks["keys"] if key.get("kid") == kid), None)
    if not jwk:
        raise AssertionError("Signing key ID was not found in JWKS.")

    pubkey = jwk_public_key_pem(jwk)
    with tempfile.TemporaryDirectory() as tmp:
        pubkey_path = os.path.join(tmp, "pubkey.pem")
        message_path = os.path.join(tmp, "message.txt")
        signature_path = os.path.join(tmp, "signature.bin")
        with open(pubkey_path, "w", encoding="utf-8") as handle:
            handle.write(pubkey)
        with open(message_path, "wb") as handle:
            handle.write(f"{parts[0]}.{parts[1]}".encode("ascii"))
        with open(signature_path, "wb") as handle:
            handle.write(b64url_decode(parts[2]))
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", pubkey_path, "-signature", signature_path, message_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode != 0:
            raise AssertionError("JWT signature validation failed.")

    return json.loads(b64url_decode(parts[1]).decode("utf-8"))


def normalize_audience(aud):
    if aud is None:
        return set()
    if isinstance(aud, str):
        return {aud}
    return set(aud)


def validate_token(token, jwks, expected_roles=None, forbidden_roles=None, issuer=EXPECTED_ISSUER, audience=EXPECTED_AUDIENCE, now=None):
    payload = verify_rs256(token, jwks)
    current = int(time.time()) if now is None else now
    if payload.get("iss") != issuer:
        raise AssertionError("Issuer validation failed.")
    if audience and audience not in normalize_audience(payload.get("aud")):
        raise AssertionError("Audience validation failed.")
    if int(payload.get("exp", 0)) <= current:
        raise AssertionError("Expiration validation failed.")
    if not payload.get("sub"):
        raise AssertionError("Subject claim missing.")
    if not payload.get("preferred_username"):
        raise AssertionError("preferred_username claim missing.")

    roles = set(payload.get("roles", []))
    if expected_roles and not expected_roles.issubset(roles):
        raise AssertionError(f"Missing expected roles: {sorted(expected_roles - roles)}")
    if forbidden_roles and roles.intersection(forbidden_roles):
        raise AssertionError(f"Unexpected unauthorized roles: {sorted(roles.intersection(forbidden_roles))}")
    return payload


def invalid_credentials_test(opener, password):
    verifier = secrets.token_urlsafe(48)
    with opener.open(auth_url(verifier), timeout=20) as response:
        login_page = read_response(response)
    action = parse_login_action(login_page)
    payload = urllib.parse.urlencode(
        {
            "username": "demo-user",
            "password": password,
            "credentialId": "",
            "login": "Sign In",
        }
    ).encode("utf-8")
    request = urllib.request.Request(action, data=payload, headers={"Content-Type": "application/x-www-form-urlencoded"}, method="POST")
    try:
        with opener.open(request, timeout=20) as response:
            body = read_response(response)
            if "Invalid username or password" in body or "login" in body.lower():
                return
    except RedirectSeen as redirect:
        if "code=" in redirect.location:
            raise AssertionError("Invalid credentials produced an authorization code.")


def invalid_redirect_test(opener):
    verifier = secrets.token_urlsafe(48)
    try:
        with opener.open(auth_url(verifier, redirect_uri="https://evil.example/callback"), timeout=20) as response:
            body = read_response(response)
            if "Invalid redirect" in body or "invalid" in body.lower():
                return
    except urllib.error.HTTPError as error:
        if error.code in (400, 403):
            return
        raise
    except RedirectSeen as redirect:
        if "code=" not in redirect.location:
            return
        raise AssertionError("Invalid redirect URI produced an authorization code.")
    raise AssertionError("Invalid redirect URI was not rejected.")


def invalid_pkce_test(opener, username, password):
    verifier = secrets.token_urlsafe(48)
    code = get_authorization_code(opener, username, password, verifier)
    exchange_code(opener, code, "wrong-" + verifier)


def main():
    parser = argparse.ArgumentParser(description="Validate VDIForge Keycloak OIDC Authorization Code + PKCE flow.")
    parser.add_argument("--env", default=".local/phase5/phase5.env")
    parser.add_argument("--ca", default=".local/phase5/tls/vdiforge-local-ca.crt")
    parser.add_argument("--resolve-ip", default=os.environ.get("VDIFORGE_INGRESS_IP", "192.168.56.11"))
    args = parser.parse_args()

    env = load_env(args.env)
    install_dns_override(AUTH_HOST, args.resolve_ip)
    opener = build_opener(args.ca)

    discovery = http_get_json(opener, f"{EXPECTED_ISSUER}/.well-known/openid-configuration")
    if discovery.get("issuer") != EXPECTED_ISSUER:
        raise AssertionError("OIDC discovery issuer mismatch.")
    for key in ("authorization_endpoint", "token_endpoint", "jwks_uri", "end_session_endpoint"):
        if not discovery.get(key):
            raise AssertionError(f"OIDC discovery missing {key}.")
    print("PASS: OIDC discovery metadata")

    jwks = http_get_json(opener, discovery["jwks_uri"])
    if not jwks.get("keys"):
        raise AssertionError("JWKS contains no signing keys.")
    print("PASS: JWKS signing keys")

    tokens = {}
    payloads = {}
    for username, role_expectation in EXPECTED_ROLES.items():
        user_opener = build_opener(args.ca)
        verifier = secrets.token_urlsafe(48)
        password = env[PASSWORD_ENV[username]]
        code = get_authorization_code(user_opener, username, password, verifier)
        token_response = exchange_code(user_opener, code, verifier)
        access_token = token_response.get("access_token")
        if not access_token:
            raise AssertionError(f"No access token returned for {username}.")
        payload = validate_token(
            access_token,
            jwks,
            expected_roles=role_expectation["required"],
            forbidden_roles=role_expectation["forbidden"],
        )
        tokens[username] = access_token
        payloads[username] = payload
        print(f"PASS: PKCE token and RBAC claims for {username}")

    invalid_credentials_test(build_opener(args.ca), "definitely-wrong-password")
    print("PASS: Invalid credentials rejected")
    invalid_redirect_test(build_opener(args.ca))
    print("PASS: Invalid redirect URI rejected")
    expect_http_failure(
        "Invalid PKCE verifier rejected",
        lambda: invalid_pkce_test(build_opener(args.ca), "demo-user", env["DEMO_USER_PASSWORD"]),
    )

    demo_user_token = tokens["demo-user"]
    parts = demo_user_token.split(".")
    tampered_payload = json.loads(b64url_decode(parts[1]).decode("utf-8"))
    tampered_payload["preferred_username"] = "tampered-user"
    tampered_body = b64url_no_padding(json.dumps(tampered_payload, separators=(",", ":")).encode("utf-8"))
    tampered = f"{parts[0]}.{tampered_body}.{parts[2]}"
    expect_assertion_failure("Tampered JWT rejected", lambda: validate_token(tampered, jwks))

    expired_now = int(payloads["demo-user"]["exp"]) + 1
    expect_assertion_failure("Expired JWT rejected", lambda: validate_token(demo_user_token, jwks, now=expired_now))

    expect_assertion_failure(
        "Wrong issuer rejected",
        lambda: validate_token(demo_user_token, jwks, issuer="https://wrong-issuer.example/realms/vdiforge"),
    )

    expect_assertion_failure(
        "Wrong audience rejected",
        lambda: validate_token(demo_user_token, jwks, audience="wrong-audience"),
    )

    try:
        validate_token(demo_user_token, jwks, forbidden_roles={"vdi-admin"})
        print("PASS: Unauthorized admin role absent")
    except AssertionError:
        raise AssertionError("Unauthorized admin role was present for demo-user.")

    print("Phase 5 OIDC PKCE/JWT/RBAC validation: PASS")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Phase 5 OIDC PKCE/JWT/RBAC validation: FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
