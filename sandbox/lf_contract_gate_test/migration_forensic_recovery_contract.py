#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "sandbox" / "lf_contract_gate_test" / "lf_migration_source_parity.py"
spec = importlib.util.spec_from_file_location("lf_migration_source_parity_forensic_contract", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)

def expect_fail(prefix, fn):
    try:
        fn()
    except SystemExit as exc:
        assert str(exc).startswith(prefix), (prefix, exc)
        return
    raise AssertionError(prefix)

os.environ["GITHUB_REPOSITORY"] = "o/r"
base_row = {
    "version": "20260922010101",
    "name": "forensic_probe",
    "path": "supabase/migrations/20260922010101_forensic_probe.sql",
    "currentness_execution_id": "EXEC-FORENSIC",
    "currentness_execution_status": "COMPLETED",
    "operation_code": "ACTUALIZACION_DB_LF",
    "target_repo": "o/r",
    "pr_state": "OPEN",
    "pr_head_sha": "a" * 40,
    "source_blob": "b" * 40,
    "write_readback": "PASS",
    "currentness_result": mod.FORENSIC_RECOVERY_RESULT,
    "ddl_replayed": False,
    "ownership_mode": mod.FORENSIC_RECOVERY_OWNER_MODE,
    "owner_receipt_schema": mod.FORENSIC_RECOVERY_RECEIPT_SCHEMA,
    "source_recovery_basis": mod.FORENSIC_RECOVERY_BASIS,
    "source_materialization_mode": mod.FORENSIC_SOURCE_MODE,
    "original_source_search_complete": True,
    "original_source_found": False,
    "provenance_gap_ekb_code": "EKB-PROBE",
    "source_search_evidence_ref": "evidence://search",
}
evidence = {
    "schema_version": mod.EXTERNAL_OWNER_EVIDENCE_SCHEMA,
    "complete": True,
    "repository": "o/r",
    "owners": [base_row],
}
row = mod._select_external_owner_record(
    version=base_row["version"],
    name=base_row["name"],
    evidence=evidence,
    current_head="c" * 40,
)
mod._validate_owner_transport_constraints(
    row,
    remote_statement_count=1,
    representation="DIRECT_SOURCE",
)

for key, value, code in [
    ("original_source_search_complete", False, "FAIL_LF_MIGRATION_FORENSIC_RECOVERY_EVIDENCE"),
    ("original_source_found", True, "FAIL_LF_MIGRATION_FORENSIC_RECOVERY_EVIDENCE"),
    ("provenance_gap_ekb_code", "", "FAIL_LF_MIGRATION_FORENSIC_RECOVERY_EKB_MISSING"),
    ("source_search_evidence_ref", "", "FAIL_LF_MIGRATION_FORENSIC_RECOVERY_SEARCH_EVIDENCE_MISSING"),
]:
    bad = {**evidence, "owners": [{**base_row, key: value}]}
    expect_fail(
        code,
        lambda bad=bad: mod._select_external_owner_record(
            version=base_row["version"],
            name=base_row["name"],
            evidence=bad,
            current_head="c" * 40,
        ),
    )

expect_fail(
    "FAIL_LF_MIGRATION_FORENSIC_RECOVERY_STATEMENT_COUNT",
    lambda: mod._validate_owner_transport_constraints(
        row, remote_statement_count=2, representation="DIRECT_SOURCE"
    ),
)
expect_fail(
    "FAIL_LF_MIGRATION_FORENSIC_RECOVERY_REPRESENTATION",
    lambda: mod._validate_owner_transport_constraints(
        row, remote_statement_count=1, representation="CLI_STATEMENT_STORAGE"
    ),
)

bad_mode = {**evidence, "owners": [{**base_row, "ownership_mode": "UNKNOWN"}]}
expect_fail(
    "FAIL_LF_MIGRATION_EXTERNAL_OWNER_MODE",
    lambda: mod._select_external_owner_record(
        version=base_row["version"],
        name=base_row["name"],
        evidence=bad_mode,
        current_head="c" * 40,
    ),
)

normal = {
    **base_row,
    "ownership_mode": mod.NORMAL_OWNER_MODE,
    "currentness_result": "OWNER_PR_EXACT_OPEN",
}
for key in [
    "owner_receipt_schema",
    "source_recovery_basis",
    "source_materialization_mode",
    "original_source_search_complete",
    "original_source_found",
    "provenance_gap_ekb_code",
    "source_search_evidence_ref",
]:
    normal.pop(key, None)
mod._select_external_owner_record(
    version=normal["version"],
    name=normal["name"],
    evidence={**evidence, "owners": [normal]},
    current_head="c" * 40,
)
print("PASS_MIGRATION_FORENSIC_RECOVERY_CONTRACT=9/9")
