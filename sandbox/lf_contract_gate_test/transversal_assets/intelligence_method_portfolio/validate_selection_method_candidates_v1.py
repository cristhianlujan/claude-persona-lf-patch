#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load(name: str):
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


def require(cond: bool, msg: str):
    if not cond:
        raise AssertionError(msg)


def validate(requal, rebind, challengers, batch):
    checks = 0
    require(requal["result"]["historical_methods_checked"] == 7, "historical method count"); checks += 1
    require(requal["result"]["eligible_methods"] == 0, "historical prior art must not be runtime eligible"); checks += 1
    require(requal["authority_readback"]["selection_method_registry_matches"] == 0, "unexpected current method authority"); checks += 1

    methods = {m["historical_id"]: m for m in rebind["candidates"]}
    require(set(methods) == {f"IG0{i}" for i in range(7)}, "IG00..IG06 exact set"); checks += 1
    require(all(not m["eligible_for_runtime_selection"] for m in methods.values()), "candidate promoted prematurely"); checks += 1
    require(all(m["release_state"] == "CANDIDATE" for m in methods.values()), "non-candidate release state"); checks += 1
    require(methods["IG01"]["source_version"] == "arXiv:2601.10112v1", "RIG version"); checks += 1
    require(methods["IG02"]["source_version"] == "arXiv:2606.01385v1", "MAAD version"); checks += 1
    require(methods["IG03"]["source_version"] == "arXiv:2607.18886v1", "TraceDev version"); checks += 1
    require(methods["IG04"]["source_version"] == "arXiv:2607.00269v3", "Mnemosyne current version"); checks += 1
    require(methods["IG05"]["mix_mode"] == "UNION_COMPLEMENTARY" and methods["IG06"]["mix_mode"] == "UNION_COMPLEMENTARY", "mix mode"); checks += 1
    require("COMPONENTS_MUST_BE_INDIVIDUALLY_QUALIFIED" == methods["IG05"]["promotion_precondition"], "mix component guard"); checks += 1

    expected = {
        "DETERMINISTIC_INVARIANT_VETO@0.1.0-candidate",
        "DETERMINISTIC_SIGNAL_RULE_CLASSIFIER@0.1.0-candidate",
        "HYBRID_RULE_FIRST_SEMANTIC_CLASSIFIER@0.1.0-candidate",
        "CONSTRAINT_ELIMINATION@0.1.0-candidate",
        "DEPENDENCY_CONSTRAINT_PARTITION_SELECTOR@0.1.0-candidate",
        "CLAIM_METHOD_CONSTRAINT_SELECTOR@0.1.0-candidate",
        "OBLIGATION_PRESERVING_BUDGET@0.1.0-candidate",
        "ADAPTIVE_EVIDENCE_ESCALATION@0.1.0-candidate",
    }
    ch = {c["method_ref"]: c for c in challengers["challengers"]}
    require(set(ch) == expected, "unexpected challenger set"); checks += 1
    require(challengers["result"]["missing_challenger_contracts_materialized"] == 8, "challenger count"); checks += 1
    require(challengers["common_boundary"]["selection_is_execution_permission"] is False, "selection permission boundary"); checks += 1
    require(challengers["common_boundary"]["arbitrary_numeric_weights_forbidden"] is True, "weight guard"); checks += 1
    require(all(c["hard_guards"] for c in ch.values()), "challenger without hard guard"); checks += 1
    require(all(c["failure_states"] for c in ch.values()), "challenger without failure states"); checks += 1

    units = set(batch["scope_units"])
    require(units == {"A6","A7","A9","PG-02","PG-03","PG-04","TST-07","TST-08","TST-09","TST-10"}, "Wave 2 scope drift"); checks += 1
    require(batch["current_result"]["champions_promoted"] == 0, "champion fabricated"); checks += 1
    require(batch["benchmark_protocol"]["candidate_freeze_before_holdout"] is True, "holdout leakage guard"); checks += 1
    require(batch["core_boundary"]["final_judge_separate"] is True, "judge separation"); checks += 1
    return checks


def expect_failure(mutator, requal, rebind, challengers, batch):
    a, b, c, d = map(copy.deepcopy, (requal, rebind, challengers, batch))
    mutator(a, b, c, d)
    try:
        validate(a, b, c, d)
    except AssertionError:
        return True
    return False


def main():
    requal = load("current_source_requalification_v1.json")
    rebind = load("historical_method_rebind_candidates_v1.json")
    challengers = load("wave2_new_challenger_contracts_v1.json")
    batch = load("wave2_selection_method_qualification_batch_v2.json")
    checks = validate(requal, rebind, challengers, batch)

    negatives = [
        lambda a,b,c,d: a["result"].__setitem__("eligible_methods", 1),
        lambda a,b,c,d: b["candidates"][1].__setitem__("eligible_for_runtime_selection", True),
        lambda a,b,c,d: b["candidates"][4].__setitem__("source_version", "arXiv:2607.00269"),
        lambda a,b,c,d: c["common_boundary"].__setitem__("selection_is_execution_permission", True),
        lambda a,b,c,d: c["common_boundary"].__setitem__("arbitrary_numeric_weights_forbidden", False),
        lambda a,b,c,d: c["challengers"].pop(),
        lambda a,b,c,d: d["current_result"].__setitem__("champions_promoted", 1),
        lambda a,b,c,d: d["benchmark_protocol"].__setitem__("candidate_freeze_before_holdout", False),
        lambda a,b,c,d: d["core_boundary"].__setitem__("final_judge_separate", False),
    ]
    for idx, mutator in enumerate(negatives, 1):
        require(expect_failure(mutator, requal, rebind, challengers, batch), f"negative {idx} did not fail")

    print(f"PASS_SELECTION_METHOD_CANDIDATES checks={checks} negatives={len(negatives)}")


if __name__ == "__main__":
    main()
