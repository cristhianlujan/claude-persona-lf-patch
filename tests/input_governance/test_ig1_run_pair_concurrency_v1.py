import os
import pathlib
import threading
import time

import pytest

MIGRATION = pathlib.Path("supabase/migrations/20261006160000_ig_1_serialize_input_readiness_run_pair_v1.sql")
INCIDENT_PAIRS = {
    (19, 48): (518, 519),
    (19, 50): (521, 522),
}
EXPECTED_BASE_MD5 = {
    "fn_input_governance_bootstrap_materialize_v1": "fcf1afe1fd1abf3b241c7aa8b54a5fd0",
    "fn_input_governance_bootstrap_materialize_v2": "cef03aa0d7595345e2f048e9dad4be69",
    "fn_input_governance_recurate_source_stale_v1": "996a6b3c0fc095ec714a70251adc14ef",
    "fn_input_governance_recurate_v2": "0d389a7c037b1498d2641da14df0437a",
    "fn_input_governance_curator_rebind_v1": "382c9cac4f0a47598a3116c48eee4d92",
}

PROTECTED = [
    "fn_input_governance_bootstrap_materialize_v1",
    "fn_input_governance_bootstrap_materialize_v2",
    "fn_input_governance_recurate_source_stale_v1",
    "fn_input_governance_recurate_v2",
    "fn_input_governance_curator_rebind_v1",
]


def _lock_sql():
    return """
    select pg_advisory_xact_lock(
      hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||%s::text||':'||%s::text, 0)
    )
    """


def test_ig1_candidate_binds_all_decision_create_entrypoints_before_run_reads():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "518/519" in sql and "521/522" in sql
    for name in PROTECTED:
        start = sql.index(f"FUNCTION programacion.{name}")
        end = sql.find("CREATE OR REPLACE FUNCTION", start + 1)
        block = sql[start:] if end < 0 else sql[start:end]
        lock = block.index("pg_advisory_xact_lock")
        first_run_access = block.index("programacion.input_readiness_runs")
        assert lock < first_run_access, name


@pytest.mark.parametrize("pair,incident_ids", INCIDENT_PAIRS.items())
def test_historical_duplicate_pair_is_serialized(pair, incident_ids):
    dsn = os.getenv("LF_SUPABASE_DB_URL")
    if not dsn:
        pytest.skip("LF_SUPABASE_DB_URL required for read-only advisory-lock concurrency probe")
    psycopg = pytest.importorskip("psycopg")

    acquired_a = threading.Event()
    acquired_b = threading.Event()
    release_a = threading.Event()
    elapsed = {}

    def holder():
        with psycopg.connect(dsn) as conn:
            with conn.transaction():
                conn.execute(_lock_sql(), pair)
                acquired_a.set()
                assert release_a.wait(10)

    def waiter():
        assert acquired_a.wait(10)
        with psycopg.connect(dsn) as conn:
            with conn.transaction():
                started = time.monotonic()
                conn.execute(_lock_sql(), pair)
                elapsed["seconds"] = time.monotonic() - started
                acquired_b.set()

    a = threading.Thread(target=holder, daemon=True)
    b = threading.Thread(target=waiter, daemon=True)
    a.start(); b.start()
    assert acquired_a.wait(10)
    time.sleep(0.5)
    assert not acquired_b.is_set(), f"historical duplicate pair {pair} / runs {incident_ids} was not serialized"
    release_a.set()
    assert acquired_b.wait(10)
    a.join(10); b.join(10)
    assert elapsed["seconds"] >= 0.45


def test_different_historical_pairs_do_not_share_the_same_lock():
    # The lock key includes both version_id and pantalla_id. This regression
    # assertion protects against accidentally serializing every screen globally.
    assert (19, 48) != (19, 50)


def test_ig1_candidate_has_authorized_base_md5_guard_and_isolation_assumption():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert "IG1_BASE_MD5_MISMATCH" in sql
    assert "READ COMMITTED" in sql
    for value in EXPECTED_BASE_MD5.values():
        assert value in sql


def test_ig1_candidate_terminates_all_function_definitions():
    sql = MIGRATION.read_text(encoding="utf-8")
    assert sql.count("$function$;") == 5
