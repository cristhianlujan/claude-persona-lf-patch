#!/usr/bin/env python3
"""Map a governed P0 effective handoff into the Screen Decomposer input contract."""
from __future__ import annotations

import argparse
import copy
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from validate_p0_j02_handoff import canonical_sha, load, positive_fixture, validate
from validate_p0_human_binding import (
    build_binding,
    canonical_sha as challenge_sha,
    fetch_comment,
    synthetic_comment,
    verify as verify_comment,
    verify_binding_receipt,
)


def strip_classification(item: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in item.items() if key != "classification"}


def adapt(payload: dict[str, Any], *, challenge: dict[str, Any] | None = None, binding_fetcher=None) -> dict[str, Any]:
    gate = validate(payload)
    if gate["result"] != "PASS_WITH_EVIDENCE":
        raise ValueError("p0_j02_handoff_blocked:" + ",".join(gate["blocking_assertions"]))
    decision = payload["effective_decision"]
    provenance = payload["provenance"]
    live_binding = None
    if decision.get("judge_code") == "J00R_P0_REJUDGMENT":
        human = payload.get("human_review_decision") or {}
        binding = human.get("authentication_binding") or {}
        if not isinstance(challenge, dict):
            raise ValueError("p0_j02_handoff_blocked:j00r_live_challenge_required")
        challenge_checks = {
            "review_id": challenge.get("review_id") == human.get("review_id"),
            "visual_output_sha256": challenge.get("visual_output_sha256") == payload.get("visual_output_sha256"),
            "challenge_sha256": challenge_sha(challenge) == human.get("challenge_sha256"),
        }
        if not all(challenge_checks.values()):
            failed = sorted(key for key, ok in challenge_checks.items() if not ok)
            raise ValueError("p0_j02_handoff_blocked:j00r_challenge_mismatch:" + ",".join(failed))
        kwargs = {"fetcher": binding_fetcher} if binding_fetcher is not None else {}
        live_binding = verify_binding_receipt(challenge, human.get("decision"), binding, **kwargs)
        if live_binding.get("result") != "LIVE_BINDING_VERIFIED":
            raise ValueError("p0_j02_handoff_blocked:j00r_live_binding_failed:" + ",".join(live_binding.get("blocking_assertions") or []))
    return {
        "worker_profile": "PERFIL_SCREEN_DECOMPOSER_LF",
        "target_screen_code": payload["target_screen_code"],
        "source_snapshot": {
            "screen_code": payload["target_screen_code"],
            "version": payload["source_version"],
            "sha256": payload["source_snapshot_sha256"],
            "source_refs": provenance["source_refs"],
        },
        "context_inventory": [strip_classification(item) for item in payload["context_inventory"]],
        "field_inventory": [strip_classification(item) for item in payload["field_inventory"]],
        "permission_inventory": [strip_classification(item) for item in payload["permission_inventory"]],
        "transition_inventory": [strip_classification(item) for item in payload["transition_inventory"]],
        "action_inventory": [strip_classification(item) for item in payload["action_inventory"]],
        "pending_decisions": payload["pending_decisions"],
        "p0_provenance": {
            "handoff_schema_version": payload["schema_version"],
            "handoff_sha256": canonical_sha(payload),
            "p0_execution_id": provenance["p0_execution_id"],
            "effective_decision_id": decision["decision_id"],
            "effective_judge": decision["judge_code"],
            "effective_result": decision["result"],
            "visual_output_sha256": payload["visual_output_sha256"],
            "architecture_source_sha256": provenance["architecture_source_sha256"],
            "evidence_refs": payload["evidence_refs"],
            "human_binding_live_verified": live_binding is not None,
            "human_binding_comment_id": live_binding.get("comment_id") if live_binding else None,
        },
        "next_step": "SCREEN_DECOMPOSITION",
        "next_judge": "J02_SCREEN_DECOMPOSITION",
    }


def self_test() -> int:
    good = positive_fixture()
    out = adapt(good)
    checks = {
        "target_preserved": out["target_screen_code"] == good["target_screen_code"],
        "source_hash_preserved": out["source_snapshot"]["sha256"] == good["source_snapshot_sha256"],
        "decision_preserved": out["p0_provenance"]["effective_decision_id"] == good["effective_decision"]["decision_id"],
        "visual_hash_preserved": out["p0_provenance"]["visual_output_sha256"] == good["visual_output_sha256"],
        "classification_not_leaked": all("classification" not in item for key in ("context_inventory", "field_inventory", "permission_inventory", "transition_inventory", "action_inventory") for item in out[key]),
        "routes_to_j02": out["next_judge"] == "J02_SCREEN_DECOMPOSITION",
    }
    blocked = dict(good); blocked["effective_decision"] = dict(good["effective_decision"], is_current=False)
    rejects_stale = False
    try:
        adapt(blocked)
    except ValueError:
        rejects_stale = True
    forged_j00r = dict(good); forged_j00r["effective_decision"] = dict(good["effective_decision"], judge_code="J00R_P0_REJUDGMENT", result="J00R_READY_FOR_P1")
    rejects_unadjudicated_j00r = False
    try:
        adapt(forged_j00r)
    except ValueError:
        rejects_unadjudicated_j00r = True
    fake_overlay = dict(good); fake_overlay["effective_decision"] = dict(good["effective_decision"], decision_id="DEC-P0R-FAKE", judge_code="J00R_P0_REJUDGMENT", result="J00R_READY_FOR_P1", judge_execution_id="EXEC-J00R-FAKE", judge_identity="AGENT-J00R-FAKE", adjudication_overlay_ref="x")
    fake_overlay["evidence_refs"] = ["p0://decision/DEC-P0R-FAKE"]
    rejects_fake_overlay = False
    try:
        adapt(fake_overlay)
    except ValueError:
        rejects_fake_overlay = True
    challenge = {
        "schema_version": "p0-human-review-challenge/v1", "review_id": "REV-LIVE-1", "target_screen_code": "SCR-LOGIN",
        "visual_output_sha256": good["visual_output_sha256"], "source_raw_sha256": "a" * 64, "expected_reviewer_provider": "GITHUB",
        "expected_reviewer_login": "cristhianlujan", "reviewer_role": "P0_VISUAL_ADJUDICATOR", "reviewer_scope": "LF-SANDBOX",
        "review_resource_type": "ISSUE", "review_resource_number": 999, "review_resource_url": "https://github.com/cristhianlujan/claude-persona-lf-patch/issues/999",
        "training_ack_code": "P0-REVIEW-BRIEF-v1", "training_brief_ref": "p0://review-brief/P0-REVIEW-BRIEF-v1", "training_brief_sha256": "b" * 64,
        "allowed_decisions": ["CONFIRM_OBSERVATION"], "nonce": "nonce_LIVE_1234567890",
        "issued_at": "2026-08-08T00:00:00Z", "expires_at": "2026-08-09T00:00:00Z",
    }
    comment = synthetic_comment(challenge, "CONFIRM_OBSERVATION")
    verified = verify_comment(challenge, "CONFIRM_OBSERVATION", comment, now=datetime(2026, 8, 8, 12, 0, tzinfo=timezone.utc))
    binding = build_binding(challenge, comment, verified, resource_number=999, verified_at="2026-08-08T01:00:00Z")
    live_j00r = copy.deepcopy(good)
    live_j00r["effective_decision"].update({"decision_id": "DEC-P0R-LIVE-1", "judge_code": "J00R_P0_REJUDGMENT", "result": "J00R_READY_FOR_P1", "judge_execution_id": "EXEC-J00R-LIVE-1", "judge_identity": "AGENT-J00R-LIVE-1", "adjudication_overlay_ref": "p0://adjudication/REV-LIVE-1"})
    live_j00r["human_review_decision"] = {"review_id": "REV-LIVE-1", "reviewer_identity": "github:cristhianlujan", "reviewer_role": "P0_VISUAL_ADJUDICATOR", "decision": "CONFIRM_OBSERVATION", "visual_output_sha256": good["visual_output_sha256"], "challenge_ref": "p0://challenge/REV-LIVE-1", "challenge_sha256": challenge_sha(challenge), "authentication_binding": binding, "adjudication_overlay_ref": "p0://adjudication/REV-LIVE-1", "created_at": "2026-08-08T01:00:00Z"}
    live_j00r["evidence_refs"] = ["p0://decision/DEC-P0R-LIVE-1", "p0://challenge/REV-LIVE-1", "p0://adjudication/REV-LIVE-1"]
    live_j00r_routed = False
    try:
        routed = adapt(live_j00r, challenge=challenge, binding_fetcher=lambda _: comment)
        live_j00r_routed = routed["next_judge"] == "J02_SCREEN_DECOMPOSITION" and routed["p0_provenance"]["human_binding_live_verified"] is True
    except ValueError:
        pass
    forged_receipt = copy.deepcopy(live_j00r)
    forged_receipt["human_review_decision"]["authentication_binding"]["comment_id"] += 1
    rejects_forged_receipt = False
    try:
        adapt(forged_receipt, challenge=challenge, binding_fetcher=lambda _: comment)
    except ValueError:
        rejects_forged_receipt = True
    rejects_missing_live_challenge = False
    try:
        adapt(live_j00r)
    except ValueError:
        rejects_missing_live_challenge = True
    passed = all(checks.values()) and rejects_stale and rejects_unadjudicated_j00r and rejects_fake_overlay and live_j00r_routed and rejects_forged_receipt and rejects_missing_live_challenge
    print(json.dumps({"checks": checks, "rejects_stale": rejects_stale, "rejects_unadjudicated_j00r": rejects_unadjudicated_j00r, "rejects_fake_overlay": rejects_fake_overlay, "live_j00r_routes_to_j02": live_j00r_routed, "rejects_forged_live_receipt": rejects_forged_receipt, "rejects_missing_live_challenge": rejects_missing_live_challenge, "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED"}, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--challenge", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        parser.error("input is required unless --self-test is used")
    try:
        output = adapt(load(args.input), challenge=load(args.challenge) if args.challenge else None)
    except ValueError as exc:
        print(json.dumps({"result": "BLOCKED", "error": str(exc)}, sort_keys=True))
        return 2
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
