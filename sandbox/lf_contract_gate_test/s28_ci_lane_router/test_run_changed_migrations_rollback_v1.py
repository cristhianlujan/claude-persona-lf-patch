#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "run_changed_migrations_rollback_v1.py"


def load():
    spec = importlib.util.spec_from_file_location("lf_candidate_probe_tested", TARGET)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


M = load()


def expect_block(sql: str, code: str) -> None:
    try:
        M.prepare_transaction_payload("x.sql", sql)
    except M.ProbeError as exc:
        assert code in str(exc), str(exc)
    else:
        raise AssertionError(f"expected {code}")


def test_allows_plpgsql_begin_end_inside_dollar_body() -> None:
    source = """create or replace function public.f() returns void language plpgsql as $fn$
begin
  perform 1;
end;
$fn$;
"""
    payload, frame = M.prepare_transaction_payload("x.sql", source)
    assert payload == source
    assert frame["mode"] == "NONE"


def test_allows_and_normalizes_single_outer_begin_commit() -> None:
    source = """-- migration wrapper
begin;

create table x(id int);
do $block$
begin
  perform 1;
end;
$block$;

commit;
-- trailing comment
"""
    payload, frame = M.prepare_transaction_payload("x.sql", source)
    assert frame["mode"] == "SINGLE_OUTER_BEGIN_COMMIT_NORMALIZED"
    assert frame["source_transaction_statements"] == 2
    assert frame["interior_material_preserved"] is True
    assert "create table x(id int);" in payload
    assert "perform 1;" in payload
    code = M.strip_non_code(payload)
    assert not M.TX_STMT.search(code)
    assert len(payload.encode("utf-8")) == len(source.encode("utf-8"))
    assert frame["source_sha256"] != frame["execution_payload_sha256"]


def test_blocks_lone_top_level_commit() -> None:
    expect_block(
        "create table x(id int);\ncommit;\n",
        "BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL",
    )


def test_blocks_lone_top_level_begin() -> None:
    expect_block(
        "begin;\ncreate table x(id int);\n",
        "BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL",
    )


def test_blocks_rollback_even_with_begin() -> None:
    expect_block(
        "begin;\ncreate table x(id int);\nrollback;\n",
        "BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL",
    )


def test_blocks_multiple_transaction_frames() -> None:
    expect_block(
        "begin;\ncreate table x(id int);\ncommit;\nbegin;\nselect 1;\ncommit;\n",
        "BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL",
    )


def test_blocks_code_before_outer_begin() -> None:
    expect_block(
        "select 1;\nbegin;\ncreate table x(id int);\ncommit;\n",
        "BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL",
    )


def test_blocks_code_after_outer_commit() -> None:
    expect_block(
        "begin;\ncreate table x(id int);\ncommit;\nselect 1;\n",
        "BLOCK_DB_CANDIDATE_TRANSACTION_CONTROL",
    )


def test_blocks_vacuum_inside_outer_frame() -> None:
    expect_block(
        "begin;\nVACUUM public.x;\ncommit;\n",
        "BLOCK_DB_CANDIDATE_NONTRANSACTIONAL",
    )


def test_blocks_concurrent_index_inside_outer_frame() -> None:
    expect_block(
        "begin;\nCREATE INDEX CONCURRENTLY x_i ON x(id);\ncommit;\n",
        "BLOCK_DB_CANDIDATE_NONTRANSACTIONAL",
    )


def test_ignores_comment_and_string_tokens() -> None:
    source = """-- COMMIT;
select 'BEGIN; VACUUM'::text;
/* DROP DATABASE nope; */
create table x(id int);
"""
    payload, frame = M.prepare_transaction_payload("x.sql", source)
    assert payload == source
    assert frame["mode"] == "NONE"


def test_start_transaction_outer_frame_is_supported() -> None:
    source = """START TRANSACTION;
select 1;
COMMIT;
"""
    payload, frame = M.prepare_transaction_payload("x.sql", source)
    assert frame["mode"] == "SINGLE_OUTER_BEGIN_COMMIT_NORMALIZED"
    assert frame["source_open_kind"] == "START TRANSACTION"
    assert not M.TX_STMT.search(M.strip_non_code(payload))



def test_migration_identity_is_strict() -> None:
    version, name = M.migration_identity(
        "supabase/migrations/20260918054000_lf_s30_operation_policy_context_admission_v1.sql"
    )
    assert version == "20260918054000"
    assert name == "lf_s30_operation_policy_context_admission_v1"
    try:
        M.migration_identity("supabase/migrations/not_a_canonical_name.sql")
    except M.ProbeError as exc:
        assert "FAIL_DB_CANDIDATE_MIGRATION_IDENTITY" in str(exc)
    else:
        raise AssertionError("expected strict migration identity failure")


def main() -> None:
    tests = [
        test_allows_plpgsql_begin_end_inside_dollar_body,
        test_allows_and_normalizes_single_outer_begin_commit,
        test_blocks_lone_top_level_commit,
        test_blocks_lone_top_level_begin,
        test_blocks_rollback_even_with_begin,
        test_blocks_multiple_transaction_frames,
        test_blocks_code_before_outer_begin,
        test_blocks_code_after_outer_commit,
        test_blocks_vacuum_inside_outer_frame,
        test_blocks_concurrent_index_inside_outer_frame,
        test_ignores_comment_and_string_tokens,
        test_start_transaction_outer_frame_is_supported,
        test_migration_identity_is_strict,
    ]
    for test in tests:
        test()
    print(f"LF_DB_CANDIDATE_ROLLBACK_PROBE_TESTS_PASS={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
