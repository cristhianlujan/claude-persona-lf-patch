#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "lf_migration_source_parity_repair.py"
spec = importlib.util.spec_from_file_location("lf_migration_source_parity_repair", TARGET)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

assert mod.extract_versions("FAIL_LF_MIGRATION_VERSION_PARITY: remote_only=['20260922231503'] local_only=[]") == ["20260922231503"]
assert mod.extract_versions("FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION: remote=20260923013150_restrict_profile_semantic_judge_trust_validator_acl") == ["20260923013150"]
assert mod.extract_versions("FAIL_SOMETHING_ELSE: 20260923013150") == []

repo = "cristhianlujan/claude-persona-lf-patch"
rows = [[
    "20260923013150",
    "restrict_profile_semantic_judge_trust_validator_acl",
    "73656c65637420313b",
    "1",
    "EXEC-DB-SOURCE-RECONCILE-20260923013150-20260923-001",
    repo,
    "supabase/migrations/20260923013150_restrict_profile_semantic_judge_trust_validator_acl.sql",
    "a" * 40,
    "b" * 40,
    "PASS",
    "false",
]]
locator = mod.select_locator("20260923013150", rows, repo)
assert locator["source_blob"] == "b" * 40
assert locator["path"].endswith("restrict_profile_semantic_judge_trust_validator_acl.sql")

ambiguous = rows + [list(rows[0])]
ambiguous[1][8] = "c" * 40
try:
    mod.select_locator("20260923013150", ambiguous, repo)
except RuntimeError as exc:
    assert str(exc).startswith("MIGRATION_REPAIR_LOCATOR_AMBIGUOUS")
else:
    raise AssertionError("ambiguous historical source locators accepted")

print("PASS_MIGRATION_SOURCE_PARITY_REPAIR=6/6")
