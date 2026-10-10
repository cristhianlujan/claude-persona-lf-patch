"""Reconcile existing targeted-evidence planner outputs with D1 discovery state.

PURE state transition, no SQL, no read privileges, no independent truth.
The trusted runtime must resolve admission receipts from Supabase, never GPT.
The targeted-evidence planner's "exhausted" is local to provided candidates.
"""
from __future__ import annotations
from typing import Any


def _transition(state: str, code: str) -> dict[str, Any]:
    return {
        "schema_version": "LF_D1_D2_PLANNER_RECONCILIATION_V1",
        "transition": state,
        "code": code,
        "effects_executed": False,
        "data_access_granted": False,
        "global_discovery_exhausted": False,
    }


def reconcile_planner_result(
    discovery: dict[str, Any],
    planner_input: dict[str, Any],
    planner_result: dict[str, Any],
) -> dict[str, Any]:
    """Do not infer global absence or final decision from the existing planner.

    planner_input is for structural consistency checks only; it MUST come from
    an independently authorized server adapter, not a user/LLM prediction.
    This function NEVER grants access or declares global discovery exhausted.
    """
    if not all(isinstance(x, dict) for x in (discovery, planner_input, planner_result)):
        return _transition("BLOCK", "RECONCILIATION_INPUT_INVALID")
    if (
        planner_result.get("schema_version") != "LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1"
        or planner_result.get("effects_executed") is not False
        or not isinstance(planner_input.get("candidates"), list)
        or not isinstance(planner_input.get("unresolved_reasons"), list)
    ):
        return _transition("BLOCK", "PLANNER_CONTRACT_INVALID")

    state, code = planner_result.get("state"), planner_result.get("code")
    if state == "CONTINUE":
        if code != "NEXT_MINIMAL_EVIDENCE_SELECTED":
            return _transition("BLOCK", "UNKNOWN_PLANNER_CONTINUE")
        selected = planner_result.get("next_evidence")
        if not isinstance(selected, dict):
            return _transition("BLOCK", "SELECTED_EVIDENCE_INVALID")
        candidate_ref, source_ref = selected.get("candidate_ref"), selected.get("source_ref")
        if not isinstance(candidate_ref, str) or not candidate_ref or not isinstance(source_ref, str) or not source_ref:
            return _transition("BLOCK", "SELECTED_EVIDENCE_INVALID")
        matches = [
            c for c in planner_input["candidates"]
            if isinstance(c, dict)
            and c.get("candidate_ref") == candidate_ref
            and c.get("source_ref") == source_ref
            and c == selected
            and c.get("available") is True
            and c.get("material") is True
        ]
        if len(matches) != 1:
            return _transition("BLOCK", "PLANNER_SELECTED_UNADMITTED_CANDIDATE")
        return {
            **_transition("NEXT_EVIDENCE_READBACK_REQUIRED", "PLANNER_CHOICE_MATCHED_ADMITTED_INPUT"),
            "candidate_ref": candidate_ref,
            "source_ref": source_ref,
        }

    if state == "STOP" and code == "STOP_NO_DECISION_CHANGING_EVIDENCE":
        if discovery.get("discovery_state") in ("ERROR_FAIL_CLOSED", "ACCESS_DENIED"):
            return _transition("BLOCK", "DISCOVERY_BLOCKED")
        if discovery.get("discovery_state") == "DISCOVERY_EXHAUSTED":
            return _transition("BLOCK", "CANONICAL_EXHAUSTION_RECEIPT_REQUIRED")
        # Even if planner_result.automation_options_exhausted is true,
        # it is LOCAL to the supplied admitted candidate set.
        return _transition("RETURN_TO_SOURCE_DISCOVERY", "LOCAL_CANDIDATES_EXHAUSTED_ONLY")

    if state == "STOP" and code == "STOP_DECISION_RESOLVED":
        return _transition("INDEPENDENT_DECISION_ASSESSMENT_REQUIRED", "UNRESOLVED_REASONS_EMPTY")

    return _transition("BLOCK", "PLANNER_FAILURE_OR_UNKNOWN_STATE")
