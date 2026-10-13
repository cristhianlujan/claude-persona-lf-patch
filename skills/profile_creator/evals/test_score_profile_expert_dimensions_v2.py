#!/usr/bin/env python3
"""Positive/negative contract tests for the additive expert dimension audit."""
from copy import deepcopy

from score_profile_expert_dimensions_v2 import DIMENSIONS, evaluate_dimensions
from test_score_profile_expert_behavior_v1 import good


def hold():
    return {"holdout_case_ids": [f"C{i:02d}" for i in range(10, 20)]}


def with_telemetry(raw):
    for case in raw["cases"]:
        for arm, record in case["arms"].items():
            record["resource_usage"] = {
                "provider_response_id": "response-" + record["producer_execution_id"],
                "provider_receipt_ref": "provider://" + record["producer_execution_id"],
                "telemetry_verification_ref": "verifier://" + record["evaluator_execution_id"],
                "telemetry_verification_state": "VERIFIED",
                "execution_receipt_sha256": record["execution_receipt_sha256"],
                "token_estimated": False, "input_tokens": 100, "output_tokens": 50,
                "latency_ms": 550, "cost_usd": 0.01,
            }
    return raw


def waves():
    return [
        {"wave_id": "W1", "observed_at": "2026-10-11T11:00:00Z", "cohort_sha256": "a" * 64,
         "evaluator_execution_id": "J1", "producer_execution_id": "P1", "evaluator_receipt_ref": "judge://W1",
         "execution_receipt_ref": "execution://W1",
         "causal_attribution_ref": "ablation://W1", "holdout_receipt_ref": "holdout://W1",
         "evaluator_verification_state": "VERIFIED", "quality_A": 0.60, "quality_D": 0.72},
        {"wave_id": "W2", "observed_at": "2026-10-12T11:00:00Z", "cohort_sha256": "a" * 64,
         "evaluator_execution_id": "J2", "producer_execution_id": "P2", "evaluator_receipt_ref": "judge://W2",
         "execution_receipt_ref": "execution://W2",
         "causal_attribution_ref": "ablation://W2", "holdout_receipt_ref": "holdout://W2",
         "evaluator_verification_state": "VERIFIED", "quality_A": 0.60, "quality_D": 0.77},
    ]


def run():
    raw = good()
    initial = evaluate_dimensions(raw, hold())
    assert initial["status"] == "DIMENSION_EVIDENCE_INCOMPLETE", initial
    assert initial["observed_dimensions"] == 5, initial
    assert initial["missing_dimensions"] == ["robustness", "efficiency", "longitudinal"]
    assert set(initial["dimensions"]) == set(DIMENSIONS)
    assert not initial["cutover_eligible"]

    # Existing expert benchmark evidence alone cannot fabricate three missing facets.
    prepared = with_telemetry(deepcopy(raw))
    for case in prepared["cases"]:
        case["adversarial_case"] = True
    prepared["longitudinal_evidence"] = waves()
    completed = evaluate_dimensions(prepared, hold())
    assert completed["observed_dimensions"] == 8, completed
    assert completed["status"] == "DIMENSION_FIELDS_PRESENT_AWAITING_AUTHENTICATED_READBACK"
    assert completed["dimensions"]["longitudinal"]["change_in_delta"] == 0.05
    assert not completed["expertise_certified"] and not completed["cutover_eligible"]

    tampered = deepcopy(prepared)
    tampered["cases"][0]["arms"]["A_ORIGINAL"]["blind_arm"] = False
    assert evaluate_dimensions(tampered, hold())["status"] == "BLOCK"

    tampered = deepcopy(prepared)
    tampered["cases"][0]["arms"]["D_EVOLUTION_TARGET"]["resource_usage"]["token_estimated"] = True
    result = evaluate_dimensions(tampered, hold())
    assert "efficiency" in result["missing_dimensions"]
    assert result["dimensions"]["efficiency"]["reason"] == "TELEMETRY_UNVERIFIED_OR_UNBOUND"

    tampered = deepcopy(prepared)
    tampered["longitudinal_evidence"][0]["observed_at"] = "2026-10-11T11:00:00"
    assert "longitudinal" in evaluate_dimensions(tampered, hold())["missing_dimensions"]

    tampered = deepcopy(prepared)
    tampered["longitudinal_evidence"][1]["cohort_sha256"] = "b" * 64
    assert "longitudinal" in evaluate_dimensions(tampered, hold())["missing_dimensions"]

    tampered = deepcopy(prepared)
    tampered["longitudinal_evidence"][1]["evaluator_execution_id"] = "J1"
    assert "longitudinal" in evaluate_dimensions(tampered, hold())["missing_dimensions"]

    tampered = deepcopy(prepared)
    tampered["longitudinal_evidence"] = waves()[:1]
    assert "longitudinal" in evaluate_dimensions(tampered, hold())["missing_dimensions"]

    tampered = deepcopy(prepared)
    tampered["cases"][0]["case_id"] = tampered["cases"][1]["case_id"]
    assert evaluate_dimensions(tampered, hold())["status"] == "BLOCK"

    assert evaluate_dimensions(prepared, {"holdout_case_ids": ["NON_EXISTENT"]})["status"] == "BLOCK"
    print("PASS_PROFILE_EXPERT_DIMENSIONS_V2 8_dimensions=1 missing_evidence_negative=1 "
          "fake_telemetry_negative=1 independence_negative=1 no_cutover=1")


if __name__ == "__main__":
    run()
