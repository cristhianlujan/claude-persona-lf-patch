from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIG = ROOT / "supabase/migrations/20261007021000_input_governance_r5_e_dual_hash_full_verify_resume_v1.sql"


def sql() -> str:
    return MIG.read_text(encoding="utf-8")


def test_resume_preserves_existing_baseline_and_progress():
    text = sql()
    assert "baseline_eligible_count<>10131" in text
    assert "compacted_count<>10050" in text
    assert "last_verified_assessment_id<>21609" in text
    assert "set enabled=true" in text.lower()
    assert "baseline_eligible_count=null" not in text.lower()
    assert "compacted_count=0" not in text.lower()


def test_dual_hash_accepts_current_or_legacy_over_rehydrated_evidence():
    text = sql()
    assert "fn_input_validator_evidence_rehydrate_v1(v_verify.validator_evidence)" in text
    assert "'semantic_depth_sha256',v_verify.semantic_depth_sha256" in text
    assert "v_legacy_sha:=programacion.fn_v09_sha256_jsonb" in text
    assert "elsif v_verify.validator_sha256=v_legacy_sha" in text
    assert "R5E_FULL_VERIFY_MATCH_NONE" in text


def test_verification_is_exhaustive_and_batched_not_random_sample():
    text = sql().lower()
    assert "limit 1000" in text
    assert "for v_verify_pass in 1..2 loop" in text
    assert "verification_checked_count" in text
    assert "order by random()" not in text
    assert "r5e_final_sample_receipt_hash_mismatch" not in text


def test_receipt_tracks_current_legacy_none_and_ids():
    text = sql()
    for token in (
        "input_validator_compaction_verification_receipt_v2",
        "match_current",
        "match_legacy",
        "match_none",
        "none_ids",
        "checked_count",
        "last_assessment_id",
    ):
        assert token in text


def test_match_none_stops_and_unschedules():
    text = sql()
    assert "v_verify_none>0" in text
    assert "status='FAILED'" in text
    assert "cron.unschedule('lf-r5e-validator-compaction-v1')" in text
    assert "'code','R5E_FULL_VERIFY_MATCH_NONE'" in text


def test_job30_is_never_activated():
    text = sql().lower()
    assert "lf-r5e-vacuum-assessments-v1" in text
    assert "job30_must_remain_inactive" in text
    assert "vacuum (full" not in text
    assert "disable trigger" not in text
    assert "reindex" not in text
    assert "delete from programacion.input_family_assessments" not in text
