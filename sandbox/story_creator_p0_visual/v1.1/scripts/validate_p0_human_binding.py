#!/usr/bin/env python3
"""Fail-closed temporal/binding checks for a future authenticated P0 human review.

This validator never establishes human authenticity. A local JSON object can
only prove contract binding; P0-4 still requires an authenticated external
readback of the real reviewer action and reviewable source evidence.
"""
from __future__ import annotations

import argparse
import copy
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HUMAN_ACTIONS = {
    "CONFIRM_OBSERVATION",
    "CORRECT_WITH_ADJUDICATION",
    "REQUEST_NEW_CAPTURE",
    "REQUEST_ADDITIONAL_CONTEXT",
    "REJECT_AND_BLOCK",
    "ESCALATE_SECURITY",
    "ESCALATE_PRIVACY",
}
REVIEWER_ROLES = {"P0_VISUAL_ADJUDICATOR", "P0_SECURITY_REVIEWER", "P0_PRIVACY_REVIEWER"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc)


def validate_binding(challenge: Any, candidate: Any, *, now: datetime) -> dict[str, Any]:
    if not isinstance(challenge, dict) or not isinstance(candidate, dict):
        return {"result": "BLOCKED", "blocking_assertions": ["binding_objects_invalid"], "human_authenticity_claimed": False, "p0_4_closed": False}
    issued = parse_time(challenge.get("issued_at"))
    expires = parse_time(challenge.get("expires_at"))
    comment_time = parse_time(candidate.get("comment_created_at"))
    actions = challenge.get("reviewer_actions") if isinstance(challenge.get("reviewer_actions"), list) else []
    checks = {
        "challenge_id_missing": 0 if isinstance(challenge.get("challenge_id"), str) and len(challenge["challenge_id"]) >= 3 else 1,
        "review_id_missing": 0 if isinstance(challenge.get("review_id"), str) and len(challenge["review_id"]) >= 3 else 1,
        "head_sha_invalid": 0 if isinstance(challenge.get("head_sha"), str) and SHA1_RE.fullmatch(challenge["head_sha"]) else 1,
        "visual_output_sha_invalid": 0 if isinstance(challenge.get("visual_output_sha256"), str) and SHA256_RE.fullmatch(challenge["visual_output_sha256"]) else 1,
        "reviewer_actions_not_exact": 0 if set(actions) == HUMAN_ACTIONS and len(actions) == len(HUMAN_ACTIONS) else 1,
        "reviewer_role_invalid": 0 if challenge.get("required_reviewer_role") in REVIEWER_ROLES else 1,
        "challenge_time_invalid": 0 if issued is not None and expires is not None and issued < expires else 1,
        "challenge_not_yet_valid": 0 if issued is not None and issued <= now else 1,
        "challenge_expired": 0 if expires is not None and now < expires else 1,
        "comment_time_invalid": 0 if comment_time is not None else 1,
        "comment_before_challenge": 0 if issued is not None and comment_time is not None and issued <= comment_time else 1,
        "comment_after_expiry": 0 if expires is not None and comment_time is not None and comment_time < expires else 1,
        "challenge_id_mismatch": 0 if candidate.get("challenge_id") == challenge.get("challenge_id") else 1,
        "review_id_mismatch": 0 if candidate.get("review_id") == challenge.get("review_id") else 1,
        "head_sha_mismatch": 0 if candidate.get("head_sha") == challenge.get("head_sha") else 1,
        "visual_output_sha_mismatch": 0 if candidate.get("visual_output_sha256") == challenge.get("visual_output_sha256") else 1,
        "reviewer_role_mismatch": 0 if candidate.get("reviewer_role") == challenge.get("required_reviewer_role") else 1,
        "action_not_governed": 0 if candidate.get("action") in HUMAN_ACTIONS and candidate.get("action") in actions else 1,
        "reviewer_identity_missing": 0 if isinstance(candidate.get("reviewer_identity"), str) and len(candidate["reviewer_identity"]) >= 3 else 1,
        "comment_id_missing": 0 if isinstance(candidate.get("comment_id"), int) and candidate["comment_id"] > 0 else 1,
    }
    failed = sorted(key for key, count in checks.items() if count)
    return {
        "result": "PASS_BINDING_EXTERNAL_AUTH_REQUIRED" if not failed else "BLOCKED",
        "blocking_assertions": failed,
        "checks": checks,
        "reviewer_action_count": len(actions),
        "human_authenticity_claimed": False,
        "authenticated_external_readback_required": True,
        "p0_4_closed": False,
    }


def fixture() -> tuple[dict[str, Any], dict[str, Any], datetime]:
    challenge = {
        "challenge_id": "CH-P0-BINDING-TEST",
        "review_id": "REV-P0-BINDING-TEST",
        "head_sha": "a" * 40,
        "visual_output_sha256": "b" * 64,
        "reviewer_actions": sorted(HUMAN_ACTIONS),
        "required_reviewer_role": "P0_VISUAL_ADJUDICATOR",
        "issued_at": "2026-08-09T10:00:00Z",
        "expires_at": "2026-08-09T14:00:00Z",
    }
    candidate = {
        "challenge_id": challenge["challenge_id"],
        "review_id": challenge["review_id"],
        "head_sha": challenge["head_sha"],
        "visual_output_sha256": challenge["visual_output_sha256"],
        "reviewer_identity": "synthetic-contract-identity",
        "reviewer_role": challenge["required_reviewer_role"],
        "action": "CONFIRM_OBSERVATION",
        "comment_id": 1,
        "comment_created_at": "2026-08-09T11:00:00Z",
    }
    return challenge, candidate, datetime(2026, 8, 9, 12, 0, tzinfo=timezone.utc)


def self_test() -> int:
    challenge, candidate, now = fixture()
    positive = validate_binding(challenge, candidate, now=now)
    cases: list[tuple[str, dict[str, Any], dict[str, Any], datetime, str]] = []
    c = copy.deepcopy(challenge); c["reviewer_actions"] = c["reviewer_actions"][:3]; cases.append(("reviewer_actions_truncated", c, candidate, now, "reviewer_actions_not_exact"))
    c = copy.deepcopy(challenge); c["expires_at"] = "2026-08-09T11:30:00Z"; cases.append(("expired", c, candidate, now, "challenge_expired"))
    c = copy.deepcopy(challenge); c["issued_at"] = "2026-08-09T12:30:00Z"; cases.append(("not_yet_valid", c, candidate, now, "challenge_not_yet_valid"))
    a = copy.deepcopy(candidate); a["comment_created_at"] = "2026-08-09T09:59:59Z"; cases.append(("comment_before_issued", challenge, a, now, "comment_before_challenge"))
    a = copy.deepcopy(candidate); a["comment_created_at"] = "2026-08-09T14:00:00Z"; cases.append(("comment_at_expiry", challenge, a, now, "comment_after_expiry"))
    a = copy.deepcopy(candidate); a["challenge_id"] = "CH-OTHER"; cases.append(("challenge_mismatch", challenge, a, now, "challenge_id_mismatch"))
    a = copy.deepcopy(candidate); a["head_sha"] = "c" * 40; cases.append(("head_mismatch", challenge, a, now, "head_sha_mismatch"))
    a = copy.deepcopy(candidate); a["visual_output_sha256"] = "d" * 64; cases.append(("visual_hash_mismatch", challenge, a, now, "visual_output_sha_mismatch"))
    a = copy.deepcopy(candidate); a["reviewer_role"] = "P0_SECURITY_REVIEWER"; cases.append(("role_mismatch", challenge, a, now, "reviewer_role_mismatch"))
    a = copy.deepcopy(candidate); a["action"] = "APPROVE_ALL"; cases.append(("unknown_action", challenge, a, now, "action_not_governed"))
    outcomes = []
    for name, test_challenge, test_candidate, test_now, expected in cases:
        result = validate_binding(test_challenge, test_candidate, now=test_now)
        outcomes.append({"name": name, "expected_assertion": expected, "passed": result["result"] == "BLOCKED" and expected in result["blocking_assertions"]})
    passed = positive["result"] == "PASS_BINDING_EXTERNAL_AUTH_REQUIRED" and positive["reviewer_action_count"] == 7 and positive["human_authenticity_claimed"] is False and all(item["passed"] for item in outcomes)
    print(json.dumps({
        "schema_version": "p0-human-binding-selftest/v1",
        "evidence_mode": "SYNTHETIC_CONTRACT_FIXTURE",
        "positive_binding_contract_pass": positive["result"] == "PASS_BINDING_EXTERNAL_AUTH_REQUIRED",
        "reviewer_actions_exact": positive["reviewer_action_count"] == 7,
        "negative_cases_passed": sum(item["passed"] for item in outcomes),
        "negative_cases_total": len(outcomes),
        "negative_results": outcomes,
        "human_attestation_claimed": False,
        "authenticated_external_readback_required": True,
        "p0_4_closed": False,
        "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED",
    }, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--challenge", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--now")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.challenge is None or args.candidate is None or args.now is None:
        parser.error("--challenge, --candidate and --now are required outside --self-test")
    now = parse_time(args.now)
    if now is None:
        parser.error("--now must be an ISO-8601 timezone-aware timestamp")
    result = validate_binding(json.loads(args.challenge.read_text()), json.loads(args.candidate.read_text()), now=now)
    print(json.dumps(result, sort_keys=True))
    return 0 if result["result"] == "PASS_BINDING_EXTERNAL_AUTH_REQUIRED" else 2


if __name__ == "__main__":
    raise SystemExit(main())
