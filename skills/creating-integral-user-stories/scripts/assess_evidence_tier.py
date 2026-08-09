#!/usr/bin/env python3
"""Read-only evidence-tier assessor for creating-integral-user-stories.

The assessor does not mutate validation_status. It makes the strength of
existing evidence explicit so file integrity cannot be mistaken for runtime
behavior.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

SHA40 = set("0123456789abcdef")


def valid_hex(value: Any, length: int) -> bool:
    return isinstance(value, str) and len(value) == length and all(c in SHA40 for c in value)


def assess(evidence: dict[str, Any]) -> dict[str, Any]:
    integrity = evidence.get("file_integrity") if isinstance(evidence.get("file_integrity"), dict) else {}
    positive = evidence.get("positive_execution") if isinstance(evidence.get("positive_execution"), dict) else {}
    negative = evidence.get("negative_execution") if isinstance(evidence.get("negative_execution"), dict) else {}
    blocked = evidence.get("blocked_execution") if isinstance(evidence.get("blocked_execution"), dict) else {}
    runtime = evidence.get("runtime_chain") if isinstance(evidence.get("runtime_chain"), dict) else {}
    provenance = evidence.get("source_provenance") if isinstance(evidence.get("source_provenance"), dict) else {}
    scores = evidence.get("independent_scores") if isinstance(evidence.get("independent_scores"), list) else []

    file_integrity = (
        valid_hex(integrity.get("git_blob_sha1"), 40)
        and valid_hex(integrity.get("content_sha256"), 64)
        and valid_hex(integrity.get("commit_sha"), 40)
    )
    external_positive = (
        positive.get("executed") is True
        and positive.get("fixture_external") is True
        and bool(str(positive.get("execution_id") or "").strip())
    )
    rejected_negative = (
        negative.get("executed") is True
        and negative.get("rejected") is True
        and bool(str(negative.get("execution_id") or "").strip())
    )
    real_block = (
        blocked.get("executed") is True
        and blocked.get("blocked") is True
        and bool(str(blocked.get("execution_id") or "").strip())
    )
    runtime_chain = runtime.get("executed") is True and bool(str(runtime.get("execution_id") or "").strip())

    identities, executions = set(), set()
    for item in scores:
        if not isinstance(item, dict):
            continue
        identity = str(item.get("evaluator_identity") or "").strip()
        execution = str(item.get("execution_id") or "").strip()
        if identity and execution and isinstance(item.get("score"), (int, float)):
            identities.add(identity)
            executions.add(execution)
    independent_double_score = len(identities) >= 2 and len(executions) >= 2
    source_confirmed = (
        provenance.get("classification") == "CONFIRMED"
        and provenance.get("resolvable") is True
        and len(str(provenance.get("source_ref") or "").strip()) >= 3
    )

    criteria = {
        "file_integrity": file_integrity,
        "external_positive": external_positive,
        "rejected_negative": rejected_negative,
        "real_block": real_block,
        "runtime_chain": runtime_chain,
        "independent_double_score": independent_double_score,
        "confirmed_resolvable_source": source_confirmed,
    }
    if all(criteria.values()):
        tier = "T1"
    elif file_integrity and external_positive and rejected_negative:
        tier = "T2"
    elif file_integrity and external_positive:
        tier = "T3"
    elif file_integrity:
        tier = "T4"
    else:
        tier = "UNASSESSED"

    return {
        "evidence_tier": tier,
        "criteria": criteria,
        "missing_for_t1": [name for name, passed in criteria.items() if not passed],
        "mutates_validation_status": False,
        "meaning": {
            "T1": "external positive + executed negative + executed block + runtime chain + independent double score + confirmed source",
            "T2": "file integrity + external positive + executed rejected negative",
            "T3": "file integrity + external positive",
            "T4": "file integrity only",
            "UNASSESSED": "file integrity is not proven",
        }[tier],
    }


def sample(tier: str) -> dict[str, Any]:
    base = {
        "file_integrity": {"git_blob_sha1": "a"*40, "content_sha256": "b"*64, "commit_sha": "c"*40},
        "positive_execution": {"executed": True, "fixture_external": True, "execution_id": "EXEC-POS"},
        "negative_execution": {"executed": True, "rejected": True, "execution_id": "EXEC-NEG"},
        "blocked_execution": {"executed": True, "blocked": True, "execution_id": "EXEC-BLOCK"},
        "runtime_chain": {"executed": True, "execution_id": "EXEC-RUNTIME"},
        "independent_scores": [
            {"evaluator_identity": "EVAL-A", "execution_id": "EXEC-SCORE-A", "score": 9.7},
            {"evaluator_identity": "EVAL-B", "execution_id": "EXEC-SCORE-B", "score": 9.6},
        ],
        "source_provenance": {"classification": "CONFIRMED", "source_ref": "SRC-1", "resolvable": True},
    }
    if tier == "T4":
        for key in ("positive_execution","negative_execution","blocked_execution","runtime_chain","independent_scores","source_provenance"):
            base.pop(key, None)
    elif tier == "T3":
        for key in ("negative_execution","blocked_execution","runtime_chain","independent_scores","source_provenance"):
            base.pop(key, None)
    elif tier == "T2":
        for key in ("blocked_execution","runtime_chain","independent_scores","source_provenance"):
            base.pop(key, None)
    elif tier == "UNASSESSED":
        base["file_integrity"]["content_sha256"] = "not-a-sha"
    return base


def self_test() -> int:
    expected = ["T1", "T2", "T3", "T4", "UNASSESSED"]
    observed = {tier: assess(sample(tier))["evidence_tier"] for tier in expected}
    passed = all(observed[tier] == tier for tier in expected)
    print(json.dumps({"self_test_pass": passed, "observed": observed}, sort_keys=True))
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        raise SystemExit("input_required")
    payload = json.loads(args.input.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit("input_must_be_object")
    print(json.dumps(assess(payload), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
