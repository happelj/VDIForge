#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import os
import secrets
import sys
import time
from pathlib import Path

HELPER_PATH = Path(__file__).with_name("phase9-portal-e2e-test.py")
spec = importlib.util.spec_from_file_location("phase9_portal_e2e", HELPER_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"Could not load helper module from {HELPER_PATH}")
phase9 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phase9)

AUTH_HOST = phase9.AUTH_HOST
API_HOST = phase9.API_HOST
PORTAL_HOST = phase9.PORTAL_HOST
REMOTE_HOST = phase9.REMOTE_HOST

EXPECTED_IMAGES = {
    "demo-user": ["ubuntu-base"],
    "demo-developer": ["ubuntu-base", "ubuntu-developer"],
    "demo-devops": ["ubuntu-base", "ubuntu-developer", "ubuntu-devops"],
    "demo-admin": ["ubuntu-base", "ubuntu-developer", "ubuntu-devops"],
}

EXPECTED_DEFAULTS = {
    "ubuntu-base": "1.0.0",
    "ubuntu-developer": "1.0.0",
    "ubuntu-devops": "1.2.0",
}


def version_tuple(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in value.split("."))


def assert_image_payload(username: str, payload: list[dict]) -> None:
    ids = [str(item.get("id")) for item in payload]
    expected = EXPECTED_IMAGES[username]
    if ids != expected:
        raise AssertionError(f"{username} image catalog mismatch: expected {expected}, got {ids}")

    by_id = {item["id"]: item for item in payload}
    for image_id in expected:
        image = by_id[image_id]
        expected_default = EXPECTED_DEFAULTS[image_id]
        if image.get("default_version") != expected_default:
            raise AssertionError(f"{image_id} default version mismatch: {image}")
        versions = image.get("versions", [])
        if not any(version.get("version") == expected_default for version in versions):
            raise AssertionError(f"{image_id} default version is not exposed in API payload: {image}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Phase 14 role-specific image catalog behavior.")
    parser.add_argument("--env", default=".local/phase5/phase5.env")
    parser.add_argument("--ca", default=".local/phase5/tls/vdiforge-local-ca.crt")
    parser.add_argument("--resolve-ip", default=os.environ.get("VDIFORGE_INGRESS_IP", "192.168.56.11"))
    parser.add_argument("--minimum-api-version", default="0.14.0")
    args = parser.parse_args()

    phase9.install_dns_override({AUTH_HOST, API_HOST, PORTAL_HOST, REMOTE_HOST}, args.resolve_ip)
    env = phase9.load_env(args.env)
    opener = phase9.build_opener(args.ca)

    status, health = phase9.api_request(opener, "GET", "/api/v1/health")
    if status != 200 or health.get("status") != "ok":
        raise AssertionError(f"API health failed: {status} {health}")
    if version_tuple(str(health.get("version", "0.0.0"))) < version_tuple(args.minimum_api_version):
        raise AssertionError(f"API version is below Phase 14 baseline: {health}")
    print(f"PASS: API health reports version {health['version']}")

    tokens = {username: phase9.token_for(args.ca, env, username) for username in EXPECTED_IMAGES}
    print("PASS: OIDC Authorization Code + PKCE tokens acquired for all demo users")

    for username, expected in EXPECTED_IMAGES.items():
        status, payload = phase9.api_request(opener, "GET", "/api/v1/images", tokens[username])
        if status != 200:
            raise AssertionError(f"image catalog failed for {username}: {status} {payload}")
        assert_image_payload(username, payload)
        print(f"PASS: {username} sees {', '.join(expected)}")

    negative_cases = [
        ("demo-user", "ubuntu-developer"),
        ("demo-user", "ubuntu-devops"),
        ("demo-developer", "ubuntu-devops"),
    ]
    for username, image_id in negative_cases:
        status, payload = phase9.api_request(
            opener,
            "POST",
            "/api/v1/desktops",
            tokens[username],
            {"image_id": image_id, "resource_profile": "small", "display_name": "Phase 14 Unauthorized Test"},
            {"Idempotency-Key": f"phase14-denied-{username}-{int(time.time())}-{secrets.token_hex(4)}"},
        )
        if status != 403:
            raise AssertionError(f"{username} should not launch {image_id}: {status} {payload}")
        print(f"PASS: {username} cannot launch {image_id}")

    print("Phase 14 role/image catalog validation: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Phase 14 role/image catalog validation: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
