#!/usr/bin/env python3
"""Semantic validator for J02_SCREEN_DECOMPOSITION v0.8 maturity candidate.

v0.8 preserves the v0.7 decomposition checks and adds an independent locked
screen-ingestion input. Completeness is measured against that ingestion rather
than only against the decomposition's self-declared inventories.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object, sha256_file

JUDGE = "J02_SCREEN_DECOMPOSITION"
VERSION = "v0.8"
REGISTRATION = "candidate://creating-integral-user-stories/ART_SCRIPT_VALIDATE_SCREEN_DECOMPOSITION_V08"
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
ASSERTIONS = (
    "input_schema_valid",
    "ingestion_schema_valid",
    "source_snapshot_sha_present",
    "source_screen_code_matches_target",
    "ingestion_screen_code_matches_target",
    "ingestion_source_snapshot_hash_matches",
    "ingestion_locked",
    "inventory_complete_vs_ingestion",
    "context_coverage",
    "field_coverage",
    "permission_coverage",
    "transition_coverage",
    "unmapped_count",
    "unjustified_count",
    "conflicting_count",
    "duplicate_functional_units",
    "functional_units_complete",
    "functional_units_without_code",
    "coverage_mapped_to_unknown_functional_unit",
    "confirmed_rules_have_source",
    "coverage_summary_mismatch",
    "blocking_pending_decisions",
    "blocking_ingestion_uncertainty",
)
INVENTORIES = {
    "context_coverage": ("context_inventory", "CONTEXT", ("code", "source_ref")),
    "field_coverage": ("field_inventory", "FIELD", ("code", "source_ref")),
    "permission_coverage": ("permission_inventory", "PERMISSION", ("permission_code", "source_ref")),
    "transition_coverage": ("transition_inventory", "TRANSITION", ("source_ref",)),
}
INGESTION_IDENTIFIERS = {
    "context_inventory": ("code", "source_ref"),
    "field_inventory": ("code", "source_ref"),
    "permission_inventory": ("permission_code", "source_ref"),
    "transition_inventory": ("source_ref",),
}


def canonical_sha(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def runtime_meta() -> dict[str, Any]:
    path = Path(__file__).resolve()
    raw = path.read_bytes()
    return {
        "semantic_validator_path": str(path),
        "semantic_validator_sha256": hashlib.sha256(raw).hexdigest(),
        "semantic_validator_git_blob_sha1": hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest(),
        "semantic_validator_bytes": len(raw),
    }


def schema_errors(value: dict[str, Any], filename: str) -> tuple[list[str], str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise ValidationInputError("jsonschema_not_available") from exc
    path = Path(__file__).resolve().parent.parent / "schemas" / filename
    if not path.is_file():
        raise ValidationInputError(f"schema_unavailable:{filename}")
    schema = load_json(path)
    jsonschema.Draft7Validator.check_schema(schema)
    validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
    errors = sorted(
        f"{'/'.join(map(str, e.absolute_path)) or '$'}:{e.message}"
        for e in validator.iter_errors(value)
    )
    return errors, sha256_file(path)


def ingestion_source_manifest(images: list[Any]) -> list[dict[str, Any]]:
    keys = (
        "image_ref", "raw_content_sha256", "width_px", "height_px",
        "format", "viewport_role", "sequence_order",
    )
    valid = [x for x in images if isinstance(x, dict)]
    return [
        {key: item.get(key) for key in keys}
        for item in sorted(valid, key=lambda x: (x.get("sequence_order", 0), str(x.get("image_ref", ""))))
    ]


def runtime_blockers(executor: str | None, version: str | None, expected_sha: str | None, registration: str | None, meta: dict[str, Any]) -> list[str]:
    out: list[str] = []
    if not str(executor or "").strip():
        out.append("executor_identity_missing")
    if not str(version or "").strip():
        out.append("judge_version_missing")
    elif str(version).strip() != VERSION:
        out.append("judge_version_mismatch")
    expected = str(expected_sha or "").strip()
    if not expected:
        out.append("semantic_validator_unavailable")
    elif not SHA_RE.fullmatch(expected):
        out.append("semantic_validator_sha_expected_invalid")
    elif expected != meta["semantic_validator_sha256"]:
        out.append("semantic_validator_sha_unreconciled")
    if str(registration or "").strip() != REGISTRATION:
        out.append("semantic_validator_unregistered")
    return out


def preflight(payload: Any) -> tuple[str | None, dict[str, Any] | None, dict[str, Any] | None, list[str]]:
    if not isinstance(payload, dict):
        return None, None, None, ["required_input_missing"]
    target = payload.get("target_screen_code")
    ingestion = payload.get("screen_ingestion")
    dec = payload.get("screen_decomposition")
    blockers: list[str] = []
    if not isinstance(target, str) or not target.strip():
        blockers.append("required_input_missing")
    if not isinstance(ingestion, dict) or not isinstance(dec, dict):
        blockers.append("required_input_missing")
        return str(target or "").strip() or None, ingestion if isinstance(ingestion, dict) else None, dec if isinstance(dec, dict) else None, blockers
    for key in ("context_inventory", "field_inventory", "permission_inventory", "transition_inventory"):
        if not isinstance(dec.get(key), list) or not isinstance(ingestion.get(key), list):
            blockers.append("inventory_missing_or_invalid")
    if not isinstance(dec.get("functional_units"), list):
        blockers.append("inventory_missing_or_invalid")
    elif not dec["functional_units"]:
        blockers.append("functional_units_empty")
    if not isinstance(dec.get("coverage_items"), list):
        blockers.append("inventory_missing_or_invalid")
    elif not dec["coverage_items"]:
        blockers.append("coverage_items_empty")
    if not isinstance(dec.get("coverage_summary"), dict):
        blockers.append("required_input_missing")
    if not str(dec.get("source_version") or "").strip() or not str(dec.get("main_responsibility") or "").strip():
        blockers.append("source_version_or_main_responsibility_empty")
    if not isinstance(dec.get("source_snapshot_sha"), str) or not SHA_RE.fullmatch(dec["source_snapshot_sha"]):
        blockers.append("input_sha256_missing")
    if any(
        isinstance(x, dict) and x.get("blocking") is True and x.get("status") == "OPEN"
        for x in (dec.get("pending_decisions") or [])
    ):
        blockers.append("required_decision_prevents_decomposition")
    return str(target or "").strip() or None, ingestion, dec, sorted(set(blockers))


def coverage_ids(items: list[Any], kind: str) -> set[str]:
    out: set[str] = set()
    for item in items:
        if not isinstance(item, dict) or item.get("source_type") != kind:
            continue
        if item.get("mapping_status") not in {"MAPPED", "JUSTIFIED_OUT"}:
            continue
        for key in ("source_item_code", "source_ref"):
            value = item.get(key)
            if isinstance(value, str) and value.strip():
                out.add(value.strip())
    return out


def uncovered(entries: list[Any], items: list[Any], kind: str, fields: tuple[str, ...]) -> int:
    covered = coverage_ids(items, kind)
    misses = 0
    for entry in entries:
        if not isinstance(entry, dict):
            misses += 1
            continue
        ids = {str(entry.get(field)).strip() for field in fields if str(entry.get(field) or "").strip()}
        if not ids or ids.isdisjoint(covered):
            misses += 1
    return misses


def inventory_ids(entries: list[Any], fields: tuple[str, ...]) -> set[str]:
    out: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        for field in fields:
            value = entry.get(field)
            if isinstance(value, str) and value.strip():
                out.add(value.strip())
    return out


def completeness_vs_ingestion(ingestion: dict[str, Any], dec: dict[str, Any]) -> tuple[int, dict[str, list[str]]]:
    missing: dict[str, list[str]] = {}
    count = 0
    for inventory, fields in INGESTION_IDENTIFIERS.items():
        observed_entries = ingestion.get(inventory) or []
        declared_entries = dec.get(inventory) or []
        declared = inventory_ids(declared_entries, fields)
        misses: list[str] = []
        for index, entry in enumerate(observed_entries):
            if not isinstance(entry, dict):
                misses.append(f"invalid:{index}")
                continue
            ids = {str(entry.get(field)).strip() for field in fields if str(entry.get(field) or "").strip()}
            if not ids or ids.isdisjoint(declared):
                misses.append(next(iter(sorted(ids)), f"missing-id:{index}"))
        if misses:
            missing[inventory] = sorted(misses)
            count += len(misses)
    return count, missing


def duplicate_units(units: list[Any]) -> tuple[int, list[str]]:
    seen_codes: set[str] = set()
    seen_semantics: set[tuple[str, str, str]] = set()
    keys: list[str] = []
    count = 0
    for index, unit in enumerate(units):
        if not isinstance(unit, dict):
            count += 1
            keys.append(f"invalid:{index}")
            continue
        code = str(unit.get("functional_unit_code") or "").strip()
        semantic = tuple(str(unit.get(k) or "").strip().casefold() for k in ("actor", "goal", "observable_output"))
        duplicate = False
        if code and code in seen_codes:
            keys.append(f"code:{code}")
            duplicate = True
        if all(semantic) and semantic in seen_semantics:
            keys.append("semantic:" + "|".join(semantic))
            duplicate = True
        if duplicate:
            count += 1
        if code:
            seen_codes.add(code)
        if all(semantic):
            seen_semantics.add(semantic)
    return count, sorted(set(keys))


def semantic(target: str, ingestion: dict[str, Any], dec: dict[str, Any]) -> tuple[dict[str, int], dict[str, Any]]:
    dec_errors, dec_schema_sha = schema_errors(dec, "screen-decomposition.schema.json")
    ingestion_errors, ingestion_schema_sha = schema_errors(ingestion, "screen-ingestion.schema.json")
    contexts = dec.get("context_inventory") or []
    fields = dec.get("field_inventory") or []
    permissions = dec.get("permission_inventory") or []
    transitions = dec.get("transition_inventory") or []
    units = dec.get("functional_units") or []
    items = dec.get("coverage_items") or []
    summary = dec.get("coverage_summary") or {}

    codes = {
        str(x.get("functional_unit_code")).strip()
        for x in units if isinstance(x, dict) and str(x.get("functional_unit_code") or "").strip()
    }
    statuses = [x.get("mapping_status") for x in items if isinstance(x, dict)]
    unmapped = unjustified = conflicting = unknown = 0
    for item in items:
        if not isinstance(item, dict):
            unmapped += 1
            continue
        status, mapped = item.get("mapping_status"), item.get("mapped_to")
        if status == "CONFLICT":
            conflicting += 1
        if status not in {"MAPPED", "JUSTIFIED_OUT"}:
            unmapped += 1
        if status == "JUSTIFIED_OUT" and len(str(item.get("justification") or "").strip()) < 3:
            unjustified += 1
        if status == "MAPPED" and (
            not isinstance(mapped, list) or not mapped
            or any(not isinstance(code, str) or code not in codes for code in mapped)
        ):
            unknown += 1

    duplicates, duplicate_keys = duplicate_units(units)
    incomplete = without_code = confirmed_without_source = 0
    required = (
        "actor", "goal", "trigger", "observable_output", "risk_level",
        "decision", "justification", "source_ref", "classification",
    )
    for unit in units:
        if not isinstance(unit, dict):
            incomplete += 1
            without_code += 1
            continue
        if not str(unit.get("functional_unit_code") or "").strip():
            without_code += 1
        if any(not str(unit.get(k) or "").strip() for k in required):
            incomplete += 1
        if unit.get("decision") == "MERGE_WITH" and not str(unit.get("merge_target") or "").strip():
            incomplete += 1
        if unit.get("classification") == "CONFIRMED" and len(str(unit.get("source_ref") or "").strip()) < 3:
            confirmed_without_source += 1

    calculated = {
        "source_items_count": len(items),
        "mapped_count": statuses.count("MAPPED"),
        "justified_count": statuses.count("JUSTIFIED_OUT"),
        "unmapped_count": unmapped,
        "unjustified_count": unjustified,
        "conflicting_count": conflicting,
        "duplicate_functional_units_count": duplicates,
    }
    mismatch = [key for key, value in calculated.items() if summary.get(key) != value]
    blocking = sum(
        1 for x in (dec.get("pending_decisions") or [])
        if isinstance(x, dict) and x.get("blocking") is True and x.get("status") == "OPEN"
    )
    ingestion_blocking = sum(
        1 for x in (ingestion.get("uncertainties") or [])
        if isinstance(x, dict) and x.get("critical") is True
    )
    completeness_count, missing_from_dec = completeness_vs_ingestion(ingestion, dec)
    computed_ingestion_sha = canonical_sha(ingestion_source_manifest(ingestion.get("source_images") or []))

    checks = {
        "input_schema_valid": len(dec_errors),
        "ingestion_schema_valid": len(ingestion_errors),
        "source_snapshot_sha_present": 0 if isinstance(dec.get("source_snapshot_sha"), str) and SHA_RE.fullmatch(dec["source_snapshot_sha"]) else 1,
        "source_screen_code_matches_target": 0 if dec.get("screen_code") == target else 1,
        "ingestion_screen_code_matches_target": 0 if ingestion.get("screen_code") == target else 1,
        "ingestion_source_snapshot_hash_matches": 0 if (
            ingestion.get("source_snapshot_sha") == computed_ingestion_sha
            and dec.get("source_snapshot_sha") == ingestion.get("source_snapshot_sha")
        ) else 1,
        "ingestion_locked": 0 if (
            ingestion.get("locked") is True
            and isinstance(ingestion.get("context_isolation"), dict)
            and ingestion["context_isolation"].get("auxiliary_context_before_lock") is False
            and ingestion["context_isolation"].get("separate_context_window") is True
            and ingestion["context_isolation"].get("action_tools_enabled") is False
        ) else 1,
        "inventory_complete_vs_ingestion": completeness_count,
        "unmapped_count": unmapped,
        "unjustified_count": unjustified,
        "conflicting_count": conflicting,
        "duplicate_functional_units": duplicates,
        "functional_units_complete": incomplete,
        "functional_units_without_code": without_code,
        "coverage_mapped_to_unknown_functional_unit": unknown,
        "confirmed_rules_have_source": confirmed_without_source,
        "coverage_summary_mismatch": len(mismatch),
        "blocking_pending_decisions": blocking,
        "blocking_ingestion_uncertainty": ingestion_blocking,
    }
    for assertion, (inventory, kind, identifiers) in INVENTORIES.items():
        checks[assertion] = uncovered(dec.get(inventory) or [], items, kind, identifiers)
    checks = {key: int(checks.get(key, 1)) for key in ASSERTIONS}

    evidence = {
        "input_schema_ref": "schemas/screen-decomposition.schema.json",
        "input_schema_sha256": dec_schema_sha,
        "ingestion_schema_ref": "schemas/screen-ingestion.schema.json",
        "ingestion_schema_sha256": ingestion_schema_sha,
        "schema_validation_errors": dec_errors,
        "ingestion_schema_validation_errors": ingestion_errors,
        "source_snapshot_sha": dec.get("source_snapshot_sha"),
        "computed_ingestion_source_snapshot_sha": computed_ingestion_sha,
        "ingestion_evidence_kind": ingestion.get("evidence_kind"),
        "ingestion_blind_read_id": ingestion.get("blind_read_id"),
        "ingestion_execution_id": ingestion.get("execution_id"),
        "ingestion_visual_runtime_proven": False,
        "source_version": dec.get("source_version"),
        "main_responsibility": dec.get("main_responsibility"),
        "context_count": len(contexts),
        "field_count": len(fields),
        "permission_count": len(permissions),
        "transition_count": len(transitions),
        "functional_units_count": len(units),
        "coverage_items_count": len(items),
        "recomputed_coverage_summary": calculated,
        "declared_coverage_summary": summary,
        "semantic_duplicate_keys": duplicate_keys,
        "mismatched_summary_fields": mismatch,
        "missing_from_decomposition_vs_ingestion": missing_from_dec,
        "checks": checks,
    }
    return checks, evidence


def build(payload: Any, refs: list[str], retry: int, executor: str | None, version: str | None, expected_sha: str | None, registration: str | None, input_sha: str, input_path: str | None, command: str) -> dict[str, Any]:
    meta = runtime_meta()
    blockers = runtime_blockers(executor, version, expected_sha, registration, meta)
    target, ingestion, dec, preflight_blockers = preflight(payload)
    blockers = sorted(set(blockers + preflight_blockers))
    evidence: dict[str, Any] = {
        **meta,
        "semantic_validator_registration_ref": registration,
        "semantic_validator_expected_sha256": expected_sha,
        "executor_identity": executor,
        "judge_version": version,
        "input_sha256": input_sha,
        "input_path": input_path,
        "checks": {},
    }
    checks: dict[str, int] = {}
    if not blockers and target and ingestion is not None and dec is not None:
        checks, extra = semantic(target, ingestion, dec)
        evidence.update(extra)
    evidence["blocking_assertions"] = blockers
    repairs = [
        failure(key, f"$.evidence.checks.{key}", f"Repair until {key}=0 without weakening screen-ingestion or A44.")
        for key, value in checks.items() if value
    ]
    return result_object(
        JUDGE,
        [key for key, value in checks.items() if value],
        evidence,
        refs,
        repairs,
        blockers,
        retry_count=retry,
        judge_version=version,
        executor_identity=executor,
        command=command,
    )


def self_test() -> int:
    root = Path(__file__).resolve().parent.parent
    fixture = root / "evals" / "fixtures" / "j02_external_positive.json"
    omission = root / "evals" / "fixtures" / "j02_source_omission.json"
    meta = runtime_meta()
    executor = "LF_J02_SELF_TEST"
    def run(path: Path) -> dict[str, Any]:
        payload = load_json(path)
        return build(
            payload, [f"self-test://{path.name}"], 0, executor, VERSION,
            meta["semantic_validator_sha256"], REGISTRATION,
            sha256_file(path), str(path), f"self-test:{path.name}",
        )
    positive = run(fixture)
    negative = run(omission)
    passed = (
        positive["result"] == "PASS_WITH_EVIDENCE"
        and positive["assertions_passed"] == positive["assertions_total"]
        and negative["result"] == "RETURN_TO_WORKER"
        and "inventory_complete_vs_ingestion" in set(negative["failed_assertions"])
    )
    print(json.dumps({
        "judge": JUDGE,
        "version": VERSION,
        "self_test_pass": passed,
        "positive_result": positive["result"],
        "positive_assertions": f"{positive['assertions_passed']}/{positive['assertions_total']}",
        "source_omission_result": negative["result"],
        "source_omission_failed_assertions": negative["failed_assertions"],
    }, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--evidence-ref", action="append", default=[])
    parser.add_argument("--retry-count", type=int, default=0)
    parser.add_argument("--expected-validator-sha256", default=os.getenv("LF_EXPECTED_VALIDATOR_SHA256"))
    parser.add_argument("--registration-ref", default=os.getenv("LF_VALIDATOR_REGISTRATION_REF"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        raise ValidationInputError("input_required")
    payload = load_json(args.input)
    out = build(
        payload,
        args.evidence_ref,
        args.retry_count,
        os.getenv("LF_EXECUTOR_IDENTITY"),
        os.getenv("LF_JUDGE_VERSION"),
        args.expected_validator_sha256,
        args.registration_ref,
        sha256_file(args.input),
        str(args.input),
        " ".join(sys.argv),
    )
    return emit(out)


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, main))
