#!/usr/bin/env python3
"""Compare Trivy image scan output with the accepted Phase 12 baseline."""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import sys
import tempfile
from datetime import UTC, date, datetime
from pathlib import Path


SEVERITIES = ("CRITICAL", "HIGH")


def count_findings(report: dict) -> dict[str, int]:
    counts = {severity: 0 for severity in SEVERITIES}
    for result in report.get("Results", []):
        for finding in result.get("Vulnerabilities", []) or []:
            severity = str(finding.get("Severity", "")).upper()
            if severity in counts:
                counts[severity] += 1
    return counts


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"missing required file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON in {path}: {exc}") from exc


def parse_expiry(raw: str) -> date:
    try:
        return datetime.strptime(raw, "%Y-%m-%d").replace(tzinfo=UTC).date()
    except ValueError as exc:
        raise SystemExit(f"invalid baseline expiry date: {raw}") from exc


def check_baseline(component: str, report_path: Path, baseline_path: Path) -> int:
    report = load_json(report_path)
    baseline = load_json(baseline_path)

    expires = parse_expiry(str(baseline.get("expires", "")))
    if expires < datetime.now(UTC).date():
        print(f"FAIL: Trivy baseline expired on {expires.isoformat()}", file=sys.stderr)
        return 1

    component_baseline = baseline.get("components", {}).get(component)
    if not component_baseline:
        print(f"FAIL: no Trivy baseline entry for component '{component}'", file=sys.stderr)
        return 1

    counts = count_findings(report)
    failures: list[str] = []
    for severity in SEVERITIES:
        actual = counts[severity]
        allowed = int(component_baseline.get(severity.lower(), 0))
        if actual > allowed:
            failures.append(f"{severity}: actual {actual} exceeds baseline {allowed}")

    if failures:
        print(f"FAIL: {component} Trivy scan exceeded accepted baseline", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(
        "PASS: "
        f"{component} Trivy scan is within baseline "
        f"(critical={counts['CRITICAL']}/{component_baseline.get('critical', 0)}, "
        f"high={counts['HIGH']}/{component_baseline.get('high', 0)})"
    )
    return 0


def run_self_test() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        baseline = root / "baseline.json"
        report_pass = root / "pass.json"
        report_fail = root / "fail.json"
        baseline.write_text(
            json.dumps(
                {
                    "expires": "2099-12-31",
                    "components": {"api": {"critical": 1, "high": 2}},
                }
            ),
            encoding="utf-8",
        )
        report_pass.write_text(
            json.dumps(
                {
                    "Results": [
                        {
                            "Vulnerabilities": [
                                {"Severity": "CRITICAL"},
                                {"Severity": "HIGH"},
                            ]
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        report_fail.write_text(
            json.dumps(
                {
                    "Results": [
                        {
                            "Vulnerabilities": [
                                {"Severity": "CRITICAL"},
                                {"Severity": "CRITICAL"},
                            ]
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        if check_baseline("api", report_pass, baseline) != 0:
            return 1
        with contextlib.redirect_stderr(io.StringIO()):
            over_baseline_result = check_baseline("api", report_fail, baseline)
        if over_baseline_result == 0:
            print("FAIL: self-test expected the over-baseline report to fail", file=sys.stderr)
            return 1
    print("PASS: Trivy baseline checker self-test")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--component", choices=("api", "frontend"))
    parser.add_argument("--report", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    if not args.component or not args.report or not args.baseline:
        parser.error("--component, --report, and --baseline are required unless --self-test is used")

    return check_baseline(args.component, args.report, args.baseline)


if __name__ == "__main__":
    raise SystemExit(main())
