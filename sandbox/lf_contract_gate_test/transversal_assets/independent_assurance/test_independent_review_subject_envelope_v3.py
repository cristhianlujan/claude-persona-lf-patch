#!/usr/bin/env python3
from __future__ import annotations

import copy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import validate_independent_review_subject_envelope_v3 as v3  # noqa: E402

GOOD = {"subject_type": "ANY_OPAQUE_SUBJECT_TYPE", "subject_ref": "plan/unit/cp",
        "subject_sha256": "a" * 64, "source_head_sha": "b" * 40,
        "subject_receipt_id": "rcpt-1", "producer_execution_id": "px-1",
        "reviewer_execution_id": "rx-2", "review_required": True,
        "required_dimensions": ["d1", "d2"]}


def check(envelope, expected_reason):
    verdict, reason = v3.validate_envelope(envelope)
    assert verdict == v3.BLOCK and reason == expected_reason, (verdict, reason, expected_reason)


def main() -> None:
    assert v3.validate_envelope(GOOD) == ("PASS_ENVELOPE_SHAPE", "")
    # subject type is opaque: no whitelist
    assert v3.validate_envelope(dict(GOOD, subject_type="NEVER_SEEN_BEFORE"))[0].startswith("PASS")
    for key in v3.REQUIRED_FIELDS:
        broken = copy.deepcopy(GOOD)
        del broken[key]
        check(broken, "MISSING_" + key)
    check(None, "ENVELOPE_NOT_OBJECT")
    check(dict(GOOD, subject_sha256="xyz"), "INVALID_subject_sha256")
    check(dict(GOOD, source_head_sha="b" * 39), "INVALID_source_head_sha")
    check(dict(GOOD, subject_type="  "), "INVALID_subject_type")
    check(dict(GOOD, review_required=False), "REVIEW_NOT_REQUIRED_TRUE")
    check(dict(GOOD, required_dimensions=[]), "MISSING_required_dimensions")
    check(dict(GOOD, required_dimensions=["d", "d"]), "INVALID_required_dimensions")
    check(dict(GOOD, required_dimensions="d1"), "INVALID_required_dimensions")
    check(dict(GOOD, reviewer_execution_id="px-1"), "SELF_REVIEW")
    print("PASS_INDEPENDENT_REVIEW_ENVELOPE_V3 positives=2 negatives=%d governed_receipts=0"
          % (len(v3.REQUIRED_FIELDS) + 9))


if __name__ == "__main__":
    main()
