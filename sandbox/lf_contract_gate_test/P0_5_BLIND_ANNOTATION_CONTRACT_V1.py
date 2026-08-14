#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[2]
P0 = ROOT / "sandbox" / "story_creator_p0_visual" / "v1.1"
INTEGRITY = P0 / "evidence" / "p0-5-candidate-source-integrity-v1.json"
SCHEMA = P0 / "schemas" / "p0-independent-ground-truth-annotation-v1.schema.json"
SHA64 = set("0123456789abcdef")
FIXTURE_PREFIX = "CONTRACT-FIXTURE-"


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def require(condition: bool, code: str) -> None:
    if not condition:
        raise AssertionError(code)


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"OBJECT_REQUIRED:{path.name}")
    return value


def is_sha64(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and set(value) <= SHA64


def canonical_annotation_preimage(annotation: dict) -> bytes:
    # The annotation hash is finalized before independent review/provider readback.
    # The entire review block is therefore excluded from the preimage; the review
    # later attests this immutable human-annotation hash without circularity.
    value = copy.deepcopy(annotation)
    review = value.pop("review", None)
    require(isinstance(review, dict), "ANNOTATION_REVIEW_OBJECT_REQUIRED")
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def canonical_annotation_sha256(annotation: dict) -> str:
    return sha256_bytes(canonical_annotation_preimage(annotation))


def validate_integrity_manifest(manifest: dict) -> list[dict]:
    require(manifest.get("schema_version") == "p0-5-candidate-source-integrity/v1", "MANIFEST_SCHEMA")
    require(manifest.get("issue") == 142, "ISSUE_BINDING")
    require(manifest.get("verification_event_id") == 5449, "EVENT_BINDING")
    require(manifest.get("verification_method") == "GOOGLE_DRIVE_RAW_BYTES_SHA256", "VERIFICATION_METHOD")
    require(manifest.get("candidate_output_visible_to_annotator") is False, "GLOBAL_CANDIDATE_OUTPUT_VISIBLE")
    require(manifest.get("independent_human_annotation_count") == 0, "HUMAN_ANNOTATION_COUNT_MUST_START_ZERO")
    require(manifest.get("corpus_credit_granted") == 0, "CORPUS_CREDIT_MUST_START_ZERO")
    require(manifest.get("sealed_holdout_accessed") is False, "SEALED_HOLDOUT_ACCESSED")
    require(manifest.get("p0_5_authorized") is False, "P0_5_AUTHORIZED")
    require(manifest.get("production_authorized") is False, "PRODUCTION_AUTHORIZED")
    sources = manifest.get("sources")
    require(isinstance(sources, list) and len(sources) == 9, "SOURCE_COUNT_9_REQUIRED")
    source_ids: set[str] = set()
    drive_ids: set[str] = set()
    shas: set[str] = set()
    for ordinal, source in enumerate(sources, 1):
        require(isinstance(source, dict), f"SOURCE_OBJECT:{ordinal}")
        source_id = source.get("source_id")
        drive_id = source.get("drive_file_id")
        expected = source.get("expected_sha256")
        observed = source.get("observed_sha256")
        require(isinstance(source_id, str) and source_id, f"SOURCE_ID:{ordinal}")
        require(isinstance(drive_id, str) and len(drive_id) >= 10, f"DRIVE_ID:{ordinal}")
        require(source_id not in source_ids, f"DUP_SOURCE_ID:{source_id}")
        require(drive_id not in drive_ids, f"DUP_DRIVE_ID:{drive_id}")
        require(is_sha64(expected) and is_sha64(observed), f"SOURCE_SHA_FORMAT:{source_id}")
        require(expected == observed, f"SOURCE_SHA_MISMATCH:{source_id}")
        require(expected not in shas, f"DUP_SOURCE_SHA:{source_id}")
        require(isinstance(source.get("content_bytes"), int) and source["content_bytes"] > 0, f"SOURCE_BYTES:{source_id}")
        require(source.get("byte_identity_verified") is True, f"BYTE_IDENTITY_NOT_VERIFIED:{source_id}")
        require(source.get("holdout") is False, f"HOLDOUT_IN_CANDIDATE_MANIFEST:{source_id}")
        require(source.get("annotation_state") == "UNANNOTATED", f"ANNOTATION_STATE_NOT_BLIND:{source_id}")
        require(source.get("candidate_output_visible_to_annotator") is False, f"CANDIDATE_OUTPUT_VISIBLE:{source_id}")
        require(source.get("corpus_credit") == 0, f"PREMATURE_CORPUS_CREDIT:{source_id}")
        source_ids.add(source_id); drive_ids.add(drive_id); shas.add(expected)
    return sources


def validate_annotation_against_manifest(
    annotation: dict,
    sources: list[dict],
    validator: jsonschema.Validator,
    *,
    allow_contract_fixture: bool = False,
) -> None:
    validator.validate(annotation)
    source = annotation["source"]
    matches = [item for item in sources if item["source_id"] == source["source_id"]]
    require(len(matches) == 1, "ANNOTATION_SOURCE_ID_NOT_IN_VERIFIED_MANIFEST")
    expected = matches[0]
    require(source["drive_file_id"] == expected["drive_file_id"], "ANNOTATION_DRIVE_ID_MISMATCH")
    require(source["source_sha256"] == expected["expected_sha256"], "ANNOTATION_SOURCE_SHA_MISMATCH")
    require(source["content_bytes"] == expected["content_bytes"], "ANNOTATION_SOURCE_BYTES_MISMATCH")
    require(source["holdout"] is False, "ANNOTATION_HOLDOUT_FORBIDDEN")
    require(source["candidate_output_visible_to_annotator"] is False, "ANNOTATION_CANDIDATE_OUTPUT_FORBIDDEN")
    require(annotation["review"]["source_sha256"] == source["source_sha256"], "REVIEW_SOURCE_SHA_MISMATCH")
    require(annotation["review"]["annotation_sha256"] == canonical_annotation_sha256(annotation), "ANNOTATION_SHA_MISMATCH")
    require(annotation["annotator"]["identity"] != annotation["review"]["reviewer_identity"], "ANNOTATOR_REVIEWER_IDENTITY_NOT_INDEPENDENT")

    truth_ids = [item["truth_item_id"] for item in annotation["text_items"]] + [item["truth_item_id"] for item in annotation["nontext_items"]]
    require(len(truth_ids) == len(set(truth_ids)), "DUPLICATE_TRUTH_ITEM_ID")
    group_ids = [group["group_id"] for group in annotation["groups"]]
    require(len(group_ids) == len(set(group_ids)), "DUPLICATE_GROUP_ID")
    known_truth = set(truth_ids)
    for group in annotation["groups"]:
        require(all(member in known_truth for member in group["member_truth_item_ids"]), f"GROUP_MEMBER_UNKNOWN:{group['group_id']}")
    reading_order = [item["reading_order_index"] for item in annotation["text_items"]]
    require(len(reading_order) == len(set(reading_order)), "DUPLICATE_READING_ORDER_INDEX")

    if not allow_contract_fixture:
        require(not annotation["annotation_id"].startswith(FIXTURE_PREFIX), "CONTRACT_FIXTURE_CANNOT_BE_ADMITTED")
        require(not annotation["annotator"]["identity"].startswith(FIXTURE_PREFIX), "CONTRACT_FIXTURE_ANNOTATOR_CANNOT_BE_ADMITTED")
        require(not annotation["review"]["reviewer_identity"].startswith(FIXTURE_PREFIX), "CONTRACT_FIXTURE_REVIEWER_CANNOT_BE_ADMITTED")
        require(not annotation["review"]["provider_readback_ref"].startswith("fixture://"), "CONTRACT_FIXTURE_READBACK_CANNOT_BE_ADMITTED")


def annotation_fixture(source: dict) -> dict:
    # CONTRACT_FIXTURE_NOT_GROUND_TRUTH: schema/semantic contract test only.
    # It is never persisted as annotation evidence and never contributes corpus credit.
    raw = {
        "schema_version": "p0-independent-ground-truth-annotation/v1",
        "annotation_id": "CONTRACT-FIXTURE-NOT-GROUND-TRUTH",
        "source": {
            "source_id": source["source_id"],
            "drive_file_id": source["drive_file_id"],
            "source_sha256": source["expected_sha256"],
            "content_bytes": source["content_bytes"],
            "holdout": False,
            "candidate_output_visible_to_annotator": False,
        },
        "annotator": {
            "identity": "CONTRACT-FIXTURE-ANNOTATOR",
            "role": "INDEPENDENT_HUMAN_ANNOTATOR",
            "annotated_at": "2026-08-14T00:00:00Z",
        },
        "text_items": [{
            "truth_item_id": "FIX-TEXT-1",
            "bbox_xywh": [0, 0, 1, 1],
            "transcription_verbatim": "fixture",
            "material": False,
            "surface_role": "fixture_only",
            "reading_order_index": 0,
        }],
        "nontext_items": [],
        "groups": [{"group_id": "FIX-GROUP-1", "member_truth_item_ids": ["FIX-TEXT-1"]}],
        "review": {
            "reviewer_identity": "CONTRACT-FIXTURE-REVIEWER",
            "reviewer_role": "INDEPENDENT_GROUND_TRUTH_REVIEWER",
            "source_sha256": source["expected_sha256"],
            "annotation_sha256": "0" * 64,
            "reviewed_at": "2026-08-14T00:00:00Z",
            "provider_readback_ref": "fixture://not-persisted",
        },
    }
    raw["review"]["annotation_sha256"] = canonical_annotation_sha256(raw)
    return raw


def must_schema_fail(validator: jsonschema.Validator, value: dict, label: str) -> str:
    errors = sorted(validator.iter_errors(value), key=lambda error: list(error.path))
    require(bool(errors), f"NEGATIVE_SCHEMA_MUTATION_NOT_BLOCKED:{label}")
    return label


def must_semantic_fail(validator: jsonschema.Validator, sources: list[dict], value: dict, label: str) -> str:
    try:
        validate_annotation_against_manifest(value, sources, validator, allow_contract_fixture=True)
    except (AssertionError, jsonschema.ValidationError):
        return label
    raise AssertionError(f"NEGATIVE_SEMANTIC_MUTATION_NOT_BLOCKED:{label}")


def validate_external_annotation(path: Path, sources: list[dict], validator: jsonschema.Validator) -> int:
    annotation = load_json(path)
    validate_annotation_against_manifest(annotation, sources, validator, allow_contract_fixture=False)
    result = {
        "schema_version": "p0-5-independent-annotation-preflight/v1",
        "gate": "STRUCTURALLY_ADMISSIBLE_PENDING_AUTHENTICATED_PROVIDER_READBACK",
        "annotation_id": annotation["annotation_id"],
        "source_id": annotation["source"]["source_id"],
        "source_sha256": annotation["source"]["source_sha256"],
        "annotation_sha256": annotation["review"]["annotation_sha256"],
        "candidate_output_visible_to_annotator": False,
        "corpus_credit_granted": 0,
        "p0_5_authorized": False,
        "production_authorized": False,
    }
    print(json.dumps(result, sort_keys=True))
    return 0


def main() -> int:
    manifest = load_json(INTEGRITY)
    schema = load_json(SCHEMA)
    sources = validate_integrity_manifest(manifest)
    jsonschema.Draft202012Validator.check_schema(schema)
    validator = jsonschema.Draft202012Validator(schema, format_checker=jsonschema.FormatChecker())

    if len(sys.argv) == 3 and sys.argv[1] == "--annotation":
        return validate_external_annotation(Path(sys.argv[2]), sources, validator)
    require(len(sys.argv) == 1, "USAGE: P0_5_BLIND_ANNOTATION_CONTRACT_V1.py [--annotation FILE]")

    fixture = annotation_fixture(sources[0])
    validate_annotation_against_manifest(fixture, sources, validator, allow_contract_fixture=True)

    negatives: list[str] = []
    mutated = copy.deepcopy(fixture); mutated["source"]["candidate_output_visible_to_annotator"] = True
    negatives.append(must_schema_fail(validator, mutated, "CANDIDATE_OUTPUT_VISIBLE"))
    mutated = copy.deepcopy(fixture); mutated["source"]["holdout"] = True
    negatives.append(must_schema_fail(validator, mutated, "HOLDOUT_TRUE"))
    mutated = copy.deepcopy(fixture); mutated["candidate_output"] = {"forbidden": True}
    negatives.append(must_schema_fail(validator, mutated, "UNEXPECTED_CANDIDATE_OUTPUT_FIELD"))
    mutated = copy.deepcopy(fixture); mutated["annotator"]["role"] = "MACHINE_ANNOTATOR"
    negatives.append(must_schema_fail(validator, mutated, "WRONG_ANNOTATOR_ROLE"))
    mutated = copy.deepcopy(fixture); mutated["review"]["reviewer_role"] = "BUILDER"
    negatives.append(must_schema_fail(validator, mutated, "WRONG_REVIEWER_ROLE"))
    mutated = copy.deepcopy(fixture); del mutated["review"]["annotation_sha256"]
    negatives.append(must_schema_fail(validator, mutated, "MISSING_ANNOTATION_SHA"))
    mutated = copy.deepcopy(fixture); mutated["source"]["source_sha256"] = "bad"
    negatives.append(must_schema_fail(validator, mutated, "BAD_SOURCE_SHA"))

    mutated = copy.deepcopy(fixture); mutated["source"]["source_id"] = "UNKNOWN-SOURCE"; mutated["review"]["annotation_sha256"] = canonical_annotation_sha256(mutated)
    negatives.append(must_semantic_fail(validator, sources, mutated, "UNKNOWN_SOURCE_ID"))
    mutated = copy.deepcopy(fixture); mutated["source"]["source_sha256"] = "f" * 64; mutated["review"]["source_sha256"] = "f" * 64; mutated["review"]["annotation_sha256"] = canonical_annotation_sha256(mutated)
    negatives.append(must_semantic_fail(validator, sources, mutated, "MANIFEST_SOURCE_SHA_MISMATCH"))
    mutated = copy.deepcopy(fixture); mutated["source"]["content_bytes"] += 1; mutated["review"]["annotation_sha256"] = canonical_annotation_sha256(mutated)
    negatives.append(must_semantic_fail(validator, sources, mutated, "MANIFEST_SOURCE_BYTES_MISMATCH"))
    mutated = copy.deepcopy(fixture); mutated["review"]["source_sha256"] = "f" * 64; mutated["review"]["annotation_sha256"] = canonical_annotation_sha256(mutated)
    negatives.append(must_semantic_fail(validator, sources, mutated, "REVIEW_SOURCE_SHA_MISMATCH"))
    mutated = copy.deepcopy(fixture); mutated["review"]["annotation_sha256"] = "f" * 64
    negatives.append(must_semantic_fail(validator, sources, mutated, "ANNOTATION_SHA_MISMATCH"))
    mutated = copy.deepcopy(fixture); mutated["review"]["reviewer_identity"] = mutated["annotator"]["identity"]
    negatives.append(must_semantic_fail(validator, sources, mutated, "SAME_ANNOTATOR_AND_REVIEWER"))
    mutated = copy.deepcopy(fixture); mutated["groups"][0]["member_truth_item_ids"] = ["MISSING-TRUTH-ID"]
    negatives.append(must_semantic_fail(validator, sources, mutated, "DANGLING_GROUP_MEMBER"))
    mutated = copy.deepcopy(fixture); mutated["nontext_items"] = [{"truth_item_id":"FIX-TEXT-1","bbox_xywh":[2,2,1,1],"kind":"fixture","material":False}]
    negatives.append(must_semantic_fail(validator, sources, mutated, "DUPLICATE_TRUTH_ITEM_ID"))

    result = {
        "schema_version": "p0-5-blind-annotation-contract-gate/v1",
        "gate": "P0_5_BLIND_ANNOTATION_CONTRACT_VALID",
        "integrity_manifest_sha256": sha256_bytes(INTEGRITY.read_bytes()),
        "annotation_schema_sha256": sha256_bytes(SCHEMA.read_bytes()),
        "candidate_source_count": len(sources),
        "exact_source_identity_count": len(sources),
        "contract_fixture_ground_truth": False,
        "contract_fixture_persisted": False,
        "annotation_sha_preimage": "CANONICAL_JSON_EXCLUDING_entire_review_block",
        "negative_mutations_blocked": len(negatives),
        "negative_mutations": negatives,
        "candidate_output_visible_to_annotator": False,
        "independent_human_annotation_count": 0,
        "corpus_credit_granted": 0,
        "sealed_holdout_accessed": False,
        "p0_5_authorized": False,
        "production_authorized": False,
    }
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
