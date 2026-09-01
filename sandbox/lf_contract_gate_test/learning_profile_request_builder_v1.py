#!/usr/bin/env python3
from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Iterable

from learning_read_only_context_selector_v1 import BindingSpec, LearningSelectionError, select_read_only_context

SCHEMA = "LF_LEARNING_PROFILE_REQUEST_BUILDER_V1"
REQUIRED_GOVERNANCE_CONSUMER = "CONTEXT_PACK"
MAX_INPUT_LITERAL_BYTES = 24000


class LearningRequestBuildError(ValueError):
    pass


@dataclass(frozen=True)
class GovernanceReceipt:
    current_run_id: int
    pantalla_id: int
    screen_code: str
    contract_revision: str
    current: bool
    governance_consumer: str = REQUIRED_GOVERNANCE_CONSUMER


def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _assert_governance(receipt: GovernanceReceipt) -> None:
    if receipt.current_run_id <= 0:
        raise LearningRequestBuildError("CURRENT_INPUT_GOVERNANCE_RUN_REQUIRED")
    if receipt.pantalla_id <= 0 or not receipt.screen_code:
        raise LearningRequestBuildError("EXACT_INPUT_GOVERNANCE_SUBJECT_REQUIRED")
    if not receipt.current:
        raise LearningRequestBuildError("INPUT_GOVERNANCE_RECEIPT_NOT_CURRENT")
    if receipt.governance_consumer != REQUIRED_GOVERNANCE_CONSUMER:
        raise LearningRequestBuildError("INPUT_GOVERNANCE_CONSUMER_MISMATCH")
    if not receipt.contract_revision:
        raise LearningRequestBuildError("INPUT_GOVERNANCE_CONTRACT_REVISION_REQUIRED")


def build_profile_request(
    rows: Iterable[dict[str, Any]],
    *,
    profile_code: str,
    task_intent: str,
    explicit_constraints: list[str],
    binding: BindingSpec,
    governance: GovernanceReceipt,
    provenance: dict[str, Any] | None = None,
) -> dict[str, Any]:
    profile_code = _text(profile_code)
    task_intent = _text(task_intent)
    if not profile_code or profile_code != binding.consumer_id:
        raise LearningRequestBuildError("PROFILE_CONSUMER_EXACT_BINDING_REQUIRED")
    if not task_intent:
        raise LearningRequestBuildError("TASK_INTENT_REQUIRED")
    _assert_governance(governance)
    try:
        context = select_read_only_context(rows, binding=binding)
    except LearningSelectionError as exc:
        raise LearningRequestBuildError(f"LEARNING_CONTEXT_SELECTION_FAILED:{exc}") from exc

    constraints = [_text(x) for x in explicit_constraints if _text(x)]
    envelope = {
        "schema": SCHEMA,
        "mode": "READ_ONLY",
        "profile_code": profile_code,
        "consumer_id": binding.consumer_id,
        "capability_id": binding.capability_id,
        "task_intent": task_intent,
        "explicit_constraints": constraints,
        "input_governance": {
            "current_run_id": governance.current_run_id,
            "pantalla_id": governance.pantalla_id,
            "screen_code": governance.screen_code,
            "contract_revision": governance.contract_revision,
            "current": True,
            "governance_consumer": governance.governance_consumer,
        },
        "learning_context": context,
        "learning_selection": {
            "selector": context["selector"],
            "llm_calls": 0,
            "round_trips": 0,
            "automatic_impact": False,
            "production_authorized": False,
        },
        "fallback": "RUN_PROFILE_WITHOUT_COMPETITIVE_CONTEXT" if context["selected_count"] == 0 else None,
        "provenance": provenance or {},
    }
    input_literal = json.dumps(envelope, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    input_bytes = len(input_literal.encode("utf-8"))
    if input_bytes > MAX_INPUT_LITERAL_BYTES:
        raise LearningRequestBuildError("PROFILE_REQUEST_INPUT_LITERAL_BUDGET_EXCEEDED")
    return {
        "schema": SCHEMA,
        "mode": "READ_ONLY",
        "profile_code": profile_code,
        "input_literal": input_literal,
        "input_literal_bytes": input_bytes,
        "max_input_literal_bytes": MAX_INPUT_LITERAL_BYTES,
        "input_budget_pass": True,
        "context_selected_count": context["selected_count"],
        "context_bytes": context["context_bytes"],
        "context_budget_bytes": context["context_budget_bytes"],
        "llm_calls_for_materialization": 0,
        "round_trips_for_materialization": 0,
        "enqueue_performed": False,
        "writes_performed": False,
        "automatic_impact": False,
        "production_authorized": False,
    }
