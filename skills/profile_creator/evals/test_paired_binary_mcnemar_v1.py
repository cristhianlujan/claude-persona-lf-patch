#!/usr/bin/env python3
"""McNemar exact negative controls, zero-discordance and frozen holdout tests."""
from copy import deepcopy

from paired_binary_mcnemar_v1 import evaluate_mcnemar
from test_score_profile_expert_behavior_v1 import good


def setup():
    raw = good()
    hold = {"holdout_case_ids": [f"C{i:02d}" for i in range(10, 20)]}
    for i, case in enumerate(raw["cases"]):
        for arm, value in case["arms"].items():
            value["binary_correct"] = arm == "D_EVOLUTION_TARGET"
            value["binary_outcome_receipt_ref"] = "verifier://" + value["evaluator_execution_id"]
            value["binary_outcome_verification_state"] = "VERIFIED"
    return raw, hold


def run():
    raw, hold = setup()
    r = evaluate_mcnemar(raw, hold)
    assert r["status"] == "REPORTED_STATS_AWAITING_AUTHENTICATED_READBACK", r
    a = r["comparisons"]["D_vs_A"]
    assert a["all"]["candidate_wins"] == 20 and a["all"]["candidate_losses"] == 0
    assert a["all"]["mcnemar_exact_two_sided_p"] == 0.000001907349
    assert a["holdout"]["candidate_wins"] == 10
    assert a["holdout"]["mcnemar_exact_two_sided_p"] == 0.001953125
    assert not r["cutover_eligible"] and not r["expertise_certified"]

    # No discordances is not evidence for superiority.
    equal = deepcopy(raw)
    for case in equal["cases"]:
        case["arms"]["A_ORIGINAL"]["binary_correct"] = True
    q = evaluate_mcnemar(equal, hold)
    assert q["comparisons"]["D_vs_A"]["all"]["mcnemar_exact_two_sided_p"] == 1.0
    assert q["comparisons"]["D_vs_A"]["all"]["discordant_cases"] == 0

    negative = deepcopy(raw)
    negative["cases"][0]["arms"]["D_EVOLUTION_TARGET"].pop("binary_correct")
    assert evaluate_mcnemar(negative, hold)["status"] == "NOT_OBSERVED"
    negative = deepcopy(raw)
    negative["cases"][0]["arms"]["D_EVOLUTION_TARGET"]["binary_outcome_verification_state"] = "UNVERIFIED"
    assert evaluate_mcnemar(negative, hold)["status"] == "NOT_OBSERVED"
    negative = deepcopy(raw)
    negative["cases"][0]["arms"]["D_EVOLUTION_TARGET"]["blind_arm"] = False
    assert evaluate_mcnemar(negative, hold)["status"] == "BLOCK"
    negative = deepcopy(raw)
    negative["raw_frozen"] = False
    assert evaluate_mcnemar(negative, hold)["status"] == "BLOCK"
    negative = deepcopy(raw)
    negative["cases"][0]["case_id"] = negative["cases"][1]["case_id"]
    assert evaluate_mcnemar(negative, hold)["status"] == "BLOCK"
    assert evaluate_mcnemar(raw, {"holdout_case_ids": ["FAKE"]})["status"] == "BLOCK"
    assert evaluate_mcnemar(None, hold)["status"] == "BLOCK"
    print("PASS_PROFILE_PAIRED_BINARY_MCNEMAR_V1 exact_p=1 paired_holdout=1 "
          "zero_discordance=1 missing_binary_negative=1 independent_judge_negative=1 no_cutover=1")


if __name__ == "__main__":
    run()
