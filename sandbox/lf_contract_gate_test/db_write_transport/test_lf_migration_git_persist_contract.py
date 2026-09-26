#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
TARGET = HERE / "lf_migration_git_persist.py"
spec = importlib.util.spec_from_file_location("lf_migration_git_persist", TARGET)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)

base = {
    "repository": "cristhianlujan/claude-persona-lf-patch",
    "base_sha": "a" * 40,
    "source_sha": "b" * 40,
    "source_blob": "c" * 40,
    "source_sha256": "d" * 64,
    "target_path": "supabase/migrations/20260925010101_lf_probe_v1.sql",
    "target_branch": "lf/migration-source-repair/20260925010101",
    "execution_id": "EXEC-MIGRATION-SOURCE-REPAIR-001",
}
assert mod.validate_request(dict(base)).target_branch.startswith("lf/migration-source-repair/")

for bad_branch in ("main", "master", "feature/free-write", "lf/migration-source-repair/../main"):
    bad = dict(base, target_branch=bad_branch)
    try:
        mod.validate_request(bad)
    except ValueError as exc:
        assert str(exc) == "MIGRATION_GIT_PERSIST_BRANCH_INVALID"
    else:
        raise AssertionError(f"unsafe branch accepted: {bad_branch}")

bad = dict(base, target_path="README.md")
try:
    mod.validate_request(bad)
except ValueError as exc:
    assert str(exc) == "MIGRATION_GIT_PERSIST_PATH_INVALID"
else:
    raise AssertionError("non-migration path accepted")

print("PASS_MIGRATION_GIT_PERSIST_CONTRACT=6/6")
