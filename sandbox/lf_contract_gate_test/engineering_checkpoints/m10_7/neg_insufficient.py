#!/usr/bin/env python3
"""M10.7 NEG_INSUFFICIENT exact negative verifier.

Proves that an observation window below any canonical M9.11 soak threshold
cannot close M10.7. The test is deterministic, read-only and fail-closed.

Material authority is the verified SOAK_OBSERVATION_HISTORY_V2 receipt.
Execution evidence is supplied by the governed GPT Native current context.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Any

TEST_CODE = "ENG_M10_7_NEG_INSUFFICIENT"
SUITE_CODE = "INPUT_GOVERNANCE_REGRESSION"
INPUT_SCHEMA = "M10_7_NEG_INSUFFICIENT_INPUT_V1"
RESULT_SCHEMA = "M10_7_NEG_INSUFFICIENT_RESULT_V1"
RECEIPT_SCHEMA = "SOAK_OBSERVATION_HISTORY_V2"
RECEIPT_SHA256 = "17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972"

MIN_SCREENS = 13
MIN_FAMILIES = 47
MIN_OBSERVATIONS = 2
MAX_TIMEOUTS = 0
MAX_FALSE_PASS = 0
MAX_D4 = 0


class EvidenceError(ValueError):
    pass


def _as_int(value: Any, field: str) -> int:
    if isinstance(value, bool):
        raise EvidenceError(f"{field}:bool_not_int")
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise EvidenceError(f"{field}:invalid_int") from exc


def _validate_receipt(receipt: dict[str, Any]) -> dict[str, Any]:
    if receipt.get("receipt_sha256") != RECEIPT_SHA256:
        raise EvidenceError("receipt:sha256")
    payload = receipt.get("payload")
    if not isinstance(payload, dict):
        raise EvidenceError("receipt:payload")
    expected = {
        "schema_version": RECEIPT_SCHEMA,
        "verification_status": "VERIFIED",
        "pass": True,
        "screens_total": MIN_SCREENS,
        "families_total": MIN_FAMILIES,
        "screens_below_2": 0,
        "families_below_2": 0,
        "known_false_pass_signals": 0,
        "unresolved_d4": 0,
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            raise EvidenceError(f"receipt:{key}")
    if _as_int(payload.get("min_screen_observations"), "receipt:min_screen_observations") < MIN_OBSERVATIONS:
        raise EvidenceError("receipt:min_screen_observations")
    if _as_int(payload.get("min_family_observations"), "receipt:min_family_observations") < MIN_OBSERVATIONS:
        raise EvidenceError("receipt:min_family_observations")
    return payload


def can_close_soak(window: dict[str, Any]) -> bool:
    required = (
        "screens_covered",
        "families_covered",
        "min_screen_observations",
        "min_family_observations",
        "known_false_pass_signals",
        "unresolved_d4",
        "timeout_over_150s_count",
    )
    if any(key not in window for key in required):
        return False
    try:
        return (
            _as_int(window["screens_covered"], "window:screens_covered") >= MIN_SCREENS
            and _as_int(window["families_covered"], "window:families_covered") >= MIN_FAMILIES
            and _as_int(window["min_screen_observations"], "window:min_screen_observations") >= MIN_OBSERVATIONS
            and _as_int(window["min_family_observations"], "window:min_family_observations") >= MIN_OBSERVATIONS
            and _as_int(window["known_false_pass_signals"], "window:known_false_pass_signals") <= MAX_FALSE_PASS
            and _as_int(window["unresolved_d4"], "window:unresolved_d4") <= MAX_D4
            and _as_int(window["timeout_over_150s_count"], "window:timeout_over_150s_count") <= MAX_TIMEOUTS
        )
    except EvidenceError:
        return False


def _positive_from_receipt(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "screens_covered": _as_int(payload["screens_total"], "receipt:screens_total"),
        "families_covered": _as_int(payload["families_total"], "receipt:families_total"),
        "min_screen_observations": _as_int(payload["min_screen_observations"], "receipt:min_screen_observations"),
        "min_family_observations": _as_int(payload["min_family_observations"], "receipt:min_family_observations"),
        "known_false_pass_signals": _as_int(payload["known_false_pass_signals"], "receipt:known_false_pass_signals"),
        "unresolved_d4": _as_int(payload["unresolved_d4"], "receipt:unresolved_d4"),
        "timeout_over_150s_count": 0,
    }


def _negative_cases(positive: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    specs = [
        ("screen_coverage", "screens_covered", MIN_SCREENS - 1),
        ("family_coverage", "families_covered", MIN_FAMILIES - 1),
        ("screen_observation_depth", "min_screen_observations", MIN_OBSERVATIONS - 1),
        ("family_observation_depth", "min_family_observations", MIN_OBSERVATIONS - 1),
        ("known_false_pass", "known_false_pass_signals", 1),
        ("unresolved_d4", "unresolved_d4", 1),
        ("timeout_over_150s", "timeout_over_150s_count", 1),
    ]
    cases: list[tuple[str, dict[str, Any]]] = []
    for name, field, value in specs:
        candidate = copy.deepcopy(positive)
        candidate[field] = value
        cases.append((name, candidate))
    missing = copy.deepcopy(positive)
    missing.pop("screens_covered")
    cases.append(("missing_required_coverage_field", missing))
    return cases


def adjudicate(data: dict[str, Any]) -> dict[str, Any]:
    if data.get("schema_version") != INPUT_SCHEMA:
        raise EvidenceError("input:schema_version")
    receipt = data.get("historical_receipt")
    if not isinstance(receipt, dict):
        raise EvidenceError("input:historical_receipt")

    payload = _validate_receipt(receipt)
    positive = _positive_from_receipt(payload)
    if not can_close_soak(positive):
        raise EvidenceError("positive_control_rejected")

    rejected: list[str] = []
    for name, candidate in _negative_cases(positive):
        if can_close_soak(candidate):
            raise EvidenceError(f"negative_false_close:{name}")
        rejected.append(name)

    return {
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "adversarial_case_executed": True,
        "positive_control_admitted": True,
        "insufficient_window_rejected": True,
        "negative_cases_executed": len(rejected),
        "negative_cases_rejected": rejected,
        "historical_receipt_sha256": RECEIPT_SHA256,
        "thresholds": {
            "min_screens": MIN_SCREENS,
            "min_families": MIN_FAMILIES,
            "min_observations": MIN_OBSERVATIONS,
            "max_false_pass": MAX_FALSE_PASS,
            "max_unresolved_d4": MAX_D4,
            "max_timeout_over_150s": MAX_TIMEOUTS,
        },
    }


def _fixture() -> dict[str, Any]:
    return {
        "schema_version": INPUT_SCHEMA,
        "historical_receipt": {
            "receipt_sha256": RECEIPT_SHA256,
            "payload": {
                "schema_version": RECEIPT_SCHEMA,
                "verification_status": "VERIFIED",
                "pass": True,
                "screens_total": 13,
                "families_total": 47,
                "screens_below_2": 0,
                "families_below_2": 0,
                "min_screen_observations": 4,
                "min_family_observations": 189,
                "known_false_pass_signals": 0,
                "unresolved_d4": 0,
            },
        },
    }


def self_test() -> None:
    observed = adjudicate(_fixture())
    assert observed["test_passed"] is True
    assert observed["test_exit_code"] == 0
    assert observed["adversarial_case_executed"] is True
    assert observed["insufficient_window_rejected"] is True
    assert observed["negative_cases_executed"] == 8


def _load(path: str) -> dict[str, Any]:
    if path == "-":
        value = json.load(sys.stdin)
    else:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise EvidenceError("input:not_object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--input")
    parser.add_argument("--evidence-ref")
    parser.add_argument("--output")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        print("PASS_LOGIC_SELF_TEST_ONLY material_pass=false checkpoint_done=false")
        return 0

    if not args.input:
        parser.error("--input is required outside --self-test")
    if not args.evidence_ref or not args.evidence_ref.strip():
        print(json.dumps({
            "schema_version": RESULT_SCHEMA,
            "status": "BLOCKED",
            "test_code": TEST_CODE,
            "reason": "GPT_NATIVE_EVIDENCE_REF_REQUIRED",
        }, sort_keys=True, separators=(",", ":")))
        return 2

    try:
        observed = adjudicate(_load(args.input))
        result = {
            "schema_version": RESULT_SCHEMA,
            "status": "PASS",
            "suite_code": SUITE_CODE,
            "test_code": TEST_CODE,
            "evidence_ref": args.evidence_ref.strip(),
            "observed": observed,
        }
        code = 0
    except (EvidenceError, json.JSONDecodeError, OSError) as exc:
        result = {
            "schema_version": RESULT_SCHEMA,
            "status": "FAIL",
            "suite_code": SUITE_CODE,
            "test_code": TEST_CODE,
            "evidence_ref": args.evidence_ref.strip(),
            "reason": str(exc),
            "observed": {
                "test_passed": False,
                "test_exit_code": 2,
                "semantic_authority_bound": False,
                "adversarial_case_executed": False,
            },
        }
        code = 2

    rendered = json.dumps(result, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    if args.output:
        Path(args.output).write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
