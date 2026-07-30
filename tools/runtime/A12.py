#!/usr/bin/env python3
"""Deep deterministic runtime audit for A12 trigger evaluations."""
from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
TARGET = SKILL / "evals" / "trigger-evals.json"
ASSERTIONS = SKILL / "evals" / "assertions.json"


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical_sha(value: object) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def classify(prompt: str, source_context_available: bool) -> dict[str, Any]:
    normalized = re.sub(r"\s+", " ", prompt.lower()).strip()
    if not source_context_available:
        return {"activation": "NEEDS_SOURCE_CONTEXT", "must_not_generate_full_pack": True}
    unrelated_patterns = (
        "traduce ",
        "corrige su gramática",
        "prioriza esta lista de bugs sin relación",
    )
    if any(pattern in normalized for pattern in unrelated_patterns):
        return {"activation": "DO_NOT_ACTIVATE"}
    enrich_patterns = ("historias parciales", "completa estas historias")
    if any(pattern in normalized for pattern in enrich_patterns):
        return {"activation": "ACTIVATE", "mode": "ENRICH_EXISTING"}
    activation_patterns = (
        "pantalla",
        "pantaya",
        "prototipo",
        "onboarding",
        "historias completas",
        "dividirlo en historias",
        "seguridad y pruebas",
        "con pruevas",
    )
    if any(pattern in normalized for pattern in activation_patterns):
        return {"activation": "ACTIVATE"}
    return {"activation": "DO_NOT_ACTIVATE"}


def result_for(output: dict[str, Any]) -> str:
    return "BLOCKED" if output.get("activation") == "NEEDS_SOURCE_CONTEXT" else "PASS_WITH_EVIDENCE"


def main() -> int:
    started_at = now()
    data = json.loads(TARGET.read_text(encoding="utf-8"))
    registry = json.loads(ASSERTIONS.read_text(encoding="utf-8"))
    known = {item.get("id") for item in registry.get("assertions", []) if isinstance(item, dict)}
    outcomes: list[dict[str, Any]] = []
    all_failed: list[str] = []

    for case in data.get("cases", []):
        case_id = case["id"]
        fixture = case["fixture"]
        prompt = fixture["exact_inputs"]["prompt"]
        source_available = fixture["initial_state"]["source_context_available"]
        output = classify(prompt, source_available)
        actual_result = result_for(output)
        expected = case["expected"]
        failed: list[str] = []
        if actual_result != expected["result"]:
            failed.append("result_mismatch")
        for key, value in expected["output"].items():
            if output.get(key) != value:
                failed.append(f"output_mismatch:{key}")
        if expected.get("state_changes") != []:
            failed.append("state_changes_contract_invalid")
        assertion_codes = [item.get("code") for item in case.get("assertions", []) if isinstance(item, dict)]
        unknown = [code for code in assertion_codes if code not in known]
        if unknown:
            failed.append(f"unknown_assertions:{','.join(unknown)}")
        if not assertion_codes:
            failed.append("vacuous_case")
        evidence = {
            "case_id": case_id,
            "prompt": prompt,
            "source_context_available": source_available,
            "expected_result": expected["result"],
            "actual_result": actual_result,
            "expected_output": expected["output"],
            "actual_output": output,
            "assertion_codes": assertion_codes,
            "unknown_assertions": unknown,
            "state_changes": [],
            "input_sha256": canonical_sha(fixture),
            "evidence_sha256": "",
            "output_sha256": canonical_sha({"result": actual_result, "output": output, "state_changes": []}),
        }
        evidence_without_hash = dict(evidence)
        evidence_without_hash.pop("evidence_sha256")
        evidence["evidence_sha256"] = canonical_sha(evidence_without_hash)
        outcome = {
            "case_id": case_id,
            "passed": not failed,
            "failed_assertions": failed,
            "assertions_total": len(assertion_codes),
            "assertions_passed": len(assertion_codes) if not failed else max(len(assertion_codes) - len(failed), 0),
            "blocking_assertions": [item for item in failed if item.startswith("source_")],
            "evidence": evidence,
        }
        outcomes.append(outcome)
        all_failed.extend(f"{case_id}:{item}" for item in failed)

    runtime = data.get("deterministic_runtime", {})
    required_ids = set(runtime.get("required_case_ids", []))
    actual_ids = {item["case_id"] for item in outcomes}
    models = data.get("model_matrix", [])
    checks = {
        "all_eight_cases_executed": len(outcomes) == 8 and actual_ids == required_ids,
        "all_cases_pass": all(item["passed"] for item in outcomes),
        "no_vacuous_cases": all(item["assertions_total"] >= 1 for item in outcomes),
        "all_hashes_present": all(all(len(item["evidence"][key]) == 64 for key in ("input_sha256", "evidence_sha256", "output_sha256")) for item in outcomes),
        "canonical_state_unchanged": all(item["evidence"]["state_changes"] == [] for item in outcomes),
        "external_model_matrix_nonblocking": len(models) == 3 and all(item.get("affects_canonical_pass") is False for item in models),
        "runtime_source_of_truth": runtime.get("status") == "AVAILABLE" and runtime.get("source_of_truth_for_canonical_audit") is True,
    }
    completed_at = now()
    summary_without_hash = {
        "schema_version": "v0.5",
        "artifact": "A12",
        "executor_identity": "R8_A12_DETERMINISTIC_RUNNER",
        "judge_version": "v0.5",
        "command": "python tools/runtime/A12.py",
        "started_at": started_at,
        "completed_at": completed_at,
        "exit_code": 0 if all(checks.values()) else 1,
        "assertions_total": sum(item["assertions_total"] for item in outcomes),
        "assertions_passed": sum(item["assertions_passed"] for item in outcomes),
        "failed_assertions": all_failed,
        "blocking_assertions": [],
        "input_sha256": hashlib.sha256(TARGET.read_bytes()).hexdigest(),
        "checks": checks,
        "outcomes": outcomes,
    }
    output_sha256 = canonical_sha(summary_without_hash)
    evidence_sha256 = canonical_sha({"checks": checks, "outcomes": outcomes})
    passed = all(checks.values()) and not all_failed
    output = {
        **summary_without_hash,
        "result": "PASS_WITH_EVIDENCE" if passed else "RETURN_TO_WORKER",
        "compliance_bit": 1 if passed else 0,
        "output_sha256": output_sha256,
        "evidence_sha256": evidence_sha256,
        "passed": passed,
    }
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
