#!/usr/bin/env python3
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "images" / "catalog.json"

EXPECTED = {
    "ubuntu-base": {"vdi-user", "vdi-developer", "vdi-devops", "vdi-admin"},
    "ubuntu-developer": {"vdi-developer", "vdi-devops", "vdi-admin"},
    "ubuntu-devops": {"vdi-devops", "vdi-admin"},
}


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    try:
      data = json.loads(CATALOG.read_text(encoding="utf-8"))
    except Exception as exc:
      fail(f"catalog JSON is invalid: {exc}")

    if data.get("schemaVersion") != "vdiforge.io/image-catalog/v1alpha1":
        fail("unexpected catalog schemaVersion")

    images = data.get("images")
    if not isinstance(images, list):
        fail("catalog images must be a list")

    by_id = {image.get("id"): image for image in images}
    missing = sorted(set(EXPECTED) - set(by_id))
    if missing:
        fail(f"missing image definitions: {', '.join(missing)}")

    if len(by_id) != len(images):
        fail("duplicate image IDs found")

    for image_id, expected_roles in EXPECTED.items():
        image = by_id[image_id]
        roles = set(image.get("allowedRoles", []))
        if roles != expected_roles:
            fail(f"{image_id} allowedRoles mismatch: {sorted(roles)}")

        versions = image.get("versions", [])
        if not versions:
            fail(f"{image_id} has no versions")

        default_version = image.get("defaultVersion")
        version_ids = {version.get("version") for version in versions}
        if default_version not in version_ids:
            fail(f"{image_id} defaultVersion is not present in versions")

        for version in versions:
            if version.get("ubuntuRelease") != "26.04 LTS":
                fail(f"{image_id} {version.get('version')} is not pinned to Ubuntu 26.04 LTS")
            if version.get("architecture") != "amd64":
                fail(f"{image_id} {version.get('version')} is not amd64")
            if version.get("artifactFormat") != "qcow2":
                fail(f"{image_id} {version.get('version')} is not qcow2")
            if version.get("lifecycle") not in {"candidate", "available", "deprecated", "blocked"}:
                fail(f"{image_id} {version.get('version')} has invalid lifecycle")
            if not version.get("manifestPath", "").endswith(".manifest.json"):
                fail(f"{image_id} {version.get('version')} manifestPath is invalid")
            if version.get("lifecycle") == "available" and not version.get("sourcePvcName"):
                fail(f"{image_id} {version.get('version')} is available but lacks sourcePvcName")

    print("PASS: image catalog validation completed")


if __name__ == "__main__":
    main()
