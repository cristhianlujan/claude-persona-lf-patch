#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

EXPECTED_SUITES = {
    "TS-STRATEGY-FINANCIAL-V1": "FINANCIAL_DECISION",
    "TS-STRATEGY-HIGH-RISK-V1": "HIGH_RISK",
    "TS-STRATEGY-MODEL-HOLDOUT-V1": "USES_MODEL",
}


def analyze(payload: dict[str, Any]) -> dict[str, Any]:
    bindings = payload.get("active_requirement_bindings") or []
    observed: dict[str, str] = {}
    findings: list[str] = []

    for row in bindings:
        suite = row.get("suite_code")
        characteristic = row.get("characteristic_code")
        if row.get("independent_review_required") is not True:
            findings.append(f"BINDING_NOT_INDEPENDENT:{suite}")
            continue
        if not isinstance(suite, str) or not isinstance(characteristic, str):
            findings.append("BINDING_IDENTITY_INVALID")
            continue
        if suite in observed:
            findings.append(f"DUPLICATE_SUITE_BINDING:{suite}")
        observed[suite] = characteristic

    for suite, characteristic in EXPECTED_SUITES.items():
        if observed.get(suite) != characteristic:
            findings.append(f"EXPECTED_BINDING_MISSING_OR_MISMATCH:{suite}:{characteristic}")

    pattern = payload.get("suite_case_pattern") or {}
    if pattern.get("test_code") != "A03":
        findings.append("INDEPENDENT_CASE_CODE_DRIFT")
    if pattern.get("execution_mode") != "INDEPENDENT_REVIEW":
        findings.append("INDEPENDENT_EXECUTION_MODE_DRIFT")
    if pattern.get("probe_code") != "INDEPENDENT_REVIEW":
        findings.append("INDEPENDENT_PROBE_DRIFT")

    return {
        "status": "PASS" if not findings else "BLOCKED",
        "binding_count": len(bindings),
        "observed_suites": observed,
        "findings": findings,
        "authority_model": "REQUIREMENT_BINDING_PLUS_SUITE_CASE",
        "review_case_authoritative": False,
    }


def main() -> int:
    here = Path(__file__).resolve().parent
    payload = json.loads((here / "live_independent_review_inventory_20260914.json").read_text(encoding="utf-8"))
    result = analyze(payload)
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
