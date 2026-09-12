"""Deterministic source-integrity validator for J01_SOURCE_INTEGRITY."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object

JUDGE = "J01_SOURCE_INTEGRITY"
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
    required = ("source_snapshot", "source_references", "classification_ledger", "target_source_version")
    missing = [key for key in required if key not in payload]
    if missing:
        raise ValidationInputError("source_integrity_required_inputs_missing:" + ",".join(missing))

    snap = obj(payload["source_snapshot"], "source_snapshot")
    refs = arr(payload["source_references"], "source_references")
    ledger = arr(payload["classification_ledger"], "classification_ledger")
    if not refs:
        raise ValidationInputError("source_references_empty")
    if not ledger:
        raise ValidationInputError("classification_ledger_empty")

    content = non_empty_text(snap.get("content"), "source_snapshot.content")
    source_version = non_empty_text(snap.get("source_version"), "source_snapshot.source_version")
    target_version = non_empty_text(payload["target_source_version"], "target_source_version")
    declared = snap.get("sha256")
    actual = hashlib.sha256(content.encode()).hexdigest()

    checks = {
        "source_snapshot_sha_present": 0 if isinstance(declared, str) and SHA256_RE.fullmatch(declared) else 1,
        "source_version_matches_target": 0 if source_version == target_version else 1,
        "source_references_resolvable": sum(
            1
            for ref in refs
            if not isinstance(ref, dict)
            or not str(ref.get("ref", "")).strip()
            or ref.get("resolved") is not True
        ),
        "source_hash_mismatches": 0 if declared == actual else 1,
        "confirmed_rules_without_literal_source": sum(
            1
            for item in ledger
            if isinstance(item, dict)
            and item.get("classification") == "CONFIRMED"
            and not str(item.get("source_ref", "")).strip()
        ),
        "inferred_rules_without_label": sum(
            1
            for item in ledger
            if isinstance(item, dict)
            and item.get("inferred") is True
            and item.get("classification") != "INFERRED"
        ),
        "blocked_items_without_reason": sum(
            1
            for item in ledger
            if isinstance(item, dict)
            and item.get("classification") == "BLOCKED"
            and not str(item.get("blocked_reason", "")).strip()
        ),
    }
    evidence = {
        "checks": checks,
        "source_snapshot_sha": declared,
        "computed_sha": actual,
        "source_version": source_version,
        "target_source_version": target_version,
        "source_reference_resolution_count": len(refs) - checks["source_references_resolvable"],
        "source_reference_count": len(refs),
        "classification_ledger_count": len(ledger),
        "classification_counts": {
            classification: sum(
                1
                for item in ledger
                if isinstance(item, dict) and item.get("classification") == classification
            )
            for classification in ("CONFIRMED", "INFERRED", "PROPOSED", "BLOCKED")
        },
    }
    return checks, evidence


def run(path: Path, refs: list[str], retry: int) -> int:
    payload = obj(load_json(path), "input")
    checks, evidence = validate_payload(payload)
    evidence["input_path"] = str(path)
    failed = [key for key, value in checks.items() if value]
    repairs = [failure(key, f"$.evidence.checks.{key}", f"Repair source integrity until {key}=0") for key in failed]
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


def self_test() -> int:
    content = "canonical source"
    sha = hashlib.sha256(content.encode()).hexdigest()
    good = {
        "source_snapshot": {"content": content, "sha256": sha, "source_version": "v1"},
        "target_source_version": "v1",
        "source_references": [{"ref": "S1", "resolved": True}],
        "classification_ledger": [{"classification": "CONFIRMED", "source_ref": "S1"}],
    }
    bad = json.loads(json.dumps(good))
    bad["source_snapshot"]["sha256"] = "0" * 64
    bad["source_references"][0]["resolved"] = False
    positive_checks, _ = validate_payload(good)
    negative_checks, _ = validate_payload(bad)
    blocked_cases: dict[str, bool] = {}
    for name, payload in {
        "missing_target_version": {key: value for key, value in good.items() if key != "target_source_version"},
        "empty_references": {**good, "source_references": []},
        "empty_ledger": {**good, "classification_ledger": []},
        "empty_content": {**good, "source_snapshot": {**good["source_snapshot"], "content": ""}},
    }.items():
        try:
            validate_payload(payload)
            blocked_cases[name] = False
        except ValidationInputError:
            blocked_cases[name] = True
    output = {
        "positive_pass": all(value == 0 for value in positive_checks.values()),
        "negative_rejected": negative_checks["source_hash_mismatches"] > 0 and negative_checks["source_references_resolvable"] > 0,
        "blocked_cases": blocked_cases,
        "positive_checks": positive_checks,
        "negative_checks": negative_checks,
    }
    print(json.dumps(output, sort_keys=True))
    return 0 if output["positive_pass"] and output["negative_rejected"] and all(blocked_cases.values()) else 1


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
