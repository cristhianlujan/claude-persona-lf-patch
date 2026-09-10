from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from lf_execution_authority import (  # noqa: E402
    BLOCKED,
    DETERMINISTIC,
    MODEL_REQUIRED,
    WORK_DETERMINISTIC,
    WORK_HYBRID,
    WORK_SEMANTIC,
    build_model_request,
    classify_work,
    decide_execution_authority,
    execute_with_authority,
    load_execution_authority,
    validate_semantic_delta,
)


def semantic_task(*, hybrid: bool = False) -> dict:
    task = {
        "category": "SEMANTIC_INTERPRETATION_SELECTION_REASONING",
        "requires_semantic_interpretation": True,
        "non_derivable_from_authority": True,
        "non_calculable": True,
        "not_known_structure": True,
        "model_reason": "select among semantically plausible alternatives not derivable from current Authority/Typed Context",
        "semantic_context": {"goal": "choose visual hierarchy", "known_components": ["search", "categories", "service_card"]},
        "unresolved_semantic_gap": {"decision": "relative hierarchy and grouping"},
        "candidate_alternatives": ["dense", "balanced", "editorial"],
        "semantic_constraints": ["preserve known components"],
        "execution_id": "MUST_NOT_REACH_MODEL",
        "hashes": {"must": "not reach model"},
        "bindings": {"must": "not reach model"},
    }
    if hybrid:
        task["canonical_working_graph"] = {
            "contract_version": "S30_CANONICAL_WORKING_GRAPH_V1",
            "ids": ["cmp-search", "cmp-category", "cmp-service-card"],
            "known_content": {"search": "Buscar"},
        }
    return task


def valid_delta() -> dict:
    return {
        "semantic_delta": {
            "decisions": [{"choice": "balanced hierarchy"}],
            "proposals": [{"grouping": "search then categories then cards"}],
            "rationale": ["reduces scanning cost while preserving authority-defined components"],
            "unresolved": [],
        }
    }


def main() -> None:
    policy = load_execution_authority(HERE / "execution_authority_policy_v1.json")
    deterministic_categories = [
        "IDENTITY_HASH_ROUTING_CONTRACT_DEFAULTS",
        "TYPED_CONTEXT_DERIVATION",
        "CALCULABLE_VALIDATION_LIMITS_SCORING",
        "KNOWN_STRUCTURE_REPETITION_FORMATTING",
        "MATERIALIZATION_GUARDS_FINAL_VALIDATION",
    ]
    for category in deterministic_categories:
        d = decide_execution_authority({"category": category}, policy)
        assert d["authority"] == DETERMINISTIC and d["model_call_allowed"] is False, d
        assert d["work_classification"] == WORK_DETERMINISTIC

    # Even a semantic-looking task stays deterministic if Authority/Typed Context derives it.
    derived = decide_execution_authority({
        "category": "SEMANTIC_INTERPRETATION_SELECTION_REASONING",
        "derivable_from_authority": True,
        "requires_semantic_interpretation": True,
        "non_derivable_from_authority": False,
    }, policy)
    assert derived["authority"] == DETERMINISTIC, derived
    assert derived["code"] == "PASS_DETERMINISTIC_ROUTE_WINS"
    assert classify_work({"category": "SEMANTIC_INTERPRETATION_SELECTION_REASONING", "derivable_from_authority": True}, policy) == WORK_DETERMINISTIC

    # Pure semantic gap and hybrid graph+gap are classified explicitly.
    semantic = semantic_task(hybrid=False)
    hybrid = semantic_task(hybrid=True)
    assert classify_work(semantic, policy) == WORK_SEMANTIC
    assert classify_work(hybrid, policy) == WORK_HYBRID
    model = decide_execution_authority(hybrid, policy)
    assert model["authority"] == MODEL_REQUIRED and model["model_call_allowed"] is True, model
    assert model["work_classification"] == WORK_HYBRID

    ambiguous = dict(semantic)
    ambiguous["non_calculable"] = False
    blocked = decide_execution_authority(ambiguous, policy)
    assert blocked["status"] == BLOCKED and blocked["model_call_allowed"] is False, blocked
    assert blocked["code"] == "BLOCK_EXECUTION_AUTHORITY_AMBIGUOUS"

    missing_reason = dict(semantic)
    missing_reason["model_reason"] = ""
    blocked = decide_execution_authority(missing_reason, policy)
    assert blocked["code"] == "BLOCK_MODEL_REASON_MISSING", blocked

    unknown = decide_execution_authority({"category": "INVENTED"}, policy)
    assert unknown["code"] == "BLOCK_EXECUTION_AUTHORITY_UNKNOWN_CATEGORY", unknown

    # Model input is compact and excludes system/admin context and the canonical graph.
    request = build_model_request(hybrid, policy)
    forwarded = request["semantic_context"]
    assert set(forwarded) == {"semantic_context", "unresolved_semantic_gap", "candidate_alternatives", "semantic_constraints"}, forwarded
    serialized_request = json.dumps(request, sort_keys=True)
    for forbidden in ("MUST_NOT_REACH_MODEL", "cmp-search", "execution_id", '"hashes"', '"bindings"'):
        assert forbidden not in serialized_request, serialized_request
    assert request["output_contract"]["contract_version"] == "S30_SEMANTIC_DELTA_V1"

    # Model can emit only semantic_delta, never producer-owned/system-owned fields.
    good = validate_semantic_delta(valid_delta(), policy)
    assert good["status"] == "PASS" and good["model_output_is_authority"] is False, good

    extra_root = valid_delta()
    extra_root["worker"] = "invented"
    assert validate_semantic_delta(extra_root, policy)["code"] == "BLOCK_MODEL_SEMANTIC_DELTA_CONTRACT"

    bad_score = valid_delta()
    bad_score["semantic_delta"]["decisions"] = [{"choice": "balanced", "score": 99}]
    assert validate_semantic_delta(bad_score, policy)["code"] == "BLOCK_MODEL_SYSTEM_OWNED_FIELD"

    bad_verdict = valid_delta()
    bad_verdict["semantic_delta"]["proposals"] = [{"self_verdict": "PASS"}]
    assert validate_semantic_delta(bad_verdict, policy)["code"] == "BLOCK_MODEL_SYSTEM_OWNED_FIELD"

    missing_field = valid_delta()
    del missing_field["semantic_delta"]["unresolved"]
    assert validate_semantic_delta(missing_field, policy)["code"] == "BLOCK_MODEL_SEMANTIC_DELTA_CONTRACT"

    calls = {"deterministic": 0, "model": 0, "materializer": 0, "validator": 0}
    model_requests: list[dict] = []
    materializer_inputs: list[dict] = []

    def deterministic_backend(task):
        calls["deterministic"] += 1
        return {"derived": "known"}

    def model_backend(req):
        calls["model"] += 1
        model_requests.append(dict(req))
        return valid_delta()

    def materializer(value):
        calls["materializer"] += 1
        materializer_inputs.append(dict(value))
        # System-owned output is deterministically materialized here, not by the model.
        return {
            "worker": "UI_PRODUCT_AGENT",
            "output_type": "PRODUCTION_UI_SPEC",
            "score": 4,
            "handoff_to_next": "VALIDATOR",
            "technical_verdict": "PENDING_VALIDATION",
            "payload": value,
        }

    def validator(value):
        calls["validator"] += 1
        assert value["worker"] == "UI_PRODUCT_AGENT"
        return {"status": "PASS", "shape": sorted(value)}

    deterministic_run = execute_with_authority(
        {"category": "TYPED_CONTEXT_DERIVATION", "derivable_from_authority": True, "canonical_working_graph": {"known": True}},
        policy,
        deterministic_backend=deterministic_backend,
        model_backend=model_backend,
        materializer=materializer,
        final_validator=validator,
    )
    assert deterministic_run["status"] == "PASS"
    assert deterministic_run["model_backend_called"] is False
    assert calls == {"deterministic": 1, "model": 0, "materializer": 1, "validator": 1}, calls

    model_run = execute_with_authority(
        hybrid,
        policy,
        deterministic_backend=deterministic_backend,
        model_backend=model_backend,
        materializer=materializer,
        final_validator=validator,
    )
    assert model_run["status"] == "PASS" and model_run["model_backend_called"] is True
    assert calls == {"deterministic": 1, "model": 1, "materializer": 2, "validator": 2}, calls
    assert model_run["post_model_authority"]["model_output_is_authority"] is False
    assert model_run["semantic_delta_validation"]["status"] == "PASS"
    assert "canonical_working_graph" not in json.dumps(model_requests[0], sort_keys=True)
    assert materializer_inputs[-1]["canonical_working_graph"]["ids"] == ["cmp-search", "cmp-category", "cmp-service-card"]
    assert set(materializer_inputs[-1]["semantic_delta"]) == {"decisions", "proposals", "rationale", "unresolved"}

    # Invalid model output is stopped before deterministic materialization or final validation.
    calls_before = dict(calls)
    invalid_model_run = execute_with_authority(
        hybrid,
        policy,
        deterministic_backend=deterministic_backend,
        model_backend=lambda req: {"semantic_delta": {"decisions": [{"self_verdict": "PASS"}], "proposals": [], "rationale": [], "unresolved": []}},
        materializer=materializer,
        final_validator=validator,
    )
    assert invalid_model_run["status"] == BLOCKED
    assert invalid_model_run["code"] == "BLOCK_MODEL_SYSTEM_OWNED_FIELD"
    assert invalid_model_run["materializer_called"] is False
    assert invalid_model_run["final_validator_called"] is False
    assert calls["materializer"] == calls_before["materializer"] and calls["validator"] == calls_before["validator"]

    failed_validation = execute_with_authority(
        hybrid,
        policy,
        deterministic_backend=deterministic_backend,
        model_backend=model_backend,
        materializer=materializer,
        final_validator=lambda value: {"status": "BLOCKED", "reason": "shape mismatch"},
    )
    assert failed_validation["status"] == BLOCKED
    assert failed_validation["code"] == "BLOCK_FINAL_DETERMINISTIC_VALIDATION"

    assert policy["scoring_policy"]["calculable_score_authority"] == DETERMINISTIC
    assert policy["scoring_policy"]["model_may_emit_calculable_score"] is False
    assert policy["judge_policy"]["producer_self_verdict_allowed"] is False
    assert policy["judge_policy"]["independent_semantic_judge_role"] == "EVALUATION_ONLY"
    assert policy["judge_policy"]["independent_judge_may_replace_hard_guards"] is False

    print(json.dumps({
        "result": "PASS",
        "contract": policy["contract_version"],
        "work_classifications": [WORK_DETERMINISTIC, WORK_SEMANTIC, WORK_HYBRID],
        "deterministic_categories": len(deterministic_categories),
        "deterministic_wins_on_equivalent_contract": True,
        "model_only_on_non_derivable_semantic_gap": True,
        "model_input_mode": policy["model_input_policy"]["mode"],
        "model_output_contract": policy["semantic_delta_contract"]["contract_version"],
        "model_calls_for_deterministic_cases": 0,
        "model_system_owned_fields_allowed": False,
        "producer_self_verdict_allowed": False,
        "calculable_scoring_authority": DETERMINISTIC,
        "independent_semantic_judge_role": "EVALUATION_ONLY",
        "post_model_materialization_and_validation": "DETERMINISTIC",
        "negative_cases": 8,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
