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
    decide_execution_authority,
    execute_with_authority,
    load_execution_authority,
)


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

    # Even a semantic-looking task stays deterministic if Authority/Typed Context derives it.
    derived = decide_execution_authority({
        "category": "SEMANTIC_INTERPRETATION_SELECTION_REASONING",
        "derivable_from_authority": True,
        "requires_semantic_interpretation": True,
        "non_derivable_from_authority": False,
    }, policy)
    assert derived["authority"] == DETERMINISTIC, derived
    assert derived["code"] == "PASS_DETERMINISTIC_ROUTE_WINS"

    # Model is admitted only for an explicit non-derivable semantic gap.
    semantic = {
        "category": "SEMANTIC_INTERPRETATION_SELECTION_REASONING",
        "requires_semantic_interpretation": True,
        "non_derivable_from_authority": True,
        "non_calculable": True,
        "not_known_structure": True,
        "model_reason": "select among semantically plausible alternatives not derivable from current Authority/Typed Context",
    }
    model = decide_execution_authority(semantic, policy)
    assert model["authority"] == MODEL_REQUIRED and model["model_call_allowed"] is True, model

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

    calls = {"deterministic": 0, "model": 0, "materializer": 0, "validator": 0}
    def deterministic_backend(task):
        calls["deterministic"] += 1
        return {"value": "known"}
    def model_backend(task):
        calls["model"] += 1
        return {"value": "semantic"}
    def materializer(raw):
        calls["materializer"] += 1
        return {"materialized": raw["value"]}
    def validator(value):
        calls["validator"] += 1
        return {"status": "PASS", "shape": sorted(value)}

    deterministic_run = execute_with_authority(
        {"category": "TYPED_CONTEXT_DERIVATION", "derivable_from_authority": True},
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
        semantic,
        policy,
        deterministic_backend=deterministic_backend,
        model_backend=model_backend,
        materializer=materializer,
        final_validator=validator,
    )
    assert model_run["status"] == "PASS" and model_run["model_backend_called"] is True
    assert calls == {"deterministic": 1, "model": 1, "materializer": 2, "validator": 2}, calls
    assert model_run["post_model_authority"]["model_output_is_authority"] is False

    failed_validation = execute_with_authority(
        semantic,
        policy,
        deterministic_backend=deterministic_backend,
        model_backend=model_backend,
        materializer=materializer,
        final_validator=lambda value: {"status": "BLOCKED", "reason": "shape mismatch"},
    )
    assert failed_validation["status"] == BLOCKED
    assert failed_validation["code"] == "BLOCK_FINAL_DETERMINISTIC_VALIDATION"

    print(json.dumps({
        "result": "PASS",
        "contract": policy["contract_version"],
        "deterministic_categories": len(deterministic_categories),
        "deterministic_wins_on_equivalent_contract": True,
        "model_only_on_non_derivable_semantic_gap": True,
        "model_calls_for_deterministic_cases": 0,
        "post_model_materialization_and_validation": "DETERMINISTIC",
        "negative_cases": 4,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
