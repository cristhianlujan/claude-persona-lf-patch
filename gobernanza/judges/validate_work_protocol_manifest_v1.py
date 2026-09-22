#!/usr/bin/env python3
"""Deterministic validator for LF_WORK_PROTOCOL_MANIFEST_V1.

Stdlib-only by design. It validates the frozen manifest and reconciles an execution
observation packet without trusting producer-reported progress.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

VERSION = "LF_WORK_PROTOCOL_MANIFEST_V1"
HEX64 = set("0123456789abcdef")
INDEPENDENT_MODES = {"INDEPENDENT_READBACK", "SEMANTIC_JUDGE", "COMPOSITE"}
CLEAN_STATUSES = {"PASS", "PASS_CLEAN", "STEP_PASS_WITH_EVIDENCE"}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest_without_self(manifest: dict[str, Any]) -> str:
    body = copy.deepcopy(manifest)
    body.pop("manifest_digest", None)
    return hashlib.sha256(canonical_bytes(body)).hexdigest()


def _nonempty(v: Any) -> bool:
    return isinstance(v, str) and bool(v.strip())


def _hex64(v: Any) -> bool:
    return isinstance(v, str) and len(v) == 64 and all(ch in HEX64 for ch in v)


def _parse_ts(v: Any) -> datetime | None:
    if not _nonempty(v):
        return None
    try:
        dt = datetime.fromisoformat(v.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        return None
    return dt.astimezone(timezone.utc)


def _sha256_text(v: str) -> str:
    return hashlib.sha256(v.encode("utf-8")).hexdigest()


def _evaluate_exact_evidence(
    *,
    manifest: dict[str, Any],
    obligation: dict[str, Any],
    evidence: Any,
    execution_started_at: Any,
    ledger_rows: Any,
) -> tuple[str, str]:
    if not isinstance(evidence, dict):
        return "BLOCKED", "EVIDENCE_OBJECT_MISSING"
    envelope = evidence.get("work_protocol_evidence")
    if not isinstance(envelope, dict):
        return "BLOCKED", "EXACT_EVIDENCE_ENVELOPE_MISSING"

    required_identity = {
        "schema_version": "LF_WORK_PROTOCOL_EVIDENCE_V1",
        "execution_id": manifest["execution_id"],
        "step_id": obligation["step_id"],
        "gate_contract_sha256": obligation["gate_contract_sha256"],
    }
    for key, expected in required_identity.items():
        if envelope.get(key) != expected:
            return "BLOCKED", f"EVIDENCE_IDENTITY_MISMATCH:{key}"

    actor_execution_id = envelope.get("actor_execution_id")
    if not _nonempty(actor_execution_id):
        return "BLOCKED", "EVIDENCE_ACTOR_INVALID"

    reproduction = envelope.get("reproduction")
    if not isinstance(reproduction, dict):
        return "BLOCKED", "EVIDENCE_REPRODUCTION_MISSING"
    if reproduction.get("kind") not in {"SQL", "COMMAND", "API", "READBACK"}:
        return "BLOCKED", "EVIDENCE_REPRODUCTION_KIND_INVALID"
    for key in ("locator", "reproduction_spec", "result_ref"):
        if not _nonempty(reproduction.get(key)):
            return "BLOCKED", f"EVIDENCE_REPRODUCTION_FIELD_INVALID:{key}"
    for key in ("reproduction_spec_sha256", "input_sha256", "result_sha256", "source_revision_sha256"):
        if not _hex64(reproduction.get(key)):
            return "BLOCKED", f"EVIDENCE_REPRODUCTION_HASH_INVALID:{key}"
    if reproduction["reproduction_spec_sha256"] != _sha256_text(reproduction["reproduction_spec"]):
        return "BLOCKED", "EVIDENCE_REPRODUCTION_SPEC_DIGEST_MISMATCH"
    result_count = reproduction.get("result_count")
    if not isinstance(result_count, int) or isinstance(result_count, bool) or result_count < 0:
        return "BLOCKED", "EVIDENCE_RESULT_COUNT_INVALID"

    observed_at = _parse_ts(envelope.get("observed_at"))
    started_at = _parse_ts(execution_started_at)
    if observed_at is None or started_at is None:
        return "BLOCKED", "EVIDENCE_TIMESTAMP_INVALID"
    policy = manifest["evidence_policy"]
    now_utc = datetime.now(timezone.utc)
    if observed_at < started_at:
        return "BLOCKED", "EVIDENCE_PRE_EXECUTION"
    if observed_at.timestamp() > now_utc.timestamp() + policy["future_clock_skew_seconds"]:
        return "BLOCKED", "EVIDENCE_FUTURE_TIMESTAMP"
    if now_utc.timestamp() - observed_at.timestamp() > policy["max_age_seconds"]:
        return "STALE", "EVIDENCE_STALE"

    independent_required = (
        obligation.get("verifier_mode") in INDEPENDENT_MODES
        or obligation.get("gate_type") == "CLOSURE"
    )
    if not independent_required:
        return "PASS", "EVIDENCE_EXACT_PASS"

    receipt_id = envelope.get("ledger_receipt_id")
    receipt_sha256 = envelope.get("ledger_receipt_sha256")
    if not _nonempty(receipt_id) or not _hex64(receipt_sha256):
        return "BLOCKED", "INDEPENDENT_LEDGER_RECEIPT_MISSING"
    if not isinstance(ledger_rows, list):
        return "BLOCKED", "EVIDENCE_LEDGER_READBACK_MISSING"
    row = next((x for x in ledger_rows if isinstance(x, dict) and x.get("receipt_id") == receipt_id), None)
    if row is None:
        return "BLOCKED", "EVIDENCE_LEDGER_RECEIPT_NOT_FOUND"
    if row.get("receipt_sha256") != receipt_sha256:
        return "BLOCKED", "EVIDENCE_LEDGER_RECEIPT_DIGEST_MISMATCH"
    if row.get("execution_id") != manifest["execution_id"]:
        return "BLOCKED", "EVIDENCE_LEDGER_EXECUTION_MISMATCH"
    if row.get("gate_code") != f"WORK_PROTOCOL_GATE:{obligation['step_id']}":
        return "BLOCKED", "EVIDENCE_LEDGER_GATE_MISMATCH"
    if row.get("receipt_kind") != policy["ledger_receipt_kind"]:
        return "BLOCKED", "EVIDENCE_LEDGER_RECEIPT_KIND_MISMATCH"
    if row.get("verification_state") != "VERIFIED":
        return "BLOCKED", "EVIDENCE_LEDGER_NOT_VERIFIED"
    if row.get("subject_ref") != reproduction["result_ref"] or row.get("subject_sha256") != reproduction["result_sha256"]:
        return "BLOCKED", "EVIDENCE_LEDGER_SUBJECT_MISMATCH"
    if row.get("authority_ref") != obligation.get("authority_ref"):
        return "BLOCKED", "EVIDENCE_LEDGER_AUTHORITY_MISMATCH"
    if row.get("created_by_execution_id") != actor_execution_id or actor_execution_id == manifest["execution_id"]:
        return "BLOCKED", "EVIDENCE_INDEPENDENT_ACTOR_MISMATCH"

    verified_at = _parse_ts(row.get("verified_at"))
    if verified_at is None:
        return "BLOCKED", "EVIDENCE_LEDGER_VERIFIED_AT_INVALID"
    if verified_at.timestamp() + policy["future_clock_skew_seconds"] < observed_at.timestamp():
        return "BLOCKED", "EVIDENCE_LEDGER_VERIFIED_BEFORE_OBSERVATION"
    if now_utc.timestamp() - verified_at.timestamp() > policy["max_age_seconds"]:
        return "STALE", "EVIDENCE_LEDGER_STALE"

    vp = row.get("verification_payload")
    if not isinstance(vp, dict) or vp.get("provider_readback_verified") is not True or vp.get("digest_recomputed") is not True:
        return "BLOCKED", "EVIDENCE_LEDGER_VERIFICATION_PROOF_INCOMPLETE"

    rp = row.get("receipt_payload")
    expected_payload = {
        "work_protocol_execution_id": manifest["execution_id"],
        "work_protocol_step_id": obligation["step_id"],
        "work_protocol_gate_contract_sha256": obligation["gate_contract_sha256"],
        "evidence_result_sha256": reproduction["result_sha256"],
        "reproduction_spec_sha256": reproduction["reproduction_spec_sha256"],
        "source_revision_sha256": reproduction["source_revision_sha256"],
    }
    if not isinstance(rp, dict) or any(rp.get(k) != v for k, v in expected_payload.items()):
        return "BLOCKED", "EVIDENCE_LEDGER_WORK_PROTOCOL_BINDING_MISMATCH"

    if evidence.get("verification_actor_execution_id") != actor_execution_id:
        return "BLOCKED", "EVIDENCE_VERIFIER_ACTOR_BINDING_MISMATCH"
    if evidence.get("verification_target_execution_id") != manifest["execution_id"]:
        return "BLOCKED", "EVIDENCE_VERIFIER_TARGET_BINDING_MISMATCH"

    return "PASS", "EVIDENCE_INDEPENDENT_LEDGER_PASS"


def validate_manifest(m: Any) -> list[str]:
    e: list[str] = []
    if not isinstance(m, dict):
        return ["MANIFEST_NOT_OBJECT"]
    required = {
        "manifest_version", "manifest_id", "execution_id", "operation_code", "work_owner", "request_sha256", "target", "frozen_at",
        "authority_snapshot", "authorized_scope", "execution_policy", "evidence_policy", "solution_isolation_policy", "control_policy",
        "controller_policy", "closure_controller_policy", "waivers", "irreversible_approvals", "supersession", "obligations", "closure_policy", "manifest_digest",
    }
    missing = sorted(required - set(m))
    e += [f"MANIFEST_FIELD_MISSING:{x}" for x in missing]
    if missing:
        return e
    if m.get("manifest_version") != VERSION:
        e.append("MANIFEST_VERSION_INVALID")
    for k in ("manifest_id", "execution_id", "operation_code", "frozen_at"):
        if not _nonempty(m.get(k)):
            e.append(f"MANIFEST_FIELD_INVALID:{k}")
    if not _hex64(m.get("request_sha256")):
        e.append("REQUEST_SHA256_INVALID")
    target = m.get("target")
    if not isinstance(target, dict) or not _nonempty(target.get("type")) or not _nonempty(target.get("code")):
        e.append("TARGET_INVALID")
    owner = m.get("work_owner")
    if not isinstance(owner, dict):
        e.append("OWNER_BINDING_INVALID")
    else:
        if not _nonempty(owner.get("owner_id")):
            e.append("OWNER_ID_INVALID")
        if owner.get("owner_type") not in {"HUMAN", "AGENT", "TEAM"}:
            e.append("OWNER_TYPE_INVALID")
        if not _nonempty(owner.get("declaration_ref")):
            e.append("OWNER_DECLARATION_REF_INVALID")
        if not _hex64(owner.get("declaration_sha256")):
            e.append("OWNER_DECLARATION_SHA256_INVALID")
        elif owner.get("declaration_sha256") != m.get("request_sha256"):
            e.append("OWNER_REQUEST_BINDING_MISMATCH")
        if owner.get("change_mode") != "SUPERSEDE_NEW_EXECUTION":
            e.append("OWNER_CHANGE_MODE_INVALID")
    a = m.get("authority_snapshot")
    if not isinstance(a, dict):
        e.append("AUTHORITY_SNAPSHOT_INVALID")
    else:
        if not _hex64(a.get("operation_revision_sha256")):
            e.append("OPERATION_REVISION_INVALID")
        if not _nonempty(a.get("contract_code")):
            e.append("CONTRACT_BINDING_INVALID")
        if a.get("contract_sha") is not None and not _nonempty(a.get("contract_sha")):
            e.append("CONTRACT_SOURCE_SHA_INVALID")
        if not _hex64(a.get("contract_revision_sha256")):
            e.append("CONTRACT_REVISION_INVALID")
        if not _hex64(a.get("obligation_set_sha256")):
            e.append("OBLIGATION_SET_SHA_INVALID")
        if not _hex64(a.get("policy_set_sha256")):
            e.append("POLICY_SET_SHA_INVALID")
        refs = a.get("source_refs")
        if not isinstance(refs, list) or not refs or any(not _nonempty(x) for x in refs) or len(refs) != len(set(refs)):
            e.append("SOURCE_REFS_INVALID")
    scope = m.get("authorized_scope")
    if not isinstance(scope, dict) or not all(isinstance(scope.get(k), list) for k in ("read", "write", "effects")):
        e.append("AUTHORIZED_SCOPE_INVALID")
    elif not _nonempty(scope.get("authorization_ref")) or not _hex64(scope.get("authorization_sha256")):
        e.append("AUTHORIZED_SCOPE_PROVENANCE_INVALID")
    elif scope.get("authorization_sha256") != m.get("request_sha256"):
        e.append("AUTHORIZED_SCOPE_REQUEST_BINDING_MISMATCH")
    ep = m.get("execution_policy")
    if not isinstance(ep, dict):
        e.append("EXECUTION_POLICY_INVALID")
    else:
        expected_ep = {
            "timeout_recovery_required": True,
            "preserve_verified_progress": True,
            "exhausted_timeout_result": "BLOCKED_OPERATIONAL_TIMEOUT",
        }
        for k, v in expected_ep.items():
            if ep.get(k) != v:
                e.append(f"EXECUTION_POLICY_INVALID:{k}")
        max_recovery_attempts = ep.get("max_recovery_attempts")
        if not isinstance(max_recovery_attempts, int) or isinstance(max_recovery_attempts, bool) or not (1 <= max_recovery_attempts <= 10):
            e.append("EXECUTION_POLICY_INVALID:max_recovery_attempts")

    evidence_policy = m.get("evidence_policy")
    if not isinstance(evidence_policy, dict):
        e.append("EVIDENCE_POLICY_INVALID")
    else:
        expected_evidence_policy = {
            "exact_envelope_required": True,
            "reproduction_spec_required": True,
            "append_only_ledger_required_for_independent": True,
            "independent_actor_distinct_required": True,
            "ledger_receipt_kind": "WORK_PROTOCOL_GATE_EVIDENCE",
        }
        for k, v in expected_evidence_policy.items():
            if evidence_policy.get(k) != v:
                e.append(f"EVIDENCE_POLICY_INVALID:{k}")
        max_age_seconds = evidence_policy.get("max_age_seconds")
        if not isinstance(max_age_seconds, int) or isinstance(max_age_seconds, bool) or not (60 <= max_age_seconds <= 86400):
            e.append("EVIDENCE_POLICY_INVALID:max_age_seconds")
        future_clock_skew_seconds = evidence_policy.get("future_clock_skew_seconds")
        if not isinstance(future_clock_skew_seconds, int) or isinstance(future_clock_skew_seconds, bool) or not (0 <= future_clock_skew_seconds <= 300):
            e.append("EVIDENCE_POLICY_INVALID:future_clock_skew_seconds")

    solution_isolation_policy = m.get("solution_isolation_policy")
    if not isinstance(solution_isolation_policy, dict):
        e.append("SOLUTION_ISOLATION_POLICY_INVALID")
    else:
        expected_solution_isolation = {
            "unit_mode": "ONE_SOLUTION_PER_PR",
            "mixed_solution_pr_allowed": False,
            "scope_expansion_requires_new_pr": True,
            "migration_apply_requires_separate_pr": True,
            "receipt_must_bind_exact_pr_scope": True,
        }
        for k, v in expected_solution_isolation.items():
            if solution_isolation_policy.get(k) != v:
                e.append(f"SOLUTION_ISOLATION_POLICY_INVALID:{k}")

    control_policy = m.get("control_policy")
    if not isinstance(control_policy, dict):
        e.append("CONTROL_POLICY_INVALID")
        waiver_ttl = None
    else:
        expected_control = {
            "scope_change_mode": "SUPERSEDE_NEW_EXECUTION_FULL_REVALIDATION",
            "authorization_rebind_required": True,
            "carry_forward_verified_progress": False,
            "required_obligation_waivers_allowed": False,
            "irreversible_human_approval_required": True,
        }
        for k, v in expected_control.items():
            if control_policy.get(k) != v:
                e.append(f"CONTROL_POLICY_INVALID:{k}")
        waiver_ttl = control_policy.get("waiver_max_ttl_seconds")
        if not isinstance(waiver_ttl, int) or isinstance(waiver_ttl, bool) or not (60 <= waiver_ttl <= 3600):
            e.append("CONTROL_POLICY_INVALID:waiver_max_ttl_seconds")

    controller_policy = m.get("controller_policy")
    if not isinstance(controller_policy, dict):
        e.append("CONTROLLER_POLICY_INVALID")
    else:
        expected_controller = {
            "dependency_mode": "CANONICAL_DAG",
            "material_wip_limit": 1,
            "parallelism_policy": "READ_ONLY_SAME_CLOSURE_UNIT_ONLY",
            "lease_required_for_activation": True,
            "fenced_checkpoint_required": True,
            "failed_predecessor_blocks_dependents": True,
            "resume_from_canonical_state": True,
        }
        for k, v in expected_controller.items():
            if controller_policy.get(k) != v:
                e.append(f"CONTROLLER_POLICY_INVALID:{k}")

    closure_controller_policy = m.get("closure_controller_policy")
    if not isinstance(closure_controller_policy, dict):
        e.append("CLOSURE_CONTROLLER_POLICY_INVALID")
    else:
        expected_closure_controller = {
            "unit_progression_mode": "CLOSE_OR_BLOCK_WITH_EVIDENCE_BEFORE_NEXT",
            "blocked_continue_mode": "DEPENDENCY_SAFE_ONLY",
            "closure_receipt_kind": "WORK_PROTOCOL_CLOSURE_UNIT",
            "blocked_receipt_kind": "WORK_PROTOCOL_BLOCKED_UNIT",
            "receipt_chain_required": True,
            "reopen_on_unit_digest_change": True,
            "global_close_requires_zero_debt": True,
        }
        for k, v in expected_closure_controller.items():
            if closure_controller_policy.get(k) != v:
                e.append(f"CLOSURE_CONTROLLER_POLICY_INVALID:{k}")

    obs = m.get("obligations")
    if not isinstance(obs, list) or not obs:
        e.append("OBLIGATIONS_INVALID")
    else:
        req_ids: set[str] = set()
        step_ids: set[str] = set()
        for i, o in enumerate(obs):
            if not isinstance(o, dict):
                e.append(f"OBLIGATION_INVALID:{i}")
                continue
            rid, sid = o.get("requirement_id"), o.get("step_id")
            if not _nonempty(rid) or rid in req_ids:
                e.append(f"REQUIREMENT_ID_INVALID_OR_DUPLICATE:{i}")
            else:
                req_ids.add(rid)
            if not _nonempty(sid) or sid in step_ids:
                e.append(f"STEP_ID_INVALID_OR_DUPLICATE:{i}")
            else:
                step_ids.add(sid)
            if not isinstance(o.get("required"), bool) or not isinstance(o.get("blocking"), bool) or not isinstance(o.get("close_required"), bool):
                e.append(f"OBLIGATION_FLAGS_INVALID:{rid or i}")
            keys = o.get("evidence_keys")
            if not isinstance(keys, list) or any(not _nonempty(x) for x in keys) or len(keys) != len(set(keys)):
                e.append(f"EVIDENCE_KEYS_INVALID:{rid or i}")
            if o.get("verifier_mode") not in {"DETERMINISTIC", "INDEPENDENT_READBACK", "SEMANTIC_JUDGE", "COMPOSITE"}:
                e.append(f"VERIFIER_MODE_INVALID:{rid or i}")
            if o.get("gate_type") not in {"ENTRY", "STEP", "EXIT", "CLOSURE"}:
                e.append(f"GATE_TYPE_INVALID:{rid or i}")
            if not _hex64(o.get("gate_contract_sha256")):
                e.append(f"GATE_CONTRACT_SHA256_INVALID:{rid or i}")
            execution_class = o.get("execution_class")
            recovery_mode = o.get("timeout_recovery_mode")
            if execution_class not in {"ATOMIC", "CHUNKABLE", "CHECKPOINTABLE"}:
                e.append(f"EXECUTION_CLASS_INVALID:{rid or i}")
            if recovery_mode not in {"RETRY_ATOMIC", "REDUCE_UNIT", "RESUME_CHECKPOINT"}:
                e.append(f"TIMEOUT_RECOVERY_MODE_INVALID:{rid or i}")
            if not isinstance(o.get("checkpoint_required"), bool) or not isinstance(o.get("idempotent"), bool):
                e.append(f"EXECUTION_RECOVERY_FLAGS_INVALID:{rid or i}")
            if not all(isinstance(o.get(k), bool) for k in ("waiver_allowed", "irreversible_effect", "human_approval_required")):
                e.append(f"CONTROL_FLAGS_INVALID:{rid or i}")
            deps = o.get("depends_on_step_ids")
            if not isinstance(deps, list) or any(not _nonempty(x) for x in deps) or len(deps) != len(set(deps)):
                e.append(f"CONTROLLER_DEPENDENCIES_INVALID:{rid or i}")
            if not _nonempty(o.get("closure_unit_id")):
                e.append(f"CONTROLLER_CLOSURE_UNIT_INVALID:{rid or i}")
            controller_order = o.get("controller_order")
            if not isinstance(controller_order, int) or isinstance(controller_order, bool) or controller_order < 0:
                e.append(f"CONTROLLER_ORDER_INVALID:{rid or i}")
            if o.get("execution_effect") not in {"READ_ONLY", "MUTATING", "JUDGE", "CLOSURE"}:
                e.append(f"CONTROLLER_EFFECT_INVALID:{rid or i}")
            if not isinstance(o.get("parallel_safe"), bool):
                e.append(f"CONTROLLER_PARALLEL_FLAG_INVALID:{rid or i}")
            elif o.get("parallel_safe") is True and o.get("execution_effect") != "READ_ONLY":
                e.append(f"CONTROLLER_PARALLEL_NON_READ_ONLY_FORBIDDEN:{rid or i}")
            if o.get("irreversible_effect") is True and o.get("human_approval_required") is not True:
                e.append(f"IRREVERSIBLE_REQUIRES_HUMAN_APPROVAL:{rid or i}")
            if execution_class == "ATOMIC" and recovery_mode != "RETRY_ATOMIC":
                e.append(f"EXECUTION_RECOVERY_CLASS_MISMATCH:{rid or i}")
            if execution_class == "CHUNKABLE" and (recovery_mode != "REDUCE_UNIT" or o.get("idempotent") is not True):
                e.append(f"EXECUTION_RECOVERY_CLASS_MISMATCH:{rid or i}")
            if execution_class == "CHECKPOINTABLE" and (recovery_mode != "RESUME_CHECKPOINT" or o.get("checkpoint_required") is not True):
                e.append(f"EXECUTION_RECOVERY_CLASS_MISMATCH:{rid or i}")
    if isinstance(obs, list):
        by_step = {o.get("step_id"): o for o in obs if isinstance(o, dict) and _nonempty(o.get("step_id"))}
        for sid, o in by_step.items():
            for dep in o.get("depends_on_step_ids") or []:
                if dep == sid:
                    e.append(f"CONTROLLER_SELF_DEPENDENCY:{sid}")
                elif dep not in by_step:
                    e.append(f"CONTROLLER_UNKNOWN_DEPENDENCY:{sid}:{dep}")
        visiting: set[str] = set()
        visited: set[str] = set()
        def visit(node: str) -> bool:
            if node in visiting:
                return False
            if node in visited:
                return True
            visiting.add(node)
            for dep in by_step.get(node, {}).get("depends_on_step_ids") or []:
                if dep in by_step and not visit(dep):
                    return False
            visiting.remove(node)
            visited.add(node)
            return True
        if any(not visit(sid) for sid in by_step):
            e.append("CONTROLLER_DAG_CYCLE")
        required_orders = [o.get("controller_order") for o in obs if isinstance(o, dict)]
        if any(required_orders.count(v) > 1 for v in required_orders):
            e.append("CONTROLLER_ORDER_DUPLICATE")

    frozen_at = _parse_ts(m.get("frozen_at"))
    if frozen_at is None:
        e.append("FROZEN_AT_INVALID")

    supersession = m.get("supersession")
    if supersession is not None:
        if not isinstance(supersession, dict):
            e.append("SUPERSESSION_INVALID")
        else:
            required_sup = (
                "previous_execution_id", "previous_manifest_digest", "change_authorization_ref",
                "change_authorization_sha256", "change_reason", "previous_scope_sha256",
                "new_scope_sha256", "revalidation_mode"
            )
            if any(k not in supersession for k in required_sup):
                e.append("SUPERSESSION_FIELDS_MISSING")
            if supersession.get("previous_execution_id") == m.get("execution_id"):
                e.append("SUPERSESSION_SELF_REFERENCE")
            if not _hex64(supersession.get("previous_manifest_digest")):
                e.append("SUPERSESSION_PREVIOUS_DIGEST_INVALID")
            if not _nonempty(supersession.get("change_authorization_ref")) or not _hex64(supersession.get("change_authorization_sha256")):
                e.append("SUPERSESSION_AUTHORIZATION_INVALID")
            elif supersession.get("change_authorization_sha256") != m.get("request_sha256"):
                e.append("SUPERSESSION_AUTHORIZATION_REQUEST_MISMATCH")
            if not isinstance(supersession.get("change_reason"), str) or len(supersession.get("change_reason", "").strip()) < 20:
                e.append("SUPERSESSION_REASON_INVALID")
            if supersession.get("revalidation_mode") != "FULL_REQUIRED":
                e.append("SUPERSESSION_REVALIDATION_INVALID")
            if not _hex64(supersession.get("previous_scope_sha256")) or not _hex64(supersession.get("new_scope_sha256")):
                e.append("SUPERSESSION_SCOPE_DIGEST_INVALID")
            elif isinstance(scope, dict):
                current_scope_sha = hashlib.sha256(canonical_bytes(scope)).hexdigest()
                if supersession.get("new_scope_sha256") != current_scope_sha:
                    e.append("SUPERSESSION_NEW_SCOPE_DIGEST_MISMATCH")
                if supersession.get("previous_scope_sha256") == current_scope_sha:
                    e.append("SUPERSESSION_SCOPE_NOT_CHANGED")

    waiver_rows = m.get("waivers")
    if not isinstance(waiver_rows, list):
        e.append("WAIVERS_INVALID")
    else:
        seen_waiver_requirements: set[str] = set()
        obligations_by_rid = {o.get("requirement_id"): o for o in obs or [] if isinstance(o, dict)}
        for i, w in enumerate(waiver_rows):
            if not isinstance(w, dict):
                e.append(f"WAIVER_INVALID:{i}")
                continue
            rid = w.get("requirement_id")
            if not _nonempty(rid) or rid in seen_waiver_requirements:
                e.append(f"WAIVER_REQUIREMENT_INVALID_OR_DUPLICATE:{i}")
                continue
            seen_waiver_requirements.add(rid)
            o = obligations_by_rid.get(rid)
            if o is None:
                e.append(f"WAIVER_UNKNOWN_REQUIREMENT:{rid}")
                continue
            if o.get("required") is True:
                e.append(f"WAIVER_REQUIRED_OBLIGATION_FORBIDDEN:{rid}")
            if o.get("waiver_allowed") is not True:
                e.append(f"WAIVER_NOT_CANONICALLY_ALLOWED:{rid}")
            if not isinstance(w.get("reason"), str) or len(w.get("reason", "").strip()) < 20:
                e.append(f"WAIVER_REASON_INVALID:{rid}")
            if not isinstance(w.get("residual_risk"), str) or len(w.get("residual_risk", "").strip()) < 10:
                e.append(f"WAIVER_RESIDUAL_RISK_INVALID:{rid}")
            if not _nonempty(w.get("authorized_by")) or not _nonempty(w.get("authorization_ref")) or not _hex64(w.get("authorization_sha256")):
                e.append(f"WAIVER_AUTHORIZATION_INVALID:{rid}")
            exp = _parse_ts(w.get("expires_at"))
            if exp is None or frozen_at is None or exp <= frozen_at:
                e.append(f"WAIVER_EXPIRY_INVALID:{rid}")
            elif isinstance(waiver_ttl, int) and (exp - frozen_at).total_seconds() > waiver_ttl:
                e.append(f"WAIVER_TTL_EXCEEDED:{rid}")

    approval_rows = m.get("irreversible_approvals")
    if not isinstance(approval_rows, list):
        e.append("IRREVERSIBLE_APPROVALS_INVALID")
    else:
        obligations_by_step = {o.get("step_id"): o for o in obs or [] if isinstance(o, dict)}
        seen_approval_steps: set[str] = set()
        for i, arow in enumerate(approval_rows):
            if not isinstance(arow, dict):
                e.append(f"IRREVERSIBLE_APPROVAL_INVALID:{i}")
                continue
            sid = arow.get("step_id")
            if not _nonempty(sid) or sid in seen_approval_steps:
                e.append(f"IRREVERSIBLE_APPROVAL_STEP_INVALID_OR_DUPLICATE:{i}")
                continue
            seen_approval_steps.add(sid)
            o = obligations_by_step.get(sid)
            if o is None or o.get("irreversible_effect") is not True or o.get("human_approval_required") is not True:
                e.append(f"IRREVERSIBLE_APPROVAL_NOT_AUTHORIZED_FOR_STEP:{sid}")
            if not _hex64(arow.get("action_sha256")) or not _hex64(arow.get("approval_sha256")):
                e.append(f"IRREVERSIBLE_APPROVAL_DIGEST_INVALID:{sid}")
            if not _nonempty(arow.get("approved_by")) or not _nonempty(arow.get("approval_ref")):
                e.append(f"IRREVERSIBLE_APPROVAL_PROVENANCE_INVALID:{sid}")
            approved_at = _parse_ts(arow.get("approved_at"))
            expires_at = _parse_ts(arow.get("expires_at"))
            if approved_at is None or expires_at is None or frozen_at is None:
                e.append(f"IRREVERSIBLE_APPROVAL_TIME_INVALID:{sid}")
            elif not (approved_at <= frozen_at < expires_at):
                e.append(f"IRREVERSIBLE_APPROVAL_NOT_CURRENT_AT_FREEZE:{sid}")
        irreversible_steps = {
            o.get("step_id") for o in obs or []
            if isinstance(o, dict) and o.get("irreversible_effect") is True
        }
        if irreversible_steps != seen_approval_steps:
            for sid in sorted(irreversible_steps - seen_approval_steps):
                e.append(f"IRREVERSIBLE_APPROVAL_MISSING:{sid}")

    cp = m.get("closure_policy")
    expected = {
        "progress_formula": "VERIFIED_REQUIRED_OBLIGATIONS_DIV_REQUIRED_OBLIGATIONS",
        "self_reported_progress_allowed": False,
        "zero_blockers_required": True,
        "authority_currentness_required": True,
        "manifest_digest_immutable": True,
        "independent_closure_required": True,
    }
    if not isinstance(cp, dict):
        e.append("CLOSURE_POLICY_INVALID")
    else:
        for k, v in expected.items():
            if cp.get(k) != v:
                e.append(f"CLOSURE_POLICY_INVALID:{k}")
        closure_step = cp.get("independent_closure_step_id")
        if not _nonempty(closure_step):
            e.append("INDEPENDENT_CLOSURE_STEP_INVALID")
        elif isinstance(obs, list):
            matches = [x for x in obs if isinstance(x, dict) and x.get("step_id") == closure_step]
            if not matches:
                e.append("INDEPENDENT_CLOSURE_STEP_NOT_DECLARED")
            elif matches[0].get("verifier_mode") not in INDEPENDENT_MODES or matches[0].get("required") is not True:
                e.append("INDEPENDENT_CLOSURE_STEP_NOT_INDEPENDENT")
    if not _hex64(m.get("manifest_digest")):
        e.append("MANIFEST_DIGEST_INVALID")
    elif m.get("manifest_digest") != digest_without_self(m):
        e.append("MANIFEST_DIGEST_CONTENT_MISMATCH")
    return e


def _evaluate_gate_contract(authority_gate: dict[str, Any], gate_packet: Any, evidence: dict[str, Any]) -> tuple[str, str]:
    if not isinstance(gate_packet, dict):
        return "BLOCKED", "GATE_PACKET_MISSING_OR_INVALID"
    if gate_packet.get("gate_contract_sha256") != authority_gate.get("gate_contract_sha256"):
        return "BLOCKED", "GATE_CONTRACT_DIGEST_MISMATCH"

    required_keys = authority_gate.get("required_evidence_keys") or []
    if any(k not in evidence or evidence[k] in (None, "", [], {}) for k in required_keys):
        return "BLOCKED", "GATE_REQUIRED_EVIDENCE_MISSING"

    pre = gate_packet.get("precondition_result")
    if pre not in {"PASS", "FAIL", "BLOCKED"}:
        return "BLOCKED", "GATE_PRECONDITION_RESULT_MISSING_OR_INVALID"
    if pre != "PASS":
        if "deterministic_result" in gate_packet or "judge_result" in gate_packet:
            return "BLOCKED", "GATE_EXECUTED_AFTER_PRECONDITION_NONPASS"
        return pre, f"GATE_PRECONDITION_{pre}"

    det_seq = 0
    if authority_gate.get("deterministic_required") is True:
        det = gate_packet.get("deterministic_result")
        if det not in {"PASS", "FAIL", "BLOCKED"}:
            return "BLOCKED", "GATE_DETERMINISTIC_RESULT_MISSING_OR_INVALID"
        det_seq = gate_packet.get("deterministic_seq")
        if not isinstance(det_seq, int) or isinstance(det_seq, bool) or det_seq < 1:
            return "BLOCKED", "GATE_DETERMINISTIC_SEQUENCE_MISSING_OR_INVALID"
        if det != "PASS":
            if "judge_result" in gate_packet or "judge_seq" in gate_packet:
                return "BLOCKED", "GATE_JUDGE_AFTER_DETERMINISTIC_NONPASS_FORBIDDEN"
            return det, f"GATE_DETERMINISTIC_{det}"

    if authority_gate.get("judge_required") is True:
        judge_result = gate_packet.get("judge_result")
        judge_seq = gate_packet.get("judge_seq")
        if not _nonempty(judge_result):
            return "BLOCKED", "GATE_JUDGE_RESULT_MISSING"
        if not isinstance(judge_seq, int) or isinstance(judge_seq, bool) or judge_seq < 1:
            return "BLOCKED", "GATE_JUDGE_SEQUENCE_MISSING_OR_INVALID"
        if judge_seq <= det_seq:
            return "BLOCKED", "GATE_JUDGE_BEFORE_DETERMINISTIC_FORBIDDEN"
        if judge_result == authority_gate.get("clean_result_value"):
            return "PASS", "GATE_EVALUATED"
        if judge_result == authority_gate.get("return_result_value"):
            return "FAIL", "GATE_EVALUATED"
        if judge_result == authority_gate.get("blocked_result_value"):
            return "BLOCKED", "GATE_EVALUATED"
        return "BLOCKED", "GATE_JUDGE_RESULT_NOT_CANONICAL"

    return "PASS", "GATE_EVALUATED"


def _derive_controller_frontier(
    manifest: dict[str, Any],
    steps: dict[str, dict[str, Any]],
    verified_step_ids: set[str],
) -> dict[str, Any]:
    obligations = sorted(
        [o for o in manifest.get("obligations", []) if isinstance(o, dict)],
        key=lambda o: (o.get("controller_order", 10**9), o.get("step_id", "")),
    )
    by_step = {o["step_id"]: o for o in obligations}
    ready: list[dict[str, Any]] = []
    waiting: list[str] = []
    blocked: list[str] = []

    for o in obligations:
        sid = o["step_id"]
        if sid in verified_step_ids:
            continue
        deps = o.get("depends_on_step_ids") or []
        blocked_dep = False
        incomplete_dep = False
        for dep in deps:
            if dep in verified_step_ids:
                continue
            dep_step = steps.get(dep)
            if dep_step is not None:
                blocked_dep = True
            else:
                incomplete_dep = True
        if blocked_dep:
            blocked.append(sid)
        elif incomplete_dep:
            waiting.append(sid)
        else:
            ready.append(o)

    if not ready:
        return {
            "active_closure_unit_id": None,
            "allowed_step_ids": [],
            "ready_step_ids": [],
            "waiting_step_ids": waiting,
            "blocked_by_predecessor_step_ids": blocked,
        }

    unit_min: dict[str, int] = {}
    for o in ready:
        unit = o["closure_unit_id"]
        unit_min[unit] = min(unit_min.get(unit, 10**9), o["controller_order"])
    active_unit = min(unit_min, key=lambda u: (unit_min[u], u))
    unit_ready = [o for o in ready if o["closure_unit_id"] == active_unit]
    material = [o for o in unit_ready if o["execution_effect"] != "READ_ONLY"]

    if material:
        primary = min(material, key=lambda o: (o["controller_order"], o["step_id"]))
        allowed = [primary["step_id"]]
        allowed += [
            o["step_id"] for o in unit_ready
            if o["execution_effect"] == "READ_ONLY" and o.get("parallel_safe") is True
        ]
    else:
        nonparallel = [o for o in unit_ready if o.get("parallel_safe") is not True]
        if nonparallel:
            primary = min(nonparallel, key=lambda o: (o["controller_order"], o["step_id"]))
            allowed = [primary["step_id"]]
        else:
            allowed = [o["step_id"] for o in unit_ready]

    allowed = sorted(set(allowed), key=lambda sid: (by_step[sid]["controller_order"], sid))
    return {
        "active_closure_unit_id": active_unit,
        "allowed_step_ids": allowed,
        "ready_step_ids": [o["step_id"] for o in ready],
        "waiting_step_ids": waiting,
        "blocked_by_predecessor_step_ids": blocked,
    }


def _derive_closure_controller(
    manifest: dict[str, Any],
    steps: dict[str, dict[str, Any]],
    verified_step_ids: set[str],
    closure_receipts: list[dict[str, Any]],
) -> dict[str, Any]:
    obligations = [
        o for o in manifest.get("obligations", [])
        if isinstance(o, dict) and o.get("close_required") is True
    ]
    unit_order: dict[str, int] = {}
    unit_steps: dict[str, list[str]] = {}
    order_by_step = {o["step_id"]: o["controller_order"] for o in obligations}
    for o in obligations:
        unit = o["closure_unit_id"]
        unit_order[unit] = min(unit_order.get(unit, 10**9), o["controller_order"])
        unit_steps.setdefault(unit, []).append(o["step_id"])
    ordered_units = sorted(unit_steps, key=lambda u: (unit_order[u], u))

    latest_by_unit: dict[str, dict[str, Any]] = {}
    for row in closure_receipts:
        if not isinstance(row, dict):
            continue
        unit = row.get("closure_unit_id")
        seq = row.get("receipt_seq")
        if unit not in unit_steps or not isinstance(seq, int):
            continue
        prev = latest_by_unit.get(unit)
        if prev is None or seq > prev.get("receipt_seq", -1):
            latest_by_unit[unit] = row

    previous_receipt_sha: str | None = None
    previous_terminal = True
    unit_states: list[dict[str, Any]] = []
    debt_count = 0
    reopen_count = 0

    for unit in ordered_units:
        sids = sorted(unit_steps[unit], key=lambda sid: (order_by_step[sid], sid))
        state_rows = []
        has_blocked = False
        all_verified = True
        for sid in sids:
            if sid in verified_step_ids:
                state = "VERIFIED"
            elif sid in steps:
                state = "BLOCKED"
                has_blocked = True
                all_verified = False
            else:
                state = "PENDING"
                all_verified = False
            step_row = steps.get(sid)
            step_evidence_sha = (
                hashlib.sha256(canonical_bytes(step_row)).hexdigest()
                if isinstance(step_row, dict)
                else None
            )
            state_rows.append({
                "step_id": sid,
                "state": state,
                "step_evidence_sha256": step_evidence_sha,
            })
        unit_state = {
            "execution_id": manifest.get("execution_id"),
            "manifest_digest": manifest.get("manifest_digest"),
            "closure_unit_id": unit,
            "steps": state_rows,
        }
        unit_state_sha = hashlib.sha256(canonical_bytes(unit_state)).hexdigest()
        receipt = latest_by_unit.get(unit)

        if not previous_terminal:
            if receipt is None:
                state = "WAITING_PREVIOUS_CLOSURE"
                receipt_sha = None
            else:
                state = "REOPEN_REQUIRED"
                receipt_sha = receipt.get("receipt_sha256")
                reopen_count += 1
        elif receipt is None:
            if all_verified:
                state = "READY_TO_CLOSE"
            elif has_blocked:
                state = "READY_TO_BLOCK_WITH_EVIDENCE"
            else:
                state = "OPEN"
            receipt_sha = None
        else:
            expected_outcome = (
                "CLOSED_WITH_EVIDENCE"
                if all_verified
                else ("BLOCKED_WITH_EVIDENCE" if has_blocked else None)
            )
            valid = (
                receipt.get("verified") is True
                and receipt.get("execution_id") == manifest.get("execution_id")
                and receipt.get("manifest_digest") == manifest.get("manifest_digest")
                and receipt.get("unit_state_sha256") == unit_state_sha
                and receipt.get("outcome") == expected_outcome
                and receipt.get("previous_unit_receipt_sha256") == previous_receipt_sha
                and _hex64(receipt.get("receipt_sha256"))
            )
            if valid:
                state = expected_outcome
                receipt_sha = receipt["receipt_sha256"]
                previous_receipt_sha = receipt_sha
                if state == "BLOCKED_WITH_EVIDENCE":
                    debt_count += 1
            else:
                state = "REOPEN_REQUIRED"
                receipt_sha = receipt.get("receipt_sha256")
                reopen_count += 1

        previous_terminal = state in {"CLOSED_WITH_EVIDENCE", "BLOCKED_WITH_EVIDENCE"}
        unit_states.append({
            "closure_unit_id": unit,
            "state": state,
            "unit_state_sha256": unit_state_sha,
            "receipt_sha256": receipt_sha,
        })

    global_close_allowed = bool(unit_states) and all(
        x["state"] == "CLOSED_WITH_EVIDENCE" for x in unit_states
    ) and debt_count == 0 and reopen_count == 0
    return {
        "units": unit_states,
        "closure_debt_count": debt_count,
        "reopen_required_count": reopen_count,
        "global_close_allowed": global_close_allowed,
    }


def evaluate(packet: Any) -> dict[str, Any]:
    if not isinstance(packet, dict):
        return {"result": "BLOCKED", "errors": ["PACKET_NOT_OBJECT"], "progress_percent": 0}
    m = packet.get("manifest")
    errors = validate_manifest(m)
    if errors:
        return {"result": "BLOCKED", "errors": errors, "progress_percent": 0}

    authority = packet.get("authority_readback") or {}
    frozen = m["authority_snapshot"]
    if authority.get("operation_revision_sha256") != frozen.get("operation_revision_sha256"):
        return {"result": "STALE_AUTHORITY", "errors": ["OPERATION_REVISION_DRIFT"], "progress_percent": 0}
    if authority.get("contract_code") != frozen.get("contract_code") or authority.get("contract_revision_sha256") != frozen.get("contract_revision_sha256"):
        return {"result": "STALE_AUTHORITY", "errors": ["CONTRACT_DRIFT"], "progress_percent": 0}
    if authority.get("obligation_set_sha256") != frozen.get("obligation_set_sha256"):
        return {"result": "STALE_AUTHORITY", "errors": ["OBLIGATION_SET_DRIFT"], "progress_percent": 0}
    if authority.get("policy_set_sha256") != frozen.get("policy_set_sha256"):
        return {"result": "STALE_AUTHORITY", "errors": ["POLICY_SET_DRIFT"], "progress_percent": 0}
    if packet.get("persisted_manifest_digest") != m.get("manifest_digest"):
        return {"result": "BLOCKED", "errors": ["PERSISTED_MANIFEST_DIGEST_MISMATCH"], "progress_percent": 0}
    if packet.get("request_sha256_readback") != m.get("request_sha256"):
        return {"result": "BLOCKED", "errors": ["REQUEST_SHA256_BINDING_MISMATCH"], "progress_percent": 0}
    scope_rb = packet.get("scope_authority_readback") or {}
    if scope_rb.get("authorization_ref") != m["authorized_scope"].get("authorization_ref") or scope_rb.get("authorization_sha256") != m["authorized_scope"].get("authorization_sha256"):
        return {"result": "BLOCKED", "errors": ["AUTHORIZED_SCOPE_PROVENANCE_MISMATCH"], "progress_percent": 0}
    if packet.get("manifest_readback") != m:
        return {"result": "BLOCKED", "errors": ["MANIFEST_READBACK_MISMATCH"], "progress_percent": 0}

    required_authority = authority.get("required_steps")
    if not isinstance(required_authority, list):
        return {"result": "BLOCKED", "errors": ["AUTHORITY_REQUIRED_STEPS_MISSING"], "progress_percent": 0}
    expected_by_step: dict[str, dict[str, Any]] = {}
    for row in required_authority:
        if (
            not isinstance(row, dict)
            or not _nonempty(row.get("step_id"))
            or not isinstance(row.get("required_evidence_keys"), list)
            or row.get("gate_type") not in {"ENTRY", "STEP", "EXIT", "CLOSURE"}
            or row.get("verifier_mode") not in {"DETERMINISTIC", "INDEPENDENT_READBACK", "SEMANTIC_JUDGE", "COMPOSITE"}
            or not _hex64(row.get("gate_contract_sha256"))
            or not isinstance(row.get("deterministic_required"), bool)
            or not isinstance(row.get("judge_required"), bool)
            or not isinstance(row.get("waiver_allowed"), bool)
            or not isinstance(row.get("irreversible_effect"), bool)
            or not isinstance(row.get("human_approval_required"), bool)
            or not isinstance(row.get("depends_on_step_ids"), list)
            or not _nonempty(row.get("closure_unit_id"))
            or not isinstance(row.get("controller_order"), int)
            or isinstance(row.get("controller_order"), bool)
            or row.get("controller_order") < 0
            or row.get("execution_effect") not in {"READ_ONLY", "MUTATING", "JUDGE", "CLOSURE"}
            or not isinstance(row.get("parallel_safe"), bool)
        ):
            return {"result": "BLOCKED", "errors": ["AUTHORITY_REQUIRED_STEPS_INVALID"], "progress_percent": 0}
        if row.get("judge_required") is True and not all(
            _nonempty(row.get(k)) for k in ("clean_result_value", "blocked_result_value", "return_result_value")
        ):
            return {"result": "BLOCKED", "errors": ["AUTHORITY_GATE_JUDGE_MAPPING_INVALID"], "progress_percent": 0}
        expected_by_step[row["step_id"]] = row

    manifest_required = {o["step_id"]: o for o in m["obligations"] if o.get("required") is True}
    if set(manifest_required) != set(expected_by_step):
        return {"result": "BLOCKED", "errors": ["REQUIRED_STEP_COVERAGE_MISMATCH"], "progress_percent": 0}
    for step_id, authority_gate in expected_by_step.items():
        obligation = manifest_required[step_id]
        required_keys = set(authority_gate.get("required_evidence_keys") or [])
        if not required_keys.issubset(set(obligation.get("evidence_keys") or [])):
            return {"result": "BLOCKED", "errors": [f"REQUIRED_EVIDENCE_CONTRACT_MISMATCH:{step_id}"], "progress_percent": 0}
        if obligation.get("gate_type") != authority_gate.get("gate_type"):
            return {"result": "BLOCKED", "errors": [f"GATE_TYPE_AUTHORITY_MISMATCH:{step_id}"], "progress_percent": 0}
        if obligation.get("verifier_mode") != authority_gate.get("verifier_mode"):
            return {"result": "BLOCKED", "errors": [f"VERIFIER_MODE_AUTHORITY_MISMATCH:{step_id}"], "progress_percent": 0}
        if obligation.get("gate_contract_sha256") != authority_gate.get("gate_contract_sha256"):
            return {"result": "BLOCKED", "errors": [f"GATE_CONTRACT_AUTHORITY_MISMATCH:{step_id}"], "progress_percent": 0}
        for control_key in ("waiver_allowed", "irreversible_effect", "human_approval_required"):
            if obligation.get(control_key) != authority_gate.get(control_key):
                return {"result": "BLOCKED", "errors": [f"CONTROL_AUTHORITY_MISMATCH:{step_id}:{control_key}"], "progress_percent": 0}
        for controller_key in ("depends_on_step_ids", "closure_unit_id", "controller_order", "execution_effect", "parallel_safe"):
            if obligation.get(controller_key) != authority_gate.get(controller_key):
                return {"result": "BLOCKED", "errors": [f"CONTROLLER_AUTHORITY_MISMATCH:{step_id}:{controller_key}"], "progress_percent": 0}

    supersession = m.get("supersession")
    if supersession is not None:
        srb = packet.get("supersession_readback")
        if not isinstance(srb, dict):
            return {"result": "BLOCKED", "errors": ["SUPERSESSION_READBACK_MISSING"], "progress_percent": 0}
        if (
            srb.get("execution_id") != supersession.get("previous_execution_id")
            or srb.get("manifest_digest") != supersession.get("previous_manifest_digest")
            or srb.get("operation_code") != m.get("operation_code")
            or srb.get("target") != m.get("target")
        ):
            return {"result": "BLOCKED", "errors": ["SUPERSESSION_PREDECESSOR_BINDING_MISMATCH"], "progress_percent": 0}
        previous_scope = srb.get("authorized_scope")
        if not isinstance(previous_scope, dict):
            return {"result": "BLOCKED", "errors": ["SUPERSESSION_PREVIOUS_SCOPE_MISSING"], "progress_percent": 0}
        previous_scope_sha = hashlib.sha256(canonical_bytes(previous_scope)).hexdigest()
        if previous_scope_sha != supersession.get("previous_scope_sha256"):
            return {"result": "BLOCKED", "errors": ["SUPERSESSION_PREVIOUS_SCOPE_DIGEST_MISMATCH"], "progress_percent": 0}
        change_rb = packet.get("change_authorization_readback")
        if not isinstance(change_rb, dict) or change_rb.get("authorization_ref") != supersession.get("change_authorization_ref") or change_rb.get("authorization_sha256") != supersession.get("change_authorization_sha256") or change_rb.get("verified") is not True:
            return {"result": "BLOCKED", "errors": ["SUPERSESSION_CHANGE_AUTHORIZATION_NOT_VERIFIED"], "progress_percent": 0}
        carried = packet.get("carried_forward_step_ids") or []
        if not isinstance(carried, list) or carried:
            return {"result": "BLOCKED", "errors": ["SUPERSESSION_PROGRESS_CARRY_FORWARD_FORBIDDEN"], "progress_percent": 0}

    waiver_rb = packet.get("waiver_authority_readback") or []
    if not isinstance(waiver_rb, list):
        return {"result": "BLOCKED", "errors": ["WAIVER_AUTHORITY_READBACK_INVALID"], "progress_percent": 0}
    for w in m.get("waivers") or []:
        if not any(
            isinstance(r, dict)
            and r.get("requirement_id") == w.get("requirement_id")
            and r.get("authorization_ref") == w.get("authorization_ref")
            and r.get("authorization_sha256") == w.get("authorization_sha256")
            and r.get("authorized_by") == w.get("authorized_by")
            and r.get("actor_type") == "HUMAN"
            and r.get("verified") is True
            for r in waiver_rb
        ):
            return {"result": "BLOCKED", "errors": [f"WAIVER_AUTHORIZATION_NOT_VERIFIED:{w.get('requirement_id')}"], "progress_percent": 0}

    approval_rb = packet.get("human_approval_readback") or []
    if not isinstance(approval_rb, list):
        return {"result": "BLOCKED", "errors": ["HUMAN_APPROVAL_READBACK_INVALID"], "progress_percent": 0}
    approvals_by_step = {a.get("step_id"): a for a in (m.get("irreversible_approvals") or []) if isinstance(a, dict)}
    for sid, approval in approvals_by_step.items():
        if not any(
            isinstance(r, dict)
            and r.get("step_id") == sid
            and r.get("action_sha256") == approval.get("action_sha256")
            and r.get("approval_ref") == approval.get("approval_ref")
            and r.get("approval_sha256") == approval.get("approval_sha256")
            and r.get("approved_by") == approval.get("approved_by")
            and r.get("actor_type") == "HUMAN"
            and r.get("verified") is True
            for r in approval_rb
        ):
            return {"result": "BLOCKED", "errors": [f"IRREVERSIBLE_HUMAN_APPROVAL_NOT_VERIFIED:{sid}"], "progress_percent": 0}

    steps_raw = packet.get("execution_steps")
    if not isinstance(steps_raw, list):
        return {"result": "BLOCKED", "errors": ["EXECUTION_STEPS_INVALID"], "progress_percent": 0}
    steps: dict[str, dict[str, Any]] = {}
    for s in steps_raw:
        if isinstance(s, dict) and _nonempty(s.get("step_id")):
            if s["step_id"] in steps:
                errors.append(f"DUPLICATE_EXECUTION_STEP:{s['step_id']}")
            steps[s["step_id"]] = s

    required = [o for o in m["obligations"] if o.get("required") is True]
    verified = 0
    verified_step_ids: set[str] = set()
    blocking: list[str] = []
    unmet: list[str] = []
    for o in required:
        rid, sid = o["requirement_id"], o["step_id"]
        s = steps.get(sid)
        if not s:
            unmet.append(rid)
            continue
        status = s.get("status")
        if status in {"BLOCKED", "FAIL", "RETURN_TO_WORKER"}:
            unmet.append(rid)
            if o.get("blocking"):
                blocking.append(rid)
            continue
        if status not in CLEAN_STATUSES:
            unmet.append(rid)
            continue
        evidence = s.get("evidence")
        if o.get("irreversible_effect") is True:
            approval = approvals_by_step.get(sid)
            if approval is None or not isinstance(evidence, dict) or evidence.get("irreversible_action_sha256") != approval.get("action_sha256"):
                unmet.append(rid)
                blocking.append(f"IRREVERSIBLE_APPROVAL:{rid}")
                errors.append(f"IRREVERSIBLE_ACTION_APPROVAL_BINDING_MISMATCH:{rid}")
                continue
        if not isinstance(evidence, dict) or any(k not in evidence or evidence[k] in (None, "", [], {}) for k in o.get("evidence_keys", [])):
            unmet.append(rid)
            errors.append(f"REQUIRED_EVIDENCE_MISSING:{rid}")
            continue

        evidence_result, evidence_code = _evaluate_exact_evidence(
            manifest=m,
            obligation=o,
            evidence=evidence,
            execution_started_at=packet.get("execution_started_at"),
            ledger_rows=packet.get("evidence_ledger_readback"),
        )
        if evidence_result == "STALE":
            unmet.append(rid)
            blocking.append(f"STALE_EVIDENCE:{rid}")
            errors.append(f"{evidence_code}:{rid}")
            continue
        if evidence_result != "PASS":
            unmet.append(rid)
            blocking.append(f"EVIDENCE:{rid}")
            errors.append(f"{evidence_code}:{rid}")
            continue

        gate_result, gate_code = _evaluate_gate_contract(
            expected_by_step[sid],
            evidence.get("work_protocol_gate"),
            evidence,
        )
        if gate_result == "BLOCKED":
            unmet.append(rid)
            blocking.append(f"GATE:{rid}")
            errors.append(f"{gate_code}:{rid}")
            continue
        if gate_result == "FAIL":
            unmet.append(rid)
            errors.append(f"GATE_FAIL:{rid}:{gate_code}")
            continue

        if o.get("verifier_mode") in INDEPENDENT_MODES:
            observer_execution_id = s.get("observer_execution_id")
            if s.get("observer_role") == "PRODUCER" or not _nonempty(observer_execution_id) or observer_execution_id == m["execution_id"]:
                unmet.append(rid)
                errors.append(f"INDEPENDENT_VERIFICATION_REQUIRED:{rid}")
                continue
            actor_rows = packet.get("independent_actor_readback") or []
            actor_ok = any(
                isinstance(a, dict)
                and a.get("execution_id") == observer_execution_id
                and a.get("target_execution_id") == m["execution_id"]
                and a.get("status") in {"PASS_WITH_EVIDENCE", "PASS_CLEAN", "COMPLETED"}
                for a in actor_rows
            )
            if not actor_ok:
                unmet.append(rid)
                errors.append(f"INDEPENDENT_VERIFIER_EXECUTION_NOT_PROVEN:{rid}")
                continue
        verified += 1
        verified_step_ids.add(sid)

    controller = _derive_controller_frontier(m, steps, verified_step_ids)
    closure_receipts = packet.get("closure_ledger_readback") or []
    if not isinstance(closure_receipts, list):
        return {"result": "BLOCKED", "errors": ["CLOSURE_LEDGER_READBACK_INVALID"], "progress_percent": 0}
    closure_controller = _derive_closure_controller(m, steps, verified_step_ids, closure_receipts)

    recovery_state = packet.get("recovery_state")
    recovering: list[str] = []
    if recovery_state is not None:
        if not isinstance(recovery_state, dict):
            blocking.append("RECOVERY_PROTOCOL")
            errors.append("TIMEOUT_RECOVERY_STATE_INVALID")
        else:
            recovery_step_id = recovery_state.get("step_id")
            obligation = next((o for o in required if o.get("step_id") == recovery_step_id), None)
            if obligation is None:
                blocking.append("RECOVERY_PROTOCOL")
                errors.append("TIMEOUT_RECOVERY_STEP_NOT_REQUIRED")
            else:
                rid = obligation["requirement_id"]
                attempt = recovery_state.get("attempt")
                max_attempts = m["execution_policy"]["max_recovery_attempts"]
                if not isinstance(attempt, int) or isinstance(attempt, bool) or attempt < 1:
                    blocking.append(f"RECOVERY_PROTOCOL:{rid}")
                    errors.append(f"TIMEOUT_RECOVERY_ATTEMPT_INVALID:{rid}")
                elif attempt > max_attempts:
                    blocking.append(f"BLOCKED_OPERATIONAL_TIMEOUT:{rid}")
                    errors.append(f"TIMEOUT_RECOVERY_EXHAUSTED:{rid}")
                else:
                    strategy = recovery_state.get("strategy")
                    recovery_ok = strategy == obligation.get("timeout_recovery_mode")
                    execution_class = obligation.get("execution_class")
                    if execution_class == "CHUNKABLE":
                        previous_unit = recovery_state.get("previous_work_unit")
                        next_unit = recovery_state.get("next_work_unit")
                        recovery_ok = (
                            recovery_ok
                            and isinstance(previous_unit, (int, float)) and not isinstance(previous_unit, bool)
                            and isinstance(next_unit, (int, float)) and not isinstance(next_unit, bool)
                            and previous_unit > 0 and next_unit > 0 and next_unit < previous_unit
                        )
                    if execution_class == "CHECKPOINTABLE" or obligation.get("checkpoint_required") is True:
                        recovery_ok = recovery_ok and _nonempty(recovery_state.get("checkpoint_ref"))
                    if steps.get(recovery_step_id, {}).get("status") in CLEAN_STATUSES:
                        recovery_ok = False
                        errors.append(f"TIMEOUT_RECOVERY_ON_VERIFIED_STEP:{rid}")
                    if not recovery_ok:
                        blocking.append(f"RECOVERY_PROTOCOL:{rid}")
                        if f"TIMEOUT_RECOVERY_ON_VERIFIED_STEP:{rid}" not in errors:
                            errors.append(f"TIMEOUT_RECOVERY_STRATEGY_INVALID:{rid}")
                    else:
                        recovering.append(rid)

    total = len(required)
    progress = 100 if total == 0 else (100 * verified) // total
    closure_step_id = m["closure_policy"]["independent_closure_step_id"]
    closure_step = steps.get(closure_step_id)
    closure_independent = bool(
        closure_step
        and closure_step.get("status") in CLEAN_STATUSES
        and closure_step.get("observer_role") not in (None, "PRODUCER")
        and _nonempty(closure_step.get("observer_execution_id"))
    )

    scope_violations = packet.get("scope_violations") or []
    if scope_violations:
        blocking += [f"SCOPE:{x}" for x in scope_violations]
    external_blockers = packet.get("blockers") or []
    if external_blockers:
        blocking += [f"EXTERNAL:{x}" for x in external_blockers]

    if blocking:
        result = "BLOCKED"
    elif errors:
        result = "RETURN_TO_WORKER"
    elif recovering:
        result = "RECOVERING"
    elif progress < 100:
        result = "IN_PROGRESS"
    elif closure_controller["reopen_required_count"] > 0:
        result = "BLOCKED"
        errors.extend(
            f"CLOSURE_REOPEN_REQUIRED:{u['closure_unit_id']}"
            for u in closure_controller["units"] if u["state"] == "REOPEN_REQUIRED"
        )
    elif closure_controller["closure_debt_count"] > 0:
        result = "BLOCKED_CLOSURE_DEBT"
    elif not closure_independent:
        result = "RETURN_TO_WORKER"
        errors.append("INDEPENDENT_CLOSURE_NOT_VERIFIED")
    elif not closure_controller["global_close_allowed"]:
        result = "IN_PROGRESS"
    else:
        result = "PASS_WITH_EVIDENCE"

    return {
        "result": result,
        "progress_percent": progress,
        "required_obligations": total,
        "verified_required_obligations": verified,
        "unmet_requirement_ids": unmet,
        "recovering_requirement_ids": recovering,
        "blocking": blocking,
        "errors": errors,
        "authority_current": True,
        "manifest_digest_match": True,
        "independent_closure_verified": closure_independent,
        "active_waiver_count": len(m.get("waivers") or []),
        "residual_risks": [w.get("residual_risk") for w in (m.get("waivers") or []) if isinstance(w, dict)],
        "supersedes_execution_id": (m.get("supersession") or {}).get("previous_execution_id"),
        "controller": controller,
        "closure_controller": closure_controller,
    }


def valid_fixture() -> dict[str, Any]:
    m = {
        "manifest_version": VERSION,
        "manifest_id": "WPM-TEST-001",
        "execution_id": "EXEC-WPM-TEST-001",
        "operation_code": "TEST_OPERATION_LF",
        "work_owner": {
            "owner_id": "AGENT-WPM-TEST",
            "owner_type": "AGENT",
            "declaration_ref": "request://test/001",
            "declaration_sha256": "c" * 64,
            "change_mode": "SUPERSEDE_NEW_EXECUTION",
        },
        "request_sha256": "c" * 64,
        "target": {"type": "TEST", "code": "T-001", "repo": None, "path": None},
        "frozen_at": "2026-09-22T12:00:00Z",
        "authority_snapshot": {
            "operation_revision_sha256": "a" * 64,
            "contract_code": "CONTRACT-TEST-v1",
            "contract_sha": "contractsha123",
            "contract_revision_sha256": "d" * 64,
            "obligation_set_sha256": "e" * 64,
            "policy_set_sha256": "b" * 64,
            "source_refs": ["supabase://operation/TEST_OPERATION_LF"],
        },
        "authorized_scope": {"authorization_ref": "request://test/001", "authorization_sha256": "c" * 64, "read": ["supabase://test"], "write": [], "effects": ["NONE", "READ_ONLY"]},
        "execution_policy": {
            "timeout_recovery_required": True,
            "preserve_verified_progress": True,
            "max_recovery_attempts": 3,
            "exhausted_timeout_result": "BLOCKED_OPERATIONAL_TIMEOUT",
        },
        "evidence_policy": {
            "exact_envelope_required": True,
            "reproduction_spec_required": True,
            "append_only_ledger_required_for_independent": True,
            "independent_actor_distinct_required": True,
            "max_age_seconds": 86400,
            "future_clock_skew_seconds": 300,
            "ledger_receipt_kind": "WORK_PROTOCOL_GATE_EVIDENCE",
        },
        "solution_isolation_policy": {
            "unit_mode": "ONE_SOLUTION_PER_PR",
            "mixed_solution_pr_allowed": False,
            "scope_expansion_requires_new_pr": True,
            "migration_apply_requires_separate_pr": True,
            "receipt_must_bind_exact_pr_scope": True,
        },
        "control_policy": {
            "scope_change_mode": "SUPERSEDE_NEW_EXECUTION_FULL_REVALIDATION",
            "authorization_rebind_required": True,
            "carry_forward_verified_progress": False,
            "required_obligation_waivers_allowed": False,
            "waiver_max_ttl_seconds": 3600,
            "irreversible_human_approval_required": True,
        },
        "controller_policy": {
            "dependency_mode": "CANONICAL_DAG",
            "material_wip_limit": 1,
            "parallelism_policy": "READ_ONLY_SAME_CLOSURE_UNIT_ONLY",
            "lease_required_for_activation": True,
            "fenced_checkpoint_required": True,
            "failed_predecessor_blocks_dependents": True,
            "resume_from_canonical_state": True,
        },
        "closure_controller_policy": {
            "unit_progression_mode": "CLOSE_OR_BLOCK_WITH_EVIDENCE_BEFORE_NEXT",
            "blocked_continue_mode": "DEPENDENCY_SAFE_ONLY",
            "closure_receipt_kind": "WORK_PROTOCOL_CLOSURE_UNIT",
            "blocked_receipt_kind": "WORK_PROTOCOL_BLOCKED_UNIT",
            "receipt_chain_required": True,
            "reopen_on_unit_digest_change": True,
            "global_close_requires_zero_debt": True,
        },
        "waivers": [],
        "irreversible_approvals": [],
        "supersession": None,
        "obligations": [
            {"requirement_id": "WP-01", "step_id": "resolve", "required": True, "evidence_keys": ["authority_ref"], "verifier_mode": "DETERMINISTIC", "blocking": True, "close_required": True, "authority_ref": "operation", "execution_class": "CHUNKABLE", "timeout_recovery_mode": "REDUCE_UNIT", "checkpoint_required": True, "idempotent": True, "gate_type": "ENTRY", "gate_contract_sha256": "1" * 64, "waiver_allowed": False, "irreversible_effect": False, "human_approval_required": False, "depends_on_step_ids": [], "closure_unit_id": "CU-01", "controller_order": 10, "execution_effect": "READ_ONLY", "parallel_safe": False},
            {"requirement_id": "WP-02", "step_id": "readback", "required": True, "evidence_keys": ["readback_ref"], "verifier_mode": "INDEPENDENT_READBACK", "blocking": True, "close_required": True, "authority_ref": "operation", "execution_class": "CHECKPOINTABLE", "timeout_recovery_mode": "RESUME_CHECKPOINT", "checkpoint_required": True, "idempotent": True, "gate_type": "EXIT", "gate_contract_sha256": "2" * 64, "waiver_allowed": False, "irreversible_effect": False, "human_approval_required": False, "depends_on_step_ids": ["resolve"], "closure_unit_id": "CU-02", "controller_order": 20, "execution_effect": "JUDGE", "parallel_safe": False},
            {"requirement_id": "WP-03", "step_id": "independent_close", "required": True, "evidence_keys": ["judge_receipt"], "verifier_mode": "SEMANTIC_JUDGE", "blocking": True, "close_required": True, "authority_ref": "operation", "execution_class": "ATOMIC", "timeout_recovery_mode": "RETRY_ATOMIC", "checkpoint_required": False, "idempotent": True, "gate_type": "CLOSURE", "gate_contract_sha256": "3" * 64, "waiver_allowed": False, "irreversible_effect": False, "human_approval_required": False, "depends_on_step_ids": ["readback"], "closure_unit_id": "CU-03", "controller_order": 30, "execution_effect": "CLOSURE", "parallel_safe": False},
        ],
        "closure_policy": {
            "progress_formula": "VERIFIED_REQUIRED_OBLIGATIONS_DIV_REQUIRED_OBLIGATIONS",
            "self_reported_progress_allowed": False,
            "zero_blockers_required": True,
            "authority_currentness_required": True,
            "manifest_digest_immutable": True,
            "independent_closure_required": True,
            "independent_closure_step_id": "independent_close",
        },
    }
    m["manifest_digest"] = digest_without_self(m)

    def exact_evidence(step_id: str, gate_sha: str, actor: str, observed_at: str, result_ref: str, result_sha: str, ledger_id: str | None = None, ledger_sha: str | None = None) -> dict[str, Any]:
        reproduction_spec = f"READBACK {step_id} FROM canonical authority"
        envelope: dict[str, Any] = {
            "schema_version": "LF_WORK_PROTOCOL_EVIDENCE_V1",
            "execution_id": m["execution_id"],
            "step_id": step_id,
            "gate_contract_sha256": gate_sha,
            "actor_execution_id": actor,
            "observed_at": observed_at,
            "reproduction": {
                "kind": "READBACK",
                "locator": f"supabase://test/{step_id}",
                "reproduction_spec": reproduction_spec,
                "reproduction_spec_sha256": _sha256_text(reproduction_spec),
                "input_sha256": m["request_sha256"],
                "result_ref": result_ref,
                "result_sha256": result_sha,
                "result_count": 1,
                "source_revision_sha256": m["authority_snapshot"]["operation_revision_sha256"],
            },
        }
        if ledger_id is not None:
            envelope["ledger_receipt_id"] = ledger_id
            envelope["ledger_receipt_sha256"] = ledger_sha
        return envelope

    read_ledger_id = "11111111-1111-4111-8111-111111111111"
    judge_ledger_id = "22222222-2222-4222-8222-222222222222"
    read_ledger_sha = "4" * 64
    judge_ledger_sha = "5" * 64

    steps = [
        {
            "step_id": "resolve",
            "status": "PASS_CLEAN",
            "observer_role": "PRODUCER",
            "evidence": {
                "authority_ref": "db://authority",
                "work_protocol_evidence": exact_evidence("resolve", "1" * 64, m["execution_id"], "2026-09-22T12:01:00Z", "result://resolve", "6" * 64),
                "work_protocol_gate": {"gate_contract_sha256": "1" * 64, "precondition_result": "PASS", "deterministic_result": "PASS", "deterministic_seq": 1, "judge_result": "PASS_CLEAN", "judge_seq": 2},
            },
        },
        {
            "step_id": "readback",
            "status": "PASS_CLEAN",
            "observer_role": "INDEPENDENT_READER",
            "observer_execution_id": "EXEC-INDEP-READ-001",
            "evidence": {
                "readback_ref": "db://readback",
                "verification_actor_execution_id": "EXEC-INDEP-READ-001",
                "verification_target_execution_id": m["execution_id"],
                "work_protocol_evidence": exact_evidence("readback", "2" * 64, "EXEC-INDEP-READ-001", "2026-09-22T12:02:00Z", "result://readback", "7" * 64, read_ledger_id, read_ledger_sha),
                "work_protocol_gate": {"gate_contract_sha256": "2" * 64, "precondition_result": "PASS", "deterministic_result": "PASS", "deterministic_seq": 1, "judge_result": "PASS_CLEAN", "judge_seq": 2},
            },
        },
        {
            "step_id": "independent_close",
            "status": "PASS_CLEAN",
            "observer_role": "INDEPENDENT_JUDGE",
            "observer_execution_id": "EXEC-INDEP-JUDGE-001",
            "evidence": {
                "judge_receipt": "receipt://1",
                "verification_actor_execution_id": "EXEC-INDEP-JUDGE-001",
                "verification_target_execution_id": m["execution_id"],
                "work_protocol_evidence": exact_evidence("independent_close", "3" * 64, "EXEC-INDEP-JUDGE-001", "2026-09-22T12:03:00Z", "result://close", "8" * 64, judge_ledger_id, judge_ledger_sha),
                "work_protocol_gate": {"gate_contract_sha256": "3" * 64, "precondition_result": "PASS", "deterministic_result": "PASS", "deterministic_seq": 1, "judge_result": "PASS_CLEAN", "judge_seq": 2},
            },
        },
    ]

    evidence_ledger_readback = [
        {
            "receipt_id": read_ledger_id,
            "receipt_sha256": read_ledger_sha,
            "execution_id": m["execution_id"],
            "gate_code": "WORK_PROTOCOL_GATE:readback",
            "receipt_kind": "WORK_PROTOCOL_GATE_EVIDENCE",
            "subject_ref": "result://readback",
            "subject_sha256": "7" * 64,
            "authority_ref": "operation",
            "verification_state": "VERIFIED",
            "verification_payload": {"provider_readback_verified": True, "digest_recomputed": True},
            "receipt_payload": {
                "work_protocol_execution_id": m["execution_id"],
                "work_protocol_step_id": "readback",
                "work_protocol_gate_contract_sha256": "2" * 64,
                "evidence_result_sha256": "7" * 64,
                "reproduction_spec_sha256": _sha256_text("READBACK readback FROM canonical authority"),
                "source_revision_sha256": m["authority_snapshot"]["operation_revision_sha256"],
            },
            "created_by_execution_id": "EXEC-INDEP-READ-001",
            "verified_at": "2026-09-22T12:02:30Z",
        },
        {
            "receipt_id": judge_ledger_id,
            "receipt_sha256": judge_ledger_sha,
            "execution_id": m["execution_id"],
            "gate_code": "WORK_PROTOCOL_GATE:independent_close",
            "receipt_kind": "WORK_PROTOCOL_GATE_EVIDENCE",
            "subject_ref": "result://close",
            "subject_sha256": "8" * 64,
            "authority_ref": "operation",
            "verification_state": "VERIFIED",
            "verification_payload": {"provider_readback_verified": True, "digest_recomputed": True},
            "receipt_payload": {
                "work_protocol_execution_id": m["execution_id"],
                "work_protocol_step_id": "independent_close",
                "work_protocol_gate_contract_sha256": "3" * 64,
                "evidence_result_sha256": "8" * 64,
                "reproduction_spec_sha256": _sha256_text("READBACK independent_close FROM canonical authority"),
                "source_revision_sha256": m["authority_snapshot"]["operation_revision_sha256"],
            },
            "created_by_execution_id": "EXEC-INDEP-JUDGE-001",
            "verified_at": "2026-09-22T12:03:30Z",
        },
    ]
    steps_by_id = {s["step_id"]: s for s in steps}
    base_closure = _derive_closure_controller(
        m,
        steps_by_id,
        {"resolve", "readback", "independent_close"},
        [],
    )
    closure_ledger_readback = []
    previous_receipt_sha = None
    for seq, unit in enumerate(base_closure["units"], start=1):
        receipt_sha = _sha256_text(
            f"{m['execution_id']}|{unit['closure_unit_id']}|{unit['unit_state_sha256']}|{previous_receipt_sha or ''}"
        )
        closure_ledger_readback.append({
            "receipt_seq": seq,
            "execution_id": m["execution_id"],
            "closure_unit_id": unit["closure_unit_id"],
            "manifest_digest": m["manifest_digest"],
            "unit_state_sha256": unit["unit_state_sha256"],
            "outcome": "CLOSED_WITH_EVIDENCE",
            "previous_unit_receipt_sha256": previous_receipt_sha,
            "receipt_sha256": receipt_sha,
            "verified": True,
        })
        previous_receipt_sha = receipt_sha

    return {
        "manifest": m,
        "persisted_manifest_digest": m["manifest_digest"],
        "execution_started_at": "2026-09-22T12:00:00Z",
        "evidence_ledger_readback": evidence_ledger_readback,
        "closure_ledger_readback": closure_ledger_readback,
        "waiver_authority_readback": [],
        "human_approval_readback": [],
        "carried_forward_step_ids": [],
        "authority_readback": {
            **copy.deepcopy(m["authority_snapshot"]),
            "required_steps": [
                {"step_id": "resolve", "required_evidence_keys": ["authority_ref"], "gate_type": "ENTRY", "verifier_mode": "DETERMINISTIC", "gate_contract_sha256": "1" * 64, "depends_on_step_ids": [], "closure_unit_id": "CU-01", "controller_order": 10, "execution_effect": "READ_ONLY", "parallel_safe": False, "deterministic_required": True, "judge_required": True, "clean_result_value": "PASS_CLEAN", "blocked_result_value": "BLOCKED_BY_ENFORCEMENT", "return_result_value": "RETURN_TO_WORKER", "waiver_allowed": False, "irreversible_effect": False, "human_approval_required": False},
                {"step_id": "readback", "required_evidence_keys": ["readback_ref"], "gate_type": "EXIT", "verifier_mode": "INDEPENDENT_READBACK", "gate_contract_sha256": "2" * 64, "depends_on_step_ids": ["resolve"], "closure_unit_id": "CU-02", "controller_order": 20, "execution_effect": "JUDGE", "parallel_safe": False, "deterministic_required": True, "judge_required": True, "clean_result_value": "PASS_CLEAN", "blocked_result_value": "BLOCKED_BY_ENFORCEMENT", "return_result_value": "RETURN_TO_WORKER", "waiver_allowed": False, "irreversible_effect": False, "human_approval_required": False},
                {"step_id": "independent_close", "required_evidence_keys": ["judge_receipt"], "gate_type": "CLOSURE", "verifier_mode": "SEMANTIC_JUDGE", "gate_contract_sha256": "3" * 64, "depends_on_step_ids": ["readback"], "closure_unit_id": "CU-03", "controller_order": 30, "execution_effect": "CLOSURE", "parallel_safe": False, "deterministic_required": True, "judge_required": True, "clean_result_value": "PASS_CLEAN", "blocked_result_value": "BLOCKED_BY_ENFORCEMENT", "return_result_value": "RETURN_TO_WORKER", "waiver_allowed": False, "irreversible_effect": False, "human_approval_required": False},
            ],
        },
        "manifest_readback": copy.deepcopy(m),
        "request_sha256_readback": m["request_sha256"],
        "scope_authority_readback": {"authorization_ref": m["authorized_scope"]["authorization_ref"], "authorization_sha256": m["authorized_scope"]["authorization_sha256"]},
        "independent_actor_readback": [
            {"execution_id": "EXEC-INDEP-READ-001", "target_execution_id": m["execution_id"], "status": "COMPLETED"},
            {"execution_id": "EXEC-INDEP-JUDGE-001", "target_execution_id": m["execution_id"], "status": "PASS_WITH_EVIDENCE"},
        ],
        "execution_steps": steps,
        "scope_violations": [],
        "blockers": [],
    }


def self_test() -> dict[str, str]:
    out: dict[str, str] = {}

    def refresh_closure_receipts(packet: dict[str, Any]) -> None:
        manifest = packet["manifest"]
        steps = {s["step_id"]: s for s in packet.get("execution_steps", []) if isinstance(s, dict) and _nonempty(s.get("step_id"))}
        verified_ids = {
            sid for sid, s in steps.items()
            if s.get("status") in CLEAN_STATUSES
        }
        base = _derive_closure_controller(manifest, steps, verified_ids, [])
        receipts: list[dict[str, Any]] = []
        previous_sha: str | None = None
        seq = 0
        for unit in base["units"]:
            seq += 1
            sha = _sha256_text(
                f"{manifest['execution_id']}|{unit['closure_unit_id']}|{unit['unit_state_sha256']}|{previous_sha or ''}"
            )
            receipts.append({
                "receipt_seq": seq,
                "execution_id": manifest["execution_id"],
                "closure_unit_id": unit["closure_unit_id"],
                "manifest_digest": manifest["manifest_digest"],
                "unit_state_sha256": unit["unit_state_sha256"],
                "outcome": "CLOSED_WITH_EVIDENCE",
                "previous_unit_receipt_sha256": previous_sha,
                "receipt_sha256": sha,
                "verified": True,
            })
            previous_sha = sha
        packet["closure_ledger_readback"] = receipts

    p = valid_fixture()
    r = evaluate(p); assert r["result"] == "PASS_WITH_EVIDENCE" and r["progress_percent"] == 100, r
    out["positive_full_closure"] = "PASS"

    x = copy.deepcopy(p); x["execution_steps"] = x["execution_steps"][:-1]
    r = evaluate(x); assert r["result"] == "IN_PROGRESS" and r["progress_percent"] == 66, r
    out["negative_missing_required_step"] = "PASS"

    x = copy.deepcopy(p); x["execution_steps"][1]["evidence"] = {}
    r = evaluate(x); assert r["result"] == "RETURN_TO_WORKER" and r["progress_percent"] == 66, r
    out["negative_missing_evidence"] = "PASS"

    x = copy.deepcopy(p); x["authority_readback"]["operation_revision_sha256"] = "c" * 64
    r = evaluate(x); assert r["result"] == "STALE_AUTHORITY", r
    out["negative_authority_drift"] = "PASS"

    x = copy.deepcopy(p); x["persisted_manifest_digest"] = "d" * 64
    r = evaluate(x); assert r["result"] == "BLOCKED" and "PERSISTED_MANIFEST_DIGEST_MISMATCH" in r["errors"], r
    out["negative_manifest_mutation"] = "PASS"

    x = copy.deepcopy(p); x["execution_steps"][2]["observer_role"] = "PRODUCER"
    r = evaluate(x); assert r["result"] == "RETURN_TO_WORKER" and r["progress_percent"] == 66, r
    out["negative_self_certified_close"] = "PASS"

    x = copy.deepcopy(p); x["execution_steps"][0]["status"] = "BLOCKED"
    r = evaluate(x); assert r["result"] == "BLOCKED", r
    out["negative_blocking_required_step"] = "PASS"

    x = copy.deepcopy(p); x["scope_violations"] = ["WRITE_OUTSIDE_AUTHORIZED_SCOPE"]
    r = evaluate(x); assert r["result"] == "BLOCKED", r
    out["negative_scope_deviation"] = "PASS"

    x = copy.deepcopy(p); x["manifest"]["closure_policy"]["self_reported_progress_allowed"] = True
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and "CLOSURE_POLICY_INVALID:self_reported_progress_allowed" in r["errors"], r
    out["negative_self_reported_progress_policy"] = "PASS"

    x = copy.deepcopy(p); x["manifest"]["manifest_digest"] = "bad"; x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = "bad"
    r = evaluate(x); assert r["result"] == "BLOCKED" and "MANIFEST_DIGEST_INVALID" in r["errors"], r
    out["negative_bad_manifest_digest"] = "PASS"

    x = copy.deepcopy(p); x["manifest_readback"]["target"]["code"] = "MUTATED"
    r = evaluate(x); assert r["result"] == "BLOCKED" and "MANIFEST_READBACK_MISMATCH" in r["errors"], r
    out["negative_manifest_readback_mutation"] = "PASS"

    x = copy.deepcopy(p)
    del x["manifest"]["work_owner"]
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and "MANIFEST_FIELD_MISSING:work_owner" in r["errors"], r
    out["negative_owner_missing_fails_closed"] = "PASS"

    x = copy.deepcopy(p)
    x["manifest"]["work_owner"]["declaration_sha256"] = "9" * 64
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and "OWNER_REQUEST_BINDING_MISMATCH" in r["errors"], r
    out["negative_owner_must_bind_exact_request"] = "PASS"

    x = copy.deepcopy(p)
    x["manifest"]["work_owner"]["change_mode"] = "IN_PLACE"
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and "OWNER_CHANGE_MODE_INVALID" in r["errors"], r
    out["negative_owner_reassignment_requires_new_execution"] = "PASS"


    x = copy.deepcopy(p); x["manifest"]["obligations"] = x["manifest"]["obligations"][:-1]
    x["manifest"]["closure_policy"]["independent_closure_step_id"] = "readback"
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and "REQUIRED_STEP_COVERAGE_MISMATCH" in r["errors"], r
    out["negative_required_step_omission"] = "PASS"

    x = copy.deepcopy(p); x["execution_steps"][0]["status"] = "NO_APLICA_CON_MOTIVO"
    r = evaluate(x); assert r["result"] == "IN_PROGRESS" and r["progress_percent"] == 66, r
    out["negative_required_no_aplica_does_not_count"] = "PASS"

    x = copy.deepcopy(p); x["execution_steps"][2]["observer_execution_id"] = "EXEC-FAKE-001"
    r = evaluate(x); assert r["result"] == "RETURN_TO_WORKER" and "INDEPENDENT_VERIFIER_EXECUTION_NOT_PROVEN:WP-03" in r["errors"], r
    out["negative_independent_role_label_without_execution"] = "PASS"

    x = copy.deepcopy(p); x["manifest"]["target"]["code"] = "MUTATED"; x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and "MANIFEST_DIGEST_CONTENT_MISMATCH" in r["errors"], r
    out["negative_content_change_with_stale_digest"] = "PASS"

    x = copy.deepcopy(p); x["manifest"]["obligations"][0]["evidence_keys"] = []
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and "REQUIRED_EVIDENCE_CONTRACT_MISMATCH:resolve" in r["errors"], r
    out["negative_required_evidence_contract_omission"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_steps"] = [x["execution_steps"][0]]
    x["recovery_state"] = {
        "step_id": "readback",
        "condition": "TIMEOUT_RECOVERING",
        "attempt": 1,
        "strategy": "RESUME_CHECKPOINT",
        "checkpoint_ref": "checkpoint://readback/1",
    }
    r = evaluate(x); assert r["result"] == "RECOVERING" and r["progress_percent"] == 33 and r["recovering_requirement_ids"] == ["WP-02"], r
    out["positive_timeout_recovery_preserves_progress"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_steps"] = []
    x["recovery_state"] = {
        "step_id": "resolve",
        "condition": "TIMEOUT_RECOVERING",
        "attempt": 1,
        "strategy": "REDUCE_UNIT",
        "checkpoint_ref": "checkpoint://resolve/1",
        "previous_work_unit": 100,
        "next_work_unit": 100,
    }
    r = evaluate(x); assert r["result"] == "BLOCKED" and "TIMEOUT_RECOVERY_STRATEGY_INVALID:WP-01" in r["errors"], r
    out["negative_timeout_recovery_requires_smaller_unit"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_steps"] = [x["execution_steps"][0]]
    x["recovery_state"] = {
        "step_id": "readback",
        "condition": "TIMEOUT_RECOVERING",
        "attempt": 4,
        "strategy": "RESUME_CHECKPOINT",
        "checkpoint_ref": "checkpoint://readback/4",
    }
    r = evaluate(x); assert r["result"] == "BLOCKED" and "BLOCKED_OPERATIONAL_TIMEOUT:WP-02" in r["blocking"], r
    out["negative_timeout_recovery_exhaustion_blocks_operationally"] = "PASS"

    x = copy.deepcopy(p)
    del x["execution_steps"][0]["evidence"]["work_protocol_gate"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("GATE_PACKET_MISSING_OR_INVALID:WP-01") for e in r["errors"]), r
    out["negative_gate_packet_missing_fails_closed"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_steps"][0]["evidence"]["work_protocol_gate"]["gate_contract_sha256"] = "9" * 64
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("GATE_CONTRACT_DIGEST_MISMATCH:WP-01") for e in r["errors"]), r
    out["negative_gate_contract_digest_mismatch"] = "PASS"

    x = copy.deepcopy(p)
    g = x["execution_steps"][0]["evidence"]["work_protocol_gate"]
    g["deterministic_result"] = "FAIL"
    g.pop("judge_result", None); g.pop("judge_seq", None)
    r = evaluate(x); assert r["result"] == "RETURN_TO_WORKER" and any(e.startswith("GATE_FAIL:WP-01") for e in r["errors"]), r
    out["negative_deterministic_fail_stops_before_judge"] = "PASS"

    x = copy.deepcopy(p)
    g = x["execution_steps"][0]["evidence"]["work_protocol_gate"]
    g["deterministic_result"] = "FAIL"
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("GATE_JUDGE_AFTER_DETERMINISTIC_NONPASS_FORBIDDEN:WP-01") for e in r["errors"]), r
    out["negative_judge_after_deterministic_fail_forbidden"] = "PASS"

    x = copy.deepcopy(p)
    g = x["execution_steps"][0]["evidence"]["work_protocol_gate"]
    g["judge_seq"] = g["deterministic_seq"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("GATE_JUDGE_BEFORE_DETERMINISTIC_FORBIDDEN:WP-01") for e in r["errors"]), r
    out["negative_judge_must_follow_deterministic"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_steps"][0]["evidence"]["work_protocol_gate"]["judge_result"] = "RETURN_TO_WORKER"
    r = evaluate(x); assert r["result"] == "RETURN_TO_WORKER" and any(e.startswith("GATE_FAIL:WP-01") for e in r["errors"]), r
    out["negative_canonical_return_normalizes_to_fail"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_steps"][0]["evidence"]["work_protocol_evidence"]["reproduction"]["reproduction_spec_sha256"] = "0" * 64
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("EVIDENCE_REPRODUCTION_SPEC_DIGEST_MISMATCH:WP-01") for e in r["errors"]), r
    out["negative_evidence_reproduction_digest_mismatch"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_started_at"] = "2026-09-20T12:00:00Z"
    x["execution_steps"][0]["evidence"]["work_protocol_evidence"]["observed_at"] = "2026-09-20T12:01:00Z"
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("EVIDENCE_STALE:WP-01") for e in r["errors"]), r
    out["negative_stale_evidence_blocks_progress"] = "PASS"

    x = copy.deepcopy(p)
    x["evidence_ledger_readback"] = x["evidence_ledger_readback"][1:]
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("EVIDENCE_LEDGER_RECEIPT_NOT_FOUND:WP-02") for e in r["errors"]), r
    out["negative_independent_evidence_requires_ledger_receipt"] = "PASS"

    x = copy.deepcopy(p)
    x["evidence_ledger_readback"][0]["created_by_execution_id"] = x["manifest"]["execution_id"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("EVIDENCE_INDEPENDENT_ACTOR_MISMATCH:WP-02") for e in r["errors"]), r
    out["negative_independent_evidence_forbids_producer_actor"] = "PASS"

    x = copy.deepcopy(p)
    x["evidence_ledger_readback"][0]["execution_id"] = "EXEC-OTHER-001"
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("EVIDENCE_LEDGER_EXECUTION_MISMATCH:WP-02") for e in r["errors"]), r
    out["negative_evidence_receipt_not_reusable_cross_execution"] = "PASS"

    x = copy.deepcopy(p)
    x["evidence_ledger_readback"][0]["verified_at"] = "2026-09-20T12:02:30Z"
    r = evaluate(x); assert r["result"] == "BLOCKED" and any(e.startswith("EVIDENCE_LEDGER_VERIFIED_BEFORE_OBSERVATION:WP-02") or e.startswith("EVIDENCE_LEDGER_STALE:WP-02") for e in r["errors"]), r
    out["negative_independent_ledger_freshness"] = "PASS"

    x = copy.deepcopy(p)
    x["manifest"]["obligations"][1]["verifier_mode"] = "DETERMINISTIC"
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and "VERIFIER_MODE_AUTHORITY_MISMATCH:readback" in r["errors"], r
    out["negative_verifier_mode_cannot_be_downgraded_by_producer"] = "PASS"

    x = copy.deepcopy(p)
    x["manifest"]["obligations"].append({
        "requirement_id": "WP-OPT-01",
        "step_id": "optional_advisory",
        "required": False,
        "evidence_keys": [],
        "verifier_mode": "DETERMINISTIC",
        "blocking": False,
        "close_required": False,
        "authority_ref": "operation",
        "execution_class": "ATOMIC",
        "timeout_recovery_mode": "RETRY_ATOMIC",
        "checkpoint_required": False,
        "idempotent": True,
        "gate_type": "STEP",
        "gate_contract_sha256": "9" * 64,
        "waiver_allowed": True,
        "irreversible_effect": False,
        "human_approval_required": False,
        "depends_on_step_ids": ["independent_close"],
        "closure_unit_id": "CU-04",
        "controller_order": 40,
        "execution_effect": "READ_ONLY",
        "parallel_safe": False,
    })
    x["manifest"]["waivers"] = [{
        "requirement_id": "WP-OPT-01",
        "reason": "Optional advisory is explicitly deferred for this bounded execution.",
        "residual_risk": "Advisory insight is unavailable until the next execution.",
        "authorized_by": "HUMAN-TEST-APPROVER",
        "authorization_ref": "human-approval://waiver/wp-opt-01",
        "authorization_sha256": "a" * 64,
        "expires_at": "2026-09-22T12:30:00Z",
    }]
    x["waiver_authority_readback"] = [{
        "requirement_id": "WP-OPT-01",
        "authorization_ref": "human-approval://waiver/wp-opt-01",
        "authorization_sha256": "a" * 64,
        "authorized_by": "HUMAN-TEST-APPROVER",
        "actor_type": "HUMAN",
        "verified": True,
    }]
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    refresh_closure_receipts(x)
    r = evaluate(x); assert r["result"] == "PASS_WITH_EVIDENCE" and r["active_waiver_count"] == 1, r
    out["positive_optional_waiver_with_human_readback"] = "PASS"

    x = copy.deepcopy(p)
    x["manifest"]["solution_isolation_policy"]["mixed_solution_pr_allowed"] = True
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"])
    x["manifest_readback"] = copy.deepcopy(x["manifest"])
    x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x)
    assert r["result"] == "BLOCKED" and "SOLUTION_ISOLATION_POLICY_INVALID:mixed_solution_pr_allowed" in r["errors"], r
    out["negative_mixed_solution_pr_forbidden"] = "PASS"

    x = copy.deepcopy(p)
    x["manifest"]["waivers"] = [{
        "requirement_id": "WP-01",
        "reason": "Attempt to waive a required obligation must be rejected by policy.",
        "residual_risk": "Required authority resolution would not be proven.",
        "authorized_by": "HUMAN-TEST-APPROVER",
        "authorization_ref": "human-approval://waiver/wp-01",
        "authorization_sha256": "a" * 64,
        "expires_at": "2026-09-22T12:30:00Z",
    }]
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x); assert r["result"] == "BLOCKED" and "WAIVER_REQUIRED_OBLIGATION_FORBIDDEN:WP-01" in r["errors"], r
    out["negative_required_obligation_waiver_forbidden"] = "PASS"

    x = copy.deepcopy(p)
    x["manifest"]["obligations"][0]["irreversible_effect"] = True
    x["manifest"]["obligations"][0]["human_approval_required"] = True
    x["authority_readback"]["required_steps"][0]["irreversible_effect"] = True
    x["authority_readback"]["required_steps"][0]["human_approval_required"] = True
    x["manifest"]["irreversible_approvals"] = [{
        "step_id": "resolve",
        "action_sha256": "f" * 64,
        "approved_by": "HUMAN-TEST-APPROVER",
        "approval_ref": "human-approval://irreversible/resolve",
        "approval_sha256": "e" * 64,
        "approved_at": "2026-09-22T11:59:00Z",
        "expires_at": "2026-09-22T12:30:00Z",
    }]
    x["human_approval_readback"] = [{
        "step_id": "resolve",
        "action_sha256": "f" * 64,
        "approved_by": "HUMAN-TEST-APPROVER",
        "approval_ref": "human-approval://irreversible/resolve",
        "approval_sha256": "e" * 64,
        "actor_type": "HUMAN",
        "verified": True,
    }]
    x["execution_steps"][0]["evidence"]["irreversible_action_sha256"] = "f" * 64
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    refresh_closure_receipts(x)
    r = evaluate(x); assert r["result"] == "PASS_WITH_EVIDENCE", r
    out["positive_irreversible_action_exact_human_approval"] = "PASS"

    y = copy.deepcopy(x)
    y["execution_steps"][0]["evidence"]["irreversible_action_sha256"] = "0" * 64
    r = evaluate(y); assert r["result"] == "BLOCKED" and any(e.startswith("IRREVERSIBLE_ACTION_APPROVAL_BINDING_MISMATCH:WP-01") for e in r["errors"]), r
    out["negative_irreversible_action_digest_mismatch"] = "PASS"

    y = copy.deepcopy(x)
    y["human_approval_readback"] = []
    r = evaluate(y); assert r["result"] == "BLOCKED" and "IRREVERSIBLE_HUMAN_APPROVAL_NOT_VERIFIED:resolve" in r["errors"], r
    out["negative_irreversible_action_missing_human_readback"] = "PASS"

    x = copy.deepcopy(p)
    old_scope = copy.deepcopy(x["manifest"]["authorized_scope"])
    new_scope = copy.deepcopy(old_scope)
    new_scope["read"] = old_scope["read"] + ["supabase://test/new-scope"]
    new_request = "9" * 64
    new_scope["authorization_ref"] = "request://test/002"
    new_scope["authorization_sha256"] = new_request
    x["manifest"]["request_sha256"] = new_request
    x["manifest"]["work_owner"]["declaration_ref"] = "request://test/002"
    x["manifest"]["work_owner"]["declaration_sha256"] = new_request
    x["manifest"]["authorized_scope"] = new_scope
    x["request_sha256_readback"] = new_request
    x["scope_authority_readback"] = {"authorization_ref": new_scope["authorization_ref"], "authorization_sha256": new_request}
    x["manifest"]["supersession"] = {
        "previous_execution_id": "EXEC-WPM-PREV-001",
        "previous_manifest_digest": "d" * 64,
        "change_authorization_ref": "request://test/002",
        "change_authorization_sha256": new_request,
        "change_reason": "Authorized scope expanded to include one additional read-only authority source.",
        "previous_scope_sha256": hashlib.sha256(canonical_bytes(old_scope)).hexdigest(),
        "new_scope_sha256": hashlib.sha256(canonical_bytes(new_scope)).hexdigest(),
        "revalidation_mode": "FULL_REQUIRED",
    }
    x["supersession_readback"] = {
        "execution_id": "EXEC-WPM-PREV-001",
        "manifest_digest": "d" * 64,
        "operation_code": x["manifest"]["operation_code"],
        "target": copy.deepcopy(x["manifest"]["target"]),
        "authorized_scope": old_scope,
    }
    x["change_authorization_readback"] = {
        "authorization_ref": "request://test/002",
        "authorization_sha256": new_request,
        "verified": True,
    }
    x["carried_forward_step_ids"] = []
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"]); x["manifest_readback"] = copy.deepcopy(x["manifest"]); x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    refresh_closure_receipts(x)
    r = evaluate(x); assert r["result"] == "PASS_WITH_EVIDENCE" and r["supersedes_execution_id"] == "EXEC-WPM-PREV-001", r
    out["positive_scope_change_supersession_full_revalidation"] = "PASS"

    y = copy.deepcopy(x)
    y["carried_forward_step_ids"] = ["resolve"]
    r = evaluate(y); assert r["result"] == "BLOCKED" and "SUPERSESSION_PROGRESS_CARRY_FORWARD_FORBIDDEN" in r["errors"], r
    out["negative_scope_change_carry_forward_forbidden"] = "PASS"

    y = copy.deepcopy(x)
    y["change_authorization_readback"]["verified"] = False
    r = evaluate(y); assert r["result"] == "BLOCKED" and "SUPERSESSION_CHANGE_AUTHORIZATION_NOT_VERIFIED" in r["errors"], r
    out["negative_scope_change_requires_new_verified_authorization"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_steps"] = []
    r = evaluate(x)
    assert r["result"] == "IN_PROGRESS" and r["controller"]["allowed_step_ids"] == ["resolve"], r
    out["positive_controller_initial_frontier"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_steps"] = [copy.deepcopy(p["execution_steps"][0])]
    r = evaluate(x)
    assert r["result"] == "IN_PROGRESS" and r["controller"]["allowed_step_ids"] == ["readback"], r
    out["positive_controller_dependency_advance"] = "PASS"

    x = copy.deepcopy(p)
    x["execution_steps"] = [copy.deepcopy(p["execution_steps"][0])]
    x["execution_steps"][0]["status"] = "BLOCKED"
    r = evaluate(x)
    assert "readback" in r["controller"]["blocked_by_predecessor_step_ids"], r
    out["negative_controller_failed_predecessor_blocks_dependent"] = "PASS"

    x = copy.deepcopy(p)
    x["manifest"]["obligations"][0]["depends_on_step_ids"] = ["independent_close"]
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"])
    x["manifest_readback"] = copy.deepcopy(x["manifest"])
    x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x)
    assert r["result"] == "BLOCKED" and "CONTROLLER_DAG_CYCLE" in r["errors"], r
    out["negative_controller_cycle_rejected"] = "PASS"

    x = copy.deepcopy(p)
    x["manifest"]["obligations"][0]["parallel_safe"] = True
    x["manifest"]["obligations"][0]["execution_effect"] = "MUTATING"
    x["manifest"]["manifest_digest"] = digest_without_self(x["manifest"])
    x["manifest_readback"] = copy.deepcopy(x["manifest"])
    x["persisted_manifest_digest"] = x["manifest"]["manifest_digest"]
    r = evaluate(x)
    assert r["result"] == "BLOCKED" and "CONTROLLER_PARALLEL_NON_READ_ONLY_FORBIDDEN:WP-01" in r["errors"], r
    out["negative_controller_parallel_mutation_forbidden"] = "PASS"

    m2 = copy.deepcopy(p["manifest"])
    m2["obligations"] = [
        {
            **copy.deepcopy(m2["obligations"][0]),
            "requirement_id": "PX-01", "step_id": "ro_a",
            "depends_on_step_ids": [], "closure_unit_id": "CU-P", "controller_order": 10,
            "execution_effect": "READ_ONLY", "parallel_safe": True,
        },
        {
            **copy.deepcopy(m2["obligations"][0]),
            "requirement_id": "PX-02", "step_id": "ro_b",
            "depends_on_step_ids": [], "closure_unit_id": "CU-P", "controller_order": 20,
            "execution_effect": "READ_ONLY", "parallel_safe": True,
        },
        {
            **copy.deepcopy(m2["obligations"][0]),
            "requirement_id": "PX-03", "step_id": "mutate",
            "depends_on_step_ids": [], "closure_unit_id": "CU-M", "controller_order": 30,
            "execution_effect": "MUTATING", "parallel_safe": False,
        },
    ]
    plan = _derive_controller_frontier(m2, {}, set())
    assert plan["active_closure_unit_id"] == "CU-P" and plan["allowed_step_ids"] == ["ro_a", "ro_b"], plan
    out["positive_controller_parallel_read_only_same_unit"] = "PASS"

    plan = _derive_controller_frontier(m2, {}, {"ro_a", "ro_b"})
    assert plan["active_closure_unit_id"] == "CU-M" and plan["allowed_step_ids"] == ["mutate"], plan
    out["positive_controller_material_wip_one"] = "PASS"

    steps_by_id = {s["step_id"]: copy.deepcopy(s) for s in p["execution_steps"]}
    verified_ids = {"resolve", "readback", "independent_close"}

    closure = _derive_closure_controller(p["manifest"], steps_by_id, verified_ids, [])
    assert closure["units"][0]["state"] == "READY_TO_CLOSE", closure
    assert closure["units"][1]["state"] == "WAITING_PREVIOUS_CLOSURE", closure
    assert closure["global_close_allowed"] is False, closure
    out["negative_closure_before_next_required"] = "PASS"

    closure = _derive_closure_controller(
        p["manifest"], steps_by_id, verified_ids, p["closure_ledger_readback"][:1]
    )
    assert closure["units"][0]["state"] == "CLOSED_WITH_EVIDENCE", closure
    assert closure["units"][1]["state"] == "READY_TO_CLOSE", closure
    assert closure["units"][2]["state"] == "WAITING_PREVIOUS_CLOSURE", closure
    out["positive_sequential_closure_advances_one_unit"] = "PASS"

    blocked_steps = {"resolve": copy.deepcopy(steps_by_id["resolve"])}
    blocked_steps["resolve"]["status"] = "BLOCKED"
    blocked_base = _derive_closure_controller(p["manifest"], blocked_steps, set(), [])
    first = blocked_base["units"][0]
    blocked_receipt_sha = _sha256_text(
        f"{p['manifest']['execution_id']}|{first['closure_unit_id']}|{first['unit_state_sha256']}|blocked"
    )
    blocked_receipt = {
        "receipt_seq": 1,
        "execution_id": p["manifest"]["execution_id"],
        "closure_unit_id": first["closure_unit_id"],
        "manifest_digest": p["manifest"]["manifest_digest"],
        "unit_state_sha256": first["unit_state_sha256"],
        "outcome": "BLOCKED_WITH_EVIDENCE",
        "previous_unit_receipt_sha256": None,
        "receipt_sha256": blocked_receipt_sha,
        "verified": True,
    }
    closure = _derive_closure_controller(
        p["manifest"], blocked_steps, set(), [blocked_receipt]
    )
    assert closure["units"][0]["state"] == "BLOCKED_WITH_EVIDENCE", closure
    assert closure["closure_debt_count"] == 1 and closure["global_close_allowed"] is False, closure
    out["positive_blocked_with_evidence_creates_closure_debt"] = "PASS"

    stale_steps = copy.deepcopy(steps_by_id)
    stale_steps["resolve"]["closure_probe_mutation"] = "changed-after-close"
    closure = _derive_closure_controller(
        p["manifest"], stale_steps, verified_ids, p["closure_ledger_readback"]
    )
    assert closure["units"][0]["state"] == "REOPEN_REQUIRED", closure
    assert closure["reopen_required_count"] >= 1 and closure["global_close_allowed"] is False, closure
    out["negative_closed_unit_digest_change_reopens"] = "PASS"

    broken_chain = copy.deepcopy(p["closure_ledger_readback"])
    broken_chain[0]["receipt_sha256"] = "f" * 64
    closure = _derive_closure_controller(
        p["manifest"], steps_by_id, verified_ids, broken_chain
    )
    assert closure["units"][0]["state"] == "CLOSED_WITH_EVIDENCE", closure
    assert closure["units"][1]["state"] == "REOPEN_REQUIRED", closure
    assert closure["global_close_allowed"] is False, closure
    out["negative_closure_receipt_chain_break_reopens_downstream"] = "PASS"

    closure = _derive_closure_controller(
        p["manifest"], steps_by_id, verified_ids, p["closure_ledger_readback"]
    )
    assert closure["closure_debt_count"] == 0 and closure["reopen_required_count"] == 0, closure
    assert closure["global_close_allowed"] is True, closure
    out["positive_zero_debt_allows_global_close"] = "PASS"
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    output: dict[str, Any] = {}
    if a.self_test:
        output["self_test"] = {"status": "PASS", "cases": self_test()}
    if a.input:
        output["evaluation"] = evaluate(json.loads(Path(a.input).read_text(encoding="utf-8")))
    if not output:
        ap.error("provide --self-test and/or --input")
    print(json.dumps(output, indent=2, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
