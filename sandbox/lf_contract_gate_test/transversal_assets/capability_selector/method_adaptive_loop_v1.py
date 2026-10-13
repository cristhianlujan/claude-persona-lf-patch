"""Bounded evidence-driven method execution loop — isolated non-authority only.

Uses existing V3 selection/replan; never promotes a method or changes authority.
"""
from __future__ import annotations

from copy import deepcopy
from typing import Any, Callable

from capability_selector_v3 import compose_capabilities_v3, replan_composition
from method_execution_bridge_v1 import execute_method_selection


def run_adaptive_method_loop(
    *,
    context: dict[str, Any],
    catalog: list[dict[str, Any]],
    capability_policy: dict[str, Any],
    registry: dict[str, Any],
    precondition_state: dict[str, Any],
    bindings: dict[str, dict[str, Any]],
    method_inputs: dict[str, dict[str, Any]],
    execution_id: str,
    evidence_refs: list[str],
    permission_receipt: dict[str, Any],
    verify_permission: Callable,
    verify_selection: Callable,
    verify_result: Callable,
    result_verifier_id: str,
    observation_evidence_refs: list[str],
    max_cycles: int = 2,
) -> dict[str, Any]:
    """Dispatch selected methods; upon an actual failure, replan and retry
    with the failed method excluded for this run. No silent retry of failures.
    """
    fail = {
        "schema": "PROFILE_ADAPTIVE_METHOD_LOOP_V1",
        "status": "BLOCKED",
        "cycles": [],
        "production_authorized": False,
        "profile_source_write_authorized": False,
        "cutover_eligible": False,
    }
    if not isinstance(max_cycles, int) or isinstance(max_cycles, bool) or not 1 <= max_cycles <= 5:
        return {**fail, "blocking_codes": ["ITERATION_BUDGET_INVALID"]}
    if not isinstance(context, dict):
        return {**fail, "blocking_codes": ["CONTEXT_INVALID"]}
    current = deepcopy(context)
    selection = compose_capabilities_v3(
        current, catalog, capability_policy, registry, precondition_state)
    history = []
    for index in range(max_cycles):
        event = execute_method_selection(
            selection, registry, bindings, method_inputs,
            execution_id=execution_id, evidence_refs=evidence_refs,
            scope="TEST_NON_AUTHORITY", permission_receipt=permission_receipt,
            verify_permission=verify_permission,
            verify_selection=verify_selection, verify_result=verify_result,
            result_verifier_id=result_verifier_id,
        )
        cycle = {"cycle": index, "selected_method_ids": [
            x.get("method_id") for x in selection.get("selected_methods", [])
        ], "execution": event}
        history.append(cycle)
        if event["status"] in {"EXECUTED_TEST_ONLY", "NO_METHOD_REQUIRED"}:
            return {
                **fail, "status": "COMPLETED_TEST_ONLY",
                "blocking_codes": [],
                "cycles": history,
                "actual_invocations": sum(
                    c["execution"].get("actual_method_invocations", 0) for c in history),
            }
        if event["status"] != "METHOD_FAILED":
            return {**fail, "blocking_codes": event.get("blocking_codes", ["EXECUTION_BLOCKED"]),
                    "cycles": history}
        if index + 1 >= max_cycles:
            return {**fail, "status": "STOP_ITERATION_BUDGET",
                    "blocking_codes": ["ITERATION_BUDGET_EXHAUSTED"],
                    "cycles": history}
        if not isinstance(observation_evidence_refs, list) or not observation_evidence_refs:
            return {**fail, "blocking_codes": ["REPLAN_EVIDENCE_REQUIRED"], "cycles": history}
        failed = event.get("invocations", [])[-1]["method_id"]
        observation = {
            "trigger": "METHOD_FAILED",
            "method_id": failed,
            "evidence_refs": observation_evidence_refs,
        }
        replay = replan_composition(
            current, observation, catalog, capability_policy,
            registry, precondition_state)
        cycle["replan"] = replay
        if replay.get("status") != "REPLANNED":
            return {**fail, "blocking_codes": replay.get("blocking_codes", ["REPLAN_FAILED"]),
                    "cycles": history}
        current["selection_cycle"] = replay["new_cycle"]
        current["blocked_methods"] = replay["blocked_methods_for_current_run"]
        selection = replay["new_composition"]
    return {**fail, "status": "STOP_ITERATION_BUDGET", "blocking_codes": ["ITERATION_BUDGET_EXHAUSTED"],
            "cycles": history}
