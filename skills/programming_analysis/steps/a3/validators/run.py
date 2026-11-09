"""A3 source-only consumer of existing A2→A3 canonical handoff and LF readback.

No new source resolver, Router, classifier, SQL, network, model, or A4
dispatch. The host performs existing governed source reads. This module only
organizes *supplied* source rows and never attests identity or currentness.
"""
from __future__ import annotations

from copy import deepcopy
from typing import Any

SCHEMA = "TARGETED_EVIDENCE_SET_V1"
INPUTS = {"REQUEST_CONTEXT_V1", "ANALYSIS_CHANGE_CLASSIFICATION_V1"}


def blocked(code: str) -> dict:
    return {
        "schema_version": SCHEMA, "status": "BLOCKED",
        "blocking_codes": [code], "sufficiency_verdict": "BLOCKED",
        "evidence_items": [], "source_refs": [], "currentness_refs": [],
        "target_granularity": None, "authority_state": "UNKNOWN",
        "implementation_state": "UNKNOWN", "target_resolution": None,
        "authority_binding_refs": [],
        "as_is_baseline_or_new_implementation_evidence": None,
        "unresolved_material_gaps": [code], "a4_allowed": False,
        "source_attested": False, "independent_judge_verified": False,
        "runtime_qualified": False, "no_write_performed": True,
    }


def run(canonical_inputs: Any, resolved_sources: Any = None,
        *, business: str = "LF") -> dict:
    """Project already retrieved evidence; no authority is derived from args.

    canonical_inputs contains EXACTLY A3's two canonical input contracts.
    resolved_sources is an untrusted readback sidecar supplied by the existing
    authorized source adapter, NOT a third canonical input or an RPC handle.
    """
    if business != "LF":
        return blocked("A3_BUSINESS_NOT_ENABLED_FOR_LF_SKILL")
    if not isinstance(canonical_inputs, dict) or set(canonical_inputs) != INPUTS:
        return blocked("A3_EXACT_TWO_CANONICAL_INPUTS_REQUIRED")
    context = canonical_inputs["REQUEST_CONTEXT_V1"]
    cls = canonical_inputs["ANALYSIS_CHANGE_CLASSIFICATION_V1"]
    if (not isinstance(context, dict) or not isinstance(cls, dict)
            or context.get("schema_version") != "REQUEST_CONTEXT_V1"
            or cls.get("schema_version") != "ANALYSIS_CHANGE_CLASSIFICATION_V1"
            or context.get("no_solution_inferred") is not True
            or not isinstance(context.get("objective"), dict)
            or not isinstance(context.get("constraints"), list)
            or not isinstance(context.get("source_refs"), list)
            or not isinstance(context.get("target_hints"), list)):
        return blocked("A3_CANONICAL_INPUT_SHAPE_INVALID")
    target = cls.get("target_ref")
    if (not isinstance(target, str) or not target
            or target not in context["target_hints"]
            or cls.get("target_granularity") != "SCREEN"):
        return blocked("A3_TARGET_SCOPE_OR_GRANULARITY_UNRESOLVED")
    if not isinstance(resolved_sources, dict):
        return blocked("A3_GOVERNED_SOURCE_READBACK_REQUIRED")
    if (resolved_sources.get("schema_version") != "LF_SCREEN_SOURCE_READBACK_V1"
            or resolved_sources.get("business") != "LF"
            or resolved_sources.get("target_ref") != target
            or resolved_sources.get("source_function") != "lf_ops.fn_screen_contract_v1"):
        return blocked("A3_LF_SOURCE_IDENTITY_CONFLICT")
    ref = resolved_sources.get("screen_ref")
    if ref != "supabase://lf_ops.pantallas/" + target:
        return blocked("A3_EXACT_SCREEN_REF_MISMATCH")
    if (not isinstance(resolved_sources.get("screen_status"), str)
            or not isinstance(resolved_sources.get("contract_version"), str)):
        return blocked("A3_SCREEN_METADATA_MISSING")
    rows = resolved_sources.get("linked_rules")
    policies = resolved_sources.get("policy_links")
    if not isinstance(rows, list) or not isinstance(policies, list):
        return blocked("A3_LINKED_RULES_AND_POLICIES_REQUIRED")
    seen, approved, excluded = set(), [], []
    for item in rows:
        if not isinstance(item, dict):
            return blocked("A3_RULE_ROW_INVALID")
        code, status, pending = item.get("code"), item.get("status"), item.get("pending_decision")
        source, assoc = item.get("source_ref"), item.get("association_ref")
        if (not isinstance(code, str) or not code or code in seen
                or status not in ("VIGENTE", "CANDIDATO", "SUSPENDIDO", "INACTIVO")
                or type(pending) is not bool
                or not isinstance(source, str)
                or not source.startswith("supabase://lf_ops.reglas/")
                or not isinstance(assoc, str)
                or not assoc.startswith("supabase://lf_ops.reglas_pantallas/")):
            return blocked("A3_RULE_SOURCE_ROW_CONFLICT_OR_DUPLICATED")
        seen.add(code)
        row = {
            "rule_code": code, "title": item.get("title"),
            "description": item.get("description"),
            "rule_status": status, "pending_decision": pending,
            "source_ref": source, "association_ref": assoc,
            "evidence_kind": "DIRECT_SCREEN_RULE",
            "source_attestation_state": "PROVIDER_READBACK_UNATTESTED",
        }
        if status == "VIGENTE" and pending is False:
            approved.append(row)
        else:
            row["exclusion_reason"] = (
                "DECISION_PENDING" if pending else "RULE_NOT_VIGENTE"
            )
            excluded.append(row)
    policy_states = []
    for p in policies:
        if (not isinstance(p, dict)
                or not isinstance(p.get("status"), str)
                or not isinstance(p.get("source_ref"), str)
                or not p["source_ref"].startswith("supabase://lf_ops.pantallas_politicas/")):
            return blocked("A3_POLICY_LINK_SOURCE_INVALID")
        policy_states.append({
            "source_ref": p["source_ref"], "policy_kind": p.get("policy_kind"),
            "status": p["status"], "is_approved_binding": p["status"] == "VIGENTE",
        })
    gaps = [
        "SOURCE_READBACK_CURRENTNESS_AND_AUTHORITY_NOT_ATTESTED",
        "GITHUB_CURRENT_IMPLEMENTATION_AND_AS_IS_MISSING",
    ]
    if resolved_sources["screen_status"] != "VIGENTE":
        gaps.append("SCREEN_DEFINITION_NOT_VIGENTE")
    if any(not p["is_approved_binding"] for p in policy_states):
        gaps.append("SCREEN_POLICY_ASSOCIATIONS_NOT_ALL_VIGENTE")
    if excluded:
        gaps.append("CANDIDATE_OR_UNRESOLVED_RULES_EXCLUDED_FROM_APPROVED_SCOPE")
    consolidated = resolved_sources.get("consolidated_rule_status_counts")
    if consolidated is not None:
        if (not isinstance(consolidated, dict)
                or any(not isinstance(k, str) or type(v) is not int or v < 0
                       for k, v in consolidated.items())):
            return blocked("A3_CONSOLIDATED_COUNTS_INVALID")
        if sum(consolidated.values()) > len(rows):
            gaps.append("TRANSVERSAL_RULE_APPLICABILITY_NOT_BOUND_TO_SCREEN")
    return {
        "schema_version": SCHEMA,
        "status": "SOURCE_READBACK_PROCESSED_UNATTESTED",
        "blocking_codes": gaps[:],
        "sufficiency_verdict": "NEED_MORE_EVIDENCE",
        "business": "LF", "target_ref": target,
        "target_granularity": cls["target_granularity"],
        "authority_state": "UNKNOWN", "implementation_state": "UNKNOWN",
        "evidence_items": approved,
        "excluded_rule_items": excluded,
        "policy_link_items": policy_states,
        "counts": {
            "direct_rules_total": len(rows),
            "direct_rules_vigente_no_pending": len(approved),
            "direct_rules_excluded": len(excluded),
            "policy_links_total": len(policies),
            "policy_links_not_vigente": sum(not p["is_approved_binding"] for p in policy_states),
            "consolidated_rule_status_counts": deepcopy(consolidated),
        },
        "source_refs": [ref] + [x["source_ref"] for x in approved],
        "currentness_refs": [],
        "authority_binding_refs": [],
        "target_resolution": {
            "target_ref": target,
            "source_ref": ref,
            "declared_screen_status": resolved_sources["screen_status"],
            "contract_version": resolved_sources["contract_version"],
            "authority_state": "UNKNOWN", "implementation_state": "UNKNOWN",
            "screen_readback_not_source_attestation": True,
        },
        "as_is_baseline_or_new_implementation_evidence": None,
        "unresolved_material_gaps": gaps,
        "declared_constraints": deepcopy(context["constraints"]),
        "source_readback_function": resolved_sources["source_function"],
        "a4_allowed": False, "source_attested": False,
        "independent_judge_verified": False, "runtime_qualified": False,
        "no_write_performed": True,
    }
