#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parent
SCHEMA_PATH = ROOT / "canonical_capability_model_v0_2_candidate.schema.json"
LEGACY_VECTORS_PATH = ROOT / "canonical_capability_model_test_vectors_v0_1.json"


def _upgrade_manifest(source: dict) -> dict:
    manifest = copy.deepcopy(source)
    legacy = manifest.get("lifecycle") or {}
    manifest["lifecycle"] = {
        "artifact_maturity_label": legacy.get("state", "UNKNOWN_OBSERVED"),
        "runtime_activation": False,
        "promotion_authority": legacy.get("promotion_authority", "UNRESOLVED_AUTHORITY"),
        "self_certification_allowed": legacy.get("self_certification_allowed", False),
        "canonical_vocabulary_status": "UNRESOLVED",
        "deprecation_replacement": legacy.get("deprecation_replacement"),
    }
    return manifest


def _errors(validator: Draft7Validator, value: dict) -> list[str]:
    return [
        err.message
        for err in sorted(validator.iter_errors(value), key=lambda e: list(e.path))
    ]


def main() -> int:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    vectors = json.loads(LEGACY_VECTORS_PATH.read_text(encoding="utf-8"))

    Draft7Validator.check_schema(schema)
    validator = Draft7Validator(schema)

    valid_results: list[str] = []
    upgraded_valid: list[dict] = []
    for source in vectors["valid_examples"]:
        manifest = _upgrade_manifest(source)
        errors = _errors(validator, manifest)
        assert not errors, {
            "capability_id": manifest.get("capability_id"),
            "errors": errors,
        }
        assert manifest["lifecycle"]["canonical_vocabulary_status"] == "UNRESOLVED"
        assert manifest["lifecycle"]["runtime_activation"] is False
        valid_results.append(manifest["capability_id"])
        upgraded_valid.append(manifest)

    invalid_results: list[dict] = []
    for case in vectors["invalid_examples"]:
        manifest = _upgrade_manifest(case["manifest"])
        errors = _errors(validator, manifest)
        assert errors, {"case_id": case["case_id"], "unexpected": "PASS"}
        invalid_results.append({"case_id": case["case_id"], "errors": errors})

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

    # Positive: a future observed maturity label is accepted without silently
    # declaring that label part of a canonical LF ordering.
    open_label = copy.deepcopy(upgraded_valid[0])
    open_label["lifecycle"]["artifact_maturity_label"] = "FUTURE_OBSERVED_LABEL"
    assert not _errors(validator, open_label)

    # Negative: S31-A cannot claim the lifecycle vocabulary has been resolved.
    resolved_vocab = copy.deepcopy(upgraded_valid[0])
    resolved_vocab["lifecycle"]["canonical_vocabulary_status"] = "RESOLVED"
    assert _errors(validator, resolved_vocab)

    # Negative: runtime activation is an explicit independent dimension.
    missing_activation = copy.deepcopy(upgraded_valid[0])
    del missing_activation["lifecycle"]["runtime_activation"]
    assert _errors(validator, missing_activation)

    # Negative: capability remains unable to self-certify promotion.
    self_certifying = copy.deepcopy(upgraded_valid[0])
    self_certifying["lifecycle"]["self_certification_allowed"] = True
    assert _errors(validator, self_certifying)

    print(json.dumps({
        "contract": "S31_CANONICAL_CAPABILITY_MODEL_V0_2_CANDIDATE_SELF_TEST",
        "schema_valid": True,
        "legacy_valid_vectors_upgraded": len(valid_results),
        "legacy_negative_vectors_preserved": len(invalid_results),
        "representative_capabilities": sorted(valid_results),
        "lifecycle_regressions": {
            "open_observed_label_without_canonical_order": "PASS",
            "resolved_vocabulary_claim_blocked": "PASS",
            "runtime_activation_dimension_required": "PASS",
            "self_certification_forbidden": "PASS"
        },
        "result": "PASS"
    }, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
