from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIG = ROOT / "supabase/migrations/20261006232000_inventory_distinct_refresh_v1.sql"

def sql() -> str:
    return MIG.read_text(encoding="utf-8")

def section(start: str, end: str) -> str:
    text = sql()
    return text.split(start, 1)[1].split(end, 1)[0]

def test_md5_preflight_pins_live_functions():
    text = sql()
    assert "7c76b882c35721741b0340d12d0d139a" in text
    assert "fbb27646335add35b375fa67433e3855" in text
    assert "1d9c68c09412d99f0e8080cacbc314b2" in text

def test_object_upserts_are_noop_aware():
    text = sql().upper()
    assert text.count("IS DISTINCT FROM") >= 9
    assert "ce7265e91b12eebb4499cdaada9eb9f9" in sql()

def test_search_index_guard_excludes_refreshed_at():
    s = section(
        "create or replace function inventory.fn_refresh_search_index_v1()",
        "do $post$",
    )
    guard = s.lower().split("on conflict(object_id) do update set", 1)[1]
    guard = guard.split("delete from inventory.search_index", 1)[0]
    assert "inventory.search_index.refreshed_at" not in guard
    assert "inventory.search_index.search_document" in guard
    assert "inventory.search_index.currentness" in guard
    assert "inventory.search_index.source_traceability_state" in guard
    assert "inventory.search_index.object_ref like 'repo://%'" in guard
    assert "inventory.search_index.object_ref like 'edge://%'" in guard

def test_catalog_no_longer_refreshes_search_index():
    s = section(
        "create or replace function inventory.fn_refresh_catalog_v2()",
        "create or replace function inventory.fn_refresh_db_details_v2()",
    )
    assert "fn_refresh_search_index_v1" not in s

def test_small_heartbeat_preserves_poll_freshness():
    text = sql()
    assert "create table inventory.refresh_heartbeats_v1" in text.lower()
    assert "PG_CATALOG_CATALOG_V2" in text
    assert "PG_CATALOG_DETAILS_V2" in text
    assert "SEARCH_INDEX_V1" in text

def test_no_cron_schedule_change_in_candidate():
    text = sql().lower()
    assert "cron.schedule" not in text
    assert "cron.alter_job" not in text
    assert "cron.unschedule" not in text
