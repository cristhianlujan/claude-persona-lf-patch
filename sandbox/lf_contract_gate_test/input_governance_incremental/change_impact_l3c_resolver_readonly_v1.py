#!/usr/bin/env python3
"""Deterministic READ_ONLY change-impact resolver candidate.

Research only. It never authorizes SCOPED_PASS, downstream execution, promotion,
canonical writes, or production. It must not receive/use benchmark case ids.
"""
from __future__ import annotations
from typing import Any

VALID_SUBJECTS = {"copy","action","permission","route","component","field","validation","state_transition","error","api"}
KNOWN_CHANGE_KINDS = {
    "ADD_NEW_SEMANTICS","ALTER_DATA_TYPE","ALTER_EXISTING_SEMANTICS","ALTER_EXPORT_SCHEMA",
    "ALTER_FILTER_BEHAVIOR","ALTER_HTTP_SEMANTICS","ALTER_OUTCOME_SEVERITY","ALTER_PAGINATION",
    "ALTER_PARAMETER_WITHOUT_AUTHORITY","ALTER_PRIVACY_CLASSIFICATION","ALTER_REQUIREDNESS",
    "ALTER_RETRY_POLICY","ALTER_TRANSITION_ENDPOINTS","ARTIFACT_ONLY_CANONICAL_RECONCILIATION",
    "BROKEN_REFERENCE","CANONICAL_RECONCILIATION","CONTRADICT_CANONICAL_ACTION","CROSS_RESOURCE_REBIND",
    "CROSS_SCREEN_REFERENCE","DEPRECATED_REFERENCE","INVALID_READONLY_COVERAGE","NON_SEMANTIC_FORMAT",
    "NO_CHANGE","REMOVE_BINDING","REMOVE_PERMISSION_GUARD","REMOVE_REQUIRED_VALIDATION",
    "SENSITIVE_DISCLOSURE","UNPROVEN_EQUIVALENCE"
}
SAFE_KINDS = {"NO_CHANGE","CANONICAL_RECONCILIATION","NON_SEMANTIC_FORMAT","ARTIFACT_ONLY_CANONICAL_RECONCILIATION"}
HUMAN_KINDS = {"ADD_NEW_SEMANTICS","ALTER_PARAMETER_WITHOUT_AUTHORITY","ALTER_EXPORT_SCHEMA"}
LOCAL_BLOCK_KINDS = {"CONTRADICT_CANONICAL_ACTION","UNPROVEN_EQUIVALENCE","DEPRECATED_REFERENCE","INVALID_READONLY_COVERAGE","SENSITIVE_DISCLOSURE"}
UNCERTAIN_DEPENDENCY_STATES = {"UNKNOWN","STALE","CONFLICT"}


def resolve_change(change: dict[str, Any]) -> dict[str, Any]:
    # Association-only benchmark identifiers are intentionally ignored.
    subject = change.get("subject_kind")
    change_kind = change.get("change_kind")
    facts = change.get("facts") if isinstance(change.get("facts"), dict) else {}
    authority = facts.get("canonical_authority", "UNKNOWN")
    shared_state = facts.get("shared_dependency_status", "CURRENT")
    checks = ["input_shape","subject_kind","change_kind","authority"]

    if subject not in VALID_SUBJECTS or change_kind not in KNOWN_CHANGE_KINDS:
        return _result("GLOBAL_ESCALATE", {"SOURCE_AUTHORITY_PROVENANCE"}, checks, "UNKNOWN_OR_UNSUPPORTED_CHANGE")
    if shared_state in UNCERTAIN_DEPENDENCY_STATES:
        checks.append("shared_dependency")
        return _result("GLOBAL_ESCALATE", {"SOURCE_AUTHORITY_PROVENANCE"}, checks, "SHARED_DEPENDENCY_NOT_CURRENT")

    if change_kind in SAFE_KINDS and authority == "EXACT_CURRENT":
        decision, reason = "SCOPED_CANDIDATE", "BOUNDED_CURRENT_AUTHORITY"
    elif change_kind in HUMAN_KINDS and authority in {"MISSING","UNKNOWN","NOT_MATERIALIZED"}:
        decision, reason = "HUMAN_REQUIRED", "NEW_OR_SCHEMA_SEMANTICS_WITHOUT_AUTHORITY"
    elif subject == "copy" and change_kind == "CROSS_RESOURCE_REBIND" and facts.get("local_invalidity"):
        decision, reason = "SCOPED_BLOCK", "LOCAL_COPY_BINDING_INVALID"
    elif change_kind in LOCAL_BLOCK_KINDS:
        decision, reason = "SCOPED_BLOCK", "LOCAL_INVALIDITY"
    elif change_kind == "REMOVE_BINDING" and subject == "component" and facts.get("local_invalidity"):
        decision, reason = "SCOPED_BLOCK", "LOCAL_COMPONENT_BINDING_INVALID"
    else:
        decision, reason = "GLOBAL_ESCALATE", "SEMANTIC_OR_CROSS_FAMILY_CHANGE"

    impacts: set[str] = set()
    if subject == "copy":
        if change_kind == "NON_SEMANTIC_FORMAT": impacts.add("VISUAL_EVIDENCE")
        else:
            impacts.update({"ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"})
            _add_if(impacts,facts,"ui_message_change","UI_MESSAGES")
    elif subject == "action":
        impacts.add("ACTIONS"); _add_if(impacts,facts,"permission_coupled","PERMISSIONS"); _add_if(impacts,facts,"api_coupled","API_DATA_CONTRACT"); _add_if(impacts,facts,"security_sensitive","SECURITY")
    elif subject == "permission":
        impacts.add("PERMISSIONS"); _add_if(impacts,facts,"action_coupled","ACTIONS"); _add_if(impacts,facts,"security_sensitive","SECURITY"); _add_if(impacts,facts,"api_coupled","API_DATA_CONTRACT")
    elif subject == "route":
        impacts.add("ROUTING_NAVIGATION"); _add_if(impacts,facts,"action_coupled","ACTIONS")
    elif subject == "component":
        impacts.add("DESIGN_SYSTEM"); _add_if(impacts,facts,"asset_coupled","ASSETS_ICONS"); _add_if(impacts,facts,"visual_change","VISUAL_EVIDENCE"); _add_if(impacts,facts,"accessibility_coupled","ACCESSIBILITY")
    elif subject == "field":
        impacts.add("FIELDS"); _add_if(impacts,facts,"validation_coupled","VALIDATIONS"); _add_if(impacts,facts,"api_coupled","API_DATA_CONTRACT"); _add_if(impacts,facts,"ui_message_change","UI_MESSAGES"); _add_if(impacts,facts,"design_coupled","DESIGN_SYSTEM"); _add_if(impacts,facts,"privacy_sensitive","PRIVACY_PII"); _add_if(impacts,facts,"security_sensitive","SECURITY"); _add_if(impacts,facts,"audit_coupled","AUDIT")
    elif subject == "validation":
        impacts.add("VALIDATIONS"); _add_if(impacts,facts,"field_coupled","FIELDS"); _add_if(impacts,facts,"api_coupled","API_DATA_CONTRACT"); _add_if(impacts,facts,"ui_message_change","UI_MESSAGES"); _add_if(impacts,facts,"objective_coupled","OBJECTIVE_OUTCOMES")
    elif subject == "state_transition":
        _add_if(impacts,facts,"state_set_coupled","STATES"); impacts.add("TRANSITIONS"); _add_if(impacts,facts,"action_coupled","ACTIONS"); _add_if(impacts,facts,"permission_coupled","PERMISSIONS"); _add_if(impacts,facts,"security_sensitive","SECURITY")
    elif subject == "error":
        impacts.add("ERRORS"); _add_if(impacts,facts,"ui_message_change","UI_MESSAGES"); _add_if(impacts,facts,"visual_change","VISUAL_EVIDENCE"); _add_if(impacts,facts,"security_sensitive","SECURITY"); _add_if(impacts,facts,"api_coupled","API_DATA_CONTRACT"); _add_if(impacts,facts,"retry_coupled","TIMEOUT_RETRY")
    elif subject == "api":
        if change_kind == "ARTIFACT_ONLY_CANONICAL_RECONCILIATION": impacts.update({"ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"})
        else:
            impacts.add("API_DATA_CONTRACT"); _add_if(impacts,facts,"field_coupled","FIELDS"); _add_if(impacts,facts,"validation_coupled","VALIDATIONS"); _add_if(impacts,facts,"objective_coupled","OBJECTIVE_OUTCOMES"); _add_if(impacts,facts,"action_coupled","ACTIONS"); _add_if(impacts,facts,"permission_coupled","PERMISSIONS")

    if decision == "HUMAN_REQUIRED":
        impacts.add("SOURCE_AUTHORITY_PROVENANCE"); checks.append("source_authority")
    for key,value in facts.items():
        if isinstance(value,bool) and value: checks.append(f"fact:{key}")
    return _result(decision, impacts, checks, reason)


def _add_if(impacts: set[str], facts: dict[str, Any], fact: str, family: str) -> None:
    if facts.get(fact): impacts.add(family)


def _result(decision: str, impacts: set[str], checks: list[str], reason: str) -> dict[str, Any]:
    return {
        "decision":decision,
        "impact_families":sorted(impacts),
        "reason_code":reason,
        "evidence_depth":len(set(checks)),
        "authorization":{"scoped_pass_authorized":False,"downstream_authorized":False,"production_authorized":False}
    }
