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
        M.validate_transaction_safe("x.sql", sql)
    except M.ProbeError as exc:
        assert code in str(exc), str(exc)
    else:
        raise AssertionError(f"expected {code}")


def test_allows_plpgsql_begin_end_inside_dollar_body() -> None:
    M.validate_transaction_safe(
        "x.sql",
        """create or replace function public.f() returns void language plpgsql as $fn$
begin
  perform 1;
end;
$fn$;
""",
    )


def test_blocks_top_level_commit() -> None:
    expect_block("create table x(id int);\ncommit;\n", "BLOCK_DB_CANDIDATE_NONTRANSACTIONAL")


def test_blocks_top_level_begin() -> None:
    expect_block("begin;\ncreate table x(id int);\n", "BLOCK_DB_CANDIDATE_NONTRANSACTIONAL")


def test_blocks_vacuum() -> None:
    expect_block("VACUUM public.x;\n", "BLOCK_DB_CANDIDATE_NONTRANSACTIONAL")


def test_blocks_concurrent_index() -> None:
    expect_block("CREATE INDEX CONCURRENTLY x_i ON x(id);\n", "BLOCK_DB_CANDIDATE_NONTRANSACTIONAL")


def test_ignores_comment_and_string_tokens() -> None:
    M.validate_transaction_safe(
        "x.sql",
        """-- COMMIT;
select 'BEGIN; VACUUM'::text;
/* DROP DATABASE nope; */
create table x(id int);
""",
    )


def main() -> None:
    tests = [
        test_allows_plpgsql_begin_end_inside_dollar_body,
        test_blocks_top_level_commit,
        test_blocks_top_level_begin,
        test_blocks_vacuum,
        test_blocks_concurrent_index,
        test_ignores_comment_and_string_tokens,
    ]
    for test in tests:
        test()
    print(f"LF_DB_CANDIDATE_ROLLBACK_PROBE_TESTS_PASS={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
