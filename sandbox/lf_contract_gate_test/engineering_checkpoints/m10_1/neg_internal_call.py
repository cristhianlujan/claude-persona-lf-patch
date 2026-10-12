#!/usr/bin/env python3
"""M10.1 NEG_INTERNAL_CALL: validate live SQL external-consumer boundary.
Read-only; actual PG catalog rows must be obtained through the declared
governed Supabase read channel. Never treat mock controls as execution proof.
Private IG implementation calls by an IG core function are not external
consumption. Public façade shims are the *only* permitted public delegates.
"""
import hashlib
import json
import os
import sys

PLAN = "IG_CURATOR_VALIDATOR_REFACTOR_V2"
UNIT = "M10.1"
CP = "NEG_INTERNAL_CALL"
SCHEMA = "IG_M101_EXTERNAL_CONSUMER_PG_PROC_SNAPSHOT_V1"


def check(snapshot):
    problems = []
    if snapshot.get("schema_version") != SCHEMA:
        problems.append("UNKNOWN_SNAPSHOT_SCHEMA")
    if snapshot.get("plan_code") != PLAN or snapshot.get("unit_code") != UNIT:
        problems.append("WRONG_GOVERNED_UNIT")
    if snapshot.get("checkpoint_code") != CP:
        problems.append("WRONG_CHECKPOINT")
    if snapshot.get("source") != "pg_catalog.pg_proc":
        problems.append("NOT_CANONICAL_PG_PROC")
    if snapshot.get("selection_contract") != "PUBLIC_NON_FACADE_PLUS_ROUTER_EXTERNAL_SQL_ENTRYPOINTS":
        problems.append("UNBOUND_EXTERNAL_ENTRYPOINT_SCOPE")
    if not isinstance(snapshot.get("scanned_entrypoints"), int) or snapshot["scanned_entrypoints"] < 1:
        problems.append("EMPTY_OR_UNCOUNTED_SCAN")
    if not isinstance(snapshot.get("public_facade_count"), int) or snapshot["public_facade_count"] < 2:
        problems.append("FACADE_NOT_READ_BACK")
    if not isinstance(snapshot.get("router_source_sha256"), str) or len(snapshot["router_source_sha256"]) != 64:
        problems.append("ROUTER_SOURCE_UNVERIFIED")
    violations = snapshot.get("external_private_calls")
    if not isinstance(violations, list):
        problems.append("MISSING_PRIVATE_CALL_RESULTS")
        violations = []
    if snapshot.get("reported_direct_calls") != len(violations):
        problems.append("INCONSISTENT_SCAN_COUNT")
    if violations:
        problems.append("EXTERNAL_CALLS_PRIVATE_IG")
    return problems


def main():
    raw = os.environ.get("M101_CP5_LIVE_SNAPSHOT_JSON")
    if not raw:
        print(json.dumps({"status": "FAIL", "reason": "MISSING_REAL_PG_PROC_SNAPSHOT"}))
        return 2
    snapshot = json.loads(raw)
    problems = check(snapshot)

    # Adversarial proof: a synthetic private call in an otherwise identical
    # snapshot MUST be rejected. This never substitutes for real catalog proof.
    negative = json.loads(json.dumps(snapshot))
    negative["external_private_calls"] = [{
        "signature": "public.adversarial_external_consumer()",
        "callee": "programacion.fn_input_governance_execute"
    }]
    negative["reported_direct_calls"] = 1
    adversarial_rejected = "EXTERNAL_CALLS_PRIVATE_IG" in check(negative)
    if not adversarial_rejected:
        problems.append("ADVERSARIAL_BYPASS")
    status = "PASS" if not problems else "FAIL"
    result = {
        "schema_version": "IG_M101_NEG_INTERNAL_CALL_EXECUTION_V1",
        "test_code": "ENG_M10_1_NEG_INTERNAL_CALL",
        "status": status,
        "test_passed": status == "PASS",
        "test_exit_code": 0 if status == "PASS" else 1,
        "semantic_authority_bound": snapshot.get("source") == "pg_catalog.pg_proc"
            and snapshot.get("selection_contract") == "PUBLIC_NON_FACADE_PLUS_ROUTER_EXTERNAL_SQL_ENTRYPOINTS",
        "adversarial_case_executed": adversarial_rejected,
        "external_direct_call_count": len(violations),
        "scanned_entrypoints": snapshot.get("scanned_entrypoints"),
        "public_facade_count": snapshot.get("public_facade_count"),
        "router_source_sha256": snapshot.get("router_source_sha256"),
        "source_snapshot_sha256": snapshot.get("snapshot_sha256"),
        "problems": problems,
    }
    print(json.dumps(result, sort_keys=True))
    return result["test_exit_code"]


if __name__ == "__main__":
    sys.exit(main())
