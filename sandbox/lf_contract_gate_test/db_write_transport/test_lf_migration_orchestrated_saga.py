#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
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


def canonical_digest(value: dict) -> str:
    payload = dict(value)
    payload.pop("manifest_sha256", None)
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def parity_evidence(head: str) -> dict:
    report = {
        "contract": "LF_GATE_ERROR_V1",
        "producer": "LF_GATE_CHECK_OBSERVABILITY_V1",
        "schema_ref": "sandbox/lf_contract_gate_test/gate_check_observability/lf_gate_error_v1.schema.json",
        "schema_sha256": "d" * 64,
        "run_id": "RUN-PARITY-001",
        "job_id": "lf-contract-check",
        "step_id": "migration_source_parity",
        "gate_id": "ANY_CANONICAL_GATE::MIGRATION_SOURCE_PARITY",
        "gate_mode": "COLLECT_ALL",
        "gate_result": "PASS",
        "diagnostic_complete": True,
        "source_commit": head,
        "tested_commit": head,
        "source_path": [module.PARITY_SOURCE_PATH],
        "trace_id": "LF-CI-TEST",
        "timestamp": "2026-09-25T00:00:00Z",
        "owner": "LF_CONTRACT_CHECK",
        "next_action": "NONE",
        "expected_check_count": 1,
        "executed_check_count": 1,
        "pass_count": 1,
        "fail_count": 0,
        "blocked_count": 0,
        "downstream_impact": ["MIGRATION_SOURCE_PARITY"],
        "checks": [{
            "check_status": "PASS",
            "exit_code": 0,
            "rc": 0,
            "producer": "LF_GATE_CHECK_OBSERVABILITY_V1",
            "source_commit": head,
            "tested_commit": head,
            "source_path": module.PARITY_SOURCE_PATH,
        }],
    }
    report["manifest_sha256"] = canonical_digest(report)
    return report


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


def applied_payload() -> dict:
    payload = base_payload()
    payload["supabase"] = {
        "applied": True,
        "readback": True,
        "ledger_version": payload["migration_version"],
        "ledger_name": payload["migration_name"],
    }
    return payload


def attach_parity(payload: dict) -> None:
    payload["parity"] = {
        "status": "PASS",
        "source_path": payload["target_path"],
        "migration_version": payload["migration_version"],
        "migration_name": payload["migration_name"],
        "evidence": parity_evidence(payload["git"]["head_sha"]),
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

    def test_consistent_requires_canonical_parity_evidence(self) -> None:
        payload = applied_payload()
        attach_parity(payload)
        verdict = module.evaluate(payload)
        self.assertEqual(verdict.status, "CONSISTENT")
        self.assertTrue(verdict.consistent)

    def test_plain_pass_without_evidence_is_rejected(self) -> None:
        payload = applied_payload()
        payload["parity"] = {
            "status": "PASS",
            "source_path": payload["target_path"],
            "migration_version": payload["migration_version"],
            "migration_name": payload["migration_name"],
        }
        with self.assertRaisesRegex(ValueError, "CANONICAL_EVIDENCE_REQUIRED"):
            module.evaluate(payload)

    def test_parity_evidence_wrong_head_is_rejected(self) -> None:
        payload = applied_payload()
        attach_parity(payload)
        payload["parity"]["evidence"]["source_commit"] = "e" * 40
        payload["parity"]["evidence"]["manifest_sha256"] = canonical_digest(payload["parity"]["evidence"])
        with self.assertRaisesRegex(ValueError, "EVIDENCE_HEAD_MISMATCH"):
            module.evaluate(payload)

    def test_parity_evidence_tamper_is_rejected(self) -> None:
        payload = applied_payload()
        attach_parity(payload)
        payload["parity"]["evidence"]["owner"] = "TAMPERED"
        with self.assertRaisesRegex(ValueError, "EVIDENCE_DIGEST_MISMATCH"):
            module.evaluate(payload)

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
