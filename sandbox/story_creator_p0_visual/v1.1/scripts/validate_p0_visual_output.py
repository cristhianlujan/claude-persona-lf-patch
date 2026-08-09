#!/usr/bin/env python3
"""Validate P0 visual-reader output without claiming model quality."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

from p0_schema import validate_instance
from validate_p0_j02_handoff import load

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
FIXTURE = ROOT / "evals" / "p0-visual-reader-fixture.json"
LOW_CONFIDENCE_THRESHOLD = 0.70


def schema_errors(name: str, value: Any) -> list[str]:
    schema = load(SCHEMAS / name)
    return validate_instance(schema, value)


def validate(payload: Any, trusted_admissions: Any = None) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"result": "BLOCKED", "blocking_assertions": ["visual_output_invalid"]}
    bundle = payload.get("blind_bundle") if isinstance(payload.get("blind_bundle"), dict) else {}
    observations = payload.get("observations") if isinstance(payload.get("observations"), list) else []
    evidence = payload.get("evidence") if isinstance(payload.get("evidence"), list) else []
    ui_structure = payload.get("ui_structure") if isinstance(payload.get("ui_structure"), dict) else {}
    source_images = bundle.get("source_images", []) if isinstance(bundle.get("source_images"), list) else []
    dimensions = bundle.get("dimensions", []) if isinstance(bundle.get("dimensions"), list) else []
    source_refs = {item.get("ref") for item in source_images if isinstance(item, dict)}
    source_sha_by_ref = {
        item.get("ref"): item.get("sha256")
        for item in bundle.get("source_images", [])
        if isinstance(item, dict) and isinstance(item.get("ref"), str)
    }
    bundle_hashes = set(bundle.get("hashes", [])) if isinstance(bundle.get("hashes"), list) else set()
    evidence_refs = {item.get("evidence_ref") for item in evidence if isinstance(item, dict)}
    evidence_by_ref = {
        item.get("evidence_ref"): item
        for item in evidence
        if isinstance(item, dict) and isinstance(item.get("evidence_ref"), str)
    }
    observation_ids = [item.get("observation_id") for item in observations if isinstance(item, dict)]
    evidence_ref_list = [item.get("evidence_ref") for item in evidence if isinstance(item, dict)]
    admissions = trusted_admissions if isinstance(trusted_admissions, list) else []
    admission_schema_errors = sum((schema_errors("image-admission-record.schema.json", item) for item in admissions), [])
    admission_ref_list = [item.get("source_ref") for item in admissions if isinstance(item, dict)]
    admissions_by_ref = {
        item.get("source_ref"): item
        for item in admissions
        if isinstance(item, dict) and isinstance(item.get("source_ref"), str)
    }
    observation_schema_errors = sum((schema_errors("visual-observation.schema.json", item) for item in observations), [])
    evidence_schema_errors = sum((schema_errors("evidence.schema.json", item) for item in evidence), [])
    checks = {
        "blind_bundle_schema_invalid": len(schema_errors("blind-input-bundle.schema.json", bundle)),
        "observations_empty": 0 if observations else 1,
        "visual_observation_schema_invalid": len(observation_schema_errors),
        "ui_structure_schema_invalid": len(schema_errors("ui-structure.schema.json", ui_structure)),
        "evidence_schema_invalid": len(evidence_schema_errors),
        "duplicate_observation_ids": len(observation_ids) - len(set(observation_ids)),
        "duplicate_evidence_refs": len(evidence_ref_list) - len(set(evidence_ref_list)),
        "trusted_admission_missing": sum(1 for ref in source_refs if ref not in admissions_by_ref),
        "trusted_admission_unexpected": sum(1 for ref in admissions_by_ref if ref not in source_refs),
        "trusted_admission_duplicate_refs": len(admission_ref_list) - len(set(admission_ref_list)),
        "trusted_admission_schema_invalid": len(admission_schema_errors),
        "source_dimension_count_mismatch": abs(len(source_images) - len(dimensions)),
        "source_sha_mismatch_admission": sum(
            1
            for ref, sha in source_sha_by_ref.items()
            if ref in admissions_by_ref and admissions_by_ref[ref].get("raw_bytes_sha256") != sha
        ),
        "source_format_mismatch_admission": sum(
            1
            for ref in source_refs
            if ref in admissions_by_ref and admissions_by_ref[ref].get("input_format") != bundle.get("format")
        ),
        "source_dimension_mismatch_admission": sum(
            1
            for index, item in enumerate(source_images)
            if isinstance(item, dict)
            and index < len(dimensions)
            and isinstance(dimensions[index], dict)
            and item.get("ref") in admissions_by_ref
            and (
                admissions_by_ref[item["ref"]].get("width") != dimensions[index].get("width")
                or admissions_by_ref[item["ref"]].get("height") != dimensions[index].get("height")
            )
        ),
        "source_hash_missing_from_bundle_hashes": sum(
            1 for sha in source_sha_by_ref.values() if sha not in bundle_hashes
        ),
        "observation_source_unknown": sum(1 for item in observations if isinstance(item, dict) and item.get("source_image_ref") not in source_refs),
        "observation_without_evidence": sum(1 for item in observations if isinstance(item, dict) and item.get("evidence_ref") not in evidence_refs),
        "observation_evidence_source_mismatch": sum(
            1
            for item in observations
            if isinstance(item, dict)
            and item.get("evidence_ref") in evidence_by_ref
            and evidence_by_ref[item["evidence_ref"]].get("source_ref") != item.get("source_image_ref")
        ),
        "evidence_source_unknown": sum(
            1
            for item in evidence
            if isinstance(item, dict)
            and item.get("kind") in {"SOURCE_IMAGE", "CROP"}
            and item.get("source_ref") not in source_refs
        ),
        "source_image_evidence_hash_mismatch": sum(
            1
            for item in evidence
            if isinstance(item, dict)
            and item.get("kind") == "SOURCE_IMAGE"
            and (
                item.get("source_ref") not in admissions_by_ref
                or admissions_by_ref[item.get("source_ref")].get("raw_bytes_sha256") != item.get("sha256")
            )
        ),
        "low_confidence_without_abstention": sum(1 for item in observations if isinstance(item, dict) and isinstance(item.get("confidence"), (int, float)) and item["confidence"] < LOW_CONFIDENCE_THRESHOLD and item.get("abstained") is not True),
        "sensitive_retained_evidence_unredacted": sum(1 for item in evidence if isinstance(item, dict) and item.get("data_classification") == "SENSITIVE" and item.get("kind") in {"CROP", "AUXILIARY_SOURCE", "ADJUDICATION"} and item.get("redacted") is not True),
    }
    failed = sorted(key for key, value in checks.items() if value)
    return {"result": "PASS_WITH_EVIDENCE" if not failed else "BLOCKED", "blocking_assertions": failed, "checks": checks, "observation_count": len(observations), "evidence_count": len(evidence), "empirical_visual_quality_claimed": False}


def self_test() -> int:
    good = load(FIXTURE)
    source = good["blind_bundle"]["source_images"][0]
    dims = good["blind_bundle"]["dimensions"][0]
    trusted = [{
        "schema_version": "p0-image-admission/v1",
        "source_ref": source["ref"],
        "raw_bytes_sha256": source["sha256"],
        "normalized_pixel_sha256": "9" * 64,
        "processing_manifest_sha256": "8" * 64,
        "input_format": good["blind_bundle"]["format"],
        "width": dims["width"],
        "height": dims["height"],
        "normalized_mode": "RGBA",
        "decoder_name": "Pillow",
        "decoder_version": "fixture",
    }]
    positive = validate(good, trusted)
    cases = []
    x = copy.deepcopy(good); x["observations"].append(copy.deepcopy(x["observations"][0])); cases.append(("duplicate_observation", x, "duplicate_observation_ids"))
    x = copy.deepcopy(good); x["observations"][0]["confidence"] = 0.4; x["observations"][0]["abstained"] = False; cases.append(("low_confidence_without_abstention", x, "low_confidence_without_abstention"))
    x = copy.deepcopy(good); x["evidence"] = x["evidence"][1:]; cases.append(("missing_crop_evidence", x, "observation_without_evidence"))
    x = copy.deepcopy(good); x["observations"][0]["source_image_ref"] = "image://unknown"; cases.append(("unknown_source_image", x, "observation_source_unknown"))
    x = copy.deepcopy(good); x["blind_bundle"]["hashes"] = ["f" * 64]; cases.append(("source_hash_not_in_bundle_hashes", x, "source_hash_missing_from_bundle_hashes"))
    x = copy.deepcopy(good); x["evidence"][0]["kind"] = "SOURCE_IMAGE"; x["evidence"][0]["sha256"] = "f" * 64; cases.append(("source_image_evidence_hash_mismatch", x, "source_image_evidence_hash_mismatch"))
    x = copy.deepcopy(good); x["evidence"][0]["source_ref"] = "image://unknown"; cases.append(("evidence_source_mismatch", x, "observation_evidence_source_mismatch"))
    x = copy.deepcopy(good); x["blind_bundle"]["source_images"][0]["sha256"] = "f" * 64; x["blind_bundle"]["hashes"] = ["f" * 64]; cases.append(("source_sha_mismatch_trusted_admission", x, "source_sha_mismatch_admission"))
    outcomes = []
    for name, payload, expected in cases:
        result = validate(payload, trusted)
        outcomes.append({"name": name, "expected_assertion": expected, "passed": result["result"] == "BLOCKED" and expected in result["blocking_assertions"]})
    passed = positive["result"] == "PASS_WITH_EVIDENCE" and all(item["passed"] for item in outcomes)
    print(json.dumps({"positive_pass": positive["result"] == "PASS_WITH_EVIDENCE", "positive_observations": positive.get("observation_count"), "negative_cases_passed": sum(item["passed"] for item in outcomes), "negative_cases_total": len(outcomes), "negative_results": outcomes, "empirical_visual_quality_claimed": False, "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--admission-record", action="append", type=Path, default=[])
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        parser.error("input is required unless --self-test is used")
    if not args.admission_record:
        parser.error("--admission-record is required for trusted source binding")
    result = validate(load(args.input), [load(path) for path in args.admission_record])
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["result"] == "PASS_WITH_EVIDENCE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
