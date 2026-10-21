#!/usr/bin/env python3
"""RW1-05 T2 semantic consumer.

This module is deliberately outside ACT-0001. It consumes the versioned semantic
handoff, delegates only normalization to a specialist, validates the specialist's
shape/bounds, and hands the result to the authoritative DB resume validator.

T2 is shadow-only: it never authorizes an effect and never treats a specialist
result as route authority.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any, Callable, Protocol

REQUEST_SCHEMA = "LF_ROUTER_SEMANTIC_REQUEST_V1"
RESULT_SCHEMA = "LF_ROUTER_SEMANTIC_RESULT_V1"
SHADOW_SCHEMA = "LF_ROUTER_SEMANTIC_SHADOW_CONSUMER_V1"

REQUEST_REQUIRED = {
    "schema_version","router","literal_request","request_sha256","reference_kind",
    "candidate_subjects","positive_target_refs","excluded_target_refs","allowed_scope",
    "forbidden_scope","conditions","source_currentness",
}
RESULT_REQUIRED = {
    "schema_version","request_sha256","decision","positive_target_refs",
    "excluded_target_refs","allowed_scope","forbidden_scope","conditions",
    "material_ambiguities","clarification_question","semantic_receipt_sha256",
}
FORBIDDEN_AUTHORITY_FIELDS = {
    "operation_code","executor","effect_authority","downstream_execution_allowed",
    "route_authority","worker","worker_id","operation","target_authority",
}
DECISIONS = {"RESOLVED","CLARIFICATION_REQUIRED","BLOCKED"}


class SemanticConsumerBlocked(RuntimeError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


class SemanticSpecialist(Protocol):
    def normalize(self, request: dict[str, Any]) -> dict[str, Any]:
        """Return a semantic-result draft. It must not carry authority fields."""


ResumeValidator = Callable[[dict[str, Any], dict[str, Any]], dict[str, Any]]
RouterRederiver = Callable[[str], dict[str, Any]]


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def literal_sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _array(value: Any, code: str) -> list[Any]:
    if not isinstance(value, list):
        raise SemanticConsumerBlocked(code)
    return value


def _candidate_ref(item: Any) -> str | None:
    if not isinstance(item, dict):
        return None
    for key in (
        "asset_code","artifact_ref","path","screen_code","operation_code",
        "codigo_activo","code","name",
    ):
        value = item.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def _string_set(values: list[Any], code: str) -> set[str]:
    if any(not isinstance(v, str) or not v for v in values):
        raise SemanticConsumerBlocked(code)
    return set(values)


def validate_request(request: dict[str, Any]) -> None:
    if not isinstance(request, dict):
        raise SemanticConsumerBlocked("SEMANTIC_REQUEST_NOT_OBJECT")
    if not REQUEST_REQUIRED.issubset(request):
        raise SemanticConsumerBlocked("SEMANTIC_REQUEST_FIELDS_MISSING")
    if request.get("schema_version") != REQUEST_SCHEMA or request.get("router") != "ACT-0001":
        raise SemanticConsumerBlocked("SEMANTIC_REQUEST_IDENTITY_INVALID")
    if FORBIDDEN_AUTHORITY_FIELDS.intersection(request):
        raise SemanticConsumerBlocked("SEMANTIC_REQUEST_AUTHORITY_FIELD_FORBIDDEN")
    literal = request.get("literal_request")
    if not isinstance(literal, str):
        raise SemanticConsumerBlocked("SEMANTIC_REQUEST_LITERAL_INVALID")
    if request.get("request_sha256") != literal_sha256(literal):
        raise SemanticConsumerBlocked("SEMANTIC_REQUEST_HASH_MISMATCH")
    for key in (
        "candidate_subjects","positive_target_refs","excluded_target_refs",
        "allowed_scope","forbidden_scope","conditions",
    ):
        _array(request.get(key), f"SEMANTIC_REQUEST_{key.upper()}_INVALID")
    current = request.get("source_currentness")
    if not isinstance(current, dict) or current.get("status") != "CURRENT":
        raise SemanticConsumerBlocked("SEMANTIC_REQUEST_SOURCE_NOT_CURRENT")
    md5 = current.get("router_source_md5")
    if not isinstance(md5, str) or len(md5) != 32:
        raise SemanticConsumerBlocked("SEMANTIC_REQUEST_ROUTER_SOURCE_ID_INVALID")


def _contains_all(haystack: list[Any], needles: list[Any]) -> bool:
    return all(any(candidate == needle for candidate in haystack) for needle in needles)


def normalize_result(request: dict[str, Any], draft: dict[str, Any]) -> dict[str, Any]:
    validate_request(request)
    if not isinstance(draft, dict):
        raise SemanticConsumerBlocked("SEMANTIC_RESULT_NOT_OBJECT")
    forbidden = FORBIDDEN_AUTHORITY_FIELDS.intersection(draft)
    if forbidden:
        raise SemanticConsumerBlocked("SEMANTIC_RESULT_AUTHORITY_FIELD_FORBIDDEN", ",".join(sorted(forbidden)))

    decision = draft.get("decision")
    if decision not in DECISIONS:
        raise SemanticConsumerBlocked("SEMANTIC_RESULT_DECISION_INVALID")

    result = {
        "schema_version": RESULT_SCHEMA,
        "request_sha256": request["request_sha256"],
        "decision": decision,
        "positive_target_refs": list(draft.get("positive_target_refs", [])),
        "excluded_target_refs": list(draft.get("excluded_target_refs", request["excluded_target_refs"])),
        "allowed_scope": list(draft.get("allowed_scope", request["allowed_scope"])),
        "forbidden_scope": list(draft.get("forbidden_scope", request["forbidden_scope"])),
        "conditions": list(draft.get("conditions", request["conditions"])),
        "material_ambiguities": list(draft.get("material_ambiguities", [])),
        "clarification_question": draft.get("clarification_question"),
    }

    for key in (
        "positive_target_refs","excluded_target_refs","allowed_scope","forbidden_scope",
        "conditions","material_ambiguities",
    ):
        _array(result[key], f"SEMANTIC_RESULT_{key.upper()}_INVALID")

    candidates = {
        ref for ref in (_candidate_ref(item) for item in request["candidate_subjects"]) if ref is not None
    }
    positives = _string_set(result["positive_target_refs"], "SEMANTIC_RESULT_POSITIVE_TARGET_INVALID")
    exclusions = _string_set(result["excluded_target_refs"], "SEMANTIC_RESULT_EXCLUSION_INVALID")
    allowed = _string_set(result["allowed_scope"], "SEMANTIC_RESULT_ALLOWED_SCOPE_INVALID")
    request_allowed = _string_set(request["allowed_scope"], "SEMANTIC_REQUEST_ALLOWED_SCOPE_INVALID")
    forbidden_scope = _string_set(result["forbidden_scope"], "SEMANTIC_RESULT_FORBIDDEN_SCOPE_INVALID")
    request_forbidden = _string_set(request["forbidden_scope"], "SEMANTIC_REQUEST_FORBIDDEN_SCOPE_INVALID")
    request_exclusions = _string_set(request["excluded_target_refs"], "SEMANTIC_REQUEST_EXCLUSION_INVALID")

    if not positives.issubset(candidates):
        raise SemanticConsumerBlocked("SEMANTIC_RESULT_TARGET_OUTSIDE_ROUTER_CANDIDATES")
    if positives.intersection(exclusions):
        raise SemanticConsumerBlocked("SEMANTIC_RESULT_POSITIVE_EXCLUDED_CONFLICT")
    if not allowed.issubset(request_allowed):
        raise SemanticConsumerBlocked("SEMANTIC_RESULT_SCOPE_WIDENED")
    if not request_exclusions.issubset(exclusions):
        raise SemanticConsumerBlocked("SEMANTIC_RESULT_EXCLUSION_DROPPED")
    if not request_forbidden.issubset(forbidden_scope):
        raise SemanticConsumerBlocked("SEMANTIC_RESULT_FORBIDDEN_SCOPE_WEAKENED")
    if not _contains_all(result["conditions"], request["conditions"]):
        raise SemanticConsumerBlocked("SEMANTIC_RESULT_CONDITIONS_WEAKENED")

    question = result["clarification_question"]
    ambiguities = result["material_ambiguities"]
    if decision == "CLARIFICATION_REQUIRED":
        if not ambiguities:
            raise SemanticConsumerBlocked("SEMANTIC_CLARIFICATION_WITHOUT_MATERIAL_AMBIGUITY")
        if not isinstance(question, str) or not question.strip():
            raise SemanticConsumerBlocked("SEMANTIC_CLARIFICATION_QUESTION_MISSING")
        if "\n?" in question or question.count("?") > 1:
            raise SemanticConsumerBlocked("SEMANTIC_CLARIFICATION_MORE_THAN_ONE_QUESTION")
    else:
        if question not in (None, ""):
            raise SemanticConsumerBlocked("SEMANTIC_NONCLARIFY_QUESTION_FORBIDDEN")
    if decision == "RESOLVED" and ambiguities:
        raise SemanticConsumerBlocked("SEMANTIC_RESOLVED_WITH_AMBIGUITIES")

    receipt_body = dict(result)
    result["semantic_receipt_sha256"] = canonical_sha256(receipt_body)
    return result


def caller_interaction(result: dict[str, Any]) -> dict[str, Any]:
    if result.get("decision") != "CLARIFICATION_REQUIRED":
        return {
            "schema_version": "LF_ROUTER_CALLER_INTERACTION_V1",
            "action": "NO_QUESTION",
            "question_count": 0,
            "effect_authority": False,
            "downstream_execution_allowed": False,
        }
    question = result.get("clarification_question")
    if not isinstance(question, str) or not question.strip():
        raise SemanticConsumerBlocked("CALLER_INTERACTION_QUESTION_INVALID")
    return {
        "schema_version": "LF_ROUTER_CALLER_INTERACTION_V1",
        "action": "ASK_ONE_MATERIAL_QUESTION",
        "question_count": 1,
        "question": question.strip(),
        "effect_authority": False,
        "downstream_execution_allowed": False,
    }


def consume_shadow(
    request: dict[str, Any],
    *,
    specialist: SemanticSpecialist,
    resume_validator: ResumeValidator,
    router_rederive: RouterRederiver,
) -> dict[str, Any]:
    """Run T2 shadow. No result from this function authorizes an effect."""
    validate_request(request)
    draft = specialist.normalize(json.loads(json.dumps(request)))
    result = normalize_result(request, draft)
    interaction = caller_interaction(result)
    resume = resume_validator(request, result)
    if not isinstance(resume, dict):
        raise SemanticConsumerBlocked("SEMANTIC_RESUME_VALIDATOR_RESPONSE_INVALID")

    base = {
        "schema_version": SHADOW_SCHEMA,
        "phase": "T2_SEMANTIC_CONSUMER_SHADOW",
        "request_sha256": request["request_sha256"],
        "semantic_result": result,
        "resume_validation": resume,
        "caller_interaction": interaction,
        "route_authority": False,
        "effect_authority": False,
        "downstream_execution_allowed": False,
    }

    if resume.get("status") != "VALID":
        return {**base, "status": "BLOCKED", "next_action": "STAY_BLOCKED"}

    decision = result["decision"]
    if decision == "CLARIFICATION_REQUIRED":
        if resume.get("next_action") != "CALLER_INTERACTION_REQUIRED":
            raise SemanticConsumerBlocked("SEMANTIC_RESUME_CLARIFICATION_CONTRACT_MISMATCH")
        return {**base, "status": "WAITING_CLARIFICATION", "next_action": "CALLER_INTERACTION_REQUIRED"}

    if decision != "RESOLVED":
        return {**base, "status": "BLOCKED", "next_action": "STAY_BLOCKED"}

    if (
        resume.get("next_action") != "ACT0001_REDERIVE_ROUTE_AND_AUTHORITY"
        or resume.get("router_resume_allowed") is not True
        or resume.get("route_authority") is not False
        or resume.get("effect_authority") is not False
        or resume.get("downstream_execution_allowed") is not False
    ):
        raise SemanticConsumerBlocked("SEMANTIC_RESUME_AUTHORITY_CONTRACT_MISMATCH")

    # The specialist result is never the route. ACT-0001 must resolve the literal again.
    route = router_rederive(request["literal_request"])
    if not isinstance(route, dict):
        raise SemanticConsumerBlocked("ACT0001_REDERIVE_RESPONSE_INVALID")
    return {
        **base,
        "status": "SHADOW_REDERIVED",
        "next_action": "OBSERVE_ONLY_NO_EFFECT",
        "router_rederived": True,
        "router_result": route,
        "route_authority": False,
        "effect_authority": False,
        "downstream_execution_allowed": False,
    }
