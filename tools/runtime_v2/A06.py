#!/usr/bin/env python3
"""A06 v2: reconcile 23 assertions across eval and trigger registries."""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
ASSERTIONS = SKILL / "evals" / "assertions.json"
EVALS = SKILL / "evals" / "evals.json"
TRIGGERS = SKILL / "evals" / "trigger-evals.json"
OLD_RUNNER = ROOT / "tools" / "runtime" / "A06.py"


def emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("json_output_missing")


def main() -> int:
    old = subprocess.run([sys.executable, str(OLD_RUNNER)], cwd=ROOT, text=True, capture_output=True, timeout=300)
    try:
        prior = emitted(old.stdout)
    except Exception as exc:
        prior = {"error": f"{type(exc).__name__}:{exc}", "stdout": old.stdout[-4000:], "stderr": old.stderr[-2000:]}

    registry = json.loads(ASSERTIONS.read_text(encoding="utf-8"))
    evals = json.loads(EVALS.read_text(encoding="utf-8"))
    triggers = json.loads(TRIGGERS.read_text(encoding="utf-8"))
    rows = registry.get("assertions", [])
    ids = [item.get("id") for item in rows if isinstance(item, dict)]
    known = {item for item in ids if isinstance(item, str) and item}
    duplicate_ids = sorted({item for item in known if ids.count(item) > 1})
    malformed = [index for index, item in enumerate(rows) if not isinstance(item, dict) or not all(item.get(key) not in (None, "", []) for key in ("id", "target", "pass_if", "required_evidence", "repair"))]

    refs: set[str] = set()
    unknown: set[str] = set()
    for case in list(evals.get("legacy_cases", [])) + list(evals.get("executable_cases", [])):
        if not isinstance(case, dict):
            continue
        for key in ("assertions", "critical_assertions"):
            for assertion_id in case.get(key, []):
                if assertion_id in known:
                    refs.add(assertion_id)
                else:
                    unknown.add(str(assertion_id))
    for case in triggers.get("cases", []):
        if not isinstance(case, dict):
            continue
        for key in ("assertions", "critical_assertions"):
            values = case.get(key, [])
            for item in values:
                assertion_id = item.get("code") if isinstance(item, dict) else item
                if assertion_id in known:
                    refs.add(assertion_id)
                else:
                    unknown.add(str(assertion_id))

    direct = set(prior.get("checks", {}).get("directly_executed_assertions", []))
    covered = refs | direct
    orphans = sorted(known - covered)
    prior_executions = prior.get("executions", [])
    checks = {
        "assertion_count_23": len(rows) == 23 and len(known) == 23,
        "unique_assertions": not duplicate_ids,
        "malformed_assertions": malformed,
        "unknown_refs": sorted(unknown),
        "trigger_assertion_A23_covered": "A23_NO_CANONICAL_MUTATION" in refs,
        "direct_assertions_covered": {"A17_ACCESSIBILITY", "A18_OBSERVABILITY", "A19_IDEMPOTENCY", "A20_PACKAGE_INTEGRITY"}.issubset(direct),
        "orphan_assertions": orphans,
        "legacy_execution_suite_pass": bool(prior_executions) and all(item.get("passed") is True for item in prior_executions),
        "input_sha256": hashlib.sha256(ASSERTIONS.read_bytes()).hexdigest(),
    }
    passed = (
        checks["assertion_count_23"]
        and checks["unique_assertions"]
        and not malformed
        and not unknown
        and checks["trigger_assertion_A23_covered"]
        and checks["direct_assertions_covered"]
        and not orphans
        and checks["legacy_execution_suite_pass"]
    )
    output = {"artifact": "A06", "passed": passed, "checks": checks, "prior_runner_exit_code": old.returncode, "executions": prior_executions}
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
