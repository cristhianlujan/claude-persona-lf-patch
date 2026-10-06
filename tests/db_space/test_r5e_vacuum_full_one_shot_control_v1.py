from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIG = ROOT / "supabase/migrations/20261006223500_r5e_vacuum_full_one_shot_control_v1.sql"


def sql() -> str:
    return MIG.read_text(encoding="utf-8")


def test_jobs_install_inactive():
    text = sql()
    assert "lf-r5e-vacuum-full-once-v1" in text
    assert "lf-r5e-vacuum-finalizer-v1" in text
    assert text.count("active=>false") >= 2
    assert "active=>true" not in text


def test_vacuum_command_is_single_top_level_statement():
    text = sql()
    assert "'VACUUM (FULL, ANALYZE) programacion.input_family_assessments'" in text
    assert "SET lock_timeout='5s'; VACUUM" not in text


def test_no_window_is_armed_in_installation_migration():
    text = sql().lower()
    assert "alter role postgres set lock_timeout" not in text
    assert "status='armed'" not in text


def test_finalizer_resets_role_and_self_unschedules():
    text = sql().lower()
    assert "alter role postgres reset lock_timeout" in text
    assert "cron.unschedule('lf-r5e-vacuum-full-once-v1')" in text
    assert "cron.unschedule('lf-r5e-vacuum-finalizer-v1')" in text


def test_finalizer_records_pre_post_size_contract():
    text = sql()
    for token in (
        "pre_relation_bytes","pre_heap_bytes","pre_index_bytes","pre_toast_bytes",
        "pre_database_bytes","post_relation_bytes","post_heap_bytes",
        "post_index_bytes","post_toast_bytes","post_database_bytes",
    ):
        assert token in text


def test_no_destructive_evidence_operations():
    text = sql().lower()
    assert "delete from programacion.input_family_assessments" not in text
    assert "disable trigger" not in text
    assert "reindex" not in text
