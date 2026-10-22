#!/usr/bin/env python3
"""RW1-06 C1 sealed holdout commitment: structural checks, never independence proof.

The sealed corpus belongs to a materially separate GPT Native reviewer.
A synthetic self-test cannot count as a holdout, provider attestation, or C1 close.
"""
from __future__ import annotations

import argparse
import copy
import json
import re
from datetime import datetime, timezone
from pathlib import Path

SOURCE = "ec5d8ce5637c2d118941cfe4b3c88ae4fd325024"
POLICY_BLOB = "138efc3285ee5226c107827c66f84ced6be4afcb"
DIGEST = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA = re.compile(r"^[0-9a-f]{40}$")
REQUIRED_KEYS = {
    "schema_version", "checkpoint", "source_snapshot_commit", "source_policy_git_blob",
    "reviewer_method", "reviewer_reference", "reviewer_separation", "holdout_counts",
    "holdout_manifest_sha256", "holdout_content_sha256", "committed_at_utc",
    "committed_before_evaluation", "case_bodies_revealed", "producer_raw_observed",
    "provider_attested", "checkpoint_done",
}
REJECTED_EXTRAS = {
    "cases", "case_bodies", "seed", "nonce", "oracle_answers", "secret_holdout",
    "material_pass", "independent_review", "golden_promoted",
}


class CommitmentError(ValueError):
    pass


def must(condition: bool, code: str) -> None:
    if not condition:
        raise CommitmentError(code)


def validate(data: object) -> dict:
    must(isinstance(data, dict), "COMMITMENT_NOT_OBJECT")
    missing = REQUIRED_KEYS - set(data)
    must(not missing, "REQUIRED_FIELDS_MISSING")
    must(not (set(data) & REJECTED_EXTRAS), "SECRET_OR_UNSUPPORTED_CLAIM_LEAK")
    must(data["schema_version"] == "RW106_C1_INDEPENDENT_HOLDOUT_COMMITMENT_V1", "SCHEMA_MISMATCH")
    must(data["checkpoint"] == "RW1-06_C1", "CHECKPOINT_SCOPE_MISMATCH")
    must(data["source_snapshot_commit"] == SOURCE, "SOURCE_SNAPSHOT_MISMATCH")
    must(isinstance(data["source_policy_git_blob"], str) and
         GIT_SHA.fullmatch(data["source_policy_git_blob"]) is not None and
         data["source_policy_git_blob"] == POLICY_BLOB, "SOURCE_POLICY_BLOB_MISMATCH")
    must(data["reviewer_method"] == "GPT_NATIVE_NEW_CHAT", "REVIEWER_MODE_MISMATCH")
    ref = data["reviewer_reference"]
    must(isinstance(ref, str) and 12 <= len(ref) <= 1024 and
         ref not in {"NOT_YET_ATTESTED", "SAME_CHAT", "UNKNOWN"}, "REVIEWER_REFERENCE_MISSING")
    must(data["reviewer_separation"] == "OWNER_PROVIDED_SEPARATE_CHAT_UNATTESTED",
         "INDEPENDENCE_UNSUPPORTED")
    counts = data["holdout_counts"]
    must(isinstance(counts, dict) and set(counts) == {"valid", "invalid", "novel_falsifiers"} and
         all(type(counts[k]) is int for k in counts), "COUNTS_SHAPE")
    must(counts["valid"] >= 12 and counts["invalid"] >= 24 and
         counts["novel_falsifiers"] >= 2, "INSUFFICIENT_HOLDOUT_COUNTS")
    for key in ("holdout_manifest_sha256", "holdout_content_sha256"):
        must(isinstance(data[key], str) and DIGEST.fullmatch(data[key]) is not None,
             "DIGEST_INVALID")
    must(data["holdout_manifest_sha256"] != data["holdout_content_sha256"],
         "DIGESTS_IDENTICAL")
    raw = data["committed_at_utc"]
    must(isinstance(raw, str) and raw.endswith("Z"), "COMMITMENT_TIMESTAMP_MISSING")
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise CommitmentError("COMMITMENT_TIMESTAMP_INVALID") from exc
    must(dt.tzinfo is not None and dt.utcoffset().total_seconds() == 0, "TIMESTAMP_NOT_UTC")
    # A reported clock time is a reviewer claim, not trusted chronology.
    for key, expected in {
        "committed_before_evaluation": True,
        "case_bodies_revealed": False,
        "producer_raw_observed": False,
        "provider_attested": False,
        "checkpoint_done": False,
    }.items():
        must(data[key] is expected, f"UNSUPPORTED_CLAIM:{key}")
    return {
        "validation": "STRUCTURAL_PASS_INDEPENDENCE_NOT_PROVEN",
        "checkpoint": "RW1-06_C1",
        "counts": counts,
        "provider_attested": False,
        "checkpoint_done": False,
        "limits": [
            "NOT_PROOF_OF_SEPARATE_PROVIDER_CHAT",
            "NOT_PROOF_OF_HOLDOUT_BODY_HASH_UNTIL_REVEAL",
            "NOT_PROOF_OF_TIMESTAMP_ORDER",
            "NOT_C1_CLOSURE",
        ],
    }


def self_test() -> dict:
    sample = {
        "schema_version": "RW106_C1_INDEPENDENT_HOLDOUT_COMMITMENT_V1",
        "checkpoint": "RW1-06_C1",
        "source_snapshot_commit": SOURCE,
        "source_policy_git_blob": POLICY_BLOB,
        "reviewer_method": "GPT_NATIVE_NEW_CHAT",
        "reviewer_reference": "SYNTHETIC_FIXTURE_NOT_REAL_CHAT",
        "reviewer_separation": "OWNER_PROVIDED_SEPARATE_CHAT_UNATTESTED",
        "holdout_counts": {"valid": 12, "invalid": 24, "novel_falsifiers": 2},
        "holdout_manifest_sha256": "a" * 64,
        "holdout_content_sha256": "b" * 64,
        "committed_at_utc": "2026-10-21T00:00:00Z",
        "committed_before_evaluation": True,
        "case_bodies_revealed": False,
        "producer_raw_observed": False,
        "provider_attested": False,
        "checkpoint_done": False,
    }
    must(validate(sample)["validation"] == "STRUCTURAL_PASS_INDEPENDENCE_NOT_PROVEN",
         "FIXTURE_POSITIVE_FAILED")
    mutants = {
        "stale_source": {"source_snapshot_commit": "0" * 40},
        "wrong_policy_blob": {"source_policy_git_blob": "0" * 40},
        "same_producer": {"reviewer_separation": "SAME_PRODUCER"},
        "missing_reviewer": {"reviewer_reference": "UNKNOWN"},
        "insufficient_counts": {"holdout_counts": {"valid": 12, "invalid": 23, "novel_falsifiers": 2}},
        "early_reveal": {"case_bodies_revealed": True},
        "early_raw": {"producer_raw_observed": True},
        "fake_provider_attestation": {"provider_attested": True},
        "fake_done": {"checkpoint_done": True},
        "secret_leak": {"seed": "UNSAFE_PUBLIC_SEED"},
        "missing_digest": {"holdout_content_sha256": None},
    }
    rejected = {}
    for name, change in mutants.items():
        bad = copy.deepcopy(sample)
        bad.update(change)
        try:
            validate(bad)
        except CommitmentError as exc:
            rejected[name] = str(exc)
        else:
            raise AssertionError(f"FALSE_ACCEPT:{name}")
    must(len(rejected) == len(mutants), "NEGATIVE_COVERAGE_INCOMPLETE")
    return {
        "selftest": "PASS_SYNTHETIC_ONLY",
        "negatives_rejected": rejected,
        "independent_holdout_created": False,
        "checkpoint_done": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("commitment", type=Path, nargs="?")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(self_test(), sort_keys=True))
        return
    if args.commitment is None:
        parser.error("commitment JSON path required unless --self-test")
    data = json.loads(args.commitment.read_text(encoding="utf-8"))
    print(json.dumps(validate(data), sort_keys=True))


if __name__ == "__main__":
    main()
