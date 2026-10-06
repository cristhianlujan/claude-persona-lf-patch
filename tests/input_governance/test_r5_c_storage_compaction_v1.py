from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "supabase/migrations/20261006183000_input_governance_r5_c_logical_readers_storage_compaction_v1.sql"

def sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")

def test_r5c_is_draft_candidate_without_trigger_disable():
    text = sql().lower()
    assert "disable trigger" not in text
    assert "enable trigger" not in text
    assert "storage_compaction" in text

def test_r5c_pins_all_base_md5s():
    text = sql()
    for md5 in (
        "1fcbd090ac0d38945d61bc385870ab64",
        "1ed8d14016692bae1f7c83e0fb784ce9",
        "a2e62e0aa8aaea5d3e0a4c48c69a5faa",
        "b4f4e6d0f97255cd3cfe1f77df80ecb5",
        "8f46becafa22ae24cf21f316d2516511",
        "c672695362826666ac8da5799982bbad",
        "385b6a7c7cfaf56bff3c6aa8d41539d8",
        "69cf918a8510c6ba40302cbba56e5c99",
    ):
        assert md5 in text

def test_r5c_has_negative_test_for_each_owner_clause():
    text = sql()
    for marker in (
        "R5C_NEGATIVE_CLAUSE1_FAILED",
        "R5C_NEGATIVE_CLAUSE2_FAILED",
        "R5C_NEGATIVE_CLAUSE3_FAILED",
        "R5C_NEGATIVE_CLAUSE4_FAILED",
        "R5C_NEGATIVE_CLAUSE5_FAILED",
        "R5C_NON_EVIDENCE_COLUMN_CHANGED",
        "R5C_STORAGE_SHAPE_INVALID",
        "R5C_REHYDRATED_EVIDENCE_MISMATCH",
        "R5C_ASSERTION_SET_NOT_FOUND",
        "R5C_ASSERTION_SET_CONTENT_HASH_MISMATCH",
        "R5C_VALIDATOR_SHA256_CHANGED",
    ):
        assert marker in text

def test_r5c_all_assertion_complete_readers_use_rehydration():
    text = sql()
    for name in (
        "fn_guard_input_family_assessment_update",
        "fn_guard_input_family_execution_update",
        "fn_guard_input_validator_semantic_coherence_v512",
        "fn_input_auth006_build_assertions",
        "fn_input_owner_decision_assertions",
        "fn_input_v58_build_assertions",
    ):
        assert name in text
    assert "fn_input_validator_evidence_rehydrate_v1" in text

def test_r5c_terminal_invalid_updates_remain_immutable():
    text = sql()
    assert "VALIDATOR_RECEIPT_IMMUTABLE" in text
    assert "fn_guard_input_governance_continuation_currentness_v1" in text
