#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parent
SCHEMA_PATH = ROOT / "canonical_capability_model_v0_1.schema.json"
VECTORS_PATH = ROOT / "canonical_capability_model_test_vectors_v0_1.json"


def main() -> int:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    vectors = json.loads(VECTORS_PATH.read_text(encoding="utf-8"))

    Draft7Validator.check_schema(schema)
    validator = Draft7Validator(schema)

    valid_results = []
    for manifest in vectors["valid_examples"]:
        errors = sorted(validator.iter_errors(manifest), key=lambda e: list(e.path))
        assert not errors, {
            "capability_id": manifest.get("capability_id"),
            "errors": [e.message for e in errors],
        }
        valid_results.append(manifest["capability_id"])

    invalid_results = []
    for case in vectors["invalid_examples"]:
        errors = sorted(validator.iter_errors(case["manifest"]), key=lambda e: list(e.path))
        assert errors, {"case_id": case["case_id"], "unexpected": "PASS"}
        messages = [e.message for e in errors]
        assert any("False was expected" in msg for msg in messages), {
            "case_id": case["case_id"],
            "errors": messages,
        }
        invalid_results.append({
            "case_id": case["case_id"],
            "error_count": len(errors),
            "errors": messages,
        })

    expected_representative = {
        "PREEXECUTION_ASSURANCE",
        "CARD_RESOLUTION",
        "TYPED_RUNTIME_CONTEXT",
        "LEARNING_GOVERNANCE",
        "EVIDENCE_LEDGER",
        "WORK_PACKAGE",
    }
    assert expected_representative.issubset(set(valid_results)), {
        "missing": sorted(expected_representative - set(valid_results))
    }

    print(json.dumps({
        "contract": "S31_CANONICAL_CAPABILITY_MODEL_V0_1_SELF_TEST",
        "schema_valid": True,
        "valid_capabilities": valid_results,
        "negative_controls": invalid_results,
        "result": "PASS"
    }, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
