"""Fail-closed interpreter for existing PG bootstrap responses.

ChatGPT may read advice; it cannot mint validation receipts, mark checkpoints
DONE, or dispatch writes. No Supabase database mutation is performed here.
"""
from collections.abc import Mapping

PLAN = "PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1"
READ_ONLY = frozenset({
    "VALIDATE_CURRENT_CHECKPOINT",
    "REVALIDATE_CURRENT_CHECKPOINT",
    "RESOLVE_CURRENT_CHECKPOINT",
    "VALIDATION_FAILED_BLOCKED",
    "HUMAN_DECISION_REQUIRED",
    "STOP_RULE_NOT_ADMISSIBLE",
    "STOP_UNIT_NOT_FOUND",
    "UNIT_DONE",
    "UNIT_CLOSE_REQUIRED",
})
TRANSITION = "TRANSITION_CURRENT_CHECKPOINT"

class PGChatBlocked(ValueError):
    pass

def interpret_bootstrap(reply: Mapping, *, plan_code: str = PLAN) -> dict:
    if not isinstance(reply, Mapping):
        raise PGChatBlocked("BOOTSTRAP_NOT_OBJECT")
    if reply.get("schema_version") != "PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1":
        raise PGChatBlocked("BOOTSTRAP_SCHEMA_INVALID")
    action = reply.get("terminal_action")
    if action not in READ_ONLY | {TRANSITION}:
        raise PGChatBlocked("BOOTSTRAP_ACTION_UNKNOWN")
    if reply.get("plan_code", plan_code) != plan_code:
        raise PGChatBlocked("PLAN_MISMATCH")
    if action == TRANSITION:
        receipt = reply.get("validation_receipt")
        if (not isinstance(receipt, Mapping)
            or receipt.get("schema_version") != "PROGRAMMING_VALIDATION_RECEIPT_V1"
            or receipt.get("result") != "PASS"
            or receipt.get("plan_code") != plan_code
            or receipt.get("unit_code") != reply.get("unit_code")
            or receipt.get("checkpoint_code") != reply.get("checkpoint_code")
            or receipt.get("validation_code") != reply.get("validation_code")
            or type(receipt.get("run_id")) is not int):
            raise PGChatBlocked("TRANSITION_RECEIPT_NOT_VERIFIABLE")
        # Shape check is insufficient: only DB validates its stored receipt
        # against the active binding and run. Never authorize transition here.
    return {
        "schema_version": "PG_CHAT_BOOTSTRAP_ADVISORY_V1",
        "action": action,
        "unit_code": reply.get("unit_code"),
        "checkpoint_code": reply.get("checkpoint_code"),
        "requested_validation_code": reply.get("validation_code"),
        "write_authorized": False,
        "checkpoint_transition_authorized": False,
        "worker_dispatch_authorized": False,
        "required_next": (
            "DB_OWNED_CHECKPOINT_TRANSITION"
            if action == TRANSITION else
            "VALIDATOR_OR_HUMAN_RESOLUTION"
            if action in {"VALIDATE_CURRENT_CHECKPOINT","REVALIDATE_CURRENT_CHECKPOINT","RESOLVE_CURRENT_CHECKPOINT","HUMAN_DECISION_REQUIRED"}
            else "STOP_OR_INSPECT"
        ),
    }
