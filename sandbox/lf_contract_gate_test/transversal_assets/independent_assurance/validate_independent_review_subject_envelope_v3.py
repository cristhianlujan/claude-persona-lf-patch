#!/usr/bin/env python3
"""Structural validator for the INDEPENDENT_ASSURANCE v3 generic subject envelope.

Implements the contract declared by lf-independent-review-subject-contract/v3
(supabase/migrations/20261009034828_independent_assurance_generic_subject_v3.sql):
opaque non-empty subject type (no whitelist), required envelope fields, caller-bound
non-empty required_dimensions, distinct producer and reviewer executions.

It checks SHAPE and bindings only. It does not prove the review happened, does not read
the evidence ledger and never emits a receipt. Invalid input -> BLOCK_SUBJECT_CONTRACT_INVALID.
"""
from __future__ import annotations

import json
import re
import sys

BLOCK = "BLOCK_SUBJECT_CONTRACT_INVALID"
REQUIRED_FIELDS = ("subject_type", "subject_ref", "subject_sha256", "source_head_sha",
                   "subject_receipt_id", "producer_execution_id", "reviewer_execution_id",
                   "review_required", "required_dimensions")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SHA1 = re.compile(r"^[0-9a-f]{40}$")


def _text(value) -> bool:
    return isinstance(value, str) and value.strip() != ""


def validate_envelope(envelope) -> tuple[str, str]:
    """Return ("PASS_ENVELOPE_SHAPE", "") or (BLOCK, reason). Fail closed."""
    if not isinstance(envelope, dict):
        return BLOCK, "ENVELOPE_NOT_OBJECT"
    for key in REQUIRED_FIELDS:
        if key not in envelope or envelope[key] in (None, "", [], {}):
            if key == "review_required" and envelope.get(key) is False:
                break
            return BLOCK, "MISSING_" + key
    for key in ("subject_type", "subject_ref", "subject_receipt_id",
                "producer_execution_id", "reviewer_execution_id"):
        if not _text(envelope[key]):
            return BLOCK, "INVALID_" + key
    if not SHA256.match(str(envelope["subject_sha256"])):
        return BLOCK, "INVALID_subject_sha256"
    if not SHA1.match(str(envelope["source_head_sha"])):
        return BLOCK, "INVALID_source_head_sha"
    if envelope["review_required"] is not True:
        return BLOCK, "REVIEW_NOT_REQUIRED_TRUE"
    dims = envelope["required_dimensions"]
    if (not isinstance(dims, list) or not dims
            or not all(_text(d) for d in dims) or len(set(dims)) != len(dims)):
        return BLOCK, "INVALID_required_dimensions"
    if envelope["producer_execution_id"] == envelope["reviewer_execution_id"]:
        return BLOCK, "SELF_REVIEW"
    return "PASS_ENVELOPE_SHAPE", ""


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: validate_independent_review_subject_envelope_v3.py <envelope.json>")
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            envelope = json.load(handle)
    except (OSError, ValueError) as exc:
        print(BLOCK + ":UNREADABLE:" + str(exc))
        return 1
    verdict, reason = validate_envelope(envelope)
    print(verdict + (":" + reason if reason else ""))
    return 0 if verdict.startswith("PASS") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
