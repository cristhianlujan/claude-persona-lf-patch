#!/usr/bin/env python3
"""M1.A8 negative acceptance: a 59/60 run receipt cannot earn traversal coverage.

Run against an independently acquired canonical Supabase READONLY snapshot,
including the immutable V3 obligations, exact matrix, selected readiness run,
and the native EVIDENCE_LEDGER receipt. Mutations affect Python copies ONLY.
No database writes, no artificial APPLIED/N/A, no second assurance evaluator.
"""
from __future__ import annotations
import argparse
import copy
import json
import re
import sys
from pathlib import Path

TEST_CODE = "ENG_M1_A8_NEG_UNMARKED_CLAUSE"
HASH64 = re.compile(r"^[0-9a-f]{64}$")


def coverage_gate(authority: dict, candidate: dict) -> bool:
    """Independent structural completeness judge, not semantic APPLIED proof."""
    if authority.get("source") != "SUPABASE_LIVE_CANONICAL":
        return False
    contract = authority.get("matrix") or {}
    if contract.get("matrix_revision") != 1 or contract.get("contract_revision") != "5.13" or contract.get("clause_count") != 60:
        return False
    run = authority.get("run") or {}
    if run.get("status") != "COMPLETED":
        return False
    if not HASH64.fullmatch(str(run.get("source_snapshot_sha256", ""))):
        return False
    if not HASH64.fullmatch(str(run.get("contract_snapshot_sha256", ""))):
        return False
    canonical = authority.get("obligations") or []
    if not isinstance(canonical, list) or len(canonical) != 60:
        return False
    keys = [(row.get("obligation_code"), row.get("clause_key")) for row in canonical]
    if len(set(keys)) != 60 or not all(code and clause for code, clause in keys):
        return False
    if not all(row.get("classification") == "BLOCKED" for row in canonical):
        return False

    if authority.get("ledger_verification_state") != "VERIFIED" or not HASH64.fullmatch(str(authority.get("receipt_sha256", ""))):
        return False
    if candidate.get("schema_version") != "IG_SPEC_TRAVERSAL_RECEIPT_PER_RUN_V1":
        return False
    if str(candidate.get("run_id")) != str(run.get("id")):
        return False
    if str(candidate.get("pantalla_id")) != str(run.get("pantalla_id")):
        return False
    if str(candidate.get("version_id")) != str(run.get("version_id")):
        return False
    if candidate.get("source_snapshot_sha256") != run.get("source_snapshot_sha256"):
        return False
    if candidate.get("contract_snapshot_sha256") != run.get("contract_snapshot_sha256"):
        return False
    if candidate.get("clause_count") != 60 or candidate.get("blocked_count") != 60:
        return False
    if candidate.get("applied_count") != 0 or candidate.get("not_applicable_count") != 0:
        return False
    if candidate.get("semantic_pass_authorized") is not False:
        return False
    clauses = candidate.get("clauses")
    if not isinstance(clauses, list) or len(clauses) != 60:
        return False
    found = [(row.get("obligation_code"), row.get("clause_key")) for row in clauses]
    if len(set(found)) != 60 or set(found) != set(keys):
        return False
    return all(
        isinstance(row, dict)
        and row.get("classification") == "BLOCKED"
        and isinstance(row.get("reason"), str) and bool(row["reason"].strip())
        and isinstance(row.get("source_ref"), str) and bool(row["source_ref"].strip())
        and row.get("semantic_receipt_verified") is False
        for row in clauses
    )


def negative_campaign(authority: dict) -> dict:
    original = copy.deepcopy(authority["receipt_payload"])
    if not coverage_gate(authority, original):
        raise AssertionError("POSITIVE_LIVE_RECEIPT_NOT_COVERED")
    results = {"baseline_live_receipt": True}
    cases: dict[str, dict] = {}

    missing = copy.deepcopy(original)
    missing["clauses"].pop()
    cases["one_clause_unmarked_59_of_60"] = missing

    duplicate = copy.deepcopy(original)
    duplicate["clauses"][-1] = copy.deepcopy(duplicate["clauses"][0])
    cases["duplicate_clause_overwrites_one"] = duplicate

    unknown = copy.deepcopy(original)
    unknown["clauses"][-1]["obligation_code"] = "NOT_IN_CANONICAL_5_13"
    cases["unknown_clause_injected"] = unknown

    wrong_run = copy.deepcopy(original)
    wrong_run["run_id"] = int(authority["run"]["id"]) + 1
    cases["cross_run_receipt_replay"] = wrong_run

    wrong_screen = copy.deepcopy(original)
    wrong_screen["pantalla_id"] = -1
    cases["cross_screen_substitution"] = wrong_screen

    stale_snapshot = copy.deepcopy(original)
    stale_snapshot["source_snapshot_sha256"] = "0" * 64
    cases["stale_source_snapshot"] = stale_snapshot

    false_applied = copy.deepcopy(original)
    false_applied["clauses"][0]["classification"] = "APPLIED"
    cases["false_applied_without_independent_evidence"] = false_applied

    false_na = copy.deepcopy(original)
    false_na["clauses"][0]["classification"] = "N/A"
    cases["false_na_without_positive_authority"] = false_na

    missing_reason = copy.deepcopy(original)
    missing_reason["clauses"][0]["reason"] = ""
    cases["blocked_without_reason"] = missing_reason

    invented_semantic_pass = copy.deepcopy(original)
    invented_semantic_pass["semantic_pass_authorized"] = True
    cases["forged_semantic_pass"] = invented_semantic_pass

    for name, candidate in cases.items():
        if coverage_gate(authority, candidate):
            raise AssertionError(f"NEGATIVE_NOT_DETECTED:{name}")
        results[name] = True

    return {
        "status": "PASS",
        "test_code": TEST_CODE,
        "test_passed": True,
        "test_exit_code": 0,
        "semantic_authority_bound": True,
        "semantic_authority_scope": "SPEC_CLAUSE_COVERAGE_ONLY_NOT_APPLIED",
        "semantic_pass_authorized": False,
        "adversarial_case_executed": True,
        "selected_run_id": authority["run"]["id"],
        "positive_live_receipt_verified": True,
        "negative_cases_detected": len(cases),
        "tests_passed": len(results),
        "tests_total": len(results),
        "controls": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--authority-json",type=Path,required=True)
    args = parser.parse_args()
    authority = json.loads(args.authority_json.read_text(encoding="utf-8"))
    result = negative_campaign(authority)
    print(json.dumps(result,sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError,KeyError,ValueError,TypeError) as error:
        print(json.dumps({"status":"FAIL","test_code":TEST_CODE,
                          "test_passed":False,"test_exit_code":1,
                          "error":str(error)}))
        sys.exit(1)
