#!/usr/bin/env python3
"""Exact paired-binary McNemar as an additive Profile Evolution evaluation method.

Uses the existing frozen four-arm expert benchmark and its paired-bootstrap
helper. It cannot change any admission, scorer V1, profile, or runtime status.
"""
from __future__ import annotations

from math import comb
from typing import Any

from score_profile_expert_behavior_v1 import ARMS, _bootstrap, _validate_arm

COMPARISONS = (
    ("D_vs_A", "D_EVOLUTION_TARGET", "A_ORIGINAL", 20261013),
    ("D_vs_C", "D_EVOLUTION_TARGET", "C_EVOLUTION_CURRENT", 20261014),
)


def _binary_source_valid(arm: dict) -> bool:
    return (type(arm.get("binary_correct")) is bool
            and arm.get("binary_outcome_verification_state") == "VERIFIED"
            and isinstance(arm.get("binary_outcome_receipt_ref"), str)
            and bool(arm["binary_outcome_receipt_ref"].strip()))


def _paired(cases: list[dict], better: str, baseline: str, seed: int) -> dict:
    # b: baseline correct / candidate wrong; c: candidate correct / baseline wrong.
    b = sum(1 for x in cases if x["arms"][baseline]["binary_correct"] is True
            and x["arms"][better]["binary_correct"] is False)
    c = sum(1 for x in cases if x["arms"][baseline]["binary_correct"] is False
            and x["arms"][better]["binary_correct"] is True)
    n = b + c
    p = min(1.0, 2.0 * sum(comb(n, i) for i in range(min(b, c) + 1)) / (2 ** n))
    diffs = [int(x["arms"][better]["binary_correct"]) -
             int(x["arms"][baseline]["binary_correct"]) for x in cases]
    return {
        "paired_cases": len(cases),
        "discordant_cases": n,
        "candidate_wins": c,
        "candidate_losses": b,
        "candidate_gain_rate": round(sum(diffs) / len(diffs), 6),
        "mcnemar_exact_two_sided_p": round(p, 12),
        "paired_gain_bootstrap_ci95": _bootstrap(diffs, seed),
        "limitation": "NO_MULTIPLICITY_ADJUSTMENT_NO_CAUSAL_ATTRIBUTION",
    }


def evaluate_mcnemar(raw: dict[str, Any], holdout: dict[str, Any]) -> dict[str, Any]:
    base = {"schema": "PROFILE_PAIRED_BINARY_MCNEMAR_V1",
            "expertise_certified": False, "cutover_eligible": False}
    if not isinstance(raw, dict) or not isinstance(holdout, dict):
        return {**base, "status": "BLOCK", "reasons": ["INPUT_INVALID"]}
    if (raw.get("benchmark_scope") != "EXPERT_TASK_PERFORMANCE_E2E"
            or raw.get("raw_frozen") is not True
            or raw.get("thresholds_frozen_before_raw") is not True):
        return {**base, "status": "BLOCK", "reasons": ["FROZEN_EXPERT_BENCHMARK_REQUIRED"]}
    cases, ids = raw.get("cases"), holdout.get("holdout_case_ids")
    if (not isinstance(cases, list) or not cases
            or not isinstance(ids, list) or not ids
            or any(not isinstance(x, str) or not x for x in ids)
            or len(set(ids)) != len(ids)):
        return {**base, "status": "BLOCK", "reasons": ["CASE_OR_HOLDOUT_INVALID"]}
    case_ids = []
    for x in cases:
        if not isinstance(x, dict) or not isinstance(x.get("case_id"), str):
            return {**base, "status": "BLOCK", "reasons": ["CASE_ID_INVALID"]}
        case_ids.append(x["case_id"])
        if not isinstance(x.get("arms"), dict):
            return {**base, "status": "BLOCK", "reasons": ["ARMS_INVALID"]}
        if any(_validate_arm(x["arms"].get(arm)) for arm in ARMS):
            return {**base, "status": "BLOCK", "reasons": ["BLIND_INDEPENDENT_EVALUATOR_REQUIRED"]}
    if len(set(case_ids)) != len(case_ids) or not set(ids).issubset(set(case_ids)):
        return {**base, "status": "BLOCK", "reasons": ["CASE_HOLDOUT_MISMATCH"]}
    if any(not _binary_source_valid(x["arms"][arm]) for x in cases
           for arm in ("A_ORIGINAL", "C_EVOLUTION_CURRENT", "D_EVOLUTION_TARGET")):
        return {**base, "status": "NOT_OBSERVED",
                "reasons": ["BINARY_OUTCOMES_NOT_INDEPENDENTLY_VERIFIED_OR_MISSING"]}
    holdcases = [x for x in cases if x["case_id"] in set(ids)]
    paired = {name: {
        "all": _paired(cases, higher, lower, seed),
        "holdout": _paired(holdcases, higher, lower, seed + 100),
    } for name, higher, lower, seed in COMPARISONS}
    return {
        **base, "status": "REPORTED_STATS_AWAITING_AUTHENTICATED_READBACK",
        "comparisons": paired, "case_count": len(cases),
        "holdout_count": len(holdcases),
        "evidence_limit": "FIELD_LEVEL_VERIFIED_ASSERTIONS_DO_NOT_ESTABLISH_PROVIDER_AUTHENTICITY",
        "statistical_policy": "P_VALUES_ARE_DESCRIPTIVE; PRE_FROZEN_ALPHA_AND_MULTIPLICITY_REQUIRED_FOR_ANY_DECISION",
    }
