#!/usr/bin/env python3
from __future__ import annotations

from typing import Any


def evaluate(payload: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {"status": "NEEDS_MORE_EVIDENCE", "blocking_codes": ["LEARNING_PAYLOAD_INVALID"]}
    required = ("observation_refs","candidate_lesson","repeat_count","cross_case_refs","holdout_ref","admission_ref")
    missing = [k for k in required if payload.get(k) in (None, "", [], {})]
    if missing:
        return {"status": "NEEDS_MORE_EVIDENCE", "blocking_codes": ["LEARNING_EVIDENCE_INCOMPLETE"], "missing": missing}
    if not isinstance(payload.get("repeat_count"), int) or payload["repeat_count"] < 2:
        return {"status": "NEEDS_MORE_EVIDENCE", "blocking_codes": ["REPEATED_EVIDENCE_NOT_DEMONSTRATED"]}
    if payload.get("admission_verdict") != "PASS":
        return {"status": "REJECT", "blocking_codes": ["LEARNING_ADMISSION_NOT_PASS"]}
    return {"status": "ADMIT_REUSABLE_PATTERN", "blocking_codes": [], "auto_promoted": False}


if __name__ == "__main__":
    import json, sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    print(json.dumps(evaluate(data), sort_keys=True))
