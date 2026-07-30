#!/usr/bin/env python3
"""Artifact-specific executable gates used by the sequential R8 audit.

An artifact is unsupported until this module contains an explicit runtime contract for
it. This prevents a structural score from being mistaken for deep validation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SKILL_ROOT = ROOT / "skills" / "creating-integral-user-stories"
FENCE = re.compile(r"```json\n(.*?)\n```", re.S)
HEADING = re.compile(r"^(#{2,4})\s+(.+?)\s*$", re.M)


def heading_before(text: str, position: int) -> str:
    heading = ""
    for match in HEADING.finditer(text, 0, position):
        heading = match.group(2).strip()
    return heading


def examples(path: Path) -> dict[str, dict[str, Any]]:
    text = path.read_text(encoding="utf-8")
    result: dict[str, dict[str, Any]] = {}
    for match in FENCE.finditer(text):
        title = heading_before(text, match.start())
        if title.lower().startswith("caso positivo") or title.lower().startswith("caso negativo"):
            result[title] = json.loads(match.group(1))
    return result


def emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("validator_json_output_missing")


def count_value(value: Any) -> int:
    if isinstance(value, (list, dict, tuple, set)):
        return len(value)
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    return 0 if value in (None, "") else 1


def expected_checks_ok(payload: dict[str, Any], result: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    wanted = payload.get("expected_checks")
    if not isinstance(wanted, dict):
        return True, {"declared": False}
    checks = result.get("evidence", {}).get("checks", {})
    mismatches: dict[str, Any] = {}
    for key, expected in wanted.items():
        actual = count_value(checks.get(key))
        if expected == ">0" and actual <= 0:
            mismatches[key] = {"expected": expected, "actual": actual}
        if expected == 0 and actual != 0:
            mismatches[key] = {"expected": expected, "actual": actual}
    return not mismatches, {"declared": True, "mismatches": mismatches, "checks": checks}


def run_case(title: str, payload: dict[str, Any], command: list[str]) -> dict[str, Any]:
    expected_result = "PASS_WITH_EVIDENCE" if "positivo" in title.lower() else "RETURN_TO_WORKER"
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8", delete=False) as handle:
        json.dump(payload, handle, ensure_ascii=False)
        handle.write("\n")
        input_path = Path(handle.name)
    full_command = [part.replace("{input}", str(input_path)) for part in command]
    env = os.environ.copy()
    env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_DEEP_AUDIT_RUNNER")
    proc = subprocess.run(full_command, cwd=SKILL_ROOT, env=env, text=True, capture_output=True, timeout=90)
    try:
        result = emitted(proc.stdout)
        checks_ok, checks_detail = expected_checks_ok(payload, result)
        passed = result.get("result") == expected_result and checks_ok
        return {
            "title": title,
            "passed": passed,
            "command": full_command,
            "process_exit_code": proc.returncode,
            "expected_result": expected_result,
            "actual_result": result.get("result"),
            "assertions_total": result.get("assertions_total"),
            "assertions_passed": result.get("assertions_passed"),
            "failed_assertions": result.get("failed_assertions"),
            "blocking_assertions": result.get("blocking_assertions"),
            "repairs": result.get("repairs"),
            "input_sha256": result.get("input_sha256") or hashlib.sha256(input_path.read_bytes()).hexdigest(),
            "evidence_sha256": result.get("evidence_sha256"),
            "output_sha256": result.get("output_sha256"),
            "expected_checks": checks_detail,
        }
    except Exception as exc:
        return {
            "title": title,
            "passed": False,
            "command": full_command,
            "process_exit_code": proc.returncode,
            "stdout": proc.stdout[-2000:],
            "stderr": proc.stderr[-1000:],
            "error": f"{type(exc).__name__}:{exc}",
        }
    finally:
        input_path.unlink(missing_ok=True)


def audit_a01() -> dict[str, Any]:
    path = SKILL_ROOT / "agents/cross-cutting-enricher.md"
    found = examples(path)
    commands = {
        5: [sys.executable, "scripts/validate_field_coverage.py", "{input}", "--judge", "J05_OBSERVATIONS_ERRORS"],
        6: [sys.executable, "scripts/validate_security_coverage.py", "{input}", "--judge-version", "v0.5", "--executor-identity", "R8_DEEP_AUDIT_RUNNER"],
        7: [sys.executable, "scripts/validate_traceability.py", "{input}", "--judge-version", "v0.5", "--executor-identity", "R8_DEEP_AUDIT_RUNNER"],
        8: [sys.executable, "scripts/validate_tokens.py", "{input}", "--judge-version", "v0.5", "--executor-identity", "R8_DEEP_AUDIT_RUNNER"],
        9: [sys.executable, "scripts/detect_pii_telemetry.py", "{input}", "--judge-version", "v0.5", "--executor-identity", "R8_DEEP_AUDIT_RUNNER"],
    }
    expected = [f"Caso {kind} J{judge:02d}" for judge in range(5, 10) for kind in ("positivo", "negativo")]
    missing = [title for title in expected if title not in found]
    outcomes = []
    for title in expected:
        if title in found:
            judge = int(re.search(r"J(\d+)", title).group(1))
            outcomes.append(run_case(title, found[title], commands[judge]))
    return {"artifact": "A01", "missing_examples": missing, "outcomes": outcomes, "passed": not missing and all(item["passed"] for item in outcomes)}


def audit_a02() -> dict[str, Any]:
    path = SKILL_ROOT / "agents/field-contract-author.md"
    found = examples(path)
    expected = ["Caso positivo J04", "Caso negativo J04"]
    missing = [title for title in expected if title not in found]
    command = [sys.executable, "scripts/validate_field_coverage.py", "{input}", "--judge", "J04_FIELD_CONTRACTS"]
    outcomes = [run_case(title, found[title], command) for title in expected if title in found]
    return {"artifact": "A02", "missing_examples": missing, "outcomes": outcomes, "passed": not missing and all(item["passed"] for item in outcomes)}


def main() -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--artifact", required=True)
    cli.add_argument("--report-dir", type=Path, required=True)
    args = cli.parse_args()
    auditors = {"A01": audit_a01, "A02": audit_a02}
    if args.artifact not in auditors:
        payload = {"artifact": args.artifact, "passed": False, "blocking_reason": "artifact_specific_runtime_gate_not_implemented"}
        args.report_dir.mkdir(parents=True, exist_ok=True)
        (args.report_dir / f"{args.artifact}-runtime.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(payload, sort_keys=True))
        return 2
    payload = auditors[args.artifact]()
    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / f"{args.artifact}-runtime.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0 if payload["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
