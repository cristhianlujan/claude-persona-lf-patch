"""Deterministic semantic validator for J02_SCREEN_DECOMPOSITION."""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object

JUDGE = "J02_SCREEN_DECOMPOSITION"
VERSION = "v0.6"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def obj(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationInputError(f"{name}_must_be_object")
    return value


def arr(value: Any, name: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValidationInputError(f"{name}_must_be_array")
    return value


def non_empty_text(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValidationInputError(f"{name}_must_be_non_empty_string")
    return value


def validate_payload(payload: dict[str, Any]) -> tuple[dict[str, int], dict[str, Any]]:
    if "target_screen_code" not in payload or "screen_decomposition" not in payload:
        raise ValidationInputError("screen_decomposition_required_inputs_missing")
    target = non_empty_text(payload["target_screen_code"], "target_screen_code")
    dec = obj(payload["screen_decomposition"], "screen_decomposition")
    non_empty_text(dec.get("screen_code"), "screen_decomposition.screen_code")
    non_empty_text(dec.get("source_version"), "screen_decomposition.source_version")
    non_empty_text(dec.get("main_responsibility"), "screen_decomposition.main_responsibility")

    contexts = arr(dec.get("context_inventory"), "context_inventory")
    fields = arr(dec.get("field_inventory"), "field_inventory")
    permissions = arr(dec.get("permission_inventory"), "permission_inventory")
    transitions = arr(dec.get("transition_inventory"), "transition_inventory")
    units = arr(dec.get("functional_units"), "functional_units")
    coverage = arr(dec.get("coverage_items"), "coverage_items")
    summary = obj(dec.get("coverage_summary"), "coverage_summary")
    if not units:
        raise ValidationInputError("functional_units_empty")
    if not coverage:
        raise ValidationInputError("coverage_items_empty")

    statuses = [str(item.get("mapping_status")) for item in coverage if isinstance(item, dict)]
    codes = [str(item.get("functional_unit_code", "")).strip() for item in units if isinstance(item, dict)]
    valid_codes = {code for code in codes if code}
    source_types = [str(item.get("source_type", "")) for item in coverage if isinstance(item, dict)]

    calculated = {
        "source_items_count": len(coverage),
        "mapped_count": statuses.count("MAPPED"),
        "justified_count": statuses.count("JUSTIFIED_OUT"),
        "unmapped_count": sum(1 for status in statuses if status not in {"MAPPED", "JUSTIFIED_OUT"}),
        "unjustified_count": sum(
            1
            for item in coverage
            if isinstance(item, dict)
            and item.get("mapping_status") == "JUSTIFIED_OUT"
            and not str(item.get("justification", "")).strip()
        ),
        "conflicting_count": statuses.count("CONFLICT"),
        "duplicate_functional_units_count": len([code for code in codes if code]) - len(valid_codes),
    }
    summary_fields = tuple(calculated)
    mismatched_summary_fields = [field for field in summary_fields if summary.get(field) != calculated[field]]

    mapped_unknown = 0
    for item in coverage:
        if not isinstance(item, dict) or item.get("mapping_status") != "MAPPED":
            continue
        mapped_to = item.get("mapped_to")
        if not isinstance(mapped_to, list) or not mapped_to:
            mapped_unknown += 1
            continue
        if any(not isinstance(code, str) or code not in valid_codes for code in mapped_to):
            mapped_unknown += 1

    checks = {
        "source_snapshot_sha_present": 0 if isinstance(dec.get("source_snapshot_sha"), str) and SHA256_RE.fullmatch(dec["source_snapshot_sha"]) else 1,
        "source_screen_code_matches_target": 0 if dec.get("screen_code") == target else 1,
        "context_coverage": max(len(contexts) - source_types.count("CONTEXT"), 0),
        "permission_coverage": max(len(permissions) - source_types.count("PERMISSION"), 0),
        "transition_coverage": max(len(transitions) - source_types.count("TRANSITION"), 0),
        "unmapped_count": calculated["unmapped_count"],
        "unjustified_count": calculated["unjustified_count"],
        "conflicting_count": calculated["conflicting_count"],
        "duplicate_functional_units": calculated["duplicate_functional_units_count"],
        "functional_units_without_code": sum(1 for code in codes if not code),
        "functional_units_complete": sum(
            1
            for item in units
            if not isinstance(item, dict)
            or not all(str(item.get(key, "")).strip() for key in ("actor", "goal", "observable_output"))
        ),
        "coverage_mapped_to_unknown_functional_unit": mapped_unknown,
        "confirmed_rules_have_source": sum(
            1
            for item in units
            if isinstance(item, dict)
            and item.get("classification") == "CONFIRMED"
            and not str(item.get("source_ref", "")).strip()
        ),
        "coverage_summary_mismatch": len(mismatched_summary_fields),
    }
    evidence = {
        "checks": checks,
        "calculated_summary": calculated,
        "declared_summary": summary,
        "mismatched_summary_fields": mismatched_summary_fields,
        "target_screen_code": target,
        "source_version": dec.get("source_version"),
        "main_responsibility": dec.get("main_responsibility"),
        "context_count": len(contexts),
        "field_count": len(fields),
        "permission_count": len(permissions),
        "transition_count": len(transitions),
        "functional_units_count": len(units),
        "coverage_items_count": len(coverage),
    }
    return checks, evidence


def run(path: Path, refs: list[str], retry: int) -> int:
    payload = obj(load_json(path), "input")
    checks, evidence = validate_payload(payload)
    evidence["input_path"] = str(path)
    failed = [key for key, value in checks.items() if value]
    repairs = [failure(key, f"$.evidence.checks.{key}", f"Repair decomposition until {key}=0") for key in failed]
    return emit(result_object(
        JUDGE,
        failed,
        evidence,
        refs or [f"file:{path}"],
        repairs,
        retry_count=retry,
        judge_version=os.getenv("LF_JUDGE_VERSION"),
        executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),
    ))


def positive() -> dict[str, Any]:
    return {
        "target_screen_code": "SCR-X",
        "screen_decomposition": {
            "screen_code": "SCR-X",
            "source_version": "v1",
            "source_snapshot_sha": "a" * 64,
            "main_responsibility": "Manage customer search",
            "context_inventory": [{"code": "CTX-SEARCH", "description": "search", "source_ref": "SRC-CONTEXT-001"}],
            "field_inventory": [],
            "permission_inventory": [{"permission_code": "PERM-SEARCH", "actor_profile": "OPERATOR", "action_code": "SEARCH", "source_ref": "SRC-PERMISSION-001"}],
            "transition_inventory": [{"from": "IDLE", "action": "SEARCH", "to": "RESULTS", "allowed": True, "source_ref": "SRC-TRANSITION-001"}],
            "functional_units": [{"functional_unit_code": "FU-X", "actor": "Operator", "goal": "search customer", "trigger": "submit", "observable_output": "customer result", "risk_level": "LOW", "decision": "CREATE_STORY", "justification": "independent result", "source_ref": "SRC-FUNCTION-001", "classification": "CONFIRMED"}],
            "coverage_items": [
                {"source_item_code": "ITEM-CONTEXT-001", "source_type": "CONTEXT", "source_ref": "SRC-CONTEXT-001", "mapping_status": "MAPPED", "mapped_to": ["FU-X"], "justification": "mapped"},
                {"source_item_code": "ITEM-PERMISSION-001", "source_type": "PERMISSION", "source_ref": "SRC-PERMISSION-001", "mapping_status": "MAPPED", "mapped_to": ["FU-X"], "justification": "mapped"},
                {"source_item_code": "ITEM-TRANSITION-001", "source_type": "TRANSITION", "source_ref": "SRC-TRANSITION-001", "mapping_status": "MAPPED", "mapped_to": ["FU-X"], "justification": "mapped"},
            ],
            "coverage_summary": {"source_items_count": 3, "mapped_count": 3, "justified_count": 0, "unmapped_count": 0, "unjustified_count": 0, "conflicting_count": 0, "duplicate_functional_units_count": 0},
            "pending_decisions": [],
        },
    }


def self_test() -> int:
    good = positive()
    bad = json.loads(json.dumps(good))
    bad["screen_decomposition"]["coverage_items"][0]["mapping_status"] = "PENDING"
    bad["screen_decomposition"]["functional_units"].append(dict(bad["screen_decomposition"]["functional_units"][0]))
    positive_checks, _ = validate_payload(good)
    negative_checks, negative_evidence = validate_payload(bad)
    unknown = json.loads(json.dumps(good))
    unknown["screen_decomposition"]["coverage_items"][0]["mapped_to"] = ["FU-UNKNOWN"]
    unknown_checks, _ = validate_payload(unknown)
    blocked_cases: dict[str, bool] = {}
    for name, payload in {
        "missing_target": {"screen_decomposition": good["screen_decomposition"]},
        "empty_units": {**good, "screen_decomposition": {**good["screen_decomposition"], "functional_units": []}},
        "empty_coverage": {**good, "screen_decomposition": {**good["screen_decomposition"], "coverage_items": []}},
        "missing_main_responsibility": {**good, "screen_decomposition": {key: value for key, value in good["screen_decomposition"].items() if key != "main_responsibility"}},
    }.items():
        try:
            validate_payload(payload)
            blocked_cases[name] = False
        except ValidationInputError:
            blocked_cases[name] = True
    output = {
        "positive_pass": all(value == 0 for value in positive_checks.values()),
        "negative_rejected": negative_checks["unmapped_count"] > 0 and negative_checks["duplicate_functional_units"] > 0 and negative_checks["coverage_summary_mismatch"] > 0,
        "unknown_mapping_rejected": unknown_checks["coverage_mapped_to_unknown_functional_unit"] > 0,
        "blocked_cases": blocked_cases,
        "positive_checks": positive_checks,
        "negative_checks": negative_checks,
        "negative_mismatched_summary_fields": negative_evidence["mismatched_summary_fields"],
    }
    print(json.dumps(output, sort_keys=True))
    return 0 if output["positive_pass"] and output["negative_rejected"] and output["unknown_mapping_rejected"] and all(blocked_cases.values()) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--evidence-ref", action="append", default=[])
    parser.add_argument("--retry-count", type=int, default=0)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        raise ValidationInputError("input_required")
    return run(args.input, args.evidence_ref, args.retry_count)


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, main))
