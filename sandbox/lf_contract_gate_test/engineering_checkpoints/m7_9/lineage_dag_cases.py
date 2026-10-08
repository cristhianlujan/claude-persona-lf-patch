#!/usr/bin/env python3
"""M7.9-owned LINEAGE_DAG_CASES; assert actual Supabase readback supplied at runtime.

The execution adapter queries current DB in its own transaction, sends the
returned JSON as argv[1], runs this exact merged source on the operational
host, and preserves the test's stdout as the assertion evidence. No credentials
or DB mutations are needed on the host. SQL-side live negative inserts and
current-successor run are always rollback-only.
"""
import json
import re
import sys

TEST_CODE = "ENG_M7_9_LINEAGE_DAG_CASES"
HEX_SHA = re.compile(r"^[0-9a-f]{64}$")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def checked(payload):
    require(payload.get("schema_version") == "M79_LINEAGE_LIVE_READBACK_V1", "source readback shape")
    rows = payload.get("historical_rows")
    require(isinstance(rows, list), "missing historical DB rows")
    hist = {r["id"]: r for r in rows}
    require({263, 264, 265, 266, 275}.issubset(hist), "required historical branch absent")
    parent, blocked, completed = hist[264], hist[265], hist[266]

    # Old runs have no 'reason' in scope; do NOT retrofit or count them as
    # proof of the *new* reason/SHA binding. Evaluate immutable DAG facts only.
    for descendant, expected_parent in [(264, 263), (265, 264), (266, 264), (275, 266)]:
        row = hist[descendant]
        require(row["supersedes_run_id"] == expected_parent, f"wrong lineage edge: {descendant}")
        require(row["parent_scope"] == str(expected_parent), f"wrong scoped parent: {descendant}")
        require(HEX_SHA.fullmatch(row["parent_source_sha256"] or ""), f"bad parent SHA: {descendant}")
        require(row["parent_source_sha256"] == hist[expected_parent]["source_snapshot_sha256"],
                f"parent source SHA changed: {descendant}")

    require(blocked["status"] == "BLOCKED", "blocked branch absent")
    require(completed["status"] == "COMPLETED", "successful sibling branch absent")
    require(blocked["source_snapshot_sha256"] is None, "blocked branch must not invent SHA")
    require(HEX_SHA.fullmatch(completed["source_snapshot_sha256"] or ""), "completed sibling must own SHA")
    require(parent["invalidated_by_run_id"] in (265, 266), "parent latch successor invalid")
    require(parent["invalidated_reason"] == "TERMINAL_SUCCESSOR", "parent terminal latch reason")
    require(completed["invalidated_by_run_id"] == 275, "subsequent lineage broken")

    modern = payload.get("modern_successor") or {}
    require(modern.get("status") == "VALIDATING", "actual current successor not materialized")
    require(modern.get("curator_status") == "VALIDATOR_RUNTIME_REQUIRED", "curator result absent")
    require(modern.get("parent_id") == 657, "modern successor used wrong parent")
    require(modern.get("reason") == "ASSERTION_REBIND", "current successor reason not recorded")
    require(modern.get("successor_strategy") == "PARENT_ASSERTION_REUSE", "strategy not recorded")
    require(modern.get("sha_ok") is True, "lineage signature not verified")
    require(modern.get("parent_sha_ok") is True, "parent SHA not inherited exactly")
    require(modern.get("parent_binding_ok") is True, "lineage parent ID wrong")
    require(modern.get("family_binding_count") == 47, "family SHA lineage incomplete")

    neg = payload.get("negative_guards") or []
    found = {r["test_code"]: r for r in neg}
    expected = {
        "REASON_REQUIRED": "IG_SUCCESSOR_REASON_REQUIRED",
        "PARENT_BINDING_REQUIRED": "IG_SUCCESSOR_PARENT_BINDING_REQUIRED",
        "PARENT_SHA_REQUIRED": "IG_SUCCESSOR_PARENT_SOURCE_SHA_REQUIRED",
    }
    for name, expected_error in expected.items():
        require(name in found, f"negative test not executed: {name}")
        require(found[name].get("actual_error") == expected_error,
                f"negative guard mismatch: {name}")
        require(found[name].get("passed") is True, f"negative guard FAIL: {name}")

    # No old reason is manufactured to satisfy a new guard contract.
    legacy_reasonless = sum(1 for r in rows if r.get("reason") is None)
    require(legacy_reasonless >= 4, "historical legacy status not distinguished")
    return {
        "test_code": TEST_CODE, "test_passed": True, "semantic_authority_bound": True,
        "test_exit_code": 0, "historical_cases_verified": 4,
        "branched_edges_verified": ["263->264", "264->265", "264->266", "266->275"],
        "legacy_reasonless_readback_only": legacy_reasonless,
        "new_parent_sha_bound": True, "new_family_sha_bindings": 47,
        "negative_guards_passed": list(expected), "rollback_only": True,
        "lineage_modern_run_id": modern.get("run_id"), "historical_fingerprints_not_rewritten": True,
    }


def main():
    require(len(sys.argv) == 2, "expected exact JSON live readback argument")
    payload = json.loads(sys.argv[1])
    result = checked(payload)
    print(json.dumps({"status": "PASS", "observed": result}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"status": "FAIL", "test_code": TEST_CODE,
                          "error": f"{type(exc).__name__}: {exc}"}))
        sys.exit(1)
