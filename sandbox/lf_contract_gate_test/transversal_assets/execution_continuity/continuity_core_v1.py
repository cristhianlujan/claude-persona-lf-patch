#!/usr/bin/env python3
"""Pure cross-project continuity decisions. No Git, DB, network, or writes."""
from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
import re

class Mode(str, Enum):
    RECOVER = "RECOVER"
    RECONCILE = "RECONCILE"
    RESUME = "RESUME"

class Verdict(str, Enum):
    ADMIT = "ADMIT"
    SKIP = "SKIP"
    BLOCK = "BLOCK"

@dataclass(frozen=True)
class Decision:
    mode: Mode
    verdict: Verdict
    code: str
    next_action: str

def _require_authority(ctx: dict) -> str | None:
    for key in ("project", "operation_code", "router_execution_id", "source_ref",
                "exact_identity", "owner_approval_ref", "currentness_receipt",
                "contract_ref", "policy_ref", "transport_ref"):
        if not ctx.get(key):
            return f"MISSING_{key.upper()}"
    if ctx.get("scope") != "SANDBOX":
        return "PRODUCTION_NOT_AUTHORIZED"
    if ctx.get("execution_authorized") is not True:
        return "ROUTER_EXECUTION_NOT_AUTHORIZED"
    if ctx.get("dependencies_verified") is not True:
        return "DEPENDENCIES_UNVERIFIED"
    return None

def decide(mode: Mode | str, ctx: dict) -> Decision:
    mode = Mode(mode)
    missing = _require_authority(ctx)
    if missing:
        return Decision(mode, Verdict.BLOCK, missing, "RESOLVE_GOVERNED_AUTHORITY")
    if mode == Mode.RECOVER:
        for key in ("immutable_source_digest", "original_version", "target_absent",
                    "compatibility_rollback_pass", "conflict_scan_pass",
                    "replay_equivalent_absent"):
            if not ctx.get(key):
                return Decision(mode, Verdict.BLOCK, f"RECOVER_{key.upper()}_REQUIRED", "NO_APPLY")
        version = str(ctx["original_version"])
        if not re.fullmatch(r"20[0-9]{12}", version):
            return Decision(mode, Verdict.BLOCK, "RECOVER_VERSION_INVALID", "NO_APPLY")
        now = ctx.get("utc_now")
        if not isinstance(now, datetime) or now.tzinfo is None:
            return Decision(mode, Verdict.BLOCK, "RECOVER_CLOCK_REQUIRED", "NO_APPLY")
        try:
            dt = datetime.strptime(version, "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)
        except ValueError:
            return Decision(mode, Verdict.BLOCK, "RECOVER_VERSION_INVALID", "NO_APPLY")
        if dt > now.astimezone(timezone.utc) + timedelta(minutes=10):
            return Decision(mode, Verdict.BLOCK, "RECOVER_FUTURE_VERSION", "NO_APPLY")
        return Decision(mode, Verdict.ADMIT, "RECOVER_PREFLIGHT_ADMITTED", "DELEGATE_TO_AUTHORIZED_TRANSPORT")
    if mode == Mode.RECONCILE:
        if ctx.get("target_kind") != "GIT_ONLY" or ctx.get("db_write") is not False or ctx.get("ledger_write") is not False:
            return Decision(mode, Verdict.BLOCK, "RECONCILE_NON_GIT_EFFECT_FORBIDDEN", "NO_WRITE")
        if not all(ctx.get(key) for key in ("ledger_identity_readback", "byte_identity_verified", "rename_only_verified")):
            return Decision(mode, Verdict.BLOCK, "RECONCILE_IDENTITY_OR_BYTES_UNVERIFIED", "NO_WRITE")
        return Decision(mode, Verdict.ADMIT, "RECONCILE_GIT_ONLY_ADMITTED", "DELEGATE_TO_AUTHORIZED_GIT_ADAPTER")
    if ctx.get("checkpoint_verified") is not True or ctx.get("effect_guard_verified") is not True:
        return Decision(mode, Verdict.BLOCK, "RESUME_CHECKPOINT_OR_EFFECT_UNVERIFIED", "NO_REPLAY")
    state = ctx.get("effect_state")
    if state == "SUCCEEDED":
        return Decision(mode, Verdict.SKIP, "RESUME_EFFECT_ALREADY_SUCCEEDED", "CONTINUE_NEXT_STEP")
    if state == "RESERVED":
        return Decision(mode, Verdict.BLOCK, "RESUME_EFFECT_OUTCOME_UNRESOLVED", "RECONCILE_DURABLE_EFFECT_FIRST")
    if state == "ABSENT" and ctx.get("new_effect_reservation_authorized") is True:
        return Decision(mode, Verdict.ADMIT, "RESUME_EFFECT_NOT_DISPATCHED", "RESERVE_ONCE_THEN_DISPATCH")
    return Decision(mode, Verdict.BLOCK, "RESUME_EFFECT_NOT_AUTHORIZED", "NO_REPLAY")
