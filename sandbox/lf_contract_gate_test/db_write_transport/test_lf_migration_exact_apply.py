#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

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

    assert module.postgres_sqlstate("ERROR:  42501: insufficient privilege") == "42501"
    assert module.postgres_sqlstate("ERROR: controlled failure") is None
    assert module.postgres_sqlstate("ERROR: pipeline EKB writer failed") is None
    assert module.postgres_sqlstate("could not connect to server") is None
    assert module.fallback_allowed("psql: error: connection refused", allow_fallback=True)
    assert not module.fallback_allowed("ERROR:  42501: permission denied", allow_fallback=True)
    assert not module.fallback_allowed("ERROR: pipeline EKB writer failed", allow_fallback=True)
    assert not module.fallback_allowed("connection refused", allow_fallback=False)
    assert module.fallback_allowed("DRY_RUN_FAILED:exit_code=1:Remote migration history mismatch", allow_fallback=True)
    assert not module.fallback_allowed("DRY_RUN_FAILED:ERROR:  42501: denied", allow_fallback=True)
    assert module.fallback_allowed("could not connect to server", allow_fallback=True)
    checks += 1
    noisy = "DRY RUN: migrations will *not* be pushed\nConnecting to remote database...\nSkipping migration 20261014174311_x.sql (file name must match pattern)\nERROR: Remote migration version mismatch"
    clean = module.sanitize_dry_run_output(noisy)
    assert "Skipping migration" not in clean and "DRY RUN:" not in clean and "Connecting to remote" not in clean
    assert "ERROR: Remote migration version mismatch" in clean
    assert module.sanitize_dry_run_output("x" * 40, limit=12).endswith("x" * 11)
    assert len(module.sanitize_dry_run_output("z" * 1000)) == 800
    long_dry_run = ("Remote migration versions not found in local migrations directory\\n"
                    + "version " * 500 + "\\nAnd update local migrations to match remote database:\\nsupabase db pull")
    preserved_tail = module.sanitize_dry_run_output(long_dry_run)
    assert len(preserved_tail) <= 800
    assert "Remote migration versions not found in local migrations directory" in preserved_tail
    assert preserved_tail.endswith("supabase db pull")
    checks += 1

    version = "20261014174311"
    name = "probe_v1"
    decision = SimpleNamespace(executor="SUPABASE_CLI_DB_PUSH_LINKED",
                               fallback_executor="SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML",
                               migration_version=version, migration_name=name)
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        migration = root / f"{version}_{name}.sql"
        migration.write_text("select 1;", encoding="utf-8")
        base = "00000000000000"
        # Exact psql application is authoritative; a nonzero dry-run is diagnostic only.
        with patch.object(module.TRANSPORT, "select_transport", return_value=decision), \
             patch.object(module, "read_ledger", side_effect=[(None, None, None), (version, name, "writer")]), \
             patch.object(module, "read_ledger_max", return_value=base), \
             patch.object(module, "_primary_cli", return_value=(1, "Remote migration mismatch")), \
             patch.object(module, "_fallback_apply") as exact_apply:
            result = module.apply_exact(project_root=root, migration_path=migration,
                                        db_url="postgres://example", source_blob="a" * 40,
                                        allow_fallback=True)
            assert not result.fallback_used and result.code == "EXACT_APPLIED"
            assert result.apply_path == "PSQL_EXACT" and result.executor == "PSQL_EXACT"
            assert result.dry_run_exit_code == 1 and result.dry_run_tail == "Remote migration mismatch"
            exact_apply.assert_called_once()
        checks += 1

        # An already-applied version is read back and never replayed.
        with patch.object(module.TRANSPORT, "select_transport", return_value=decision), \
             patch.object(module, "read_ledger", return_value=(version, name, "writer")), \
             patch.object(module, "_primary_cli") as diagnostic, \
             patch.object(module, "_fallback_apply") as exact_apply:
            result = module.apply_exact(project_root=root, migration_path=migration,
                                        db_url="postgres://example", source_blob="a" * 40,
                                        allow_fallback=True)
            assert result.code == "ALREADY_APPLIED_EXACT"
            diagnostic.assert_not_called()
            exact_apply.assert_not_called()
        checks += 1

        # A Postgres ERROR fails the one exact apply; there is no second attempt.
        with patch.object(module.TRANSPORT, "select_transport", return_value=decision), \
             patch.object(module, "read_ledger", side_effect=[(None, None, None)]), \
             patch.object(module, "read_ledger_max", return_value=base), \
             patch.object(module, "_primary_cli", return_value=(0, "dry-run ok")), \
             patch.object(module, "_fallback_apply", side_effect=RuntimeError("ERROR:  42501: denied")) as exact_apply:
            try:
                module.apply_exact(project_root=root, migration_path=migration,
                                   db_url="postgres://example", source_blob="a" * 40,
                                   allow_fallback=True)
            except RuntimeError as exc:
                assert "EXACT_APPLY_PSQL_FAILED:sqlstate=42501" in str(exc)
            else:
                raise AssertionError("Postgres ERROR unexpectedly succeeded")
            exact_apply.assert_called_once()
        checks += 1

        # A connection error also fails without a retry; the dry-run remains diagnostic only.
        with patch.object(module.TRANSPORT, "select_transport", return_value=decision), \
             patch.object(module, "read_ledger", side_effect=[(None, None, None)]), \
             patch.object(module, "read_ledger_max", return_value=base), \
             patch.object(module, "_primary_cli", return_value=(1, "connection refused")), \
             patch.object(module, "_fallback_apply", side_effect=RuntimeError("could not connect to server")) as exact_apply:
            try:
                module.apply_exact(project_root=root, migration_path=migration,
                                   db_url="postgres://example", source_blob="a" * 40,
                                   allow_fallback=True)
            except RuntimeError as exc:
                assert "EXACT_APPLY_PSQL_FAILED:sqlstate=NOT_OBSERVED" in str(exc)
            else:
                raise AssertionError("connection error unexpectedly succeeded")
            exact_apply.assert_called_once()
        checks += 1

        old_receipt = {"code": "FALLBACK_APPLIED_EXACT", "fallback_used": True,
                       "executor": "SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML"}
        assert module.normalize_apply_receipt(old_receipt)["apply_path"] == "PSQL_EXACT"
        assert module.normalize_apply_receipt({"code": "EXACT_APPLIED", "apply_path": "PSQL_EXACT"})["apply_path"] == "PSQL_EXACT"
        checks += 1
    with patch.object(module, "_run", return_value=SimpleNamespace(returncode=0, stdout="ok", stderr="")) as run:
        assert module._psql("postgres://example", "select 1", cwd=Path(".").resolve()) == "ok"
        assert "VERBOSITY=verbose" in run.call_args.args[0]
    assert module._transport_command(["supabase", "db", "push", "--dry-run"])
    assert not module._transport_command(["supabase", "db", "push", "--help"])
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

    checks += 1
    print(f"PASS_MIGRATION_EXACT_APPLY_UNIT_TESTS={checks}/15")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
