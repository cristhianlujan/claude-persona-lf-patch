#!/usr/bin/env python3
from __future__ import annotations

def classify_analysis_gap(*, implementation_exists: bool, programmable: bool, authority_resolved: bool,
                          requirements_resolved: bool, acceptance_resolved: bool,
                          owner_decision_required: bool=False, contradiction: bool=False) -> str:
    if owner_decision_required:
        return "HUMAN_DECISION_REQUIRED"
    if contradiction:
        return "BLOCKED"
    if not authority_resolved or not requirements_resolved or not acceptance_resolved:
        return "NEED_MORE_EVIDENCE_OR_BLOCKED"
    if not implementation_exists and programmable:
        return "BUILD_REQUIRED"
    return "RESOLVED"

def owner_route(*, current_decision_exists: bool, true_owner_decision: bool, evidence_paths_exhausted: bool) -> str:
    if current_decision_exists:
        return "REUSE_CURRENT_DECISION"
    if true_owner_decision and evidence_paths_exhausted:
        return "EMIT_HUMAN_DECISION_PACKET"
    return "CONTINUE_TARGETED_EVIDENCE"

def budget_route(estimated_tokens: int, soft_limit: int, hard_limit: int) -> str:
    if estimated_tokens > hard_limit:
        return "BLOCK_RETURN_PG04"
    if estimated_tokens > soft_limit:
        return "YELLOW_JIT"
    return "GREEN_CONTINUE"

assert classify_analysis_gap(
    implementation_exists=False, programmable=True, authority_resolved=True,
    requirements_resolved=True, acceptance_resolved=True
) == "BUILD_REQUIRED"

assert owner_route(current_decision_exists=True, true_owner_decision=True, evidence_paths_exhausted=True) == "REUSE_CURRENT_DECISION"
assert owner_route(current_decision_exists=False, true_owner_decision=True, evidence_paths_exhausted=True) == "EMIT_HUMAN_DECISION_PACKET"
assert owner_route(current_decision_exists=False, true_owner_decision=False, evidence_paths_exhausted=False) == "CONTINUE_TARGETED_EVIDENCE"

assert budget_route(1400, 1500, 3000) == "GREEN_CONTINUE"
assert budget_route(2000, 1500, 3000) == "YELLOW_JIT"
assert budget_route(3001, 1500, 3000) == "BLOCK_RETURN_PG04"

print("PASS_PROGRAMMING_CONTROL_SWEEP_REGRESSION cases=7")
