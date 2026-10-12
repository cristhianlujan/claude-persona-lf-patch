#!/usr/bin/env python3
from __future__ import annotations

import base64
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "lf_migration_lifecycle_reconcile.py"
SPEC = importlib.util.spec_from_file_location("lf_migration_lifecycle_reconcile", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
mod = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = mod
SPEC.loader.exec_module(mod)


def entry(version: str, name: str, raw: bytes, statement_count: int = 1) -> dict[str, object]:
    return {
        "version": version,
        "name": name,
        "statement_count": statement_count,
        "source_base64": base64.b64encode(raw).decode("ascii"),
        "source_git_blob_sha1": mod.git_blob_sha1(raw),
        "source_sha256": mod.sha256(raw),
    }


def test_detect_and_recover_exact_remote_only(tmp_path: Path) -> None:
    migrations = tmp_path / "migrations"
    migrations.mkdir()
    raw = b"select 1;\n"
    ledger_path = tmp_path / "ledger.json"
    ledger_path.write_text(
        json.dumps([entry("20260914010101", "s30_exact_recovery_v1", raw)]),
        encoding="utf-8",
    )
    ledger = mod.load_ledger(ledger_path)
    local = mod.load_local(migrations)
    detect = mod.reconcile(
        ledger=ledger,
        local=local,
        migrations_dir=migrations,
        owner_prefix="s30_",
        min_version=None,
        max_version=None,
        materialize_remote_only=False,
    )
    assert detect["state"] == "DRIFT_DETECTED"
    assert detect["remote_only"] == ["20260914010101"]

    recovered = mod.reconcile(
        ledger=ledger,
        local=local,
        migrations_dir=migrations,
        owner_prefix="s30_",
        min_version=None,
        max_version=None,
        materialize_remote_only=True,
    )
    assert recovered["state"] == "RECOVERED_TO_WORKTREE"
    target = migrations / "20260914010101_s30_exact_recovery_v1.sql"
    assert target.read_bytes() == raw
    assert mod.git_blob_sha1(target.read_bytes()) == mod.git_blob_sha1(raw)


def test_multistatement_recovery_blocks(tmp_path: Path) -> None:
    migrations = tmp_path / "migrations"
    migrations.mkdir()
    raw = b"select 1;\nselect 2;\n"
    ledger_path = tmp_path / "ledger.json"
    ledger_path.write_text(
        json.dumps([entry("20260914010102", "s30_multi_statement_v1", raw, statement_count=2)]),
        encoding="utf-8",
    )
    receipt = mod.reconcile(
        ledger=mod.load_ledger(ledger_path),
        local=mod.load_local(migrations),
        migrations_dir=migrations,
        owner_prefix="s30_",
        min_version=None,
        max_version=None,
        materialize_remote_only=True,
    )
    assert receipt["state"] == "BLOCKED"
    assert receipt["blocked_recovery"] == [
        {"version": "20260914010102", "reason": "STATEMENT_COUNT_NOT_ONE"}
    ]
    assert not list(migrations.iterdir())


def test_tampered_git_blob_proof_rejected(tmp_path: Path) -> None:
    migrations = tmp_path / "migrations"
    migrations.mkdir()
    raw = b"select 1;\n"
    item = entry("20260914010103", "s30_tampered_proof_v1", raw)
    item["source_git_blob_sha1"] = "0" * 40
    ledger_path = tmp_path / "ledger.json"
    ledger_path.write_text(json.dumps([item]), encoding="utf-8")
    ledger = mod.load_ledger(ledger_path)
    try:
        mod.reconcile(
            ledger=ledger,
            local=mod.load_local(migrations),
            migrations_dir=migrations,
            owner_prefix="s30_",
            min_version=None,
            max_version=None,
            materialize_remote_only=True,
        )
    except mod.ReconcileError as exc:
        assert str(exc) == "LEDGER_SOURCE_GIT_SHA1_MISMATCH:20260914010103"
    else:
        raise AssertionError("tampered proof was accepted")
