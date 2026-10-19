"""Offline tests for the M10.4 guard v2 (no network; GitHub reads are stubbed)."""
from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("lf_m104_guard_v2_under_test", HERE / "legacy_freeze_guard_v2.py")
g = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(g)

REPO = "owner/repo"
_, TARGETS = g.v1.load_manifest()
SCHEMA, NAME = sorted(TARGETS)[0]
FROZEN_SQL = (
    f"CREATE OR REPLACE FUNCTION {SCHEMA}.{NAME}(x integer) RETURNS int LANGUAGE sql AS $$ SELECT 1 $$;\n"
)
CLEAN_SQL = "create or replace function programacion.not_frozen_fn() returns int language sql as $$select 1$$;\n"


def install(monkeypatch, files, texts):
    """files: PR file rows; texts: {(path, ref): content}."""
    pr = {"head": {"sha": "HEAD", "repo": {"full_name": REPO}}, "base": {"sha": "BASE"}}

    def rest(repo, endpoint):
        if endpoint.startswith("pulls/1/files"):
            return files
        if endpoint == "pulls/1":
            return pr
        raise AssertionError(endpoint)

    def file_text(repo, path, ref):
        return texts[(path, ref)]

    monkeypatch.setattr(g.v1, "rest", rest)
    monkeypatch.setattr(g.v1, "file_text", file_text)


def rename(old, new, changes=0):
    return {"status": "renamed", "previous_filename": old, "filename": new,
            "changes": changes, "additions": changes, "deletions": 0}


OLD = "supabase/migrations/20261008222000_ig_m8_6_batch_common.sql"
NEW = "supabase/migrations/20261008201658_ig_m8_6_batch_common_v1.sql"


def test_exact_rename_of_frozen_source_passes(monkeypatch):
    install(monkeypatch, [rename(OLD, NEW)], {(OLD, "BASE"): FROZEN_SQL, (NEW, "HEAD"): FROZEN_SQL})
    assert "exact_renames_not_mutation=1" in g.check_pr(REPO, 1)


def test_rename_with_content_change_fails(monkeypatch):
    install(monkeypatch, [rename(OLD, NEW, changes=1)],
            {(OLD, "BASE"): FROZEN_SQL, (NEW, "HEAD"): FROZEN_SQL + "select 1;\n"})
    with pytest.raises(ValueError, match="FAIL_M104_FROZEN_LEGACY_MUTATION"):
        g.check_pr(REPO, 1)


def test_rename_metadata_zero_but_bytes_differ_fails(monkeypatch):
    install(monkeypatch, [rename(OLD, NEW)], {(OLD, "BASE"): FROZEN_SQL, (NEW, "HEAD"): FROZEN_SQL + "\n"})
    with pytest.raises(ValueError, match="FAIL_M104_FROZEN_LEGACY_MUTATION"):
        g.check_pr(REPO, 1)


def test_modified_frozen_source_fails(monkeypatch):
    install(monkeypatch, [{"status": "modified", "filename": OLD, "changes": 1}],
            {(OLD, "BASE"): FROZEN_SQL, (OLD, "HEAD"): FROZEN_SQL})
    with pytest.raises(ValueError, match="FAIL_M104_FROZEN_LEGACY_MUTATION"):
        g.check_pr(REPO, 1)


def test_removed_frozen_source_fails(monkeypatch):
    install(monkeypatch, [{"status": "removed", "filename": OLD, "changes": 3}], {(OLD, "BASE"): FROZEN_SQL})
    with pytest.raises(ValueError, match="FAIL_M104_FROZEN_LEGACY_MUTATION"):
        g.check_pr(REPO, 1)


def test_new_migration_touching_frozen_function_fails(monkeypatch):
    install(monkeypatch, [{"status": "added", "filename": NEW, "changes": 1}], {(NEW, "HEAD"): FROZEN_SQL})
    with pytest.raises(ValueError, match="FAIL_M104_FROZEN_LEGACY_MUTATION"):
        g.check_pr(REPO, 1)


def test_clean_rename_still_passes(monkeypatch):
    install(monkeypatch, [rename(OLD, NEW, changes=1)], {(OLD, "BASE"): CLEAN_SQL, (NEW, "HEAD"): CLEAN_SQL + "-- x\n"})
    assert "exact_renames_not_mutation=0" in g.check_pr(REPO, 1)


@pytest.mark.parametrize("path", sorted(g.PROTECTED))
def test_guard_assets_are_protected(monkeypatch, path):
    install(monkeypatch, [{"status": "modified", "filename": path, "changes": 1}], {})
    with pytest.raises(ValueError, match="FAIL_M104_FROZEN_GUARD_ASSET_CHANGED"):
        g.check_pr(REPO, 1)


def test_renaming_away_a_guard_asset_is_protected(monkeypatch):
    asset = "sandbox/lf_contract_gate_test/engineering_checkpoints/m10_4/legacy_freeze_guard.py"
    install(monkeypatch, [rename(asset, asset.replace(".py", "_old.py"))], {})
    with pytest.raises(ValueError, match="FAIL_M104_FROZEN_GUARD_ASSET_CHANGED"):
        g.check_pr(REPO, 1)


def test_self_test_passes():
    g.self_test()
