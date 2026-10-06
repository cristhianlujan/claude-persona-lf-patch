from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIG = ROOT / "supabase/migrations/20261006223000_input_governance_r5_e_compaction_runner_v1.sql"


def sql() -> str:
    return MIG.read_text(encoding="utf-8")


def test_single_versioned_batch_runner():
    text = sql()
    assert "create table programacion.input_validator_compaction_checkpoint_v1" in text.lower()
    assert "fn_input_validator_compaction_batch_v1" in text
    assert "pg_try_advisory_xact_lock" in text
    assert "R5E_INPUT_VALIDATOR_COMPACTION_V1" in text


def test_job_installs_disabled():
    text = sql()
    assert "lf-r5e-validator-compaction-v1" in text
    assert "active=>false" in text
    assert "R5E_JOB_MUST_INSTALL_INACTIVE" in text
    assert "R5E_CHECKPOINT_MUST_INSTALL_DISABLED" in text


def test_only_validator_evidence_is_updated():
    text = sql()
    assert "set validator_evidence=v_new_evidence" in text
    assert "validator_sha256=" not in text.lower()
    assert "disable trigger" not in text.lower()
    assert "delete from programacion.input_family_assessments" not in text.lower()


def test_each_row_is_rehydrated_and_sha_preserved():
    text = sql()
    assert "R5E_VALIDATOR_SHA_CHANGED" in text
    assert "R5E_REHYDRATION_MISMATCH" in text
    assert "fn_input_validator_evidence_rehydrate_v1" in text
    assert "fn_input_validator_storage_compaction_check_v1" in text


def test_checkpoint_advances_with_batch():
    text = sql()
    for token in (
        "last_verified_assessment_id",
        "compacted_count",
        "batch_no",
        "last_batch_digest",
        "cumulative_digest",
        "baseline_eligible_count",
        "baseline_max_assessment_id",
    ):
        assert token in text


def test_completion_receipt_and_random_sample():
    text = sql()
    assert "R5E_FINAL_COUNT_MISMATCH" in text
    assert "order by random()" in text.lower()
    assert "R5E_FINAL_SAMPLE_RECEIPT_HASH_MISMATCH" in text
    assert "'status','VERIFIED'" in text
    assert "'remaining_inline_eligible',0" in text


def test_first_failure_stops_scheduler_and_persists_error():
    text = sql()
    assert "last_error_sqlstate" in text
    assert "last_error_message" in text
    assert "'status','FAILED'" in text
    assert text.count("cron.unschedule('lf-r5e-validator-compaction-v1')") >= 2
    assert "scheduler_cleanup=" in text


def test_activation_is_not_embedded():
    text = sql()
    # This PR only installs the mechanism. The only active assignment is false.
    assert "active=>true" not in text
    assert "status='READY'" not in text
