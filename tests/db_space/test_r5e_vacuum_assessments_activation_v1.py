from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIG = ROOT / "supabase/migrations/20261007030000_r5e_vacuum_assessments_activation_v1.sql"

def sql():
    return MIG.read_text(encoding="utf-8")

def test_phase_c_only_targets_assessments_and_keeps_job30_controlled():
    text=sql()
    assert "VACUUM (FULL, ANALYZE) programacion.input_family_assessments" in text
    assert "inventory.objects" not in text
    assert "inventory.search_index" not in text

def test_retries_lock_failures_every_15_minutes_max_four():
    text=sql()
    assert "interval '15 minutes'" in text
    assert "retry_count<v_target.max_retries" in text
    assert "max_retries=4" in text
    assert "R5E_C_LOCK_RETRIES_EXHAUSTED" in text

def test_phase_c_repeats_owner_prechecks():
    text=sql()
    assert "array[22,309]::bigint[]" in text
    assert "R5E_C_ACTIVE_IG_QUERIES" in text
    assert "R5E_C_ASSESSMENT_BUSINESS_WRITES_CHANGED" in text
    assert "R5E_C_VACUUM_REQUIRES_VERIFIED_COMPACTION" in text

def test_cleanup_and_lock_timeout_safety():
    text=sql()
    assert "alter role postgres set lock_timeout='5s'" in text
    assert "alter role postgres reset lock_timeout" in text
    assert "fn_r5e_postgres_lock_timeout_clean_v1()" in text
    assert "R5E_C_SAFETY_RESET_AT_90_MINUTES" in text
    assert "cron.unschedule" in text

def test_forbidden_operations_absent():
    text=sql().lower()
    assert "disable trigger" not in text
    assert "reindex" not in text
    assert "delete from programacion.input_family_assessments" not in text
