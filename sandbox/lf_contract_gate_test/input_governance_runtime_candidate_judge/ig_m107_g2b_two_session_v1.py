#!/usr/bin/env python3
"""Bounded IG M10.7 G2B two-backend fixture-only proof.

Distinct from N9: the trusted judge transport dispatches this exact pre-admitted
case without executing candidate SQL or importing code from the request branch.
No production consumer, source authority, workflow or credential modifications.
"""
from __future__ import annotations

import json
import threading
import time
import uuid
from contextlib import suppress
from typing import Any

TABLE = "programacion.input_g2b_source_fixture_v1"
GATE = "programacion.fn_input_g2b_fixture_commit_gate_v1"
SHA_GATE = "4499f9baaf98786b8a6146596da6ff3e"
SHA_BUMP = "4a76bae0863d718cb52f294ffca0a992"
CONTRACT = "c" * 64
RUN_ID = 900001
PANTALLA_ID = 43
SQL_GATE = (
    "SELECT " + GATE
    + "(%s::uuid,%s::bigint,%s::integer,%s::text,%s::bigint,%s::text)"
)


class G2BError(RuntimeError):
    pass


def require(condition: bool, code: str) -> None:
    if not condition:
        raise G2BError(code)


def one(conn: Any, query: str, args: tuple = ()) -> Any:
    return conn.execute(query, args).fetchone()[0]


def receipt(conn: Any, key: uuid.UUID, epoch: int, sha: str,
            run_id: int = RUN_ID, contract: str = CONTRACT,
            pantalla_id: int = PANTALLA_ID) -> dict:
    data = one(conn, SQL_GATE,
               (str(key), run_id, pantalla_id, contract, epoch, sha))
    require(isinstance(data, dict), "G2B_GATE_OUTPUT_INVALID")
    return data


def insert(conn: Any, key: uuid.UUID, value: str, run_id: int = RUN_ID) -> None:
    conn.execute(
        "INSERT INTO " + TABLE +
        " (fixture_key,run_id,pantalla_id,contract_sha256,source_payload)"
        " VALUES (%s::uuid,%s::bigint,%s::integer,%s::text,%s::jsonb)",
        (str(key), run_id, PANTALLA_ID, CONTRACT, json.dumps({"rule": value})),
    )
    conn.commit()


def snapshot(conn: Any, key: uuid.UUID) -> tuple[int, str]:
    row = conn.execute(
        "SELECT source_epoch,programacion.fn_v09_sha256_jsonb(source_payload)"
        " FROM " + TABLE + " WHERE fixture_key=%s::uuid", (str(key),)
    ).fetchone()
    require(row is not None, "G2B_FIXTURE_MISSING")
    return int(row[0]), str(row[1])


def replace(conn: Any, key: uuid.UUID, value: str) -> None:
    conn.execute(
        "UPDATE " + TABLE + " SET source_payload=%s::jsonb"
        " WHERE fixture_key=%s::uuid",
        (json.dumps({"rule": value}), str(key)),
    )
    conn.commit()


def preflight(conn: Any) -> dict:
    row = conn.execute(
        "SELECT md5(pg_get_functiondef("
        "'programacion.fn_input_g2b_fixture_commit_gate_v1(uuid,bigint,integer,text,bigint,text)'::regprocedure)),"
        "md5(pg_get_functiondef("
        "'programacion.fn_input_g2b_fixture_epoch_bump_v1()'::regprocedure)),"
        "(SELECT count(*) FROM " + TABLE + "),"
        "(SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid "
        "JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal "
        "AND t.tgenabled IN ('O','A') AND n.nspname='programacion' "
        "AND c.relname IN "
        "('input_family_assessments','input_gap_proposals','input_readiness_runs')),"
        "(SELECT count(*) FROM public.lf_error_knowledge "
        "WHERE codigo='IG-M107-FROZEN-CONTEXT-FINAL-COMMIT-FENCE-019')"
    ).fetchone()
    require(row is not None and row[0] == SHA_GATE and row[1] == SHA_BUMP,
            "G2B_FIXTURE_FUNCTION_FINGERPRINT_DRIFT")
    require(row[2] == 0, "G2B_FIXTURE_NOT_EMPTY_BEFORE_TEST")
    require(row[3] == 21, "G2B_CANONICAL_TRIGGER_INVENTORY_DRIFT")
    require(row[4] == 1, "G2B_GOVERNED_CONTRACT_MISSING")
    return {"fixture_rows_before": row[2], "canonical_triggers": row[3],
            "gate_md5": row[0], "epoch_trigger_md5": row[1]}


def run(connect) -> dict:
    keys: list[uuid.UUID] = []
    checks: dict[str, bool] = {}
    started = time.monotonic()
    phase_times: dict[str, int] = {}
    from psycopg.rows import tuple_row
    a = connect()
    b = connect()
    # The existing N9 client uses dict_row; this isolated test expects
    # positional SQL columns and changes only its own connection instances.
    a.row_factory = tuple_row
    b.row_factory = tuple_row
    try:
        pre = preflight(a)
        a.commit()
        a_pid = int(one(a, "SELECT pg_backend_pid()"))
        b_pid = int(one(b, "SELECT pg_backend_pid()"))
        require(a_pid != b_pid, "G2B_NOT_TWO_DISTINCT_PG_BACKENDS")
        isolation_a = one(a, "SHOW transaction_isolation")
        isolation_b = one(b, "SHOW transaction_isolation")
        require(isolation_a == "read committed" and isolation_b == "read committed",
                "G2B_ISOLATION_MISMATCH")
        a.commit()
        b.commit()
        checkpoints = time.monotonic()

        # Case 1: stable snapshot accepted by same-transaction check + write.
        k1 = uuid.uuid4()
        keys.append(k1)
        insert(a, k1, "A")
        e1, sha1 = snapshot(a, k1)
        ans = receipt(a, k1, e1, sha1)
        checks["positive_unchanged"] = ans.get("accepted") is True
        require(checks["positive_unchanged"], "G2B_STABLE_FIXTURE_NOT_ACCEPTED")
        a.commit()
        checks["committed_positive"] = one(
            b, "SELECT close_status='ACCEPTED' FROM " + TABLE
            + " WHERE fixture_key=%s::uuid", (str(k1),)
        ) is True
        require(checks["committed_positive"], "G2B_ACCEPTANCE_NOT_COMMITTED")
        b.commit()

        # Case 2: A pins a snapshot; B commits a real payload change; A rejects.
        k2 = uuid.uuid4()
        keys.append(k2)
        insert(a, k2, "A")
        epoch_before, old_sha = snapshot(a, k2)
        require(epoch_before == 1, "G2B_INVALID_INITIAL_EPOCH")
        replace(b, k2, "B")  # B really COMMITs independently of A.
        new_epoch, new_sha = snapshot(a, k2)
        checks["b_commit_visible"] = new_epoch == 2 and new_sha != old_sha
        require(checks["b_commit_visible"], "G2B_B_COMMIT_NOT_VISIBLE")
        stale = receipt(a, k2, epoch_before, old_sha)
        checks["stale_rejected"] = (
            stale.get("accepted") is False
            and stale.get("code") == "G2B_SOURCE_EPOCH_CHANGED")
        require(checks["stale_rejected"], "G2B_FALSE_PASS_AFTER_COMMITTED_WRITE")
        neg_cross = receipt(a, k2, new_epoch, new_sha, run_id=RUN_ID + 1)
        checks["cross_run_rejected"] = (
            neg_cross.get("accepted") is False
            and neg_cross.get("code") == "G2B_IDENTITY_MISMATCH")
        require(checks["cross_run_rejected"], "G2B_CROSS_RUN_ACCEPTED")
        neg_contract = receipt(a, k2, new_epoch, new_sha, contract="x" * 64)
        checks["contract_rejected"] = (
            neg_contract.get("accepted") is False
            and neg_contract.get("code") == "G2B_CONTRACT_CHANGED")
        require(checks["contract_rejected"], "G2B_STALE_CONTRACT_ACCEPTED")
        neg_tamper = receipt(a, k2, new_epoch, "0" * 64)
        checks["source_hash_rejected"] = (
            neg_tamper.get("accepted") is False
            and neg_tamper.get("code") == "G2B_SOURCE_SHA_CHANGED")
        require(checks["source_hash_rejected"], "G2B_TAMPERED_SOURCE_ACCEPTED")
        valid = receipt(a, k2, new_epoch, new_sha)
        checks["new_snapshot_accepted"] = valid.get("accepted") is True
        require(checks["new_snapshot_accepted"], "G2B_FRESH_SOURCE_NOT_ACCEPTED")
        a.commit()
        phase_times["stale_and_negative_ms"] = int(
            (time.monotonic() - checkpoints) * 1000)

        # Case 3: A checks + writes under row lock, holds transaction; B waits.
        k3 = uuid.uuid4()
        keys.append(k3)
        insert(a, k3, "A")
        epoch3, sha3 = snapshot(a, k3)
        accepted = receipt(a, k3, epoch3, sha3)
        checks["lock_gate_accepted"] = accepted.get("accepted") is True
        require(checks["lock_gate_accepted"], "G2B_GATE_NOT_ACCEPTED")
        started_b = threading.Event()
        finished_b = threading.Event()
        writer_error: list[BaseException] = []
        writer_elapsed = [0.0]

        def writer() -> None:
            t = time.monotonic()
            try:
                with b.cursor() as cur:
                    cur.execute("SET LOCAL lock_timeout='5000ms'")
                    started_b.set()
                    cur.execute(
                        "UPDATE " + TABLE
                        + " SET source_payload=%s::jsonb WHERE fixture_key=%s::uuid",
                        (json.dumps({"rule": "B"}), str(k3)),
                    )
                b.commit()
                writer_elapsed[0] = time.monotonic() - t
            except BaseException as exc:
                writer_error.append(exc)
                b.rollback()
            finally:
                finished_b.set()

        th = threading.Thread(target=writer, daemon=True)
        th.start()
        require(started_b.wait(3), "G2B_WRITER_NOT_STARTED")
        time.sleep(0.4)
        checks["writer_blocked_before_a_commit"] = not finished_b.is_set()
        require(checks["writer_blocked_before_a_commit"],
                "G2B_WRITER_CROSSED_ATOMIC_CLOSE")
        a.commit()  # Only now may B UPDATE and COMMIT.
        require(finished_b.wait(4), "G2B_B_NOT_RELEASED_AFTER_COMMIT")
        th.join(1)
        require(not writer_error, "G2B_WRITER_FAILURE:" +
                str(writer_error[0])[:200] if writer_error else
                "G2B_WRITER_FAILURE")
        checks["writer_released_after_commit"] = writer_elapsed[0] >= 0.35
        require(checks["writer_released_after_commit"], "G2B_WRITER_NOT_SERIALIZED")
        after = b.execute(
            "SELECT source_epoch,close_status,source_payload FROM " + TABLE +
            " WHERE fixture_key=%s::uuid", (str(k3),)
        ).fetchone()
        checks["postcommit_mutation_new_epoch"] = (
            after is not None and after[0] == 2
            and after[1] == "OPEN" and after[2] == {"rule": "B"}
        )
        require(checks["postcommit_mutation_new_epoch"],
                "G2B_POSTCOMMIT_REVERSION_FAILED")
        b.commit()
        phase_times["full_elapsed_ms"] = int((time.monotonic() - started) * 1000)
        return {
            "schema_version": "LF_IG_G2B_TWO_SESSION_FIXTURE_EVIDENCE_V1",
            "test_result": "PASS_FIXTURE_ONLY",
            "two_backend_pids": [a_pid, b_pid],
            "isolation": [isolation_a, isolation_b],
            "checks": checks,
            "all_checks_passed": all(checks.values()),
            "preflight": pre,
            "timing": phase_times,
            "g2b_end_to_end_authority_pass": False,
            "all_real_source_writers_covered": False,
            "runtime_activated": False,
            "scope": "FIXTURE_ONLY",
        }
    finally:
        with suppress(Exception):
            a.rollback()
        with suppress(Exception):
            b.rollback()
        # Delete only exact UUIDs generated by this test; commits remain
        # bounded to the isolated fixture, not LF production/source tables.
        try:
            for key in keys:
                a.execute("DELETE FROM " + TABLE + " WHERE fixture_key=%s::uuid",
                          (str(key),))
            a.commit()
            residual = int(one(a, "SELECT count(*) FROM " + TABLE))
            a.commit()
            require(residual == 0, "G2B_FIXTURE_RESIDUE")
        finally:
            a.close()
            b.close()


def self_test() -> None:
    require(TABLE == "programacion.input_g2b_source_fixture_v1", "BAD_TARGET")
    require(GATE.endswith("_commit_gate_v1"), "BAD_GATE")
    require(len(CONTRACT) == 64, "BAD_CONTRACT")
    print("G2B_REQUEST_BOUNDARY_SELFTEST_PASS")
