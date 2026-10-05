#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
TARGET = HERE / "lf_migration_exact_apply.py"
spec = importlib.util.spec_from_file_location("lf_migration_exact_apply", TARGET)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
assert spec.loader is not None
spec.loader.exec_module(module)


def main() -> int:
    checks = 0

    observed = module.pending_versions_from_dry_run(
        "DRY RUN\nWould push migration 20261005235959_local_probe_v1.sql\n"
    )
    assert observed == ["20261005235959"]
    checks += 1

    assert module.pending_versions_from_dry_run("No migrations to push") == []
    checks += 1

    source = "begin;\nselect 1;\ncommit;\n"
    sql = module.build_fallback_sql(
        version="20261005235959",
        name="local_probe_v1",
        source_sql=source,
        source_blob="a" * 40,
    )
    assert source in sql
    assert "'20261005235959'" in sql
    assert "'local_probe_v1'" in sql
    assert "SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML" in sql
    assert "gitblob:" + "a" * 40 in sql
    checks += 1

    try:
        module.build_fallback_sql(
            version="20261005235959",
            name="local_probe_v1",
            source_sql=source,
            source_blob="bad",
        )
    except ValueError as exc:
        assert str(exc) == "EXACT_APPLY_SOURCE_BLOB_INVALID"
    else:
        raise AssertionError("bad blob accepted")
    checks += 1

    old = dict(os.environ)
    try:
        os.environ["LF_SUPABASE_DB_PASSWORD"] = "p@ss/word"
        os.environ["SUPABASE_PROJECT_ID"] = "abc"
        os.environ["SUPABASE_POOLER_HOST"] = "pooler.example"
        url = module.build_db_url()
        assert "p%40ss%2Fword" in url
        assert "postgres.abc" in url
    finally:
        os.environ.clear()
        os.environ.update(old)
    checks += 1

    decision = module.TRANSPORT.select_transport(
        "MIGRATION",
        "supabase/migrations/20261005235959_local_probe_v1.sql",
    )
    assert decision.executor == "SUPABASE_CLI_DB_PUSH_LINKED"
    assert decision.fallback_executor == "SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML"
    checks += 1

    print(f"PASS_MIGRATION_EXACT_APPLY_UNIT_TESTS={checks}/6")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
