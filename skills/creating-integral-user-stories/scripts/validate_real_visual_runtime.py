#!/usr/bin/env python3
"""Validate a transferred independent blind REAL_SCREEN_RUN against the adjudicated LF visual reference.

This validator is deliberately separate from J00. J00 remains a structural gate and
must not self-promote visual runtime. This layer requires an already locked blind
observation, validates J00 structural checks, binds it to the exact adjudicated raw
image, measures omissions against the reference inventory, and emits reproducible
candidate evidence for the visual-runtime hard gate. It never authorizes promotion,
merge, canonical writes, runtime enablement, or production.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import unicodedata
from pathlib import Path
from typing import Any

from validate_screen_ingestion import canonical_sha, evaluate, source_manifest

SCHEMA_VERSION = "visual-runtime-evidence/v0.1"
EXPECTED_SCREEN_CODE = "SCR-LF-ONBOARDING-STEP1-BLIND"


def normalize(value: Any) -> str:
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = "".join(ch for ch in text if not unicodedata.combining(ch)).lower()
    return " ".join(re.sub(r"[^a-z0-9+]+", " ", text).split())


def canonical_payload_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def observed_texts(blind: dict[str, Any]) -> list[str]:
    values: list[str] = []
    for item in blind.get("region_inventory") or []:
        if isinstance(item, dict) and item.get("description"):
            values.append(str(item["description"]))
    for item in blind.get("context_inventory") or []:
        if isinstance(item, dict) and item.get("description"):
            values.append(str(item["description"]))
    for item in blind.get("field_inventory") or []:
        if isinstance(item, dict) and item.get("visible_label"):
            values.append(str(item["visible_label"]))
    return values


def expected_items(reference: dict[str, Any]) -> list[dict[str, Any]]:
    fixture = reference.get("fixture") if isinstance(reference.get("fixture"), dict) else {}
    screen = fixture.get("observed_screen") if isinstance(fixture.get("observed_screen"), dict) else {}
    out: list[dict[str, Any]] = []
    for item in screen.get("fields") or []:
        if not isinstance(item, dict):
            continue
        candidates = [item.get("label")]
        if item.get("visible_value"):
            candidates.append(item.get("visible_value"))
        out.append({"kind": "field", "code": item.get("code"), "candidates": [x for x in candidates if x]})
    for item in screen.get("consents") or []:
        if isinstance(item, dict) and item.get("visible_text"):
            out.append({"kind": "consent", "code": item.get("code"), "candidates": [item.get("visible_text")]})
    for item in screen.get("actions") or []:
        if isinstance(item, dict) and item.get("visible_text"):
            out.append({"kind": "action", "code": item.get("code"), "candidates": [item.get("visible_text")]})
    for idx, message in enumerate(screen.get("trust_messages") or [], start=1):
        if str(message).strip():
            out.append({"kind": "trust_message", "code": f"TRUST-{idx:02d}", "candidates": [str(message)]})
    return out


def candidate_matches(candidate: str, observed: list[str]) -> bool:
    needle = normalize(candidate)
    if not needle:
        return False
    for value in observed:
        haystack = normalize(value)
        if needle in haystack or (len(haystack) >= 4 and haystack in needle):
            return True
    return False


def source_binding(blind: dict[str, Any], reference: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    fixture = reference.get("fixture") if isinstance(reference.get("fixture"), dict) else {}
    source = fixture.get("source") if isinstance(fixture.get("source"), dict) else {}
    images = blind.get("source_images") if isinstance(blind.get("source_images"), list) else []
    image = images[0] if len(images) == 1 and isinstance(images[0], dict) else {}
    actual_manifest = source_manifest([image]) if image else []
    computed_snapshot = canonical_sha(actual_manifest)
    checks = {
        "single_real_source": len(images) == 1 and blind.get("evidence_kind") == "REAL_SCREEN_RUN",
        "raw_sha256_match": image.get("raw_content_sha256") == source.get("raw_content_sha256"),
        "width_match": image.get("width_px") == source.get("width_px"),
        "height_match": image.get("height_px") == source.get("height_px"),
        "format_match": str(image.get("format") or "").upper() == "PNG" and str(source.get("mime_type") or "") == "image/png",
        "snapshot_match": computed_snapshot == blind.get("source_snapshot_sha"),
        "screen_code_match": blind.get("screen_code") == EXPECTED_SCREEN_CODE,
    }
    return all(checks.values()), {"checks": checks, "computed_source_snapshot_sha": computed_snapshot}


def independence_ok(blind: dict[str, Any], reference: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    fixture = reference.get("fixture") if isinstance(reference.get("fixture"), dict) else {}
    reference_read = fixture.get("reference_read") if isinstance(fixture.get("reference_read"), dict) else {}
    isolation = blind.get("context_isolation") if isinstance(blind.get("context_isolation"), dict) else {}
    checks = {
        "auxiliary_context_before_lock_false": isolation.get("auxiliary_context_before_lock") is False,
        "separate_context_window_true": isolation.get("separate_context_window") is True,
        "action_tools_disabled": isolation.get("action_tools_enabled") is False,
        "network_egress_denied": isolation.get("network_egress") == "DENY_BY_DEFAULT",
        "locked": blind.get("locked") is True,
        "reader_identity_present": len(str(blind.get("reader_identity") or "").strip()) >= 3,
        "execution_id_present": len(str(blind.get("execution_id") or "").strip()) >= 8,
        "blind_read_id_present": len(str(blind.get("blind_read_id") or "").strip()) >= 8,
        "reader_distinct_from_reference_reader": str(blind.get("reader_identity") or "").strip() != str(reference_read.get("reader_identity") or "").strip(),
    }
    return all(checks.values()), {
        "checks": checks,
        "attestation_mode": "DECLARED_SEPARATE_CONTEXT_TRANSFER",
        "reference_reader_identity": reference_read.get("reader_identity"),
        "blind_reader_identity": blind.get("reader_identity"),
        "blind_execution_id": blind.get("execution_id"),
        "blind_read_id": blind.get("blind_read_id"),
    }


def evaluate_runtime(blind: dict[str, Any], reference: dict[str, Any]) -> dict[str, Any]:
    j00_checks, j00_evidence = evaluate(blind)
    j00_structural_green = all(value == 0 for value in j00_checks.values())
    bound, binding = source_binding(blind, reference)
    independent, independence = independence_ok(blind, reference)
    observed = observed_texts(blind)
    expected = expected_items(reference)
    matched: list[dict[str, Any]] = []
    missing: list[dict[str, Any]] = []
    for item in expected:
        candidates = [str(x) for x in item.get("candidates") or []]
        hit = next((candidate for candidate in candidates if candidate_matches(candidate, observed)), None)
        row = {"kind": item.get("kind"), "code": item.get("code"), "matched_by": hit}
        (matched if hit else missing).append(row)
    critical_uncertainties = sum(
        1 for item in blind.get("uncertainties") or []
        if isinstance(item, dict) and item.get("critical") is True
    )
    visual_runtime_proven = (
        j00_structural_green
        and bound
        and independent
        and len(expected) > 0
        and not missing
        and critical_uncertainties == 0
    )
    blockers: list[str] = []
    if not j00_structural_green:
        blockers.append("J00_STRUCTURAL_GATE_NOT_GREEN")
    if not bound:
        blockers.append("REAL_SOURCE_BINDING_FAILED")
    if not independent:
        blockers.append("BLIND_INDEPENDENCE_CONTRACT_FAILED")
    if missing:
        blockers.append("REFERENCE_OMISSIONS_DETECTED")
    if critical_uncertainties:
        blockers.append("CRITICAL_VISUAL_UNCERTAINTY_OPEN")
    result = {
        "schema_version": SCHEMA_VERSION,
        "result": "PASS_WITH_EVIDENCE" if visual_runtime_proven else "RETURN_TO_WORKER",
        "visual_runtime_proven": visual_runtime_proven,
        "promotion_authorized": False,
        "numeric_score_is_approval": False,
        "blind_observation_payload_sha256": canonical_payload_sha(blind),
        "reference_payload_sha256": canonical_payload_sha(reference),
        "source_binding": binding,
        "independence": independence,
        "j00": {
            "structural_green": j00_structural_green,
            "checks": j00_checks,
            "declared_source_snapshot_sha": j00_evidence.get("declared_source_snapshot_sha"),
            "computed_source_snapshot_sha": j00_evidence.get("computed_source_snapshot_sha"),
            "validation_scope": j00_evidence.get("validation_scope"),
        },
        "benchmark": {
            "expected_item_count": len(expected),
            "matched_item_count": len(matched),
            "omission_count": len(missing),
            "matched": matched,
            "missing": missing,
            "critical_uncertainty_count": critical_uncertainties,
        },
        "blockers": blockers,
        "limitations": [
            "Separate-context independence is attested by the transferred locked run metadata; it is not a cryptographically signed platform receipt.",
            "This evidence proves the fixed benchmark only and does not claim perfect visual recall for arbitrary screens.",
            "No merge, canonical promotion, production runtime, or maturity score is authorized by this result."
        ],
    }
    return result


def sample() -> tuple[dict[str, Any], dict[str, Any]]:
    image = {
        "image_ref": "IMG-SAMPLE", "raw_content_sha256": "1" * 64,
        "width_px": 100, "height_px": 100, "format": "PNG",
        "viewport_role": "FULL", "sequence_order": 1,
    }
    blind = {
        "schema_version": "screen-ingestion/v0.1", "screen_code": EXPECTED_SCREEN_CODE,
        "source_version": "sample-v1", "evidence_kind": "REAL_SCREEN_RUN",
        "source_images": [image], "source_snapshot_sha": canonical_sha(source_manifest([image])),
        "blind_read_id": "BLIND-SAMPLE-001", "execution_id": "EXEC-SAMPLE-001",
        "reader_identity": "INDEPENDENT_SAMPLE_READER",
        "context_isolation": {"auxiliary_context_before_lock": False, "separate_context_window": True, "action_tools_enabled": False, "network_egress": "DENY_BY_DEFAULT"},
        "region_inventory": [{"region_ref":"REG-1","image_ref":"IMG-SAMPLE","bbox":[0,0,100,100],"description":"Ayuda","confidence":1.0}],
        "context_inventory": [{"code":"CTX-1","description":"Ayuda","source_ref":"SRC-C1","region_ref":"REG-1","confidence":1.0}],
        "field_inventory": [{"code":"FLD-1","context_code":"CTX-1","source_ref":"SRC-F1","region_ref":"REG-1","control_type":"link","visible_label":"Ayuda","conditionally_visible":False,"confidence":1.0}],
        "permission_inventory": [], "transition_inventory": [],
        "coverage_evidence": {"images_scanned":["IMG-SAMPLE"],"full_viewport_scanned":True,"off_viewport_evidence":"NOT_APPLICABLE","omitted_candidate_count":0},
        "uncertainties": [], "locked": True, "locked_at": "2026-08-09T18:40:00-05:00",
    }
    reference = {
        "fixture": {
            "source": {"raw_content_sha256":"1"*64,"width_px":100,"height_px":100,"mime_type":"image/png"},
            "reference_read": {"reader_identity":"REFERENCE_READER"},
            "observed_screen": {"fields":[],"consents":[],"actions":[{"code":"ACT-HELP","visible_text":"Ayuda"}],"trust_messages":[]},
        }
    }
    return blind, reference


def self_test() -> int:
    blind, reference = sample()
    cases: list[dict[str, Any]] = []
    good = evaluate_runtime(copy.deepcopy(blind), copy.deepcopy(reference))
    cases.append({"case":"positive_real_blind_match","passed":good["visual_runtime_proven"] is True})
    bad_hash = copy.deepcopy(blind)
    bad_hash["source_images"][0]["raw_content_sha256"] = "2" * 64
    bad_hash["source_snapshot_sha"] = canonical_sha(source_manifest(bad_hash["source_images"]))
    out = evaluate_runtime(bad_hash, copy.deepcopy(reference))
    cases.append({"case":"wrong_real_source_rejected","passed":out["visual_runtime_proven"] is False and "REAL_SOURCE_BINDING_FAILED" in out["blockers"]})
    bad_context = copy.deepcopy(blind)
    bad_context["context_isolation"]["separate_context_window"] = False
    out = evaluate_runtime(bad_context, copy.deepcopy(reference))
    cases.append({"case":"non_independent_context_rejected","passed":out["visual_runtime_proven"] is False})
    omission = copy.deepcopy(blind)
    omission["field_inventory"] = []
    omission["context_inventory"][0]["description"] = "No matching action"
    omission["region_inventory"][0]["description"] = "No matching action"
    out = evaluate_runtime(omission, copy.deepcopy(reference))
    cases.append({"case":"reference_omission_rejected","passed":out["visual_runtime_proven"] is False and "REFERENCE_OMISSIONS_DETECTED" in out["blockers"]})
    ok = all(item["passed"] for item in cases)
    print(json.dumps({"self_test_pass": ok, "cases": cases}, ensure_ascii=False, sort_keys=True))
    return 0 if ok else 1


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit(f"object_required:{path}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("blind_run", nargs="?", type=Path)
    parser.add_argument("reference", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.blind_run is None or args.reference is None:
        raise SystemExit("blind_run_and_reference_required")
    result = evaluate_runtime(load(args.blind_run), load(args.reference))
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["visual_runtime_proven"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
