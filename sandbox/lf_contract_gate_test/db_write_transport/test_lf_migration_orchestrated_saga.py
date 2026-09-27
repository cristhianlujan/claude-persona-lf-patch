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
ROOT = HERE.parents[2]
TARGET = HERE / "lf_migration_orchestrated_saga.py"
spec = importlib.util.spec_from_file_location("lf_migration_orchestrated_saga", TARGET)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = module
spec.loader.exec_module(module)

CLOSURE_HEAD = "6354023d5102cc8b6c94e9141e5560c5014d0699"
REPAIRED_MIGRATIONS = (
    ("20260922163720", "lf_profile_execution_queue_terminal_reconcile_v1", "d25bf3f54e8838e23d50b71f805ec97395a9375c"),
    ("20260922215336", "lf_profile_baseline_digest_parity_guard_v1", "01d3a59eda408bac4345376ecd3bd07739c3fabd"),
    ("20260922231503", "lf_profile_execution_semantic_judge_runtime_wiring_v1", "18967809f175bb4507c2f5d5c263b7c4416d1b67"),
    ("20260923013150", "restrict_profile_semantic_judge_trust_validator_acl", "f0520007669e9088508439375e56b83cbcca1ac3"),
)

# Exact LF_GATE_ERROR_V1 PASS artifact emitted by lf-contract-check run 36280618454
# for the final repair head. Its manifest_sha256 is asserted before consumption.
EXACT_PARITY_PASS_36280618454 = {
    "blocked_count": 0,
    "checks": [{
        "actual": {"rc": 0},
        "assertion_text": None,
        "check_id": "MIGRATION_SOURCE_PARITY-001",
        "check_status": "PASS",
        "command": [
            "python3",
            "sandbox/lf_contract_gate_test/lf_migration_source_parity.py",
            "supabase/migrations",
            ".lf_gate_runtime/lf_contract_check/migration_source_parity/lf-post-cutover-migrations-compact.csv",
            ".lf_gate_runtime/lf_contract_check/migration_source_parity/lf-grandfathered-migrations.csv",
            ".lf_gate_runtime/lf_contract_check/migration_source_parity/lf-legacy-checkpoint.csv",
        ],
        "condition": "deterministic command exits with rc=0",
        "critical": False,
        "diagnostic_complete": True,
        "downstream_impact": [],
        "error_class": None,
        "error_id": None,
        "error_summary": None,
        "evidence_ref": "artifact://lf_gate_error_v1.json#checks/MIGRATION_SOURCE_PARITY-001",
        "exit_code": 0,
        "expected": {"rc": 0},
        "failure_id": None,
        "input_ref": "sandbox/lf_contract_gate_test/lf_migration_source_parity.py",
        "next_action": "NONE",
        "owner": "LF_CONTRACT_CHECK",
        "parent_trace_id": "LF-CI-GATE-76a028ec-9cde-5470-ba73-9360f7a905da",
        "producer": "sandbox/lf_contract_gate_test/lf_migration_source_parity.py",
        "rc": 0,
        "source_commit": CLOSURE_HEAD,
        "source_path": "sandbox/lf_contract_gate_test/lf_migration_source_parity.py",
        "started_at": "2026-09-26T23:49:56.484706Z",
        "stderr_ref": ".lf_gate_diagnostics/lf_contract_check/declarative_controls/groups/MIGRATION_SOURCE_PARITY/checks/MIGRATION_SOURCE_PARITY-001.stderr.log",
        "stderr_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "stdout_ref": ".lf_gate_diagnostics/lf_contract_check/declarative_controls/groups/MIGRATION_SOURCE_PARITY/checks/MIGRATION_SOURCE_PARITY-001.stdout.log",
        "stdout_sha256": "ba2d108c78f6b9547ba6f7c9566e91274f7b1084e9bf67526355ea4512d26476",
        "tested_commit": CLOSURE_HEAD,
        "timestamp": "2026-09-26T23:49:57.279885Z",
        "trace_id": "LF-CI-0514317e-43e9-5d5c-bf1c-df857db4a67d",
        "traceback_present": False,
        "traceback_ref": None,
        "traceback_sha256": None,
    }],
    "contract": "LF_GATE_ERROR_V1",
    "diagnostic_complete": True,
    "downstream_impact": [],
    "executed_check_count": 1,
    "executed_check_ids": ["MIGRATION_SOURCE_PARITY-001"],
    "expected_check_count": 1,
    "expected_check_ids": ["MIGRATION_SOURCE_PARITY-001"],
    "fail_count": 0,
    "gate_id": "LF_CONTRACT_CHECK_DECLARATIVE_CONTROLS::MIGRATION_SOURCE_PARITY",
    "gate_mode": "COLLECT_ALL",
    "gate_result": "PASS",
    "job_id": "lf-contract-check",
    "manifest_sha256": "2e34a8ca84ae8139993d4a811b02b86b6c2422859226c1c385052f5cd677112b",
    "next_action": "NONE",
    "owner": "LF_CONTRACT_CHECK",
    "parent_trace_id": None,
    "pass_count": 1,
    "producer": "LF_GATE_CHECK_OBSERVABILITY_V1",
    "remaining_after_fail_fast": [],
    "run_id": "36280618454",
    "schema_ref": "/home/runner/work/claude-persona-lf-patch/claude-persona-lf-patch/sandbox/lf_contract_gate_test/gate_check_observability/lf_gate_error_v1.schema.json",
    "schema_sha256": "53d39ec35d9f98cbb5019cae7b0221483f7d982fc7855db3eebbb9296382d7fc",
    "source_commit": CLOSURE_HEAD,
    "source_path": ["sandbox/lf_contract_gate_test/lf_migration_source_parity.py"],
    "started_at": "2026-09-26T23:49:56.484639Z",
    "step_id": "migration_source_parity",
    "tested_commit": CLOSURE_HEAD,
    "timestamp": "2026-09-26T23:49:57.279926Z",
    "trace_id": "LF-CI-GATE-76a028ec-9cde-5470-ba73-9360f7a905da",
}


def canonical_digest(value: dict) -> str:
    payload = dict(value)
    payload.pop("manifest_sha256", None)
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def git_blob_sha1(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def parity_evidence(head: str) -> dict:
    # Mirror the canonical PASS semantics emitted by run_gate_checks_v1.py:
    # envelope producer is observability; the check producer is the executable
    # source path; downstream_impact is empty for PASS and reserved for failures.
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
        "downstream_impact": [],
        "checks": [{
            "check_status": "PASS",
            "exit_code": 0,
            "rc": 0,
            "producer": module.PARITY_SOURCE_PATH,
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


def closure_payload(version: str, name: str, expected_blob: str) -> dict:
    path = f"supabase/migrations/{version}_{name}.sql"
    raw = (ROOT / path).read_bytes()
    observed_blob = git_blob_sha1(raw)
    if observed_blob != expected_blob:
        raise AssertionError(f"CLOSURE_SOURCE_BLOB_DRIFT:{version}:{observed_blob}:{expected_blob}")
    source_sha256 = hashlib.sha256(raw).hexdigest()
    return {
        "schema_version": module.SCHEMA_VERSION,
        "operation_code": module.OPERATION_CODE,
        "execution_id": f"EXEC-MIGRATION-CLOSURE-{version}",
        "effect_scope": f"MIGRATION:{version}",
        "target_path": path,
        "migration_version": version,
        "migration_name": name,
        "source_sha256": source_sha256,
        "git": {
            "persisted": True,
            "readback": True,
            "path": path,
            "head_sha": CLOSURE_HEAD,
            "blob_sha1": observed_blob,
            "source_sha256": source_sha256,
        },
        "supabase": {
            "applied": True,
            "readback": True,
            "ledger_version": version,
            "ledger_name": name,
        },
        "parity": {
            "status": "PASS",
            "source_path": path,
            "migration_version": version,
            "migration_name": name,
            "evidence": copy.deepcopy(EXACT_PARITY_PASS_36280618454),
        },
    }


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

    def test_exact_closure_artifact_closes_all_four_repaired_migrations(self) -> None:
        self.assertEqual(
            canonical_digest(EXACT_PARITY_PASS_36280618454),
            EXACT_PARITY_PASS_36280618454["manifest_sha256"],
        )
        for version, name, blob_sha1 in REPAIRED_MIGRATIONS:
            with self.subTest(version=version):
                verdict = module.evaluate(closure_payload(version, name, blob_sha1))
                self.assertEqual(verdict.status, "CONSISTENT")
                self.assertEqual(verdict.code, "PASS_MIGRATION_SAGA_CONSISTENT")
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

    def test_parity_check_wrong_producer_is_rejected(self) -> None:
        payload = applied_payload()
        attach_parity(payload)
        payload["parity"]["evidence"]["checks"][0]["producer"] = "LF_GATE_CHECK_OBSERVABILITY_V1"
        payload["parity"]["evidence"]["manifest_sha256"] = canonical_digest(payload["parity"]["evidence"])
        with self.assertRaisesRegex(ValueError, "CHECK_PRODUCER_INVALID"):
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
