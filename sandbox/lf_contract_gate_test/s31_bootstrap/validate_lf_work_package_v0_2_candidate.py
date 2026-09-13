#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Callable, Mapping

from jsonschema import Draft7Validator

PASS = "PASS"
BLOCKED = "BLOCKED"
CONTINUE = "CONTINUE_SAFE_PARALLEL"
ROOT = Path(__file__).resolve().parent
SCHEMA_PATH = ROOT / "lf_work_package_v0_2_candidate.schema.json"
EvidenceResolver = Callable[[str], Mapping[str, Any] | None]


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def _nonempty(v: Any) -> bool:
    if isinstance(v, str):
        return bool(v.strip())
    if isinstance(v, (list, dict)):
        return bool(v)
    return v is not None


def _normalized_batch(v: Any) -> str | None:
    if not _nonempty(v):
        return None
    text = str(v)
    return None if text.upper() in {"NONE", "N/A"} else text


def _canonical_digest(record: Mapping[str, Any]) -> str:
    raw = json.dumps(dict(record), sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _resolve_evidence(
    wp: Mapping[str, Any],
    binding_key: str,
    expected_type: str,
    evidence_resolver: EvidenceResolver | None,
) -> tuple[dict, Mapping[str, Any] | None]:
    binding = ((wp.get("resolved_evidence") or {}).get(binding_key))
    if not isinstance(binding, Mapping):
        return _block("BLOCK_RESOLVED_EVIDENCE_BINDING_MISSING", binding=binding_key), None
    if evidence_resolver is None:
        return _block("BLOCK_EVIDENCE_RESOLVER_MISSING", binding=binding_key), None
    ref = binding.get("ref")
    expected_digest = binding.get("digest")
    declared_resolver = binding.get("resolver_id")
    try:
        record = evidence_resolver(str(ref))
    except Exception as exc:
        return _block("BLOCK_EVIDENCE_RESOLUTION_FAILED", binding=binding_key, error=type(exc).__name__), None
    if not isinstance(record, Mapping):
        return _block("BLOCK_EVIDENCE_UNRESOLVED", binding=binding_key, ref=ref), None
    observed_digest = _canonical_digest(record)
    if observed_digest != expected_digest:
        return _block(
            "BLOCK_EVIDENCE_DIGEST_MISMATCH",
            binding=binding_key,
            expected=expected_digest,
            observed=observed_digest,
        ), None
    if record.get("evidence_type") != expected_type:
        return _block(
            "BLOCK_EVIDENCE_TYPE_MISMATCH",
            binding=binding_key,
            expected=expected_type,
            observed=record.get("evidence_type"),
        ), None
    if record.get("status") != "PASS":
        return _block("BLOCK_RESOLVED_EVIDENCE_NOT_PASS", binding=binding_key, status=record.get("status")), None
    if record.get("resolver_id") != declared_resolver:
        return _block("BLOCK_EVIDENCE_RESOLVER_ID_MISMATCH", binding=binding_key), None
    worker = ((wp.get("execution") or {}).get("worker"))
    if declared_resolver == worker:
        return _block("BLOCK_EVIDENCE_SELF_RESOLVER", binding=binding_key, resolver_id=declared_resolver), None
    return {"status": PASS, "code": "PASS_RESOLVED_EVIDENCE", "binding": binding_key}, record


def validate_schema_instance(wp: Mapping[str, Any]) -> dict:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    Draft7Validator.check_schema(schema)
    validator = Draft7Validator(schema)
    errors = sorted(validator.iter_errors(dict(wp)), key=lambda e: list(e.path))
    if errors:
        return _block(
            "BLOCK_SCHEMA_VALIDATION",
            errors=[{"path":"/".join(map(str, err.path)), "message":err.message} for err in errors[:20]],
        )
    return {"status": PASS, "code": "PASS_SCHEMA_VALIDATION"}


def validate_source_bindings(wp: Mapping[str, Any]) -> dict:
    bindings = wp.get("source_snapshot_bindings")
    if not isinstance(bindings, list) or not bindings:
        return _block("BLOCK_SOURCE_BINDINGS_MISSING")
    for i, b in enumerate(bindings):
        if not isinstance(b, Mapping):
            return _block("BLOCK_SOURCE_BINDING_INVALID", index=i)
        if b.get("material") is True:
            kind = b.get("binding_kind")
            if kind in {"GIT_COMMIT", "GIT_BLOB"} and not _nonempty(b.get("revision")):
                return _block("BLOCK_MATERIAL_SOURCE_REVISION_MISSING", index=i)
            if kind == "SHA256" and not _nonempty(b.get("digest")):
                return _block("BLOCK_MATERIAL_SOURCE_DIGEST_MISSING", index=i)
            if kind == "LIVE_AUTHORITY_RECEIPT" and not _nonempty(b.get("authority_receipt_ref")):
                return _block("BLOCK_MATERIAL_SOURCE_AUTHORITY_RECEIPT_MISSING", index=i)
    return {"status": PASS, "code": "PASS_SOURCE_BINDINGS"}


def validate_currentness(wp: Mapping[str, Any], evidence_resolver: EvidenceResolver | None) -> dict:
    x = wp.get("execution_identity") or {}
    kind = x.get("execution_ref_kind")
    head = x.get("branch_head_sha")
    executed = x.get("executed_sha")
    if x.get("exact_head_claim") is True:
        if kind != "BRANCH_HEAD":
            return _block("BLOCK_EXACT_HEAD_REF_KIND_INVALID")
        if head != executed:
            return _block("BLOCK_EXACT_HEAD_SHA_MISMATCH")
    if kind == "PR_MERGE_REF" and x.get("exact_head_claim") is True:
        return _block("BLOCK_PR_MERGE_REF_MISLABELED_EXACT_HEAD")

    resolved, receipt = _resolve_evidence(wp, "currentness_receipt", "CURRENTNESS_RECEIPT", evidence_resolver)
    if resolved.get("status") != PASS:
        return resolved
    expected = {
        "base_sha": x.get("base_sha"),
        "branch_head_sha": head,
        "executed_sha": executed,
        "execution_ref_kind": kind,
        "exact_head_claim": x.get("exact_head_claim"),
    }
    mismatches = {k: {"expected": v, "observed": receipt.get(k)} for k, v in expected.items() if receipt.get(k) != v}
    if mismatches:
        return _block("BLOCK_CURRENTNESS_RECEIPT_IDENTITY_MISMATCH", mismatches=mismatches)
    if ((wp.get("close_guard") or {}).get("currentness_verified")) is not True:
        return _block("BLOCK_CURRENTNESS_DECLARATION_NOT_VERIFIED")
    return {"status": PASS, "code": "PASS_CURRENTNESS"}


def validate_ekb(wp: Mapping[str, Any], evidence_resolver: EvidenceResolver | None) -> dict:
    ekb = ((wp.get("authority") or {}).get("ekb_execution_binding") or {})
    if ekb.get("fresh_for_execution") is not True:
        return _block("BLOCK_EKB_BINDING_NOT_FRESH")
    if not _nonempty(ekb.get("run_id")) or not _nonempty(ekb.get("resolved_at")):
        return _block("BLOCK_EKB_EXECUTION_IDENTITY_MISSING")
    codes = ekb.get("applicable_codes")
    mapping = ekb.get("control_mapping")
    if not isinstance(codes, list) or not isinstance(mapping, Mapping):
        return _block("BLOCK_EKB_APPLICABILITY_SHAPE")
    missing = [c for c in codes if c not in mapping or not _nonempty(mapping.get(c))]
    if missing:
        return _block("BLOCK_EKB_CONTROL_MAPPING_MISSING", missing=missing)

    resolved, receipt = _resolve_evidence(wp, "ekb_freshness_receipt", "EKB_FRESHNESS_RECEIPT", evidence_resolver)
    if resolved.get("status") != PASS:
        return resolved
    expected = {
        "run_id": ekb.get("run_id"),
        "resolved_at": ekb.get("resolved_at"),
        "applicable_codes": codes,
        "control_mapping": dict(mapping),
    }
    mismatches = {k: {"expected": v, "observed": receipt.get(k)} for k, v in expected.items() if receipt.get(k) != v}
    if mismatches:
        return _block("BLOCK_EKB_RECEIPT_MISMATCH", mismatches=mismatches)
    return {"status": PASS, "code": "PASS_EKB_BINDING"}


def validate_executed_validation(wp: Mapping[str, Any], evidence_resolver: EvidenceResolver | None) -> dict:
    ev = ((wp.get("execution") or {}).get("executed_validation") or {})
    if ev.get("required") is not True:
        return {"status": PASS, "code": "PASS_VALIDATION_NOT_REQUIRED"}
    if not _nonempty(ev.get("command_or_runner")):
        return _block("BLOCK_VALIDATOR_NOT_EXECUTED")
    if not _nonempty(ev.get("executed_sha")) or ev.get("exit_status") is None or not _nonempty(ev.get("receipt_ref")):
        return _block("BLOCK_VALIDATION_EXECUTION_RECEIPT_INCOMPLETE")
    if ev.get("exit_status") != 0:
        return _block("BLOCK_EXECUTED_VALIDATION_FAILED", exit_status=ev.get("exit_status"))

    identity_sha = ((wp.get("execution_identity") or {}).get("executed_sha"))
    if ev.get("executed_sha") != identity_sha:
        return _block(
            "BLOCK_VALIDATION_EXECUTED_SHA_IDENTITY_MISMATCH",
            execution_identity_sha=identity_sha,
            validation_sha=ev.get("executed_sha"),
        )
    binding = ((wp.get("resolved_evidence") or {}).get("executed_validation_receipt") or {})
    if binding.get("ref") != ev.get("receipt_ref"):
        return _block("BLOCK_VALIDATION_RECEIPT_REF_MISMATCH")
    resolved, receipt = _resolve_evidence(wp, "executed_validation_receipt", "EXECUTED_VALIDATION_RECEIPT", evidence_resolver)
    if resolved.get("status") != PASS:
        return resolved
    expected = {
        "executed_sha": identity_sha,
        "command_or_runner": ev.get("command_or_runner"),
        "exit_status": ev.get("exit_status"),
    }
    mismatches = {k: {"expected": v, "observed": receipt.get(k)} for k, v in expected.items() if receipt.get(k) != v}
    if mismatches:
        return _block("BLOCK_VALIDATION_RECEIPT_CONTENT_MISMATCH", mismatches=mismatches)
    return {"status": PASS, "code": "PASS_EXECUTED_VALIDATION"}


def validate_repair_policy(wp: Mapping[str, Any]) -> dict:
    rp = wp.get("repair_policy") or {}
    if rp.get("bounded") is not True:
        return _block("BLOCK_UNBOUNDED_REPAIR")
    if rp.get("requires_new_evidence_after_failure") is not True:
        return _block("BLOCK_RETRY_WITHOUT_NEW_EVIDENCE_ALLOWED")
    if rp.get("silent_repair_forbidden") is not True:
        return _block("BLOCK_SILENT_REPAIR_ALLOWED")
    retry = ((wp.get("execution") or {}).get("retry_policy") or {})
    if retry.get("same_failure_retries_forbidden") is not True:
        return _block("BLOCK_SAME_FAILURE_RETRY_ALLOWED")
    attempts = retry.get("max_attempts")
    if not isinstance(attempts, int) or attempts < 1 or attempts > 5:
        return _block("BLOCK_RETRY_BOUND_INVALID")
    return {"status": PASS, "code": "PASS_REPAIR_POLICY"}


def validate_frontier_close_consistency(wp: Mapping[str, Any]) -> dict:
    frontier = wp.get("frontier") or {}
    close = wp.get("close_guard") or {}
    safe = frontier.get("safe_parallel_work")
    remaining = frontier.get("remaining_safe_scope_count")
    if not isinstance(safe, list) or not isinstance(remaining, int):
        return _block("BLOCK_FRONTIER_INVALID")
    if len(safe) != len(set(safe)):
        return _block("BLOCK_SAFE_WORK_DUPLICATE")
    if remaining != len(safe):
        return _block("BLOCK_SAFE_WORK_COUNT_MISMATCH", remaining=remaining, listed=len(safe))
    frontier_batch = _normalized_batch(frontier.get("next_safe_batch"))
    if remaining == 0 and frontier_batch is not None:
        return _block("BLOCK_NEXT_SAFE_BATCH_WITH_ZERO_COUNT", next_safe_batch=frontier_batch)
    if remaining > 0:
        if frontier_batch is None:
            return _block("BLOCK_SAFE_WORK_FRONTIER_INCONSISTENT")
        if frontier_batch not in safe:
            return _block("BLOCK_NEXT_SAFE_BATCH_NOT_LISTED", next_safe_batch=frontier_batch)
    if close.get("safe_work_remaining_count") != remaining:
        return _block(
            "BLOCK_FRONTIER_CLOSE_COUNT_MISMATCH",
            frontier=remaining,
            close_guard=close.get("safe_work_remaining_count"),
        )
    close_batch = _normalized_batch(close.get("next_safe_batch"))
    if close_batch != frontier_batch:
        return _block(
            "BLOCK_FRONTIER_CLOSE_BATCH_MISMATCH",
            frontier=frontier_batch,
            close_guard=close_batch,
        )
    if close.get("global_remaining_work_scan") != frontier.get("global_remaining_work_scan"):
        return _block("BLOCK_FRONTIER_CLOSE_SCAN_MISMATCH")
    return {"status": PASS, "code": "PASS_FRONTIER_CLOSE_CONSISTENCY"}


def continuation_decision(wp: Mapping[str, Any]) -> dict:
    frontier = wp.get("frontier") or {}
    blockers = frontier.get("blockers")
    safe = frontier.get("safe_parallel_work")
    remaining = frontier.get("remaining_safe_scope_count")
    next_batch = _normalized_batch(frontier.get("next_safe_batch"))
    if not isinstance(blockers, list) or not isinstance(safe, list) or not isinstance(remaining, int):
        return _block("BLOCK_FRONTIER_INVALID")
    for i, blocker in enumerate(blockers):
        if not isinstance(blocker, Mapping):
            return _block("BLOCK_BLOCKER_SHAPE", index=i)
        independent = blocker.get("independent_safe_work")
        if not isinstance(independent, list):
            return _block("BLOCK_BLOCKER_SAFE_WORK_NOT_LIST", index=i)
    if remaining > 0:
        return {
            "status": CONTINUE,
            "code": "CONTINUE_SAFE_SCOPE_PERSIST_BLOCKED_SCOPE",
            "remaining_safe_scope_count": remaining,
            "next_safe_batch": next_batch,
        }
    if blockers:
        return _block(
            "BLOCKED_CAUSAL_NO_SAFE_WORK",
            blockers=[b.get("code") for b in blockers if isinstance(b, Mapping)],
        )
    return {"status": PASS, "code": "PASS_NO_SAFE_SCOPE_REMAINING"}


def evaluate_close_guard(wp: Mapping[str, Any], evidence_resolver: EvidenceResolver | None) -> dict:
    cg = wp.get("close_guard") or {}
    remaining = cg.get("safe_work_remaining_count")
    next_batch = _normalized_batch(cg.get("next_safe_batch"))
    reasons = []
    if remaining != 0:
        reasons.append("SAFE_WORK_REMAINING_NONZERO_OR_UNKNOWN")
    if next_batch is not None:
        reasons.append("NEXT_SAFE_BATCH_PRESENT")
    if cg.get("global_remaining_work_scan") != "PASS":
        reasons.append("GLOBAL_REMAINING_WORK_SCAN_NOT_PASS")
    if cg.get("ekb_final_readback_verified") is not True:
        reasons.append("EKB_FINAL_READBACK_NOT_VERIFIED")
    if cg.get("currentness_verified") is not True:
        reasons.append("CURRENTNESS_NOT_VERIFIED")
    if cg.get("terminal_disposition_complete") is not True:
        reasons.append("TERMINAL_DISPOSITION_INCOMPLETE")
    declared = cg.get("can_close")
    actual = not reasons
    if declared is True and not actual:
        reasons.append("DECLARED_CLOSE_CONTRADICTS_GUARD")
    if reasons:
        return _block("BLOCK_CLOSE_GUARD", reasons=reasons, can_close=False)

    resolved, receipt = _resolve_evidence(wp, "ekb_final_readback_receipt", "EKB_FINAL_READBACK_RECEIPT", evidence_resolver)
    if resolved.get("status") != PASS:
        return resolved
    identity_sha = ((wp.get("execution_identity") or {}).get("executed_sha"))
    ekb = ((wp.get("authority") or {}).get("ekb_execution_binding") or {})
    if receipt.get("executed_sha") != identity_sha or receipt.get("applicable_codes") != ekb.get("applicable_codes"):
        return _block("BLOCK_EKB_FINAL_READBACK_RECEIPT_MISMATCH")
    return {"status": PASS, "code": "PASS_CLOSE_GUARD", "can_close": True}


def validate_judge(wp: Mapping[str, Any]) -> dict:
    j = wp.get("judge") or {}
    if j.get("independent_required") is not True:
        return _block("BLOCK_INDEPENDENT_JUDGE_NOT_REQUIRED")
    if j.get("self_certification_forbidden") is not True:
        return _block("BLOCK_SELF_CERTIFICATION_NOT_FORBIDDEN")
    if not _nonempty(j.get("binding")):
        return _block("BLOCK_JUDGE_BINDING_MISSING")
    return {"status": PASS, "code": "PASS_JUDGE_POLICY"}


def evaluate_work_package(wp: Mapping[str, Any], evidence_resolver: EvidenceResolver | None = None) -> dict:
    schema_result = validate_schema_instance(wp)
    if schema_result.get("status") != PASS:
        return schema_result
    checks = [
        validate_source_bindings,
        lambda x: validate_currentness(x, evidence_resolver),
        lambda x: validate_ekb(x, evidence_resolver),
        lambda x: validate_executed_validation(x, evidence_resolver),
        validate_repair_policy,
        validate_judge,
        validate_frontier_close_consistency,
    ]
    for check in checks:
        result = check(wp)
        if result.get("status") != PASS:
            return result
    continuation = continuation_decision(wp)
    if continuation.get("status") == CONTINUE:
        close = evaluate_close_guard(wp, evidence_resolver)
        if close.get("status") == PASS:
            return _block("BLOCK_CLOSE_ALLOWED_WHILE_SAFE_WORK_REMAINS")
        return continuation
    if continuation.get("status") != PASS:
        return continuation
    return evaluate_close_guard(wp, evidence_resolver)


def _mapping_resolver(path: Path) -> EvidenceResolver:
    mapping = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(mapping, Mapping):
        raise ValueError("evidence map must be an object keyed by receipt ref")
    return lambda ref: mapping.get(ref)


if __name__ == "__main__":
    import sys
    if len(sys.argv) not in {2, 3}:
        raise SystemExit("usage: validate_lf_work_package_v0_2_candidate.py <work-package.json> [evidence-map.json]")
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    resolver = _mapping_resolver(Path(sys.argv[2])) if len(sys.argv) == 3 else None
    result = evaluate_work_package(data, resolver)
    print(json.dumps(result, sort_keys=True))
    raise SystemExit(0 if result.get("status") in {PASS, CONTINUE} else 1)
