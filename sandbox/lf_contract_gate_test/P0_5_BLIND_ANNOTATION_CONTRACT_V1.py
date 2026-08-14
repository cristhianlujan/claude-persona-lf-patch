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
HEX = set("0123456789abcdef")
FIXTURE_PREFIX = "CONTRACT-FIXTURE-"


def require(ok: bool, code: str) -> None:
    if not ok:
        raise AssertionError(code)


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"OBJECT_REQUIRED:{path.name}")
    return value


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def is_sha64(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and set(value) <= HEX


def annotation_preimage(annotation: dict) -> bytes:
    """Canonical human annotation only; review is a later attestation."""
    value = copy.deepcopy(annotation)
    review = value.pop("review", None)
    require(isinstance(review, dict), "ANNOTATION_REVIEW_OBJECT_REQUIRED")
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def annotation_sha256(annotation: dict) -> str:
    return sha256_bytes(annotation_preimage(annotation))


def validate_manifest(manifest: dict) -> list[dict]:
    expected = {
        "schema_version": "p0-5-candidate-source-integrity/v1",
        "issue": 142,
        "verification_event_id": 5449,
        "verification_method": "GOOGLE_DRIVE_RAW_BYTES_SHA256",
        "candidate_output_visible_to_annotator": False,
        "independent_human_annotation_count": 0,
        "corpus_credit_granted": 0,
        "sealed_holdout_accessed": False,
        "p0_5_authorized": False,
        "production_authorized": False,
    }
    for key, value in expected.items():
        require(manifest.get(key) == value, f"MANIFEST_BINDING:{key}")
    sources = manifest.get("sources")
    require(isinstance(sources, list) and len(sources) == 9, "SOURCE_COUNT_9_REQUIRED")
    seen_ids: set[str] = set(); seen_drive: set[str] = set(); seen_sha: set[str] = set()
    for source in sources:
        require(isinstance(source, dict), "SOURCE_OBJECT_REQUIRED")
        sid = source.get("source_id"); drive = source.get("drive_file_id")
        exp = source.get("expected_sha256"); obs = source.get("observed_sha256")
        require(isinstance(sid, str) and sid and sid not in seen_ids, f"SOURCE_ID_INVALID:{sid}")
        require(isinstance(drive, str) and len(drive) >= 10 and drive not in seen_drive, f"DRIVE_ID_INVALID:{sid}")
        require(is_sha64(exp) and is_sha64(obs) and exp == obs and exp not in seen_sha, f"SOURCE_SHA_INVALID:{sid}")
        require(isinstance(source.get("content_bytes"), int) and source["content_bytes"] > 0, f"SOURCE_BYTES_INVALID:{sid}")
        require(source.get("byte_identity_verified") is True, f"SOURCE_NOT_VERIFIED:{sid}")
        require(source.get("holdout") is False, f"HOLDOUT_FORBIDDEN:{sid}")
        require(source.get("annotation_state") == "UNANNOTATED", f"ANNOTATION_STATE_INVALID:{sid}")
        require(source.get("candidate_output_visible_to_annotator") is False, f"CANDIDATE_OUTPUT_VISIBLE:{sid}")
        require(source.get("corpus_credit") == 0, f"PREMATURE_CORPUS_CREDIT:{sid}")
        seen_ids.add(sid); seen_drive.add(drive); seen_sha.add(exp)
    return sources


def validate_annotation(annotation: dict, sources: list[dict], validator: jsonschema.Validator, *, fixture_allowed: bool) -> None:
    validator.validate(annotation)
    src = annotation["source"]
    matches = [row for row in sources if row["source_id"] == src["source_id"]]
    require(len(matches) == 1, "ANNOTATION_SOURCE_NOT_VERIFIED")
    expected = matches[0]
    require(src["drive_file_id"] == expected["drive_file_id"], "ANNOTATION_DRIVE_ID_MISMATCH")
    require(src["source_sha256"] == expected["expected_sha256"], "ANNOTATION_SOURCE_SHA_MISMATCH")
    require(src["content_bytes"] == expected["content_bytes"], "ANNOTATION_SOURCE_BYTES_MISMATCH")
    require(src["holdout"] is False, "ANNOTATION_HOLDOUT_FORBIDDEN")
    require(src["candidate_output_visible_to_annotator"] is False, "ANNOTATION_CANDIDATE_OUTPUT_FORBIDDEN")
    review = annotation["review"]
    require(review["source_sha256"] == src["source_sha256"], "REVIEW_SOURCE_SHA_MISMATCH")
    require(review["annotation_sha256"] == annotation_sha256(annotation), "ANNOTATION_SHA_MISMATCH")
    require(annotation["annotator"]["identity"] != review["reviewer_identity"], "ANNOTATOR_REVIEWER_NOT_INDEPENDENT")

    truth_ids = [x["truth_item_id"] for x in annotation["text_items"]] + [x["truth_item_id"] for x in annotation["nontext_items"]]
    require(len(truth_ids) == len(set(truth_ids)), "DUPLICATE_TRUTH_ITEM_ID")
    reading = [x["reading_order_index"] for x in annotation["text_items"]]
    require(len(reading) == len(set(reading)), "DUPLICATE_READING_ORDER_INDEX")
    group_ids = [x["group_id"] for x in annotation["groups"]]
    require(len(group_ids) == len(set(group_ids)), "DUPLICATE_GROUP_ID")
    truth_set = set(truth_ids)
    for group in annotation["groups"]:
        require(all(member in truth_set for member in group["member_truth_item_ids"]), f"GROUP_MEMBER_UNKNOWN:{group['group_id']}")

    if not fixture_allowed:
        require(not annotation["annotation_id"].startswith(FIXTURE_PREFIX), "CONTRACT_FIXTURE_CANNOT_BE_ADMITTED")
        require(not annotation["annotator"]["identity"].startswith(FIXTURE_PREFIX), "CONTRACT_FIXTURE_ANNOTATOR_CANNOT_BE_ADMITTED")
        require(not review["reviewer_identity"].startswith(FIXTURE_PREFIX), "CONTRACT_FIXTURE_REVIEWER_CANNOT_BE_ADMITTED")
        require(not review["provider_readback_ref"].startswith("fixture://"), "CONTRACT_FIXTURE_READBACK_CANNOT_BE_ADMITTED")


def fixture(source: dict) -> dict:
    value = {
        "schema_version": "p0-independent-ground-truth-annotation/v1",
        "annotation_id": "CONTRACT-FIXTURE-NOT-GROUND-TRUTH",
        "source": {
            "source_id": source["source_id"], "drive_file_id": source["drive_file_id"],
            "source_sha256": source["expected_sha256"], "content_bytes": source["content_bytes"],
            "holdout": False, "candidate_output_visible_to_annotator": False,
        },
        "annotator": {"identity": "CONTRACT-FIXTURE-ANNOTATOR", "role": "INDEPENDENT_HUMAN_ANNOTATOR", "annotated_at": "2026-08-14T00:00:00Z"},
        "text_items": [{"truth_item_id": "FIX-TEXT-1", "bbox_xywh": [0,0,1,1], "transcription_verbatim": "fixture", "material": False, "surface_role": "fixture_only", "reading_order_index": 0}],
        "nontext_items": [],
        "groups": [{"group_id": "FIX-GROUP-1", "member_truth_item_ids": ["FIX-TEXT-1"]}],
        "review": {
            "reviewer_identity": "CONTRACT-FIXTURE-REVIEWER", "reviewer_role": "P0_VISUAL_ADJUDICATOR",
            "source_sha256": source["expected_sha256"], "annotation_sha256": "0"*64,
            "reviewed_at": "2026-08-14T00:00:00Z", "provider_readback_ref": "fixture://not-persisted",
        },
    }
    value["review"]["annotation_sha256"] = annotation_sha256(value)
    return value


def schema_must_fail(validator: jsonschema.Validator, value: dict, label: str) -> str:
    require(bool(list(validator.iter_errors(value))), f"NEGATIVE_SCHEMA_NOT_BLOCKED:{label}")
    return label


def semantic_must_fail(validator: jsonschema.Validator, sources: list[dict], value: dict, label: str, *, fixture_allowed: bool = True) -> str:
    try:
        validate_annotation(value, sources, validator, fixture_allowed=fixture_allowed)
    except (AssertionError, jsonschema.ValidationError):
        return label
    raise AssertionError(f"NEGATIVE_SEMANTIC_NOT_BLOCKED:{label}")


def external_preflight(path: Path, sources: list[dict], validator: jsonschema.Validator) -> int:
    annotation = load_json(path)
    validate_annotation(annotation, sources, validator, fixture_allowed=False)
    print(json.dumps({
        "schema_version":"p0-5-independent-annotation-preflight/v1",
        "gate":"STRUCTURALLY_ADMISSIBLE_PENDING_AUTHENTICATED_PROVIDER_READBACK",
        "annotation_id":annotation["annotation_id"], "source_id":annotation["source"]["source_id"],
        "source_sha256":annotation["source"]["source_sha256"], "annotation_sha256":annotation["review"]["annotation_sha256"],
        "candidate_output_visible_to_annotator":False, "corpus_credit_granted":0,
        "p0_5_authorized":False, "production_authorized":False,
    }, sort_keys=True))
    return 0


def main() -> int:
    manifest = load_json(INTEGRITY); schema = load_json(SCHEMA)
    sources = validate_manifest(manifest)
    jsonschema.Draft202012Validator.check_schema(schema)
    validator = jsonschema.Draft202012Validator(schema, format_checker=jsonschema.FormatChecker())
    if len(sys.argv) == 3 and sys.argv[1] == "--annotation":
        return external_preflight(Path(sys.argv[2]), sources, validator)
    require(len(sys.argv) == 1, "USAGE")

    base = fixture(sources[0]); validate_annotation(base, sources, validator, fixture_allowed=True)
    blocked: list[str] = []
    m=copy.deepcopy(base); m["source"]["candidate_output_visible_to_annotator"]=True; blocked.append(schema_must_fail(validator,m,"CANDIDATE_OUTPUT_VISIBLE"))
    m=copy.deepcopy(base); m["source"]["holdout"]=True; blocked.append(schema_must_fail(validator,m,"HOLDOUT_TRUE"))
    m=copy.deepcopy(base); m["candidate_output"]={"forbidden":True}; blocked.append(schema_must_fail(validator,m,"UNEXPECTED_CANDIDATE_OUTPUT_FIELD"))
    m=copy.deepcopy(base); m["annotator"]["role"]="MACHINE_ANNOTATOR"; blocked.append(schema_must_fail(validator,m,"WRONG_ANNOTATOR_ROLE"))
    m=copy.deepcopy(base); m["review"]["reviewer_role"]="BUILDER"; blocked.append(schema_must_fail(validator,m,"WRONG_REVIEWER_ROLE"))
    m=copy.deepcopy(base); del m["review"]["annotation_sha256"]; blocked.append(schema_must_fail(validator,m,"MISSING_ANNOTATION_SHA"))
    m=copy.deepcopy(base); m["source"]["source_sha256"]="bad"; blocked.append(schema_must_fail(validator,m,"BAD_SOURCE_SHA"))

    m=copy.deepcopy(base); m["source"]["source_id"]="UNKNOWN-SOURCE"; m["review"]["annotation_sha256"]=annotation_sha256(m); blocked.append(semantic_must_fail(validator,sources,m,"UNKNOWN_SOURCE_ID"))
    m=copy.deepcopy(base); m["source"]["source_sha256"]="f"*64; m["review"]["source_sha256"]="f"*64; m["review"]["annotation_sha256"]=annotation_sha256(m); blocked.append(semantic_must_fail(validator,sources,m,"MANIFEST_SOURCE_SHA_MISMATCH"))
    m=copy.deepcopy(base); m["source"]["content_bytes"]+=1; m["review"]["annotation_sha256"]=annotation_sha256(m); blocked.append(semantic_must_fail(validator,sources,m,"MANIFEST_SOURCE_BYTES_MISMATCH"))
    m=copy.deepcopy(base); m["review"]["source_sha256"]="f"*64; blocked.append(semantic_must_fail(validator,sources,m,"REVIEW_SOURCE_SHA_MISMATCH"))
    m=copy.deepcopy(base); m["review"]["annotation_sha256"]="f"*64; blocked.append(semantic_must_fail(validator,sources,m,"ANNOTATION_SHA_MISMATCH"))
    m=copy.deepcopy(base); m["review"]["reviewer_identity"]=m["annotator"]["identity"]; blocked.append(semantic_must_fail(validator,sources,m,"SAME_ANNOTATOR_AND_REVIEWER"))
    m=copy.deepcopy(base); m["groups"][0]["member_truth_item_ids"]=["MISSING-TRUTH-ID"]; m["review"]["annotation_sha256"]=annotation_sha256(m); blocked.append(semantic_must_fail(validator,sources,m,"DANGLING_GROUP_MEMBER"))
    m=copy.deepcopy(base); m["nontext_items"]=[{"truth_item_id":"FIX-TEXT-1","bbox_xywh":[2,2,1,1],"kind":"fixture","material":False}]; m["review"]["annotation_sha256"]=annotation_sha256(m); blocked.append(semantic_must_fail(validator,sources,m,"DUPLICATE_TRUTH_ITEM_ID"))
    blocked.append(semantic_must_fail(validator,sources,base,"CONTRACT_FIXTURE_ADMISSION",fixture_allowed=False))

    print(json.dumps({
        "schema_version":"p0-5-blind-annotation-contract-gate/v1",
        "gate":"P0_5_BLIND_ANNOTATION_CONTRACT_VALID",
        "integrity_manifest_sha256":sha256_bytes(INTEGRITY.read_bytes()),
        "annotation_schema_sha256":sha256_bytes(SCHEMA.read_bytes()),
        "candidate_source_count":len(sources), "exact_source_identity_count":len(sources),
        "contract_fixture_ground_truth":False, "contract_fixture_persisted":False,
        "reviewer_role":"P0_VISUAL_ADJUDICATOR",
        "annotation_sha_preimage":"CANONICAL_JSON_EXCLUDING_entire_review_block",
        "negative_mutations_blocked":len(blocked), "negative_mutations":blocked,
        "candidate_output_visible_to_annotator":False, "independent_human_annotation_count":0,
        "corpus_credit_granted":0, "sealed_holdout_accessed":False,
        "p0_5_authorized":False, "production_authorized":False,
    }, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
