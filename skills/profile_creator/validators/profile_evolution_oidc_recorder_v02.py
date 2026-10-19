"""Bind v0.2 dynamic method decisions to the EXISTING GitHub Actions OIDC caller.

Uses profile_operation_record_batch_v1 from
supabase/functions/lf-profile-creator-governance-caller-v1/index.ts.
All authentication, current step ordering and writes remain with existing
OIDC caller / canonical run-creacion-perfil-lf Profile Updater operation.
"""
from __future__ import annotations

import uuid
from typing import Any, Callable

METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_UPDATE_V1"


def _receipt_ref(receipt_id: object) -> str:
    if not isinstance(receipt_id, str):
        raise ValueError("OIDC_EVIDENCE_RECEIPT_INVALID")
    try:
        uuid.UUID(receipt_id)
    except ValueError as exc:
        raise ValueError("OIDC_EVIDENCE_RECEIPT_INVALID") from exc
    return "supabase://private/lf_evidence_ledger_v1/" + receipt_id


def make_oidc_profile_evolution_recorder(
    post_authenticated_profile_caller: Callable[[dict[str, Any]], dict[str, Any]],
) -> Callable[[str, dict[str, Any], dict[str, Any]], dict[str, Any]]:
    """Host-owned callback must post with a real GitHub Actions OIDC token.

    NO embedded endpoint, token or service-role secret; no alternative
    execution protocol. This adapter cannot independently assert authorization.
    """
    if not callable(post_authenticated_profile_caller):
        raise ValueError("OIDC_CALLER_TRANSPORT_MISSING")

    def record(execution_id: str, method_step: dict[str, Any],
               decision_step: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(execution_id, str) or not execution_id.strip():
            raise ValueError("OIDC_EXECUTION_ID_MISSING")
        if not isinstance(method_step, dict) or not isinstance(decision_step, dict):
            raise ValueError("OIDC_STEP_PAYLOAD_INVALID")
        source_receipt = method_step.get("profile_assessment_receipt_id")
        if source_receipt != decision_step.get("profile_assessment_receipt_id"):
            raise ValueError("OIDC_ASSESSMENT_SOURCE_NOT_IDENTICAL")
        if method_step.get("source_head_sha") != decision_step.get("source_head_sha"):
            raise ValueError("OIDC_SOURCE_HEAD_MISMATCH")
        if method_step.get("method_execution_permitted") is not False:
            raise ValueError("OIDC_SELECTION_UNAUTHORIZED_PERMISSION")
        if decision_step.get("github_write_permitted") is not False:
            raise ValueError("OIDC_DECISION_UNAUTHORIZED_WRITE")
        evidence_ref = _receipt_ref(source_receipt)
        packet = {"action": "profile_operation_record_batch_v1",
                  "execution_id": execution_id,
                  "steps": [
                      {"step_id": "method_selection",
                       "evidence_ref": evidence_ref + "#method_selection",
                       "evidence_payload": method_step},
                      {"step_id": "evolution_decision",
                       "evidence_ref": evidence_ref + "#evolution_decision",
                       "evidence_payload": decision_step},
                  ]}
        answer = post_authenticated_profile_caller(packet)
        if (not isinstance(answer, dict)
                or answer.get("outcome") != "BATCH_RECORDED"
                or answer.get("execution_id") != execution_id
                or answer.get("recorded_count") != 2
                or answer.get("requested_count") != 2
                or answer.get("blocked_step_id") is not None
                or (answer.get("caller") or {}).get("method") != METHOD):
            raise ValueError("OIDC_PROFILE_STEP_BATCH_NOT_RECORDED")
        receipts = answer.get("receipts")
        if not isinstance(receipts, list) or len(receipts) != 2:
            raise ValueError("OIDC_PROFILE_STEP_RECEIPTS_INCOMPLETE")
        for i, step_id in enumerate(("method_selection", "evolution_decision")):
            row = receipts[i]
            if (not isinstance(row, dict)
                    or row.get("step_id") != step_id
                    or row.get("outcome") != "STEP_RECORDED"
                    or row.get("operation_code") != "ACTUALIZACION_PERFIL_LF"
                    or not isinstance(row.get("result"), dict)
                    or (row["result"].get("result") or {}).get("status")
                    not in ("STEP_PASS_WITH_EVIDENCE", "STEP_CLEAN_PASS")):
                raise ValueError("OIDC_STEP_NOT_CLEAN:" + step_id)
        return {"execution_id": execution_id,
                "method_selection": "STEP_PASS_WITH_EVIDENCE",
                "evolution_decision": "STEP_PASS_WITH_EVIDENCE",
                "oidc_caller": METHOD}

    return record
