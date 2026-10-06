from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "supabase/migrations/20261006180000_input_governance_r5_a_assertion_sets_rehydrate_v1.sql"


def sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def test_r5a_is_additive_only():
    text = sql().lower()
    assert "create table programacion.input_validator_assertion_sets_v1" in text
    assert "create or replace function programacion.fn_input_validator_evidence_rehydrate_v1" in text
    assert "update programacion.input_family_assessments" not in text
    assert "alter table programacion.input_family_assessments" not in text
    assert "delete from programacion.input_family_assessments" not in text
    assert "drop table programacion.input_family_assessments" not in text


def test_r5a_assertion_sets_are_content_addressed_and_private():
    text = sql()
    assert "input_validator_assertion_sets_v1_content_addressed" in text
    assert "programacion.fn_v09_sha256_jsonb(assertions)" in text
    assert "ENABLE ROW LEVEL SECURITY" in text
    assert "REVOKE ALL ON TABLE programacion.input_validator_assertion_sets_v1" in text


def test_r5a_rehydrate_is_fail_closed():
    text = sql()
    for marker in (
        "R5_REHYDRATE_AMBIGUOUS_INLINE_AND_REFERENCE",
        "R5_REHYDRATE_INVALID_ASSERTION_SET_SHA256",
        "R5_REHYDRATE_ASSERTION_SET_NOT_FOUND",
        "R5_REHYDRATE_ASSERTION_SET_HASH_MISMATCH",
        "p_validator_evidence - 'assertion_set_sha256'",
        "jsonb_build_object('assertions', v_assertions)",
    ):
        assert marker in text
