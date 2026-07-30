#!/usr/bin/env python3
"""Explicit runtime gates for R8 artifacts A05 onward.

Unsupported codes fail closed. Each implemented gate must execute the artifact's
examples or its declared validator, not merely parse the file.
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
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[1]
SKILL_ROOT = ROOT / "skills" / "creating-integral-user-stories"
FENCE = re.compile(r"```json\n(.*?)\n```", re.S)
HEADING = re.compile(r"^(#{2,4})\s+(.+?)\s*$", re.M)


def env() -> dict[str, str]:
    value = os.environ.copy()
    value.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_DEEP_AUDIT_RUNNER")
    return value


def heading_before(text: str, position: int) -> str:
    heading = ""
    for match in HEADING.finditer(text, 0, position):
        heading = match.group(2).strip()
    return heading


def examples(relative_path: str) -> dict[str, dict[str, Any]]:
    text = (SKILL_ROOT / relative_path).read_text(encoding="utf-8")
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


def count(value: Any) -> int:
    if isinstance(value, (list, dict, tuple, set)):
        return len(value)
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    return 0 if value in (None, "") else 1


def expected_checks(payload: dict[str, Any], result: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    expected = payload.get("expected_checks")
    if not isinstance(expected, dict):
        return True, {"declared": False}
    checks = result.get("evidence", {}).get("checks", {})
    mismatches: dict[str, Any] = {}
    for key, wanted in expected.items():
        actual = count(checks.get(key))
        if wanted == ">0" and actual <= 0:
            mismatches[key] = {"expected": wanted, "actual": actual}
        elif wanted == 0 and actual != 0:
            mismatches[key] = {"expected": wanted, "actual": actual}
    return not mismatches, {"declared": True, "checks": checks, "mismatches": mismatches}


def run_fixture(title: str, payload: dict[str, Any], command_template: list[str]) -> dict[str, Any]:
    expected_result = "PASS_WITH_EVIDENCE" if "positivo" in title.lower() else "RETURN_TO_WORKER"
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8", delete=False) as handle:
        json.dump(payload, handle, ensure_ascii=False)
        handle.write("\n")
        input_path = Path(handle.name)
    command = [part.replace("{input}", str(input_path)) for part in command_template]
    proc = subprocess.run(command, cwd=SKILL_ROOT, env=env(), text=True, capture_output=True, timeout=120)
    try:
        result = emitted(proc.stdout)
        checks_ok, check_evidence = expected_checks(payload, result)
        passed = result.get("result") == expected_result and checks_ok
        return {
            "title": title,
            "passed": passed,
            "command": command,
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
            "expected_checks": check_evidence,
        }
    except Exception as exc:
        return {
            "title": title,
            "passed": False,
            "command": command,
            "process_exit_code": proc.returncode,
            "stdout": proc.stdout[-2000:],
            "stderr": proc.stderr[-1000:],
            "error": f"{type(exc).__name__}:{exc}",
        }
    finally:
        input_path.unlink(missing_ok=True)


def audit_pair(code: str, relative_path: str, judge: int, command: list[str], self_test: list[str] | None = None) -> dict[str, Any]:
    found = examples(relative_path)
    required = [f"Caso positivo J{judge:02d}", f"Caso negativo J{judge:02d}"]
    missing = [title for title in required if title not in found]
    outcomes = [run_fixture(title, found[title], command) for title in required if title in found]
    if self_test:
        proc = subprocess.run(self_test, cwd=SKILL_ROOT, env=env(), text=True, capture_output=True, timeout=120)
        try:
            payload = emitted(proc.stdout)
            passed = proc.returncode == 0 and (payload.get("positive_pass") is True or payload.get("result") == "PASS_WITH_EVIDENCE") and (payload.get("negative_rejected") is True or payload.get("result") == "PASS_WITH_EVIDENCE")
        except Exception as exc:
            payload = {"error": f"{type(exc).__name__}:{exc}", "stdout": proc.stdout[-2000:], "stderr": proc.stderr[-1000:]}
            passed = False
        outcomes.append({"title": "SELF_TEST", "passed": passed, "command": self_test, "process_exit_code": proc.returncode, "result": payload})
    return {"artifact": code, "missing_examples": missing, "outcomes": outcomes, "passed": not missing and all(item["passed"] for item in outcomes)}


def audit_a05() -> dict[str, Any]:
    return audit_pair(
        "A05",
        "agents/test-deriver.md",
        10,
        [sys.executable, "scripts/validate_test_coverage.py", "{input}"],
        [sys.executable, "scripts/validate_test_coverage.py", "--self-test"],
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    args = parser.parse_args()
    auditors: dict[str, Callable[[], dict[str, Any]]] = {"A05": audit_a05}
    payload = auditors[args.artifact]() if args.artifact in auditors else {
        "artifact": args.artifact,
        "passed": False,
        "blocking_reason": "artifact_specific_runtime_gate_not_implemented",
    }
    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / f"{args.artifact}-runtime.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0 if payload.get("passed") else 2 if payload.get("blocking_reason") else 1


if __name__ == "__main__":
    raise SystemExit(main())
