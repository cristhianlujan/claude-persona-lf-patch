#!/usr/bin/env python3
"""Validate P0 visual-reader output without claiming model quality."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

from validate_p0_j02_handoff import load

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
FIXTURE = ROOT / "evals" / "p0-visual-reader-fixture.json"
LOW_CONFIDENCE_THRESHOLD = 0.70


def schema_errors(name: str, value: Any) -> list[str]:
    try:
        import jsonschema
    except ImportError as exc:
        raise RuntimeError("jsonschema_not_available") from exc
    schema = load(SCHEMAS / name)
    validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
    return sorted(error.message for error in validator.iter_errors(value))


def validate(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"result": "BLOCKED", "blocking_assertions": ["visual_output_invalid"]}
    bundle = payload.get("blind_bundle") if isinstance(payload.get("blind_bundle"), dict) else {}
    observations = payload.get("observations") if isinstance(payload.get("observations"), list) else []
    evidence = payload.get("evidence") if isinstance(payload.get("evidence"), list) else []
    ui_structure = payload.get("ui_structure") if isinstance(payload.get("ui_structure"), dict) else {}
    source_refs = {item.get("ref") for item in bundle.get("source_images", []) if isinstance(item, dict)}
    evidence_refs = {item.get("evidence_ref") for item in evidence if isinstance(item, dict)}
    observation_ids = [item.get("observation_id") for item in observations if isinstance(item, dict)]
    observation_schema_errors = sum((schema_errors("visual-observation.schema.json", item) for item in observations), [])
    evidence_schema_errors = sum((schema_errors("evidence.schema.json", item) for item in evidence), [])
    checks = {
        "blind_bundle_schema_invalid": len(schema_errors("blind-input-bundle.schema.json", bundle)),
        "observations_empty": 0 if observations else 1,
        "visual_observation_schema_invalid": len(observation_schema_errors),
        "ui_structure_schema_invalid": len(schema_errors("ui-structure.schema.json", ui_structure)),
        "evidence_schema_invalid": len(evidence_schema_errors),
        "duplicate_observation_ids": len(observation_ids) - len(set(observation_ids)),
        "observation_source_unknown": sum(1 for item in observations if isinstance(item, dict) and item.get("source_image_ref") not in source_refs),
        "observation_without_evidence": sum(1 for item in observations if isinstance(item, dict) and item.get("evidence_ref") not in evidence_refs),
        "low_confidence_without_abstention": sum(1 for item in observations if isinstance(item, dict) and isinstance(item.get("confidence"), (int, float)) and item["confidence"] < LOW_CONFIDENCE_THRESHOLD and item.get("abstained") is not True),
        "sensitive_retained_evidence_unredacted": sum(1 for item in evidence if isinstance(item, dict) and item.get("data_classification") == "SENSITIVE" and item.get("kind") in {"CROP", "AUXILIARY_SOURCE", "ADJUDICATION"} and item.get("redacted") is not True),
    }
    failed = sorted(key for key, value in checks.items() if value)
    return {"result": "PASS_WITH_EVIDENCE" if not failed else "BLOCKED", "blocking_assertions": failed, "checks": checks, "observation_count": len(observations), "evidence_count": len(evidence), "empirical_visual_quality_claimed": False}


def self_test() -> int:
    good = load(FIXTURE)
    positive = validate(good)
    cases = []
    x = copy.deepcopy(good); x["observations"].append(copy.deepcopy(x["observations"][0])); cases.append(("duplicate_observation", x, "duplicate_observation_ids"))
    x = copy.deepcopy(good); x["observations"][0]["confidence"] = 0.4; x["observations"][0]["abstained"] = False; cases.append(("low_confidence_without_abstention", x, "low_confidence_without_abstention"))
    x = copy.deepcopy(good); x["evidence"] = x["evidence"][1:]; cases.append(("missing_crop_evidence", x, "observation_without_evidence"))
    x = copy.deepcopy(good); x["observations"][0]["source_image_ref"] = "image://unknown"; cases.append(("unknown_source_image", x, "observation_source_unknown"))
    outcomes = []
    for name, payload, expected in cases:
        result = validate(payload)
        outcomes.append({"name": name, "expected_assertion": expected, "passed": result["result"] == "BLOCKED" and expected in result["blocking_assertions"]})
    passed = positive["result"] == "PASS_WITH_EVIDENCE" and all(item["passed"] for item in outcomes)
    print(json.dumps({"positive_pass": positive["result"] == "PASS_WITH_EVIDENCE", "positive_observations": positive.get("observation_count"), "negative_cases_passed": sum(item["passed"] for item in outcomes), "negative_cases_total": len(outcomes), "negative_results": outcomes, "empirical_visual_quality_claimed": False, "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        parser.error("input is required unless --self-test is used")
    result = validate(load(args.input))
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["result"] == "PASS_WITH_EVIDENCE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
