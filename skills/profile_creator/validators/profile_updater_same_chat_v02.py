"""PE10 v0.2 — use current GPT/Claude conversation, not an API/new session.

Freeze selection into a source-bound handoff for the native chat to author.
The returned capture is NOT a provider-attested execution receipt and cannot
authorize production or method qualification.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

MODES = {"GPT_NATIVE": "CHATGPT_CURRENT_CONVERSATION",
         "CLAUDE_NATIVE": "CLAUDE_CURRENT_CONVERSATION"}
SCHEMA = "LF_PE10_V02_SAME_CHAT_NATIVE_HANDOFF_V1"
CAPTURE_SCHEMA = "LF_PE10_V02_SAME_CHAT_RAW_CAPTURE_V1"
_SHA64 = re.compile(r"^[0-9a-f]{64}$")


class ChatRouteBlocked(ValueError):
    pass


def _check(ok: bool, code: str) -> None:
    if not ok:
        raise ChatRouteBlocked(code)


def _sha_json(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, ensure_ascii=False,
        sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def _sha_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def freeze_same_chat_handoff(*, contract: dict[str, Any],
                             plan: dict[str, Any],
                             input_literal: str,
                             profile_sources: list[dict[str, str]],
                             current_surface: str) -> dict[str, Any]:
    """Freeze mode and methods in this conversation.

    The chat host, not model-generated input, must supply current_surface.
    This function cannot independently authenticate an external chat session.
    """
    _check(isinstance(contract, dict), "EXECUTION_CONTRACT_MISSING")
    mode = contract.get("executor_mode")
    _check(mode in MODES, "MODE_NOT_NATIVE")
    _check(current_surface == MODES[mode], "WRONG_CURRENT_CONVERSATION")
    _check(isinstance(contract.get("run_id"), str) and bool(contract["run_id"]),
           "RUN_ID_MISSING")
    expected_digest = _sha_json({k: v for k, v in contract.items()
                                 if k != "contract_sha256"})
    _check(contract.get("contract_sha256") == expected_digest,
           "FROZEN_CONTRACT_SHA_MISMATCH")
    _check(isinstance(input_literal, str) and bool(input_literal.strip()),
           "INPUT_LITERAL_MISSING")
    _check(isinstance(plan, dict) and plan.get("schema") == "PROFILE_EVOLUTION_PLAN_V1",
           "PROFILE_PLAN_INVALID")
    _check(plan.get("operation_code") == "ACTUALIZACION_PERFIL_LF",
           "UPDATER_OPERATION_MISMATCH")
    # The canonical LF_PROFILE_EXECUTION_CONTRACT_V1 binds profile_code,
    # while build_runtime_request binds profile_slug separately. Do not invent
    # a required profile_slug field in the execution contract.
    slug = plan.get("profile_slug")
    _check(isinstance(slug, str) and bool(slug),
           "PROFILE_BINDING_MISSING")
    _check(contract.get("profile_slug") in (None, slug),
           "PROFILE_BINDING_MISMATCH")
    _check(plan.get("profile_source_write_allowed") is False,
           "UNAUTHORIZED_PROFILE_WRITE")
    _check(isinstance(profile_sources, list) and bool(profile_sources),
           "PROFILE_SOURCE_MISSING")
    for source in profile_sources:
        _check(isinstance(source, dict)
               and isinstance(source.get("ref"), str) and source["ref"]
               and isinstance(source.get("content"), str)
               and _SHA64.fullmatch(source.get("content_sha256", "")) is not None,
               "SOURCE_BINDING_INVALID")
        _check(_sha_text(source["content"]) == source["content_sha256"],
               "SOURCE_CONTENT_DRIFT")
    # Anchor this planner's slug to an actual canonical profile source.
    _check(any(source["ref"] == "profiles/" + slug + "/SKILL.md"
               for source in profile_sources), "CANONICAL_PROFILE_SOURCE_MISSING")
    assessment = plan.get("profile_assessment")
    selection = plan.get("selection")
    _check(isinstance(assessment, dict) and isinstance(selection, dict),
           "SELECTION_UNAVAILABLE")
    _check(selection.get("execution_authorized") is False,
           "SELECTOR_FALSE_EXECUTION_PERMISSION")
    _check(plan.get("automatic_production_activation") is False,
           "AUTO_ACTIVATION_FORBIDDEN")
    blockers = plan.get("blocking_codes")
    _check(isinstance(blockers, list), "SELECTION_BLOCKERS_INVALID")
    deferred = set(blockers) <= {"METHOD_AND_ASSESSMENT_AUTHORITY_UNRESOLVED"}
    _check(deferred, "SELECTION_BLOCKED_BY_SAFETY_OR_EVIDENCE")
    _check(assessment.get("assessment_status") == "EVIDENCE_SUFFICIENT",
           "ASSESSMENT_NEEDS_EVIDENCE")
    items = selection.get("method_requirements")
    _check(isinstance(items, list), "METHOD_REQUIREMENTS_MISSING")
    selected = [m["method_id"] for m in items
                if isinstance(m, dict) and m.get("eligible_for_composition") is True]
    _check(all(isinstance(m, str) and bool(m) for m in selected)
           and len(selected) == len(set(selected)),
           "METHOD_SELECTION_INVALID")
    _check(all(m.get("within_budget") is True for m in items
               if isinstance(m, dict) and m.get("eligible_for_composition") is True),
           "SELECTED_METHOD_OVER_BUDGET")
    if plan.get("evolution_mode") == "NO_CHANGE":
        _check(not selected, "NO_CHANGE_CANNOT_EXECUTE_METHODS")
    source_manifest = [{"ref": x["ref"], "sha256": x["content_sha256"]}
                       for x in profile_sources]
    frozen = {"schema": SCHEMA, "run_id": contract["run_id"],
              "profile_slug": slug, "executor_mode": mode,
              "current_chat_surface": current_surface,
              "conversation_scope": "EXISTING_CONVERSATION_ONLY",
              "session_creation": False, "api_invocation": False,
              "contract_sha256": expected_digest,
              "input_sha256": _sha_text(input_literal),
              "source_manifest": source_manifest,
              "source_manifest_sha256": _sha_json(source_manifest),
              "profile_plan_sha256": _sha_json(plan),
              "evolution_mode": plan.get("evolution_mode"),
              "selected_method_ids": selected,
              "selection_scope": "CHAT_AUTHORING_NON_ATTESTED",
              "authority_pending": bool(blockers),
              "authority_blockers": blockers,
              "input_literal": input_literal,
              "cutover_eligible": False}
    frozen["handoff_sha256"] = _sha_json(frozen)
    return frozen


def capture_current_chat_raw(handoff: dict[str, Any],
                             raw_output: dict[str, Any], *,
                             current_surface: str) -> dict[str, Any]:
    """Capture author's same-chat RAW without claiming provider attestation."""
    _check(isinstance(handoff, dict) and handoff.get("schema") == SCHEMA,
           "HANDOFF_SCHEMA_INVALID")
    _check(_sha_json({k: v for k, v in handoff.items()
                      if k != "handoff_sha256"}) == handoff.get("handoff_sha256"),
           "HANDOFF_TAMPERED")
    _check(handoff.get("conversation_scope") == "EXISTING_CONVERSATION_ONLY"
           and handoff.get("session_creation") is False
           and handoff.get("api_invocation") is False,
           "NOT_NATIVE_SAME_CONVERSATION")
    _check(current_surface == handoff.get("current_chat_surface")
           and MODES.get(handoff.get("executor_mode")) == current_surface,
           "CROSS_PROVIDER_CHAT_CAPTURE_FORBIDDEN")
    _check(isinstance(raw_output, dict) and bool(raw_output),
           "RAW_CONTENT_EMPTY")
    _check(not any(key in raw_output for key in (
        "runtime_attestation", "provider_signature",
        "provider_verified", "independent_assurance_receipt",
        "cutover_admitted", "production_activated")),
        "RAW_CONTAINS_FORGED_AUTHORITY")
    _check(raw_output.get("run_id") == handoff["run_id"]
           and raw_output.get("evolution_mode") == handoff["evolution_mode"],
           "RAW_REQUEST_BINDING_MISMATCH")
    applied = raw_output.get("methods_applied")
    _check(isinstance(applied, list) and len(applied) == len(set(applied))
           and all(isinstance(x, str) for x in applied),
           "RAW_METHODS_INVALID")
    _check(applied == handoff["selected_method_ids"],
           "RAW_SELECTED_METHODS_MISMATCH")
    _check(isinstance(raw_output.get("deliverable"), dict)
           and bool(raw_output["deliverable"]), "RAW_DELIVERABLE_EMPTY")
    receipt = {"schema": CAPTURE_SCHEMA, "run_id": handoff["run_id"],
               "executor_mode": handoff["executor_mode"],
               "producer_transport": "CHAT_SESSION_AUTHORING",
               "conversation_scope": "EXISTING_CONVERSATION_ONLY",
               "handoff_sha256": handoff["handoff_sha256"],
               "raw_output": raw_output, "raw_output_sha256": _sha_json(raw_output),
               "capture_status": "SOURCE_BOUND_NATIVE_CHAT_RAW_UNATTESTED",
               "runtime_provider_attested": False,
               "independent_review_executed": False,
               "method_qualification_claimed": False,
               "method_execution_certified": False,
               "benchmark_admitted": False, "cutover_eligible": False,
               "production_activated": False}
    receipt["capture_sha256"] = _sha_json(receipt)
    return receipt
