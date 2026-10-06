from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "supabase/migrations/20261006211500_input_governance_r5_d_compact_new_validator_writes_v1.sql"
JUDGE = ROOT / "sandbox/lf_contract_gate_test/input_governance_runtime_candidate_judge/ig_runtime_candidate_judge_v1.py"
SEMANTIC = ROOT / "sandbox/lf_contract_gate_test/input_governance_incremental/semantic_l3b_50_cases.sql"


def migration() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def test_r5d_requires_exact_contract_5131_receipt():
    text = migration()
    assert "'5.13.1'" in text
    assert "dc78d22793bfbb78a3d678b91ffdff39a3499a36d3824c65c181734e80c57516" in text
    assert "R5D_CONTRACT_5131_REQUIRED" in text


def test_r5d_pins_all_three_writer_bases():
    text = migration()
    for md5 in (
        "9a624388dc01183f05f78e8e32d5c5fc",
        "7970d71ff66d40236bd085a13a0abadd",
        "1242cb67ae2f6a9713fafe0b1928b266",
    ):
        assert md5 in text


def test_r5d_writes_assertion_sets_idempotently_with_readback():
    text = migration()
    assert text.count("on conflict (assertion_set_sha256) do nothing") == 3
    assert text.count("R5D_ASSERTION_SET_READBACK_MISMATCH") == 3
    assert text.count("R5D_LOGICAL_EVIDENCE_REHYDRATION_MISMATCH") == 3
    assert text.count("v_physical_evidence:=(v_logical_evidence-'assertions')") == 3
    assert text.count("'assertion_set_sha256',v_assertion_set_sha256") == 3


def test_r5d_does_not_assign_validator_sha256_in_writers():
    text = migration().lower()
    # validator_sha256 remains computed by fn_guard_input_family_assessment_update
    assert "validator_sha256=" not in text


def test_r5d_exact_final_writer_md5s_are_pinned():
    text = migration()
    for md5 in (
        "b9da62afa568dc8551536d6b0713764d",
        "e02287a6273b59191b1386801e58c9f3",
        "1881979fffff8dd1f954c3d982592b41",
    ):
        assert md5 in text
    assert text.count("R5D_FINAL_MD5_MISMATCH") == 3


def test_runtime_judge_uses_logical_assertions():
    text = JUDGE.read_text(encoding="utf-8")
    assert "fn_input_validator_evidence_rehydrate_v1(validator_evidence)->'assertions'" in text
    assert "validator_evidence->'assertions'" not in text


def test_semantic_l3b_uses_logical_assertions():
    text = SEMANTIC.read_text(encoding="utf-8")
    assert "fn_input_validator_evidence_rehydrate_v1(a.validator_evidence)->'assertions'" in text
    assert "a.validator_evidence->'assertions'" not in text
