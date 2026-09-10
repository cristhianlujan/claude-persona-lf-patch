from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Callable, Mapping

DETERMINISTIC = "DETERMINISTIC"
MODEL_REQUIRED = "MODEL_REQUIRED"
BLOCKED = "BLOCKED"


def load_execution_authority(path: str | Path) -> dict:
    p = json.loads(Path(path).read_text(encoding="utf-8"))
    required = {
        "contract_version", "scope", "default_authority",
        "deterministic_wins_on_equivalent_contract", "model_policy",
        "categories", "conditional_model_gate", "post_model_authority", "fail_closed",
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


def decide_execution_authority(task: Mapping[str, Any], policy: Mapping[str, Any]) -> dict:
    category = task.get("category")
    configured = (policy.get("categories") or {}).get(category)
    if configured is None:
        code = policy["fail_closed"]["unknown_category"]
        return _decision(BLOCKED, code, model_call_allowed=False, reason=f"unknown category={category}")

    deterministic_signals = {
        "derivable_from_authority": task.get("derivable_from_authority") is True,
        "calculable": task.get("calculable") is True,
        "known_structure": task.get("known_structure") is True,
    }

    if configured == DETERMINISTIC:
        return _decision(
            DETERMINISTIC,
            "PASS_DETERMINISTIC_AUTHORITY",
            model_call_allowed=False,
            reason=f"category={category} is deterministically governed",
            deterministic_signals=deterministic_signals,
        )

    if configured != "CONDITIONAL_MODEL":
        return _decision(BLOCKED, policy["fail_closed"]["unknown_category"], model_call_allowed=False, reason="invalid category authority")

    if policy.get("deterministic_wins_on_equivalent_contract") is True and any(deterministic_signals.values()):
        winning = sorted(k for k, v in deterministic_signals.items() if v)
        return _decision(
            DETERMINISTIC,
            "PASS_DETERMINISTIC_ROUTE_WINS",
            model_call_allowed=False,
            reason="deterministic capability resolves requested contract",
            deterministic_signals=deterministic_signals,
            winning_signals=winning,
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
        )
    model_reason = task.get("model_reason")
    if gate.get("model_reason_required") and (not isinstance(model_reason, str) or not model_reason.strip()):
        return _decision(BLOCKED, policy["fail_closed"]["model_reason_missing"], model_call_allowed=False, reason="model reason required")
    return _decision(
        MODEL_REQUIRED,
        "PASS_MODEL_ON_SEMANTIC_GAP",
        model_call_allowed=True,
        reason=model_reason.strip(),
        gate_observed=exact,
    )


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
    raw = deterministic_backend(task) if deterministic_called else model_backend(task)
    materialized = materializer(raw)
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
        }
    return {
        **decision,
        "deterministic_backend_called": deterministic_called,
        "model_backend_called": model_called,
        "materializer_called": True,
        "final_validator_called": True,
        "materialized": materialized,
        "validation": validation,
        "post_model_authority": dict(policy["post_model_authority"]),
    }
