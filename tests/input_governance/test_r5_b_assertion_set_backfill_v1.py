from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "supabase/migrations/20261006180500_input_governance_r5_b_assertion_set_backfill_v1.sql"


def sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def test_r5b_is_insert_only_for_assertion_sets():
    text = sql().lower()
    assert "insert into programacion.input_validator_assertion_sets_v1" in text
    assert "update programacion.input_family_assessments" not in text
    assert "delete from programacion.input_family_assessments" not in text
    assert "alter table programacion.input_family_assessments" not in text
    assert "drop " not in text


def test_r5b_pins_authorized_snapshot():
    text = sql()
    assert "expected=10131" in text
    assert "expected=3379" in text
    assert "R5B_ASSERTION_REFERENCE_SNAPSHOT_MOVED" in text
    assert "R5B_UNIQUE_ASSERTION_SET_SNAPSHOT_MOVED" in text
    assert "R5B_ASSERTION_SET_TABLE_NOT_EMPTY" in text


def test_r5b_uses_canonical_content_address():
    text = sql()
    assert "programacion.fn_v09_sha256_jsonb(assertions)" in text
    assert "SELECT DISTINCT validator_evidence->'assertions' AS assertions" in text
