#!/usr/bin/env python3
"""Thin composition runner for ASSURANCE_EVALUATOR.

The shared ORCHESTRATOR_EXECUTION_GUARD_V1 is enforced before this runner by
public.fn_lf_capability_bind_from_orchestrator_v1. This module deliberately does
not duplicate orchestrator authority, query Supabase, discover applicability,
or mutate any evidence/store.
"""
from __future__ import annotations

from typing import Any, Mapping

from assurance_activation_gate_v1 import resolve_assurance_activation
from assurance_evaluator_core_v1 import evaluate_assurance
from assurance_legacy_s36_guard_v1 import validate_review_reference

INPUT_SCHEMA = "lf-assurance-evaluator-runner-request/v1"
OUTPUT_SCHEMA = "lf-assurance-evaluator-runner-result/v1"


class AssuranceRunnerError(ValueError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _mapping(value: Any, code: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise AssuranceRunnerError(code)
    return value


def _sequence(value: Any, code: str) -> tuple[Any, ...]:
    if isinstance(value, (str, bytes)) or not isinstance(value, (list, tuple)):
        raise AssuranceRunnerError(code)
    return tuple(value)


def run_assurance_evaluator(packet: Mapping[str, Any]) -> dict[str, Any]:
    """Compose Router decision, exact binding, review guard and semantic core."""
    try:
        if not isinstance(packet, Mapping):
            raise AssuranceRunnerError("BLOCKED_RUNNER_INPUT_SHAPE")
        expected = {
            "schema_version",
            "router_decision",
            "subject_bindings",
            "claim",
            "obligations",
            "defeaters",
            "evidence",
            "review_references",
        }
        if set(packet) != expected:
            raise AssuranceRunnerError(
                "BLOCKED_RUNNER_INPUT_FIELDS",
                ",".join(sorted(set(packet) ^ expected)),
            )
        if packet["schema_version"] != INPUT_SCHEMA:
            raise AssuranceRunnerError("BLOCKED_RUNNER_INPUT_SCHEMA")

        router_decision = _mapping(
            packet["router_decision"], "BLOCKED_RUNNER_ROUTER_DECISION_SHAPE"
        )
        subject_bindings = _sequence(
            packet["subject_bindings"], "BLOCKED_RUNNER_BINDINGS_SHAPE"
        )

        activation = resolve_assurance_activation(
            router_decision=router_decision,
            subject_bindings=subject_bindings,
        )
        activation_status = activation.get("status")

        if activation_status == "NOT_APPLICABLE_NO_EXECUTION":
            return {
                "schema_version": OUTPUT_SCHEMA,
                "status": "NOT_APPLICABLE_NO_EXECUTION",
                "execute_assurance": False,
                "activation": activation,
                "evaluator_result": None,
                "review_decisions": [],
            }

        if activation_status != "READY_FOR_ASSURANCE_EVALUATOR":
            return {
                "schema_version": OUTPUT_SCHEMA,
                "status": "BLOCKED",
                "execute_assurance": False,
                "reason_code": activation.get("reason_code", "ACTIVATION_NOT_READY"),
                "activation": activation,
                "evaluator_result": None,
                "review_decisions": [],
            }

        review_decisions: list[dict[str, Any]] = []
        for review_reference in _sequence(
            packet["review_references"], "BLOCKED_RUNNER_REVIEW_REFERENCES_SHAPE"
        ):
            decision = validate_review_reference(
                _mapping(review_reference, "BLOCKED_RUNNER_REVIEW_REFERENCE_SHAPE")
            )
            review_decisions.append(decision)
            if decision.get("status") == "BLOCKED":
                return {
                    "schema_version": OUTPUT_SCHEMA,
                    "status": "BLOCKED",
                    "execute_assurance": False,
                    "reason_code": decision.get("reason_code", "REVIEW_REFERENCE_BLOCKED"),
                    "activation": activation,
                    "evaluator_result": None,
                    "review_decisions": review_decisions,
                }

        evaluator_input = {
            "schema_version": "lf-assurance-evaluator-input/v1",
            "activation": activation,
            "claim": packet["claim"],
            "obligations": packet["obligations"],
            "defeaters": packet["defeaters"],
            "evidence": packet["evidence"],
            "review_decisions": review_decisions,
        }
        evaluator_result = evaluate_assurance(evaluator_input)

        return {
            "schema_version": OUTPUT_SCHEMA,
            "status": "EVALUATED",
            "execute_assurance": True,
            "activation": activation,
            "evaluator_result": evaluator_result,
            "review_decisions": review_decisions,
        }
    except AssuranceRunnerError as exc:
        return {
            "schema_version": OUTPUT_SCHEMA,
            "status": "BLOCKED",
            "execute_assurance": False,
            "reason_code": exc.code,
            "detail": exc.detail,
            "activation": None,
            "evaluator_result": None,
            "review_decisions": [],
        }
