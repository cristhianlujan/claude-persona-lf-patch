from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Callable, Mapping

DETERMINISTIC = "DETERMINISTIC"
MODEL_REQUIRED = "MODEL_REQUIRED"
BLOCKED = "BLOCKED"
WORK_DETERMINISTIC = "DETERMINISTIC"
WORK_SEMANTIC = "SEMANTIC"
WORK_HYBRID = "HYBRID"


def load_execution_authority(path: str | Path) -> dict:
    p = json.loads(Path(path).read_text(encoding="utf-8"))
    required = {
        "contract_version", "scope", "default_authority",
        "deterministic_wins_on_equivalent_contract", "model_policy",
        "categories", "conditional_model_gate", "post_model_authority", "fail_closed",
        "work_classification", "canonical_working_graph", "model_input_policy",
        "semantic_delta_contract", "scoring_policy", "judge_policy",
    }
    missing = sorted(required - set(p))
    if missing:
        raise ValueError(f"execution authority missing keys: {missing}")
    if p["contract_version"] != "S30_EXECUTION_AUTHORITY_V1":
        raise ValueError("unsupported execution authority contract")
    if p["default_authority"] != DETERMINISTIC:
        raise ValueError("deterministic-first is mandatory")
    if p["deterministic_wins_on_equivalent_contract"] is not True:
        raise ValueError("deterministic route must win on equivalent contract")
    if p["model_policy"] != "MODEL_ONLY_ON_NON_DERIVABLE_SEMANTIC_GAP":
        raise ValueError("model policy mismatch")
    if p["semantic_delta_contract"].get("contract_version") != "S30_SEMANTIC_DELTA_V1":
        raise ValueError("semantic delta contract mismatch")
    if p["judge_policy"].get("producer_self_verdict_allowed") is not False:
        raise ValueError("producer self-verdict must be forbidden")
    if p["scoring_policy"].get("calculable_score_authority") != DETERMINISTIC:
        raise ValueError("calculable scoring must be deterministic")
    return p


def _decision(authority: str, code: str, *, model_call_allowed: bool, reason: str, **extra: Any) -> dict:
    out = {
        "status": "PASS" if authority in {DETERMINISTIC, MODEL_REQUIRED} else BLOCKED,
        "authority": authority,
        "code": code,
        "model_call_allowed": model_call_allowed,
        "reason": reason,
    }
    out.update(extra)
    return out


def _deterministic_signals(task: Mapping[str, Any]) -> dict[str, bool]:
    return {
        "derivable_from_authority": task.get("derivable_from_authority") is True,
        "calculable": task.get("calculable") is True,
        "known_structure": task.get("known_structure") is True,
    }


def classify_work(task: Mapping[str, Any], policy: Mapping[str, Any]) -> str:
    category = task.get("category")
    configured = (policy.get("categories") or {}).get(category)
    if configured == DETERMINISTIC:
        return WORK_DETERMINISTIC
    if configured != "CONDITIONAL_MODEL":
        return BLOCKED
    if any(_deterministic_signals(task).values()):
        return WORK_DETERMINISTIC
    semantic_gate = (
        task.get("requires_semantic_interpretation") is True
        and task.get("non_derivable_from_authority") is True
        and task.get("non_calculable") is True
        and task.get("not_known_structure") is True
    )
    if not semantic_gate:
        return BLOCKED
    graph = task.get("canonical_working_graph")
    return WORK_HYBRID if isinstance(graph, Mapping) and bool(graph) else WORK_SEMANTIC


def decide_execution_authority(task: Mapping[str, Any], policy: Mapping[str, Any]) -> dict:
    category = task.get("category")
    configured = (policy.get("categories") or {}).get(category)
    if configured is None:
        code = policy["fail_closed"]["unknown_category"]
        return _decision(BLOCKED, code, model_call_allowed=False, reason=f"unknown category={category}", work_classification=BLOCKED)

    deterministic_signals = _deterministic_signals(task)
    classification = classify_work(task, policy)

    if configured == DETERMINISTIC:
        return _decision(
            DETERMINISTIC,
            "PASS_DETERMINISTIC_AUTHORITY",
            model_call_allowed=False,
            reason=f"category={category} is deterministically governed",
            deterministic_signals=deterministic_signals,
            work_classification=WORK_DETERMINISTIC,
        )

    if configured != "CONDITIONAL_MODEL":
        return _decision(BLOCKED, policy["fail_closed"]["unknown_category"], model_call_allowed=False, reason="invalid category authority", work_classification=BLOCKED)

    if policy.get("deterministic_wins_on_equivalent_contract") is True and any(deterministic_signals.values()):
        winning = sorted(k for k, v in deterministic_signals.items() if v)
        return _decision(
            DETERMINISTIC,
            "PASS_DETERMINISTIC_ROUTE_WINS",
            model_call_allowed=False,
            reason="deterministic capability resolves requested contract",
            deterministic_signals=deterministic_signals,
            winning_signals=winning,
            work_classification=WORK_DETERMINISTIC,
        )

    gate = policy["conditional_model_gate"]
    exact = {
        "requires_semantic_interpretation": task.get("requires_semantic_interpretation") is True,
        "non_derivable_from_authority": task.get("non_derivable_from_authority") is True,
        "non_calculable": task.get("non_calculable") is True,
        "not_known_structure": task.get("not_known_structure") is True,
    }
    if not all(exact.values()):
        return _decision(
            BLOCKED,
            policy["fail_closed"]["ambiguous_semantic_gate"],
            model_call_allowed=False,
            reason="conditional model gate is incomplete",
            gate_observed=exact,
            work_classification=classification,
        )
    model_reason = task.get("model_reason")
    if gate.get("model_reason_required") and (not isinstance(model_reason, str) or not model_reason.strip()):
        return _decision(BLOCKED, policy["fail_closed"]["model_reason_missing"], model_call_allowed=False, reason="model reason required", work_classification=classification)
    return _decision(
        MODEL_REQUIRED,
        "PASS_MODEL_ON_SEMANTIC_GAP",
        model_call_allowed=True,
        reason=model_reason.strip(),
        gate_observed=exact,
        work_classification=classification,
    )


def build_model_request(task: Mapping[str, Any], policy: Mapping[str, Any]) -> dict:
    cfg = policy["model_input_policy"]
    allowed = set(cfg.get("allowed_task_fields") or [])
    semantic_context = {k: task[k] for k in sorted(allowed) if k in task}
    return {
        "request_contract": "S30_MODEL_SEMANTIC_GAP_REQUEST_V1",
        "semantic_context": semantic_context,
        "output_contract": {
            "contract_version": policy["semantic_delta_contract"]["contract_version"],
            "root_key": policy["semantic_delta_contract"]["root_key"],
            "required_fields": list(policy["semantic_delta_contract"]["required_fields"]),
            "additional_properties": False,
        },
    }


def _find_forbidden_key(value: Any, forbidden: set[str]) -> str | None:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if str(key) in forbidden:
                return str(key)
            found = _find_forbidden_key(child, forbidden)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _find_forbidden_key(child, forbidden)
            if found is not None:
                return found
    return None


def validate_semantic_delta(model_output: Any, policy: Mapping[str, Any]) -> dict:
    cfg = policy["semantic_delta_contract"]
    root_key = cfg["root_key"]
    if not isinstance(model_output, Mapping):
        return _decision(BLOCKED, policy["fail_closed"]["model_output_contract_invalid"], model_call_allowed=False, reason="model output must be an object")
    if set(model_output) != {root_key}:
        return _decision(BLOCKED, policy["fail_closed"]["model_output_contract_invalid"], model_call_allowed=False, reason="model output root must contain only semantic_delta")
    delta = model_output.get(root_key)
    if not isinstance(delta, Mapping):
        return _decision(BLOCKED, policy["fail_closed"]["model_output_contract_invalid"], model_call_allowed=False, reason="semantic_delta must be an object")
    required = list(cfg.get("required_fields") or [])
    if set(delta) != set(required):
        return _decision(BLOCKED, policy["fail_closed"]["model_output_contract_invalid"], model_call_allowed=False, reason=f"semantic_delta fields must equal {required}")
    for field in required:
        if not isinstance(delta[field], list):
            return _decision(BLOCKED, policy["fail_closed"]["model_output_contract_invalid"], model_call_allowed=False, reason=f"semantic_delta.{field} must be an array")
    forbidden = set(cfg.get("system_owned_fields_forbidden") or [])
    bad = _find_forbidden_key(delta, forbidden)
    if bad is not None:
        return _decision(BLOCKED, policy["fail_closed"]["model_system_owned_field"], model_call_allowed=False, reason=f"model emitted system-owned field={bad}")
    return {
        "status": "PASS",
        "code": "PASS_SEMANTIC_DELTA_VALID",
        "semantic_delta": dict(delta),
        "model_output_is_authority": False,
    }


def execute_with_authority(
    task: Mapping[str, Any],
    policy: Mapping[str, Any],
    *,
    deterministic_backend: Callable[[Mapping[str, Any]], Any],
    model_backend: Callable[[Mapping[str, Any]], Any],
    materializer: Callable[[Any], Any],
    final_validator: Callable[[Any], Mapping[str, Any]],
) -> dict:
    decision = decide_execution_authority(task, policy)
    if decision["status"] != "PASS":
        return {**decision, "deterministic_backend_called": False, "model_backend_called": False, "materializer_called": False, "final_validator_called": False}

    deterministic_called = decision["authority"] == DETERMINISTIC
    model_called = decision["authority"] == MODEL_REQUIRED
    model_request = None
    semantic_validation = None

    if deterministic_called:
        raw = deterministic_backend(task)
        materializer_input = {
            "canonical_working_graph": task.get("canonical_working_graph", {}),
            "deterministic_result": raw,
        }
    else:
        model_request = build_model_request(task, policy)
        raw = model_backend(model_request)
        semantic_validation = validate_semantic_delta(raw, policy)
        if semantic_validation["status"] != "PASS":
            return {
                **decision,
                "status": BLOCKED,
                "code": semantic_validation["code"],
                "reason": semantic_validation["reason"],
                "deterministic_backend_called": False,
                "model_backend_called": True,
                "materializer_called": False,
                "final_validator_called": False,
                "model_request": model_request,
                "semantic_delta_validation": semantic_validation,
            }
        materializer_input = {
            "canonical_working_graph": task.get("canonical_working_graph", {}),
            "semantic_delta": semantic_validation["semantic_delta"],
        }

    materialized = materializer(materializer_input)
    validation = dict(final_validator(materialized))
    if validation.get("status") != "PASS":
        return {
            **decision,
            "status": BLOCKED,
            "code": policy["fail_closed"]["final_validation_failure"],
            "deterministic_backend_called": deterministic_called,
            "model_backend_called": model_called,
            "materializer_called": True,
            "final_validator_called": True,
            "validation": validation,
            "model_request": model_request,
            "semantic_delta_validation": semantic_validation,
        }
    return {
        **decision,
        "deterministic_backend_called": deterministic_called,
        "model_backend_called": model_called,
        "materializer_called": True,
        "final_validator_called": True,
        "materialized": materialized,
        "validation": validation,
        "model_request": model_request,
        "semantic_delta_validation": semantic_validation,
        "post_model_authority": dict(policy["post_model_authority"]),
    }
