from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIG = ROOT / "supabase/migrations/20261006223500_r5e_vacuum_full_one_shot_control_v1.sql"


def sql() -> str:
    return MIG.read_text(encoding="utf-8")


def test_three_vacuums_are_separate_top_level_commands():
    text = sql()
    assert "'VACUUM (FULL, ANALYZE) programacion.input_family_assessments'" in text
    assert "'VACUUM (FULL, ANALYZE) inventory.objects'" in text
    assert "'VACUUM (FULL, ANALYZE) inventory.search_index'" in text
    assert "SET lock_timeout='5s'; VACUUM" not in text


def test_all_jobs_install_inactive():
    text = sql()
    for name in (
        "lf-r5e-vacuum-assessments-v1",
        "lf-r5e-vacuum-inventory-objects-v1",
        "lf-r5e-vacuum-inventory-search-index-v1",
        "lf-r5e-vacuum-finalizer-v1",
        "lf-r5e-vacuum-safety-reset-v1",
    ):
        assert name in text
    assert "active=>true" not in text


def test_installation_does_not_set_role_timeout():
    text = sql().lower()
    assert "alter role postgres set lock_timeout" not in text
    assert "alter role postgres reset lock_timeout" in text


def test_independent_safety_reset_exists():
    text = sql()
    assert "fn_r5e_vacuum_safety_reset_v1" in text
    assert "safety_deadline" in text
    assert "R5E_SAFETY_RESET_AT_30_MINUTES" in text
    assert "fn_r5e_postgres_lock_timeout_clean_v1" in text


def test_finalizer_sequences_targets():
    text = sql()
    assert "target_order=v_target.target_order+1" in text
    assert "'NEXT_ARMED'" in text
    assert "perform cron.alter_job(v_next.job_id,schedule=>v_schedule,active=>true)" in text


def test_per_table_pre_post_size_receipts():
    text = sql()
    for token in (
        "pre_total_bytes","pre_heap_bytes","pre_index_bytes","pre_toast_aux_bytes",
        "pre_database_bytes","post_total_bytes","post_heap_bytes",
        "post_index_bytes","post_toast_aux_bytes","post_database_bytes",
    ):
        assert token in text


def test_clean_role_setting_is_terminal_invariant():
    text = sql()
    assert "pg_db_role_setting" in text
    assert "R5E_LOCK_TIMEOUT_RESET_READBACK_FAILED" in text
    assert "R5E_VACUUM_INSTALL_REQUIRES_CLEAN_POSTGRES_LOCK_TIMEOUT" in text


def test_no_destructive_evidence_operations():
    text = sql().lower()
    assert "delete from programacion.input_family_assessments" not in text
    assert "disable trigger" not in text
    assert "reindex" not in text


def test_terminal_cleanup_unschedules_jobs():
    text=sql()
    assert "cron.unschedule(v.jobid)" in text
