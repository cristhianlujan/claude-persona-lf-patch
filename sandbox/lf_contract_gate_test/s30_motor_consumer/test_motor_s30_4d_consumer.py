from __future__ import annotations

import importlib.util
import json
from copy import deepcopy
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]
CONTRACT_PATH = ROOT / "skills/learning_engine/contracts/s30_deterministic_first_4d_v1.json"
CONSUMER_PATH = ROOT / "skills/learning_engine/adapters/s30_execution_authority_consumer.py"
VALIDATOR_PATH = ROOT / "skills/learning_engine/validators/validate_4d_ab_receipt.py"
MATRIX_PATH = ROOT / "skills/learning_engine/evals/s30_deterministic_first_4d_matrix.json"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def dimension_blocks(*, depth_passed: int = 4, elapsed=(120.0, 118.0, 122.0), input_tokens=1000, output_tokens=500, transport_bytes=8000, model_calls=1, tool_calls=3):
    return {
        "quality": {
            "semantic_checks_passed": 4,
            "semantic_checks_total": 4,
            "authority_checks_passed": 4,
            "authority_checks_total": 4,
            "unsupported_claims": 0,
        },
        "functionality": {
            "required_behaviors_passed": 5,
            "required_behaviors_total": 5,
            "positive_cases_passed": 2,
            "positive_cases_total": 2,
            "negative_cases_passed": 3,
            "negative_cases_total": 3,
            "guard_failures": 0,
        },
        "depth": {
            "obligations_preserved": depth_passed,
            "obligations_total": 4,
            "relationships_preserved": 3,
            "relationships_total": 3,
            "exceptions_preserved": 2,
            "exceptions_total": 2,
            "causal_checks_passed": 2,
            "causal_checks_total": 2,
        },
        "performance": {
            "elapsed_ms_samples": list(elapsed),
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "transport_bytes": transport_bytes,
            "model_calls": model_calls,
            "tool_calls": tool_calls,
        },
    }


def arm(*, input_sha="a" * 64, provider="same", model="same", params="b" * 64, judge=True, **dimensions):
    out = {
        "input_sha256": input_sha,
        "provider": provider,
        "model": model,
        "parameters_sha256": params,
        "independent_semantic_judge": {"executed": judge, "status": "PASS" if judge else "NOT_EXECUTED"},
    }
    out.update(dimensions)
    return out


def ab_receipt(a_dims: dict, b_dims: dict, *, semantic_case: bool = True, b_judge: bool = True) -> dict:
    return {
        "schema": "LF_4D_AB_RECEIPT_V1",
        "semantic_case": semantic_case,
        "arm_a": arm(**a_dims),
        "arm_b": arm(judge=b_judge, **b_dims),
    }


def main() -> None:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    matrix = json.loads(MATRIX_PATH.read_text(encoding="utf-8"))
    consumer = load_module("motor_s30_consumer", CONSUMER_PATH)
    validator = load_module("motor_4d_validator", VALIDATOR_PATH)

    assert contract["contract_version"] == "MOTOR_S30_DETERMINISTIC_FIRST_4D_V1"
    assert matrix["dimensions"] == ["quality", "functionality", "depth", "performance"]
    assert matrix["behavioral_model_ab_status"] == "NOT_EXECUTED"
    assert {c["id"] for c in matrix["cases"]} >= {
        "faster_but_quality_loss", "faster_but_functionality_loss", "faster_but_depth_loss"
    }

    deterministic = consumer.prepare_learning_work({
        "category": "TYPED_CONTEXT_DERIVATION",
        "derivable_from_authority": True,
        "canonical_working_graph": {"known": True},
    })
    assert deterministic["authority_contract"] == "S30_EXECUTION_AUTHORITY_V1"
    assert deterministic["decision"]["authority"] == "DETERMINISTIC"
    assert deterministic["decision"]["model_call_allowed"] is False
    assert deterministic["model_request"] is None

    hybrid_task = {
        "category": "SEMANTIC_INTERPRETATION_SELECTION_REASONING",
        "requires_semantic_interpretation": True,
        "non_derivable_from_authority": True,
        "non_calculable": True,
        "not_known_structure": True,
        "model_reason": "rank non-derivable learning alternatives",
        "semantic_context": {"goal": "select best learning candidate"},
        "unresolved_semantic_gap": {"decision": "semantic priority"},
        "candidate_alternatives": ["A", "B"],
        "semantic_constraints": ["preserve authority"],
        "canonical_working_graph": {"ids": ["known-1"]},
        "execution_id": "MUST_NOT_REACH_MODEL",
        "hashes": {"must": "not reach model"},
    }
    hybrid = consumer.prepare_learning_work(hybrid_task)
    assert hybrid["decision"]["authority"] == "MODEL_REQUIRED"
    assert hybrid["decision"]["model_call_allowed"] is True
    request_text = json.dumps(hybrid["model_request"], sort_keys=True)
    assert "MUST_NOT_REACH_MODEL" not in request_text
    assert '"hashes"' not in request_text
    assert "canonical_working_graph" not in request_text

    valid_delta = {
        "semantic_delta": {
            "decisions": [{"choice": "A"}],
            "proposals": [],
            "rationale": ["best semantic fit"],
            "unresolved": [],
        }
    }
    assert consumer.validate_learning_semantic_delta(valid_delta)["status"] == "PASS"
    invalid_delta = {
        "semantic_delta": {
            "decisions": [{"score": 99}],
            "proposals": [],
            "rationale": [],
            "unresolved": [],
        }
    }
    assert consumer.validate_learning_semantic_delta(invalid_delta)["status"] == "BLOCKED"

    a_dims = dimension_blocks(elapsed=(120, 122, 118), input_tokens=1000, output_tokens=500, transport_bytes=8000, model_calls=1, tool_calls=4)
    b_dims = dimension_blocks(elapsed=(85, 88, 84), input_tokens=450, output_tokens=220, transport_bytes=3200, model_calls=1, tool_calls=3)
    result = validator.evaluate(ab_receipt(a_dims, b_dims), contract)
    assert result["status"] == "PASS", result
    assert result["decision"] == "SELECT_B", result
    assert all(result["gates"].values()), result

    # A faster candidate never wins by sacrificing quality.
    quality_loss = deepcopy(b_dims)
    quality_loss["quality"]["semantic_checks_passed"] = 3
    result = validator.evaluate(ab_receipt(a_dims, quality_loss), contract)
    assert result["status"] == "NO_GO" and result["decision"] == "KEEP_A", result
    assert result["gates"]["quality_no_regression"] is False

    # A faster candidate never wins by sacrificing functionality.
    functionality_loss = deepcopy(b_dims)
    functionality_loss["functionality"]["required_behaviors_passed"] = 4
    result = validator.evaluate(ab_receipt(a_dims, functionality_loss), contract)
    assert result["status"] == "NO_GO" and result["decision"] == "KEEP_A", result
    assert result["gates"]["functionality_candidate_complete"] is False

    # A faster candidate never wins by sacrificing depth.
    depth_loss = dimension_blocks(depth_passed=3, elapsed=(70, 72, 68), input_tokens=300, output_tokens=150, transport_bytes=2500, model_calls=1, tool_calls=2)
    result = validator.evaluate(ab_receipt(a_dims, depth_loss), contract)
    assert result["status"] == "NO_GO" and result["decision"] == "KEEP_A", result
    assert result["gates"]["depth_no_regression"] is False

    # Semantic quality is not claimable when the independent judge did not execute.
    result = validator.evaluate(ab_receipt(a_dims, b_dims, b_judge=False), contract)
    assert result["status"] == "INCOMPLETE", result
    assert "SEMANTIC_INDEPENDENT_JUDGE_REQUIRED" in result["errors"]

    # Performance is mandatory; two elapsed samples are insufficient for a PASS.
    short_perf = dimension_blocks(elapsed=(80, 82), input_tokens=400, output_tokens=200, transport_bytes=3000, model_calls=1, tool_calls=3)
    result = validator.evaluate(ab_receipt(a_dims, short_perf, semantic_case=False), contract)
    assert result["status"] == "INCOMPLETE", result
    assert any("PERFORMANCE_ELAPSED_SAMPLES_INVALID" in e for e in result["errors"])

    print(json.dumps({
        "result": "PASS",
        "consumer": "ACT-0046",
        "authority": "S30_EXECUTION_AUTHORITY_V1",
        "dimensions_required": ["quality", "functionality", "depth", "performance"],
        "deterministic_case_model_calls": 0,
        "hybrid_model_input": "COMPACT_SEMANTIC_GAP_ONLY",
        "semantic_delta_system_fields_blocked": True,
        "faster_with_quality_loss": "NO_GO",
        "faster_with_functionality_loss": "NO_GO",
        "faster_with_depth_loss": "NO_GO",
        "missing_independent_semantic_judge": "INCOMPLETE",
        "missing_performance_samples": "INCOMPLETE",
        "behavioral_model_ab_status": "NOT_EXECUTED",
        "claim_ceiling": "STRUCTURAL_CONTRACT_ONLY_NOT_SEMANTIC_AB_PROVEN"
    }, sort_keys=True))


if __name__ == "__main__":
    main()
