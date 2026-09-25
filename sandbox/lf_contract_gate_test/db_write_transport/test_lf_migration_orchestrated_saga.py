#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
TARGET = HERE / "lf_migration_orchestrated_saga.py"
spec = importlib.util.spec_from_file_location("lf_migration_orchestrated_saga", TARGET)
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


class SagaTests(unittest.TestCase):
    def test_ready_only_after_write_ahead(self) -> None:
        verdict = module.evaluate(base_payload())
        self.assertEqual(verdict.status, "READY_TO_APPLY")
        self.assertTrue(verdict.ready_to_apply)

    def test_blocks_db_first(self) -> None:
        payload = base_payload()
        payload["git"]["persisted"] = False
        payload["git"]["readback"] = False
        payload["supabase"] = {
            "applied": True,
            "readback": True,
            "ledger_version": payload["migration_version"],
            "ledger_name": payload["migration_name"],
        }
        verdict = module.evaluate(payload)
        self.assertEqual(verdict.code, "BLOCK_WRITE_AHEAD_NOT_DURABLE")

    def test_consistent_requires_supabase_and_parity(self) -> None:
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

    def test_retry_is_idempotent(self) -> None:
        payload = base_payload()
        first = module.evaluate(copy.deepcopy(payload))
        second = module.evaluate(copy.deepcopy(payload))
        self.assertEqual(first, second)

    def test_identity_mismatch_fails_closed(self) -> None:
        payload = base_payload()
        payload["migration_name"] = "other"
        with self.assertRaisesRegex(ValueError, "TARGET_IDENTITY_MISMATCH"):
            module.evaluate(payload)


if __name__ == "__main__":
    unittest.main()
