#!/usr/bin/env python3
"""Pre-quality utility floor only; never an independent semantic judge.

The canonical validator owns schema, routing, rubric and GOV-037 gates. This
module adds only a conservative semantic floor, and grants no promotion or
Quality PASS authority.
"""
from __future__ import annotations

PLACEHOLDERS = {"todo", "tbd", "unknown", "pending", "placeholder", "lorem ipsum"}


def evaluate(payload, contract_gate=None, evidence_manifest=None):
    if isinstance(payload, dict) and isinstance(payload.get("candidate"), dict):
        payload = payload["candidate"]
    if not isinstance(payload, dict) or not isinstance(contract_gate, dict) or contract_gate.get("status") != "PASS":
        return {
            "status": "BLOCKED",
            "blocking_codes": ["QUALITY_CANONICAL_VALIDATOR_REQUIRED"],
            "independent_review_executed": False,
            "promotion_authorized": False,
        }

    errors = []
    for field in ("review_id", "reviewed_artifact", "next_gate"):
        text = payload.get(field)
        if not isinstance(text, str) or text.strip().lower() in PLACEHOLDERS:
            errors.append("QUALITY_UTILITY_PLACEHOLDER:" + field)
    for item in payload.get("remaining_risks", []):
        if isinstance(item, str) and item.strip().lower() in PLACEHOLDERS:
            errors.append("QUALITY_UTILITY_UNSPECIFIED_RISK")
    return {
        "status": "PASS" if not errors else "BLOCKED",
        "blocking_codes": sorted(set(errors)),
        "independent_review_executed": False,
        "promotion_authorized": False,
        "quality_verdict": payload.get("verdict"),
        "authority": "PROFILE_LOCAL_PRE_QUALITY_UTILITY_ONLY",
    }
