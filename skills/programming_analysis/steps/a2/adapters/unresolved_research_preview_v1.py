"""Design-only A2 research preview for an A1 material ambiguity.

No A2 depth classification, no A3 dispatch, model judge, authority or I/O.
Canonical A1/A2/A3 schemas and the A3 two-input interface remain unchanged.
"""
from __future__ import annotations

from copy import deepcopy
import hashlib
import json
from typing import Any

SCHEMA = "A2_UNRESOLVED_RESEARCH_PREVIEW_CANDIDATE_V1"
RESOLUTION_ORDER = (
    "EXACT_TARGET_IDENTITY", "CURRENT_CANONICAL_AUTHORITY",
    "CURRENT_IMPLEMENTATION", "RELATED_AUTHORITIES",
    "CONSUMERS_AND_DEPENDENCIES",
)


def _hash(data: Any) -> str:
    return hashlib.sha256(json.dumps(
        data, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")).hexdigest()


def _blocked(code: str) -> dict:
    return {
        "schema_version": SCHEMA, "status": "BLOCKED",
        "blocking_codes": [code], "research_plan": None,
        "a2_classification": None, "a3_canonical_inputs": None,
        "a3_dispatch_allowed": False, "a2_depth_classified": False,
        "source_authenticated": False, "independent_judge_attested": False,
        "runtime_integrated": False, "next_step": None,
    }


def prepare(a1_result: Any) -> dict:
    """Conserve reviewed-candidate content only; never promote an open A1.

    A1's reviewer reference is untrusted until verified by the governed host.
    Output is a plan for subsequent source investigation, NOT its execution.
    """
    if not isinstance(a1_result, dict) or any(
        a1_result.get(k) != v for k, v in (
            ("schema_version", "A1_INTERNAL_STEP_CANDIDATE_RESULT_V1"),
            ("skill_code", "PROGRAMMING_ANALYSIS_LF"),
            ("step_code", "A1"),
            ("status", "REQUIRES_DECISION"),
        )
    ):
        return _blocked("A2_RESEARCH_A1_DECISION_REQUIRED")
    if (a1_result.get("next_capability") is not None
            or a1_result.get("external_authority_verified") is not False
            or a1_result.get("operationally_integrated") is not False
            or a1_result.get("effects_executed") is not False
            or a1_result.get("semantic_review_identity_verified") is not False
            or a1_result.get("interpretation_state") not in (
                "SEMANTIC_CANDIDATE_UNATTESTED", "SEMANTIC_REVIEWED_CANDIDATE"
            )):
        return _blocked("A2_RESEARCH_A1_FALSE_AUTHORITY")
    business = a1_result.get("business")
    context, intent = a1_result.get("payload"), a1_result.get("intent_analysis")
    if (business != "LF"
            or not isinstance(context, dict) or not isinstance(intent, dict)
            or not isinstance(a1_result.get("semantic_reviewer_ref"), str)
            or not a1_result["semantic_reviewer_ref"].strip()):
        return _blocked("A2_RESEARCH_A1_CONTEXT_INVALID")
    raw = context.get("objective", {}).get("problem_statement") if isinstance(
        context.get("objective"), dict
    ) else None
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest() if isinstance(raw, str) else None
    if (not isinstance(raw, str) or not raw.strip()
            or a1_result.get("original_request_sha256") != digest
            or a1_result.get("semantic_candidate_sha256") != _hash(intent)):
        return _blocked("A2_RESEARCH_A1_DIGEST_MISMATCH")
    # The canonical A1 payload derives this outcome from its reviewed intent.
    # A digest over intent alone does not protect against payload tampering.
    outcome = context["objective"].get("desired_outcome")
    if (not isinstance(outcome, str) or not outcome.strip()
            or outcome != intent.get("desired_outcome")):
        return _blocked("A2_RESEARCH_DESIRED_OUTCOME_DRIFT")
    target, operation = intent.get("target"), intent.get("operation")
    if not isinstance(target, dict) or not isinstance(operation, dict):
        return _blocked("A2_RESEARCH_INTENT_UNTYPED")
    refs, hints, constraints = (
        context.get("source_refs"), context.get("target_hints"),
        context.get("constraints"),
    )
    mentions = target.get("raw_mentions")
    if (not isinstance(refs, list) or not refs
            or not all(isinstance(r, str) and r.strip() for r in refs)
            or not isinstance(hints, list) or not hints
            or not all(isinstance(h, str) and h.strip() for h in hints)
            or not isinstance(mentions, list) or not mentions
            or not all(isinstance(m, str) and m.strip() for m in mentions)
            or mentions[:1] != hints
            or not isinstance(constraints, list)
            or not all(isinstance(c, str) and c.strip() and c in raw for c in constraints)):
        return _blocked("A2_RESEARCH_SOURCE_OR_CONSTRAINT_DRIFT")
    # Prevent a consumer from deleting a negation while keeping intent hash
    # and the original text unchanged. All A1 constraints must travel intact.
    declared_constraints = intent.get("explicit_constraints")
    if (not isinstance(declared_constraints, list)
            or any(not isinstance(c, dict)
                   or not isinstance(c.get("text"), str)
                   or not c["text"].strip() for c in declared_constraints)
            or constraints != [c["text"] for c in declared_constraints]):
        return _blocked("A2_RESEARCH_EXPLICIT_CONSTRAINT_DRIFT")
    spans = intent.get("evidence_spans")
    if (not isinstance(spans, list) or not spans or any(
        not isinstance(s, dict) or type(s.get("start")) is not int
        or type(s.get("end")) is not int
        or not isinstance(s.get("quote"), str) or not s["quote"]
        or not (0 <= s["start"] < s["end"] <= len(raw))
        or raw[s["start"]:s["end"]] != s["quote"]
        for s in spans
    )):
        return _blocked("A2_RESEARCH_SEMANTIC_EVIDENCE_DRIFT")
    if any(not any(
        s.get("dimension") in ("NEGATION", "CONSTRAINT")
        and c in s["quote"] for s in spans
    ) for c in constraints):
        return _blocked("A2_RESEARCH_CONSTRAINT_SPAN_MISSING")
    ambiguities = context.get("ambiguities")
    declared = intent.get("material_ambiguities")
    if not isinstance(ambiguities, list) or not isinstance(declared, list):
        return _blocked("A2_RESEARCH_AMBIGUITY_INVALID")
    if any(not isinstance(a, dict)
           or not isinstance(a.get("code"), str) or not a["code"].strip()
           or not isinstance(a.get("statement"), str) or not a["statement"].strip()
           or a.get("materiality") not in ("MATERIAL", "UNKNOWN")
           for a in declared):
        return _blocked("A2_RESEARCH_AMBIGUITY_INVALID")
    if any(not isinstance(a, dict)
           or not isinstance(a.get("code"), str) or not a["code"].strip()
           or not isinstance(a.get("statement"), str) or not a["statement"].strip()
           for a in ambiguities):
        return _blocked("A2_RESEARCH_AMBIGUITY_INVALID")
    pending = [a for a in ambiguities if a.get("resolution_state") == "OPEN"
               and a.get("materiality") in ("MATERIAL", "UNKNOWN")]
    declared_map = {(a["code"], a["statement"], a["materiality"])
                    for a in declared}
    if (not pending or len(pending) != len(declared)
            or len({a.get("code") for a in pending}) != len(pending)
            or any((a.get("code"), a.get("statement"), a.get("materiality"))
                   not in declared_map for a in pending)):
        return _blocked("A2_RESEARCH_MATERIAL_AMBIGUITY_DRIFT")
    dims = intent.get("dimensions_to_investigate")
    if not isinstance(dims, list) or not dims or not all(isinstance(d, str) and d.strip() for d in dims):
        return _blocked("A2_RESEARCH_DIMENSIONS_INVALID")
    tasks = [
        {"ambiguity_code": a["code"], "materiality": a["materiality"],
         "question": a["statement"], "state": "OPEN",
         "priority_order": list(RESOLUTION_ORDER),
         "owner_decision": "ONLY_IF_MATERIAL_UNRESOLVED_AFTER_SOURCE_REVIEW"}
        for a in pending
    ]
    return {
        "schema_version": SCHEMA, "status": "RESEARCH_PLAN_ONLY",
        "blocking_codes": ["A1_MATERIAL_INTENT_AMBIGUITY_UNRESOLVED"],
        "business": business, "request_sha256": digest,
        "a1_semantic_candidate_sha256": _hash(intent),
        "research_plan": {
            "objective_literal": raw,
            "desired_outcome_declared": context["objective"].get("desired_outcome"),
            "operation_hint": operation.get("kind"),
            "artifact_hint": target.get("artifact_kind"),
            "functional_capability_hint": target.get("canonical_capability"),
            "target_hints": deepcopy(hints), "declared_source_refs": deepcopy(refs),
            "source_refs_are_current_verified": False,
            "constraints": deepcopy(constraints),
            "unresolved_ambiguities": deepcopy(pending),
            "dimensions_to_investigate": deepcopy(dims),
            "source_research_tasks": tasks,
            "classification_state": "DEFERRED_UNTIL_MATERIAL_AMBIGUITIES_RESOLVED",
        },
        "a2_classification": None, "a3_canonical_inputs": None,
        "a3_dispatch_allowed": False, "a2_depth_classified": False,
        "source_authenticated": False, "independent_judge_attested": False,
        "runtime_integrated": False, "next_step": None,
    }
