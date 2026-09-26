#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "lf_migration_source_parity_repair.py"
spec = importlib.util.spec_from_file_location("lf_migration_source_parity_repair", TARGET)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)


def digest(value: dict) -> str:
    payload = dict(value)
    payload.pop("manifest_sha256", None)
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def evidence(summary: str, *, head: str = "a" * 40) -> dict:
    report = {
        "contract": mod.PARITY_CONTRACT,
        "producer": mod.PARITY_PRODUCER,
        "run_id": "36139757922",
        "job_id": "lf-contract-check",
        "step_id": mod.PARITY_STEP_ID,
        "gate_id": "LF_CONTRACT_CHECK_DECLARATIVE_CONTROLS::MIGRATION_SOURCE_PARITY",
        "gate_result": "FAIL",
        "diagnostic_complete": True,
        "source_commit": head,
        "tested_commit": head,
        "source_path": [mod.PARITY_SOURCE_PATH],
        "expected_check_count": 1,
        "executed_check_count": 1,
        "pass_count": 0,
        "fail_count": 1,
        "blocked_count": 0,
        "downstream_impact": ["MIGRATION_SOURCE_PARITY"],
        "checks": [{
            "check_status": "FAIL",
            "producer": mod.PARITY_PRODUCER,
            "source_commit": head,
            "tested_commit": head,
            "source_path": mod.PARITY_SOURCE_PATH,
            "error_summary": summary,
        }],
    }
    report["manifest_sha256"] = digest(report)
    return report


single = evidence("FAIL_LF_MIGRATION_VERSION_PARITY: remote_only=['20260922231503'] local_only=[]")
finding = mod.parse_parity_finding(single)
assert finding is not None
assert finding["version"] == "20260922231503"
assert finding["failure_code"] == "FAIL_LF_MIGRATION_VERSION_PARITY"

unclassified = evidence("FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION: remote=20260923013150_unknown_owner")
assert mod.parse_parity_finding(unclassified) is None

noise = evidence("FAIL_LF_MIGRATION_VERSION_PARITY: remote_only=['20260922231503'] local_only=[]")
noise["unrelated_note"] = "another timestamp 20260923013150 must never become a repair candidate"
noise["manifest_sha256"] = digest(noise)
assert mod.parse_parity_finding(noise)["version"] == "20260922231503"

multi = evidence("FAIL_LF_MIGRATION_VERSION_PARITY: remote_only=['20260922231503', '20260923013150'] local_only=[]")
try:
    mod.parse_parity_finding(multi)
except RuntimeError as exc:
    assert str(exc).startswith("MIGRATION_REPAIR_EXPECTED_SINGLE_REMOTE_ONLY")
else:
    raise AssertionError("multi-version parity failure accepted as one repair")

tampered = evidence("FAIL_LF_MIGRATION_VERSION_PARITY: remote_only=['20260922231503'] local_only=[]")
tampered["source_commit"] = "b" * 40
try:
    mod.parse_parity_finding(tampered)
except RuntimeError as exc:
    assert str(exc) == "MIGRATION_REPAIR_PARITY_EVIDENCE_DIGEST_MISMATCH"
else:
    raise AssertionError("tampered parity evidence accepted")

repo = "cristhianlujan/claude-persona-lf-patch"
rows = [[
    "20260923013150",
    "restrict_profile_semantic_judge_trust_validator_acl",
    "73656c65637420313b",
    "1",
    "EXEC-DB-SOURCE-RECONCILE-20260923013150-20260923-001",
    repo,
    "supabase/migrations/20260923013150_restrict_profile_semantic_judge_trust_validator_acl.sql",
    "a" * 40,
    "b" * 40,
    "PASS",
    "false",
]]
locator = mod.select_locator("20260923013150", rows, repo)
assert locator["source_blob"] == "b" * 40
assert locator["path"].endswith("restrict_profile_semantic_judge_trust_validator_acl.sql")

ambiguous = rows + [list(rows[0])]
ambiguous[1][8] = "c" * 40
try:
    mod.select_locator("20260923013150", ambiguous, repo)
except RuntimeError as exc:
    assert str(exc).startswith("MIGRATION_REPAIR_LOCATOR_AMBIGUOUS")
else:
    raise AssertionError("ambiguous historical source locators accepted")

print("PASS_MIGRATION_SOURCE_RECONCILIATION=9/9")
