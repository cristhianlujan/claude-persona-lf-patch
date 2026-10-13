#!/usr/bin/env python3
"""Additive eight-dimension evidence audit for the frozen expert benchmark V1.

No change to V1 scoring, admission thresholds, runtime, or authority. All values
derive from paired evaluated task outputs or explicitly supplied observations.
A claim of VERIFIED is not provider attestation: external readback is required.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any

from score_profile_expert_behavior_v1 import ARMS, _max_difficulty, _validate_arm, _weighted

DIMENSIONS = (
    "domain_quality", "complexity", "robustness", "adaptation",
    "transfer", "preservation", "efficiency", "longitudinal",
)
CORE_ARMS = ARMS


def _num(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool) and v == v and abs(v) != float("inf")


def _metric(cases: list[dict], name: str) -> dict:
    if not cases:
        return {"status": "NOT_OBSERVED", "n": 0, "reason": "NO_MATCHED_EXECUTED_CASES"}
    scores = {arm: round(_weighted(cases, arm), 6) for arm in CORE_ARMS}
    return {
        "status": "SCORED_FROM_RECEIPT_FIELDS", "n": len(cases), "scores": scores,
        "delta_D_A": round(scores["D_EVOLUTION_TARGET"] - scores["A_ORIGINAL"], 6),
        "delta_D_C": round(scores["D_EVOLUTION_TARGET"] - scores["C_EVOLUTION_CURRENT"], 6),
        "measure": name,
    }


def _efficiency(cases: list[dict]) -> dict:
    values = {arm: [] for arm in CORE_ARMS}
    for case in cases:
        for arm in CORE_ARMS:
            a = case["arms"][arm]
            u = a.get("resource_usage")
            required = ("provider_response_id", "provider_receipt_ref", "telemetry_verification_ref")
            if not isinstance(u, dict) or any(not u.get(k) for k in required):
                return {"status": "NOT_OBSERVED", "reason": "PROVIDER_TELEMETRY_RECEIPTS_MISSING"}
            if (u.get("telemetry_verification_state") != "VERIFIED"
                    or u.get("token_estimated") is not False
                    or u.get("execution_receipt_sha256") != a["execution_receipt_sha256"]):
                return {"status": "NOT_OBSERVED", "reason": "TELEMETRY_UNVERIFIED_OR_UNBOUND"}
            if any(not _num(u.get(k)) or u[k] < 0 for k in
                   ("input_tokens", "output_tokens", "latency_ms", "cost_usd")):
                return {"status": "NOT_OBSERVED", "reason": "MEASURED_RESOURCE_VALUES_MISSING"}
            values[arm].append(u)
    metrics = {}
    for arm, observations in values.items():
        metrics[arm] = {
            key: round(sum(o[key] for o in observations) / len(observations), 6)
            for key in ("input_tokens", "output_tokens", "latency_ms", "cost_usd")
        }
    return {"status": "REPORTED_TELEMETRY_VERIFICATION", "n": len(cases),
            "averages": metrics, "external_provider_readback_required": True}


def _longitudinal(raw: dict) -> dict:
    waves = raw.get("longitudinal_evidence")
    if not isinstance(waves, list) or len(waves) < 2:
        return {"status": "NOT_OBSERVED", "reason": "TWO_INDEPENDENT_WAVES_REQUIRED"}
    ids, times, evaluator_ids, cohort = set(), [], set(), set()
    deltas = []
    for w in waves:
        if not isinstance(w, dict):
            return {"status": "NOT_OBSERVED", "reason": "WAVE_INVALID"}
        required = ("wave_id", "observed_at", "cohort_sha256", "evaluator_execution_id",
                    "evaluator_receipt_ref", "execution_receipt_ref", "producer_execution_id", "causal_attribution_ref",
                    "holdout_receipt_ref")
        if (any(not w.get(k) for k in required)
                or w.get("evaluator_verification_state") != "VERIFIED"
                or w.get("producer_execution_id") == w.get("evaluator_execution_id")):
            return {"status": "NOT_OBSERVED", "reason": "INDEPENDENT_WAVE_PROVENANCE_MISSING"}
        if (not _num(w.get("quality_A")) or not _num(w.get("quality_D"))
                or not all(0 <= w[k] <= 1 for k in ("quality_A", "quality_D"))):
            return {"status": "NOT_OBSERVED", "reason": "WAVE_SCORE_INVALID"}
        try:
            stamp = datetime.fromisoformat(w["observed_at"].replace("Z", "+00:00"))
            if stamp.tzinfo is None or stamp.utcoffset() is None:
                raise ValueError("Timezone required")
            times.append(stamp)
        except (AttributeError, TypeError, ValueError):
            return {"status": "NOT_OBSERVED", "reason": "WAVE_TIMESTAMP_INVALID"}
        ids.add(w["wave_id"])
        evaluator_ids.add(w["evaluator_execution_id"])
        cohort.add(w["cohort_sha256"])
        deltas.append(w["quality_D"] - w["quality_A"])
    if len(ids) != len(waves) or len(evaluator_ids) != len(waves) or len(cohort) != 1:
        return {"status": "NOT_OBSERVED", "reason": "WAVES_NOT_INDEPENDENT_OR_NOT_COMPARABLE"}
    if not all(a < b for a, b in zip(times, times[1:])):
        return {"status": "NOT_OBSERVED", "reason": "WAVE_TIME_ORDER_INVALID"}
    return {"status": "REPORTED_LONGITUDINAL_VERIFICATION", "waves": len(waves),
            "first_delta_D_A": round(deltas[0], 6),
            "last_delta_D_A": round(deltas[-1], 6),
            "change_in_delta": round(deltas[-1] - deltas[0], 6),
            "external_source_readback_required": True}


def evaluate_dimensions(raw: dict, holdout: dict) -> dict:
    """Secondary measurements. NEVER authorizes benchmark PASS or cutover."""
    blockers = []
    if raw.get("benchmark_scope") != "EXPERT_TASK_PERFORMANCE_E2E" or raw.get("raw_frozen") is not True:
        blockers.append("FROZEN_EXPERT_RAW_REQUIRED")
    cases = raw.get("cases")
    if not isinstance(cases, list) or not cases:
        blockers.append("PAIRED_TASK_CASES_MISSING")
        cases = []
    ids = [c.get("case_id") for c in cases if isinstance(c, dict)]
    hold_ids = holdout.get("holdout_case_ids") if isinstance(holdout, dict) else None
    if (len(ids) != len(cases) or any(not i for i in ids) or len(set(ids)) != len(ids)
            or not isinstance(hold_ids, list) or not hold_ids
            or not set(hold_ids).issubset(set(ids)) or len(hold_ids) != len(set(hold_ids))):
        blockers.append("CASE_OR_HOLDOUT_IDENTITY_INVALID")
    for case in cases:
        if not isinstance(case, dict):
            blockers.append("CASE_INVALID")
            continue
        if not isinstance(case.get("difficulty"), int) or isinstance(case["difficulty"], bool) or not 1 <= case["difficulty"] <= 5:
            blockers.append("DIFFICULTY_INVALID")
        if not case.get("domain_family") or not isinstance(case.get("arms"), dict):
            blockers.append("CASE_FAMILY_OR_ARMS_INVALID")
            continue
        for arm in ARMS:
            if _validate_arm(case["arms"].get(arm)):
                blockers.append("EXECUTION_OR_INDEPENDENT_EVALUATION_UNVERIFIED")
    if blockers:
        return {"schema": "PROFILE_EXPERT_DIMENSIONS_V2", "status": "BLOCK",
                "blocking_codes": sorted(set(blockers)), "cutover_eligible": False}

    metrics = {
        "domain_quality": _metric(cases, "difficulty_weighted_quality"),
        "complexity": {"status": "SCORED_FROM_RECEIPT_FIELDS", "n": len(cases),
                       "max_difficulty_solved": {a: _max_difficulty(cases, a) for a in CORE_ARMS}},
        "robustness": _metric([c for c in cases if c.get("adversarial_case") is True], "adversarial_quality"),
        "adaptation": _metric([c for c in cases if c.get("adaptation_case") is True], "adaptation_quality"),
        "transfer": _metric([c for c in cases if c.get("transfer_case") is True], "transfer_quality"),
        "preservation": _metric([c for c in cases if c.get("preservation_case") is True], "preservation_quality"),
        "efficiency": _efficiency(cases),
        "longitudinal": _longitudinal(raw),
    }
    missing = [k for k, v in metrics.items() if v["status"] == "NOT_OBSERVED"]
    return {"schema": "PROFILE_EXPERT_DIMENSIONS_V2",
            "status": "DIMENSION_EVIDENCE_INCOMPLETE" if missing else "DIMENSION_FIELDS_PRESENT_AWAITING_AUTHENTICATED_READBACK",
            "dimensions": metrics, "observed_dimensions": len(metrics) - len(missing),
            "required_dimensions": len(DIMENSIONS), "missing_dimensions": missing,
            "evidence_limit": "RECEIPT_FIELDS_ONLY_EXTERNAL_AUTHENTICITY_NOT_VERIFIED",
            "expertise_certified": False, "cutover_eligible": False}
