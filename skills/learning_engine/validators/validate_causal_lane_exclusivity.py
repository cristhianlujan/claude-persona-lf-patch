#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

HEX40 = re.compile(r"^[0-9a-f]{40}$")
ROLES = {"WRITER", "REVIEWER_READ_ONLY"}
CLAIM_OK = {"OWNERSHIP_ACQUIRED", "OWNERSHIP_REUSED_IDEMPOTENT"}


def canonical_part(value):
    return str(value or "").strip().upper()


def canonical_key(ekb_code, target_asset, primary_gate):
    return "|".join([
        canonical_part(ekb_code),
        canonical_part(target_asset),
        canonical_part(primary_gate),
    ])


def result(status, blocking_code=None, next_state=None, details=None):
    return {
        "status": status,
        "blocking_code": blocking_code,
        "next_state": next_state,
        "details": details or {},
    }


def validate(payload):
    lane = payload.get("lane_contract") or {}
    role = canonical_part(lane.get("role"))
    ekb_code = canonical_part(lane.get("ekb_code"))
    target_asset = canonical_part(lane.get("target_asset"))
    primary_gate = canonical_part(lane.get("primary_gate"))
    owner = str(lane.get("owner") or "").strip()
    execution_id = str(lane.get("execution_id") or "").strip()
    declared_key = canonical_part(lane.get("causal_lane_key"))
    computed_key = canonical_key(ekb_code, target_asset, primary_gate)

    if role not in ROLES:
        return result("BLOCK", "BLOCK_CAUSAL_LANE_ROLE_INVALID", "RETURN_TO_ROUTER")
    if not ekb_code or not target_asset or not primary_gate or not owner:
        return result("BLOCK", "BLOCK_CAUSAL_LANE_IDENTITY_INCOMPLETE", "RETURN_TO_ROUTER")
    if declared_key != computed_key:
        return result("BLOCK", "BLOCK_CAUSAL_LANE_KEY_MISMATCH", "RETURN_TO_ROUTER", {"declared": declared_key, "computed": computed_key})

    counts = {
        "lane": lane.get("declared_lane_count"),
        "owner": lane.get("declared_owner_count"),
        "gate": lane.get("declared_primary_gate_count"),
    }
    if counts != {"lane": 1, "owner": 1, "gate": 1}:
        return result("BLOCK", "BLOCK_PR_LANE_SCOPE_INVALID", "RETURN_TO_ROUTER", counts)

    write_intent = payload.get("write_intent") is True
    if role == "REVIEWER_READ_ONLY":
        if write_intent:
            return result("BLOCK", "BLOCK_REVIEWER_WRITE_FORBIDDEN", "RETURN_TO_ROUTER")
        return result("ALLOW_READ_ONLY_PARALLEL", None, "REVIEW_ONLY", {"causal_lane_key": computed_key})

    if not execution_id:
        return result("BLOCK", "BLOCK_CAUSAL_LANE_EXECUTION_ID_REQUIRED", "RETURN_TO_ROUTER")

    currentness = payload.get("currentness") or {}
    base_sha = str(currentness.get("base_main_sha") or "").strip().lower()
    current_sha = str(currentness.get("current_main_sha") or "").strip().lower()
    currentness_ok = (
        currentness.get("checked") is True
        and currentness.get("source") == "GITHUB_PUBLIC_API_EXACT_REF_V1"
        and bool(HEX40.fullmatch(base_sha))
        and base_sha == current_sha
    )
    if not currentness_ok:
        return result("BLOCK", "BLOCK_FRESH_MAIN_CURRENTNESS_REQUIRED", "WAITING_UPSTREAM", {"base_main_sha": base_sha, "current_main_sha": current_sha})

    predecessor = payload.get("predecessor") or {}
    if predecessor.get("exists") is True and predecessor.get("same_key") is True and predecessor.get("closed") is True:
        if currentness.get("stale_receipts_invalidated") is not True:
            return result("BLOCK", "BLOCK_STALE_RECEIPTS_NOT_INVALIDATED", "WAITING_UPSTREAM")

    active = []
    for item in payload.get("active_writers") or []:
        if not isinstance(item, dict):
            continue
        if item.get("active") is not True:
            continue
        if canonical_part(item.get("role") or "WRITER") != "WRITER":
            continue
        if canonical_part(item.get("causal_lane_key")) != computed_key:
            continue
        active.append(item)

    distinct = {(str(x.get("owner") or ""), str(x.get("execution_id") or "")) for x in active}
    if len(distinct) > 1:
        return result("BLOCK", "BLOCK_CAUSAL_LANE_CARDINALITY_BREACH", "WAITING_UPSTREAM", {"active_writer_count": len(distinct)})

    if active:
        existing = active[0]
        same_owner = str(existing.get("owner") or "") == owner
        same_execution = str(existing.get("execution_id") or "") == execution_id
        if not (same_owner and same_execution):
            return result("BLOCK", "BLOCK_CAUSAL_LANE_ALREADY_OWNED", "WAITING_UPSTREAM", {"current_owner": existing.get("owner"), "current_execution_id": existing.get("execution_id")})

    claim = payload.get("claim_readback")
    if not isinstance(claim, dict):
        return result("BLOCK", "BLOCK_SUPABASE_CLAIM_REQUIRED", "RETURN_TO_ROUTER")
    if claim.get("authority") != "SUPABASE" or claim.get("result") not in CLAIM_OK:
        return result("BLOCK", "BLOCK_SUPABASE_CLAIM_REQUIRED", "RETURN_TO_ROUTER")

    exact_claim = (
        canonical_part(claim.get("causal_lane_key")) == computed_key
        and str(claim.get("owner") or "") == owner
        and str(claim.get("execution_id") or "") == execution_id
        and claim.get("active") is True
    )
    if not exact_claim:
        return result("BLOCK", "BLOCK_SUPABASE_CLAIM_MISMATCH", "RETURN_TO_ROUTER")

    if active:
        return result("ALLOW_EXISTING_WRITER", None, "CONTINUE_CURRENT_GATE", {"causal_lane_key": computed_key})
    return result("ALLOW_WRITER", None, "CONTINUE_CURRENT_GATE", {"causal_lane_key": computed_key})


def run_self_test(matrix_path):
    matrix = json.loads(Path(matrix_path).read_text(encoding="utf-8"))
    failures = []
    cases = matrix.get("cases") or []
    for case in cases:
        actual = validate(case.get("input") or {})
        expected_status = case.get("expected_status")
        expected_block = case.get("expected_blocking_code")
        if actual.get("status") != expected_status or actual.get("blocking_code") != expected_block:
            failures.append({
                "id": case.get("id"),
                "expected_status": expected_status,
                "actual_status": actual.get("status"),
                "expected_blocking_code": expected_block,
                "actual_blocking_code": actual.get("blocking_code"),
            })
    out = {"status": "PASS" if not failures else "FAIL", "cases": len(cases), "failures": failures}
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if not failures else 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--self-test":
        return run_self_test(sys.argv[2])
    if len(sys.argv) != 2:
        print("usage: validate_causal_lane_exclusivity.py <payload.json> | --self-test <matrix.json>", file=sys.stderr)
        return 2
    payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = validate(payload)
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["status"].startswith("ALLOW") else 1


if __name__ == "__main__":
    raise SystemExit(main())
