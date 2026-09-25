#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGET = ROOT / "db_write_transport/lf_migration_orchestrated_saga.py"
spec = importlib.util.spec_from_file_location("lf_migration_orchestrated_saga", TARGET)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


def payload(*, git_persisted: bool, parity_status: str):
    path = "supabase/migrations/20260923013150_restrict_profile_semantic_judge_trust_validator_acl.sql"
    return {
        "schema_version": mod.SCHEMA_VERSION,
        "operation_code": "ACTUALIZACION_DB_LF",
        "execution_id": "EXEC-MIGRATION-SOURCE-REPAIR-TEST-001",
        "effect_scope": "MIGRATION:20260923013150",
        "target_path": path,
        "migration_version": "20260923013150",
        "migration_name": "restrict_profile_semantic_judge_trust_validator_acl",
        "source_sha256": "a" * 64,
        "git": {
            "path": path,
            "source_sha256": "a" * 64,
            "head_sha": "b" * 40,
            "blob_sha1": "c" * 40,
            "persisted": git_persisted,
            "readback": git_persisted,
        },
        "supabase": {
            "applied": True,
            "readback": True,
            "ledger_version": "20260923013150",
            "ledger_name": "restrict_profile_semantic_judge_trust_validator_acl",
            "ddl_replayed": False,
        },
        "parity": {
            "source_path": path,
            "migration_version": "20260923013150",
            "migration_name": "restrict_profile_semantic_judge_trust_validator_acl",
            "status": parity_status,
        },
    }


before = mod.evaluate(payload(git_persisted=False, parity_status="FAIL"))
assert before.status == "BLOCKED"
assert before.code == "BLOCK_WRITE_AHEAD_NOT_DURABLE"

persisted = mod.evaluate(payload(git_persisted=True, parity_status="FAIL"))
assert persisted.status == "BLOCKED"
assert persisted.code == "BLOCK_DUAL_SURFACE_PARITY_NOT_PASS"

after = mod.evaluate(payload(git_persisted=True, parity_status="PASS"))
assert after.status == "CONSISTENT"
assert after.consistent is True
assert after.ready_to_apply is False
print("PASS_MIGRATION_SOURCE_RECONCILIATION_SAGA=3/3")
