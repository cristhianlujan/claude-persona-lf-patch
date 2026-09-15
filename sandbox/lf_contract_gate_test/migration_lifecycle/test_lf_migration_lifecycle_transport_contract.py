#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXPORT_SQL = HERE / "lf_migration_lifecycle_export.sql"
RUNNER = HERE / "run_lf_migration_lifecycle_reconcile.sh"


def test_export_owner_scope_is_literal_not_like() -> None:
    sql = EXPORT_SQL.read_text(encoding="utf-8")
    assert "name like" not in sql.lower()
    assert "left(name, length(:'owner_prefix')) = :'owner_prefix'" in sql


def test_runner_shell_syntax_and_optional_bounds_are_fail_closed() -> None:
    text = RUNNER.read_text(encoding="utf-8")
    assert '[[ ! "$owner_prefix" =~ ^[a-z0-9][a-z0-9_]*_$ ]]' in text
    assert 'if [[ -n "$min_version" ]]; then' in text
    assert 'if [[ -n "$max_version" ]]; then' in text
    assert '--min-version "$min_version"\n  --max-version "$max_version"' not in text
    proc = subprocess.run(
        ["bash", "-n", str(RUNNER)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr


def test_runner_rejects_sql_wildcard_owner_prefix_before_db_access() -> None:
    proc = subprocess.run(
        ["bash", str(RUNNER), "--owner-prefix", "s30_%"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert proc.returncode == 2
    assert "FAIL_MIGRATION_LIFECYCLE_OWNER_PREFIX_INVALID=s30_%" in proc.stderr
