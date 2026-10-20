#!/usr/bin/env python3
"""Offline tests: pase-merge-gate carrier reads qualification with the read-only CI role only."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "pase_merge_gate_carrier_v1.py"
SHA_A = "a" * 40
SHA_B = "b" * 40


def load():
    spec = importlib.util.spec_from_file_location("pase_merge_gate_carrier_ro_test_target", TARGET)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_CARRIER_LOAD")
    module = importlib.util.module_from_spec(spec)
    import sys

    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def with_env(values: dict[str, str | None], fn):
    saved = {k: os.environ.get(k) for k in values}
    try:
        for key, value in values.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        return fn()
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def expect_block(m, code: str, fn) -> None:
    try:
        fn()
    except m.CarrierError as exc:
        assert exc.code == code, (exc.code, code)
        return
    raise AssertionError(f"expected {code}")


def main() -> int:
    m = load()
    checks = 0

    # 1. Only the write credential present -> fail closed, never used.
    expect_block(
        m,
        "BLOCK_PASE_MERGE_GATE_QUALIFICATION_RO_PASSWORD_MISSING",
        lambda: with_env({"LF_SUPABASE_DB_READONLY_PASSWORD": None, "LF_SUPABASE_DB_PASSWORD": "write-secret"}, m._pg_env),
    )
    checks += 1

    # 2. Nothing present -> fail closed.
    expect_block(
        m,
        "BLOCK_PASE_MERGE_GATE_QUALIFICATION_RO_PASSWORD_MISSING",
        lambda: with_env({"LF_SUPABASE_DB_READONLY_PASSWORD": "  ", "LF_SUPABASE_DB_PASSWORD": None}, m._pg_env),
    )
    checks += 1

    # 3. Read-only credential -> lf_ci_readonly role; write credential stripped from the child env.
    env = with_env(
        {
            "LF_SUPABASE_DB_READONLY_PASSWORD": "ro-secret",
            "LF_SUPABASE_DB_PASSWORD": "write-secret",
            "SUPABASE_PROJECT_ID": None,
            "SUPABASE_POOLER_HOST": None,
        },
        m._pg_env,
    )
    assert env["PGUSER"] == f"lf_ci_readonly.{m.PROJECT_ID}", env["PGUSER"]
    assert env["PGPASSWORD"] == "ro-secret"
    assert env["PGHOST"] == m.POOLER_HOST
    assert "LF_SUPABASE_DB_PASSWORD" not in env
    assert "postgres." not in env["PGUSER"]
    checks += 1

    # 3b. Empty repository variables fall back to the trusted constants (no "lf_ci_readonly." user).
    env = with_env(
        {"LF_SUPABASE_DB_READONLY_PASSWORD": "ro-secret", "SUPABASE_PROJECT_ID": "", "SUPABASE_POOLER_HOST": ""},
        m._pg_env,
    )
    assert env["PGUSER"] == f"lf_ci_readonly.{m.PROJECT_ID}", env["PGUSER"]
    assert env["PGHOST"] == m.POOLER_HOST, env["PGHOST"]
    checks += 1

    # 4. The readback goes through the CI read-only wrapper, not the invoker function.
    captured: dict[str, object] = {}

    def fake_psql_json(sql: str, *, variables):
        captured["sql"] = sql
        captured["variables"] = dict(variables)
        return {"schema_version": "x"}

    original = m._psql_json
    m._psql_json = fake_psql_json
    try:
        m._qualification_readback_from_db(repository="o/r", candidate_id="C", base_sha=SHA_A, head_sha=SHA_B)
    finally:
        m._psql_json = original
    sql = str(captured["sql"])
    assert "public.lf_ci_control_system_qualification_readback_v1(" in sql, sql
    assert "public.lf_control_system_qualification_readback_v1(" not in sql, sql
    assert m.CI_READBACK_FUNCTION in sql
    assert captured["variables"] == {"repository": "o/r", "candidate_id": "C", "base_sha": SHA_A, "head_sha": SHA_B}
    checks += 1

    # 5. Source never reads the write credential.
    source = TARGET.read_text(encoding="utf-8")
    assert 'os.environ.get("LF_SUPABASE_DB_PASSWORD"' not in source
    assert "postgres.{" not in source and 'f"postgres.' not in source
    checks += 1

    # 6. Existing carrier self-test still passes.
    result = m.self_test()
    assert result.get("status") == "PASS_PASE_MERGE_GATE_CARRIER_V1", result
    checks += 1

    print(f"PASS_PASE_MERGE_GATE_CARRIER_READONLY_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
