#!/usr/bin/env python3
"""Structural validator for J00_SCREEN_INGESTION candidate v0.1.

This validator checks blind-read isolation, source-manifest hashing, inventory
referential integrity and known-omission/uncertainty gates. It does not claim
that a visual model actually observed every pixel; real visual runtime remains
a separate promotion requirement.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object, sha256_file

JUDGE = "J00_SCREEN_INGESTION"
VERSION = "v0.1"
ASSERTIONS = (
    "input_schema_valid",
    "source_snapshot_hash_matches",
    "source_images_unique",
    "region_refs_resolvable",
    "inventory_source_refs_unique",
    "blind_context_lock",
    "coverage_complete",
    "no_blocking_uncertainty",
)


def canonical_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def schema_path() -> Path:
    return Path(__file__).resolve().parent.parent / "schemas" / "screen-ingestion.schema.json"


def schema_errors(value: dict[str, Any]) -> tuple[list[str], str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise ValidationInputError("jsonschema_not_available") from exc
    path = schema_path()
    schema = load_json(path)
    jsonschema.Draft7Validator.check_schema(schema)
    validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
    errors = sorted(
        f"{'/'.join(map(str, e.absolute_path)) or '$'}:{e.message}"
        for e in validator.iter_errors(value)
    )
    return errors, sha256_file(path)


def source_manifest(images: list[dict[str, Any]]) -> list[dict[str, Any]]:
    keys = (
        "image_ref", "raw_content_sha256", "width_px", "height_px",
        "format", "viewport_role", "sequence_order",
    )
    return [
        {key: item.get(key) for key in keys}
        for item in sorted(images, key=lambda x: (x.get("sequence_order", 0), str(x.get("image_ref", ""))))
    ]


def evaluate(value: dict[str, Any]) -> tuple[dict[str, int], dict[str, Any]]:
    errors, schema_sha = schema_errors(value)
    images = value.get("source_images") if isinstance(value.get("source_images"), list) else []
    regions = value.get("region_inventory") if isinstance(value.get("region_inventory"), list) else []
    region_refs = {str(x.get("region_ref")) for x in regions if isinstance(x, dict) and x.get("region_ref")}
    image_refs = [str(x.get("image_ref")) for x in images if isinstance(x, dict) and x.get("image_ref")]
    declared_snapshot = str(value.get("source_snapshot_sha") or "")
    computed_snapshot = canonical_sha(source_manifest([x for x in images if isinstance(x, dict)]))

    region_reference_errors = 0
    for region in regions:
        if not isinstance(region, dict) or region.get("image_ref") not in image_refs:
            region_reference_errors += 1
    source_refs: list[str] = []
    inventory_region_errors = 0
    for name in ("context_inventory", "field_inventory"):
        for item in value.get(name) or []:
            if not isinstance(item, dict):
                inventory_region_errors += 1
                continue
            if item.get("region_ref") not in region_refs:
                inventory_region_errors += 1
            ref = str(item.get("source_ref") or "").strip()
            if ref:
                source_refs.append(ref)
    for name in ("permission_inventory", "transition_inventory"):
        for item in value.get(name) or []:
            if isinstance(item, dict):
                ref = str(item.get("source_ref") or "").strip()
                if ref:
                    source_refs.append(ref)

    isolation = value.get("context_isolation") if isinstance(value.get("context_isolation"), dict) else {}
    blind_lock_errors = sum([
        isolation.get("auxiliary_context_before_lock") is not False,
        isolation.get("separate_context_window") is not True,
        isolation.get("action_tools_enabled") is not False,
        isolation.get("network_egress") != "DENY_BY_DEFAULT",
        value.get("locked") is not True,
    ])

    coverage = value.get("coverage_evidence") if isinstance(value.get("coverage_evidence"), dict) else {}
    scanned = set(coverage.get("images_scanned") or [])
    coverage_errors = 0
    if set(image_refs) != scanned:
        coverage_errors += 1
    if coverage.get("full_viewport_scanned") is not True:
        coverage_errors += 1
    if coverage.get("off_viewport_evidence") == "BLOCKED":
        coverage_errors += 1
    if int(coverage.get("omitted_candidate_count") or 0) != 0:
        coverage_errors += int(coverage.get("omitted_candidate_count") or 0)

    critical_uncertainties = sum(
        1 for x in (value.get("uncertainties") or [])
        if isinstance(x, dict) and x.get("critical") is True
    )

    checks = {
        "input_schema_valid": len(errors),
        "source_snapshot_hash_matches": 0 if declared_snapshot == computed_snapshot else 1,
        "source_images_unique": len(image_refs) - len(set(image_refs)),
        "region_refs_resolvable": region_reference_errors + inventory_region_errors,
        "inventory_source_refs_unique": len(source_refs) - len(set(source_refs)),
        "blind_context_lock": blind_lock_errors,
        "coverage_complete": coverage_errors,
        "no_blocking_uncertainty": critical_uncertainties,
    }
    evidence = {
        "input_schema_ref": "schemas/screen-ingestion.schema.json",
        "input_schema_sha256": schema_sha,
        "schema_validation_errors": errors,
        "declared_source_snapshot_sha": declared_snapshot,
        "computed_source_snapshot_sha": computed_snapshot,
        "image_count": len(images),
        "region_count": len(regions),
        "context_count": len(value.get("context_inventory") or []),
        "field_count": len(value.get("field_inventory") or []),
        "permission_count": len(value.get("permission_inventory") or []),
        "transition_count": len(value.get("transition_inventory") or []),
        "visual_runtime_proven": False,
        "validation_scope": "STRUCTURAL_CONTRACT_ONLY",
        "checks": checks,
    }
    return checks, evidence


def build(value: Any, refs: list[str], input_path: str | None, input_sha: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        blockers = ["required_input_missing"]
        evidence = {"checks": {}, "input_path": input_path, "input_sha256": input_sha}
        return result_object(
            JUDGE, [], evidence, refs, [], blockers,
            judge_version=VERSION, executor_identity="J00_STRUCTURAL_VALIDATOR",
            command=" ".join(sys.argv),
        )
    checks, evidence = evaluate(value)
    evidence["input_path"] = input_path
    evidence["input_sha256"] = input_sha
    repairs = [
        failure(key, f"$.{key}", f"Repair screen ingestion until {key}=0 without weakening the blind-read contract.")
        for key, result in checks.items() if result
    ]
    return result_object(
        JUDGE,
        [key for key, result in checks.items() if result],
        evidence,
        refs,
        repairs,
        judge_version=VERSION,
        executor_identity="J00_STRUCTURAL_VALIDATOR",
        command=" ".join(sys.argv),
    )


def positive_fixture() -> dict[str, Any]:
    image = {
        "image_ref": "IMG-SELF", "raw_content_sha256": "1" * 64,
        "width_px": 1000, "height_px": 1600, "format": "PNG",
        "viewport_role": "FULL", "sequence_order": 1,
    }
    snapshot = canonical_sha(source_manifest([image]))
    return {
        "schema_version": "screen-ingestion/v0.1",
        "screen_code": "SCR-SELF-TEST", "source_version": "self-v1",
        "evidence_kind": "SYNTHETIC_FIXTURE", "source_images": [image],
        "source_snapshot_sha": snapshot, "blind_read_id": "BLIND-SELF-001",
        "execution_id": "EXEC-J00-SELF-001", "reader_identity": "SELF_TEST_READER",
        "context_isolation": {
            "auxiliary_context_before_lock": False, "separate_context_window": True,
            "action_tools_enabled": False, "network_egress": "DENY_BY_DEFAULT",
        },
        "region_inventory": [{
            "region_ref": "REG-SELF", "image_ref": "IMG-SELF",
            "bbox": [0, 0, 1000, 1600], "description": "Full screen", "confidence": 1.0,
        }],
        "context_inventory": [{
            "code": "CTX-SELF", "description": "Self-test context",
            "source_ref": "IMG-SELF#CTX", "region_ref": "REG-SELF", "confidence": 1.0,
        }],
        "field_inventory": [{
            "code": "FLD-SELF", "context_code": "CTX-SELF", "source_ref": "IMG-SELF#FIELD",
            "region_ref": "REG-SELF", "control_type": "TEXT_INPUT", "visible_label": "Input",
            "conditionally_visible": False, "confidence": 1.0,
        }],
        "permission_inventory": [], "transition_inventory": [],
        "coverage_evidence": {
            "images_scanned": ["IMG-SELF"], "full_viewport_scanned": True,
            "off_viewport_evidence": "NOT_APPLICABLE", "omitted_candidate_count": 0,
        },
        "uncertainties": [], "locked": True, "locked_at": "2026-08-09T20:30:00Z",
    }


def self_test() -> int:
    good = positive_fixture()
    cases = []
    for name, mutate, expected in (
        ("positive", lambda x: None, "PASS_WITH_EVIDENCE"),
        ("bad_source_hash", lambda x: x.__setitem__("source_snapshot_sha", "0" * 64), "RETURN_TO_WORKER"),
        ("aux_context_before_lock", lambda x: x["context_isolation"].__setitem__("auxiliary_context_before_lock", True), "RETURN_TO_WORKER"),
        ("critical_uncertainty", lambda x: x["uncertainties"].append({"uncertainty_code":"U-1","critical":True,"description":"Critical unknown","source_ref":"IMG-SELF#U"}), "RETURN_TO_WORKER"),
    ):
        payload = copy.deepcopy(good)
        mutate(payload)
        out = build(payload, [f"self-test://{name}"], None, canonical_sha(payload))
        cases.append({"name": name, "result": out["result"], "passed": out["result"] == expected})
    ok = all(x["passed"] for x in cases)
    print(json.dumps({"judge_code": JUDGE, "self_test_pass": ok, "cases": cases}, sort_keys=True))
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--evidence-ref", action="append", default=[])
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        raise ValidationInputError("input_required")
    payload = load_json(args.input)
    return emit(build(payload, args.evidence_ref, str(args.input), sha256_file(args.input)))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, main))
