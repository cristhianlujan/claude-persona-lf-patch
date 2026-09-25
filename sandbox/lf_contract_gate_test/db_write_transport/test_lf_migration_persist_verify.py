#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
TARGET = HERE / "lf_migration_persist_verify.py"
spec = importlib.util.spec_from_file_location("lf_migration_persist_verify", TARGET)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def base_payload() -> dict:
    path = "supabase/migrations/20260917191749_lf_example_v1.sql"
    return {
        "schema_version": module.SCHEMA_VERSION,
        "operation_code": module.OPERATION_CODE,
        "execution_id": "EXEC-DB-WRITE-TEST-001",
        "effect_scope": "MIGRATION:20260917191749",
        "target_path": path,
        "migration_version": "20260917191749",
        "migration_name": "lf_example_v1",
        "source_sha256": "a" * 64,
        "git": {
            "persisted": True,
            "readback": True,
            "path": path,
            "head_sha": "b" * 40,
            "blob_sha1": "c" * 40,
            "source_sha256": "a" * 64,
        },
        "supabase": {"applied": False},
        "parity": {},
    }


class PersistVerifyTests(unittest.TestCase):
    def test_ready_to_apply_only_after_git_durable(self) -> None:
        verdict = module.evaluate(base_payload())
        self.assertEqual(verdict.status, "READY_TO_APPLY")
        self.assertTrue(verdict.ready_to_apply)
        self.assertFalse(verdict.consistent)

    def test_blocks_db_first(self) -> None:
        payload = base_payload()
        payload["git"]["persisted"] = False
        payload["supabase"] = {
            "applied": True,
            "readback": True,
            "ledger_version": payload["migration_version"],
            "ledger_name": payload["migration_name"],
        }
        verdict = module.evaluate(payload)
        self.assertEqual(verdict.code, "BLOCK_GIT_SOURCE_NOT_DURABLE")

    def test_consistent_requires_dual_readback_and_parity(self) -> None:
        payload = base_payload()
        payload["supabase"] = {
            "applied": True,
            "readback": True,
            "ledger_version": payload["migration_version"],
            "ledger_name": payload["migration_name"],
        }
        payload["parity"] = {
            "status": "PASS",
            "source_path": payload["target_path"],
            "migration_version": payload["migration_version"],
            "migration_name": payload["migration_name"],
        }
        verdict = module.evaluate(payload)
        self.assertEqual(verdict.status, "CONSISTENT")
        self.assertTrue(verdict.consistent)

    def test_parity_failure_cannot_close(self) -> None:
        payload = base_payload()
        payload["supabase"] = {
            "applied": True,
            "readback": True,
            "ledger_version": payload["migration_version"],
            "ledger_name": payload["migration_name"],
        }
        payload["parity"] = {
            "status": "FAIL",
            "source_path": payload["target_path"],
            "migration_version": payload["migration_version"],
            "migration_name": payload["migration_name"],
        }
        verdict = module.evaluate(payload)
        self.assertEqual(verdict.code, "BLOCK_DUAL_SURFACE_PARITY_NOT_PASS")

    def test_identity_mismatch_fails_closed(self) -> None:
        payload = base_payload()
        payload["migration_name"] = "other"
        with self.assertRaisesRegex(ValueError, "TARGET_IDENTITY_MISMATCH"):
            module.evaluate(payload)

    def test_execution_identity_is_required(self) -> None:
        payload = copy.deepcopy(base_payload())
        payload["execution_id"] = "not-governed"
        with self.assertRaisesRegex(ValueError, "EXECUTION_ID_INVALID"):
            module.evaluate(payload)


if __name__ == "__main__":
    unittest.main()
