"""Static source and negative contract for the IG M36 candidate authority patch.

This is not a real PG regression; the protected BEGIN/ROLLBACK harness is separate.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20261118052000_lf_ig_m36_noncurrent_candidate_authority_v1.sql"
PG = ROOT / "sandbox/lf_contract_gate_test/input_governance/ig_m36_noncurrent_field_42_screen_rollback.sql"

def test_m36_exact_source_guard_and_type():
    sql = MIGRATION.read_text()
    assert "61d47a6400cf910ace71936413863e16" in sql
    assert "EXPLICIT_FIELD_REFERENCE_NONCURRENT" in sql
    assert sql.count("then 'CANDIDATE_AUTHORITY'") == 4  # needle, replacement x2, postcondition
    assert "IG_M36_PREIMAGE_SOURCE_DRIFT" in sql
    assert "IG_M36_NONCURRENT_MAPPING_ANCHOR_NOT_UNIQUE" in sql
    assert "IG_M36_NONCURRENT_CANDIDATE_SOURCE_READBACK_FAIL" in sql

def test_m36_no_policy_data_or_privilege_mutations():
    sql = MIGRATION.read_text()
    for forbidden in (
        "GRANT ", "UPDATE LF_OPS.", "DELETE FROM LF_OPS.",
        "INSERT INTO LF_OPS.", "ALTER TABLE", "DROP TABLE",
        "TRUNCATE", "PROMOTE", "APPLY_RULE",
    ):
        assert forbidden not in sql.upper()
    assert "EXECUTE d;" in sql
    assert "pg_get_functiondef(sig)" in sql

def test_m36_protected_pg_harness_has_real_baseline_gates():
    sql = PG.read_text()
    assert sql.splitlines().count("BEGIN;") == 1
    assert sql.splitlines().count("ROLLBACK;") == 1
    assert "COMMIT;" not in sql
    assert "1974" in sql and "42" in sql
    assert "1833" in sql and "1824" in sql and "9" in sql
    assert "applicable_lost=0" in sql
    assert "'EXPLICIT_FIELD_REFERENCE_NONCURRENT'" in sql
    assert "'CANDIDATE_AUTHORITY'" in sql
    assert "'BLOCKED'" in sql and "'STORY'" in sql
    assert "IG_M36_POST_ROLLBACK_PASS" in sql
