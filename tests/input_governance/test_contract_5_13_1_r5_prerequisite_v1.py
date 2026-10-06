from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "supabase/migrations/20261006210000_input_governance_contract_5_13_1_validator_evidence_storage_v1.sql"


def sql() -> str:
    return MIGRATION.read_text(encoding="utf-8")


def test_train_owns_transaction_boundary():
    text = sql().strip().lower()
    assert not text.startswith("begin;")
    assert not text.endswith("commit;")


def test_orphan_gate_is_exact_and_fail_closed():
    text = sql()
    assert "CONTRACT_5131_ORPHANS_DETECTED" in text
    assert "array[22,309]::bigint[]" in text
    assert "CONTRACT_5131_ORPHAN_SET_REVIEW_REQUIRED" in text
    assert "CONTRACT_5131_LIVE_NONTERMINAL_RUNS_PRESENT" in text
    assert "cc.pantalla_id=rr.pantalla_id" in text
    assert "cc.status='COMPLETED'" in text
    assert "cc.invalidated_at is null" in text
    assert "cc.created_at>rr.created_at" in text


def test_negative_live_nonterminal_selftest_exists():
    text = sql()
    assert "CONTRACT_5131_ORPHAN_RULE_SELFTEST_FAILED" in text
    assert "array[2]::bigint[]" in text
    assert "array[1]::bigint[]" in text


def test_revision_lineage_preserves_513_snapshot_and_512_link():
    text = sql()
    assert "'previous_especificacion',c.especificacion" in text
    assert "'previous_lineage',c.especificacion->'revision_lineage'" in text
    assert "55e67871bd13b203927ed0b5978128d6462807481c1a062e2a6ac1a3092bddca" in text
    assert "e2db44d0bc4aeb6f5205d95f84c3366d37cf1644b5ec69dfd3240c4c82bbf25b" in text
    assert "CONTRACT_5131_PREVIOUS_SNAPSHOT_SHA_MISMATCH" in text


def test_exact_final_contract_and_function_identities_are_pinned():
    text = sql()
    assert "dc78d22793bfbb78a3d678b91ffdff39a3499a36d3824c65c181734e80c57516" in text
    for md5 in (
        "9c605193666ec694e0ca6a550fe7e48e",
        "916176f62880f6987fb99d4703b32a2a",
        "ce4ac1c826648c4a981a1dc65da216cb",
        "81d56655cdd96927b62aa3aef7359e35",
        "9ffa930caf6c197993bd2c3f36c9f8d9",
    ):
        assert md5 in text
    assert text.count("CONTRACT_5131_FINAL_FUNCTION_MD5_MISMATCH") == 5
