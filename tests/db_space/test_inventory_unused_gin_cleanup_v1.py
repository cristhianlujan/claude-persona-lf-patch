from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
MIG=ROOT/"supabase/migrations/20261006225000_inventory_unused_gin_cleanup_v1.sql"

def sql():
    return MIG.read_text(encoding="utf-8")

def test_only_three_audited_gins_are_dropped():
    text=sql().lower()
    for idx in (
        "inventory.inventory_objects_metadata_gin",
        "inventory.inventory_search_tags_gin",
        "inventory.inventory_search_columns_gin",
    ):
        assert f"drop index {idx};" in text
    assert "drop index inventory.inventory_search_document_gin" not in text

def test_runtime_use_is_fail_closed():
    text=sql()
    assert "INVENTORY_GIN_RUNTIME_USE_DETECTED" in text
    assert "v.idx_scan<>0" in text

def test_exact_definitions_are_pinned():
    text=sql()
    assert "INVENTORY_GIN_DEFINITION_DRIFT" in text
    assert "CREATE INDEX inventory_objects_metadata_gin ON inventory.objects USING gin (metadata)" in text
    assert "CREATE INDEX inventory_search_tags_gin ON inventory.search_index USING gin (tags_lc)" in text
    assert "CREATE INDEX inventory_search_columns_gin ON inventory.search_index USING gin (column_names_lc)" in text

def test_full_text_gin_must_remain():
    assert "INVENTORY_SEARCH_DOCUMENT_GIN_MUST_REMAIN" in sql()
