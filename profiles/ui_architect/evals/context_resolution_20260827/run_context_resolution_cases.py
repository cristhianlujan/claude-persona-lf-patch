#!/usr/bin/env python3
"""Deterministic contract regression for UI Architect context resolution V5.

This does not pretend to execute the profile/model. It validates the narrow
context-resolution semantics that the profile/judge contract must enforce.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional


CANONICAL_MODES = {"CANONICAL_TOKEN", "UPSTREAM_VALUE"}


@dataclass
class Case:
    name: str
    canonical_value: Optional[str] = None
    selected_value: Optional[str] = None
    precision_mode: Optional[str] = None
    source_bound: bool = False
    proposal_status: Optional[str] = None
    exploratory: bool = False
    missing_is_material: bool = False
    pipeline_action: str = "CONTINUE_WITH_ASSUMPTIONS"
    asks_end_user_directly: bool = False
    recoverable_from_context: bool = False
    expected_valid: bool = True
    expected_codes: List[str] = field(default_factory=list)


def validate(case: Case) -> List[str]:
    errors: List[str] = []

    if case.asks_end_user_directly:
        errors.append("DIRECT_END_USER_QUESTION_FORBIDDEN")

    if case.recoverable_from_context and case.pipeline_action != "CONTINUE_WITH_ASSUMPTIONS":
        errors.append("RECOVERABLE_CONTEXT_ESCALATED")

    if case.canonical_value is not None:
        if case.precision_mode not in CANONICAL_MODES:
            errors.append("CANONICAL_CONTEXT_NOT_USED")
        if case.selected_value != case.canonical_value:
            errors.append("CANONICAL_VALUE_MISMATCH")
        if not case.source_bound:
            errors.append("CANONICAL_SOURCE_NOT_BOUND")
        if case.proposal_status == "PROPOSED_NOT_CANONICAL":
            errors.append("CANONICAL_VALUE_MISLABELED_PROPOSAL")
    else:
        if case.precision_mode in CANONICAL_MODES:
            errors.append("FALSE_CANONICAL_AUTHORITY")
        if case.precision_mode == "EXPLORATORY_PROPOSAL" and case.proposal_status != "PROPOSED_NOT_CANONICAL":
            errors.append("EXPLORATORY_PROPOSAL_NOT_LABELED")
        if case.exploratory and not case.missing_is_material and case.pipeline_action == "BLOCK_PIPELINE":
            errors.append("EXPLORATION_BLOCKED_FOR_MISSING_TOKEN")

    if case.missing_is_material:
        if case.pipeline_action not in {"RETURN_TO_ORCHESTRATOR", "BLOCK_PIPELINE"}:
            errors.append("MATERIAL_MISSING_INPUT_NOT_ESCALATED")
    elif case.exploratory and case.pipeline_action == "RETURN_TO_ORCHESTRATOR":
        errors.append("NON_MATERIAL_EXPLORATION_ESCALATED")

    return errors


def main() -> int:
    cases = [
        Case(
            name="canonical_space_24",
            canonical_value="space_24",
            selected_value="space_24",
            precision_mode="CANONICAL_TOKEN",
            source_bound=True,
            expected_valid=True,
        ),
        Case(
            name="canonical_degraded_to_vague",
            canonical_value="space_24",
            selected_value="more_air",
            precision_mode="RELATIVE_GUIDANCE",
            source_bound=False,
            expected_valid=False,
            expected_codes=["CANONICAL_CONTEXT_NOT_USED", "CANONICAL_VALUE_MISMATCH", "CANONICAL_SOURCE_NOT_BOUND"],
        ),
        Case(
            name="exploratory_concrete_proposal",
            selected_value="24px",
            precision_mode="EXPLORATORY_PROPOSAL",
            proposal_status="PROPOSED_NOT_CANONICAL",
            exploratory=True,
            expected_valid=True,
        ),
        Case(
            name="exploratory_relative_guidance",
            selected_value="increase_one_spacing_level",
            precision_mode="RELATIVE_GUIDANCE",
            exploratory=True,
            expected_valid=True,
        ),
        Case(
            name="exploratory_missing_token_blocked",
            exploratory=True,
            pipeline_action="BLOCK_PIPELINE",
            expected_valid=False,
            expected_codes=["EXPLORATION_BLOCKED_FOR_MISSING_TOKEN"],
        ),
        Case(
            name="false_ds_token",
            selected_value="space_20",
            precision_mode="CANONICAL_TOKEN",
            exploratory=True,
            expected_valid=False,
            expected_codes=["FALSE_CANONICAL_AUTHORITY"],
        ),
        Case(
            name="material_interaction_to_orchestrator",
            missing_is_material=True,
            pipeline_action="RETURN_TO_ORCHESTRATOR",
            expected_valid=True,
        ),
        Case(
            name="material_interaction_silently_assumed",
            missing_is_material=True,
            pipeline_action="CONTINUE_WITH_ASSUMPTIONS",
            expected_valid=False,
            expected_codes=["MATERIAL_MISSING_INPUT_NOT_ESCALATED"],
        ),
        Case(
            name="recoverable_token_questioned_again",
            canonical_value="space_24",
            selected_value="space_24",
            precision_mode="CANONICAL_TOKEN",
            source_bound=True,
            recoverable_from_context=True,
            pipeline_action="RETURN_TO_ORCHESTRATOR",
            expected_valid=False,
            expected_codes=["RECOVERABLE_CONTEXT_ESCALATED"],
        ),
        Case(
            name="worker_asks_end_user",
            missing_is_material=True,
            pipeline_action="RETURN_TO_ORCHESTRATOR",
            asks_end_user_directly=True,
            expected_valid=False,
            expected_codes=["DIRECT_END_USER_QUESTION_FORBIDDEN"],
        ),
        Case(
            name="partial_context_holdout_known_spacing",
            canonical_value="space_16",
            selected_value="space_16",
            precision_mode="CANONICAL_TOKEN",
            source_bound=True,
            expected_valid=True,
        ),
    ]

    failures = []
    for case in cases:
        errors = validate(case)
        valid = not errors
        expected_codes_ok = all(code in errors for code in case.expected_codes)
        passed = valid == case.expected_valid and expected_codes_ok
        print(f"{case.name}: {'PASS' if passed else 'FAIL'} valid={valid} errors={errors}")
        if not passed:
            failures.append(case.name)

    if failures:
        print("CONTEXT_RESOLUTION_MATRIX_FAIL", failures)
        return 1

    print(f"CONTEXT_RESOLUTION_MATRIX_PASS={len(cases)}/{len(cases)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
