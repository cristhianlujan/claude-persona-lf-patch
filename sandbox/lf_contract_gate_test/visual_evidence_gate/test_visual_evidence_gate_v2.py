#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "visual_evidence_gate_v2.py"
spec = importlib.util.spec_from_file_location("visual_evidence_gate_v2_test_subject", MODULE_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_VISUAL_EVIDENCE_GATE_V2_TEST_LOAD")
M = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = M
spec.loader.exec_module(M)

SOURCE_SHA = "1" * 64
HEAD_SHA = "2" * 40
CONFIG_SHA = "3" * 64


def check(condition: bool, code: str) -> None:
    if not condition:
        raise AssertionError(code)


def clean_receipt() -> dict:
    contract = M._load_convergence_contract()
    proofs = {
        gate: contract.make_gate_proof(
            gate=gate,
            source_sha256=SOURCE_SHA,
            code_head_sha=HEAD_SHA,
            configuration_sha256=CONFIG_SHA,
            details={"test": True},
        )
        for gate in M.REQUIRED_GATE_PROOFS
    }
    return {
        "schema_version": M.ACCEPTED_RECEIPT_SCHEMA,
        "source_sha256": SOURCE_SHA,
        "code_head_sha": HEAD_SHA,
        "configuration_id": "test-config",
        "configuration_sha256": CONFIG_SHA,
        "clean_passes": [{"pass_id": "p1"}, {"pass_id": "p2"}],
        "grader_coverage_percent": 100.0,
        "critical": 0,
        "high": 0,
        "unresolved_medium": 0,
        "suspicious_confirmed": 0,
        "contradictions": 0,
        "unsupported_claims": 0,
        "critical_omissions": 0,
        "gate_proofs": proofs,
        "human_review_ready": True,
        "result": "PASS_P0_V4_CLOSED_LOOP",
    }


def expect_block(receipt: dict, code: str) -> None:
    try:
        M.validate_receipt(receipt)
    except M.VisualEvidenceGateV2Error:
        return
    raise AssertionError(code)


def test_identity_and_owner_boundary() -> None:
    result = M.self_test()
    check(result["control_id"] == "VISUAL_EVIDENCE_GATE", "BAD_CONTROL_ID")
    check(result["ownership"]["visual_evidence_validation"] is True, "OWNER_MISSING")
    for foreign in (
        "applicability",
        "path_admission",
        "visual_producer_execution",
        "human_decision_persistence",
        "exact_head_transport",
        "durable_evidence_persistence",
        "runtime_or_production_authorization",
    ):
        check(result["ownership"][foreign] is False, f"FOREIGN_OWNER:{foreign}")
    check("subprocess" not in M.__dict__, "PRODUCER_EXECUTION_TRANSPORT_LEAK")
    check(not hasattr(M, "CANONICAL_HELPERS"), "LEGACY_HELPER_EXECUTION_LEAK")


def test_clean_source_bound_receipt_passes() -> None:
    result = M.validate_receipt(clean_receipt())
    check(result["result"] == "PASS", "CLEAN_RECEIPT_NOT_PASS")
    check(result["validated_gate_proofs"] == list(M.REQUIRED_GATE_PROOFS), "PROOF_SET_DRIFT")


def test_mutated_proof_blocks() -> None:
    receipt = clean_receipt()
    receipt["gate_proofs"]["regression_suite"]["details"]["tampered"] = True
    expect_block(receipt, "MUTATED_PROOF_ALLOWED")


def test_open_visual_findings_block() -> None:
    receipt = clean_receipt()
    receipt["critical_omissions"] = 1
    expect_block(receipt, "OPEN_FINDING_ALLOWED")


def test_incomplete_coverage_blocks() -> None:
    receipt = clean_receipt()
    receipt["grader_coverage_percent"] = 99.0
    expect_block(receipt, "INCOMPLETE_COVERAGE_ALLOWED")


def test_blocked_upstream_result_blocks() -> None:
    receipt = clean_receipt()
    receipt["result"] = "BLOCKED_CONVERGENCE"
    expect_block(receipt, "BLOCKED_UPSTREAM_ALLOWED")


def test_proof_binding_replay_blocks() -> None:
    receipt = clean_receipt()
    replay = copy.deepcopy(receipt)
    replay["code_head_sha"] = "4" * 40
    expect_block(replay, "CROSS_HEAD_REPLAY_ALLOWED")


def main() -> int:
    tests = (
        test_identity_and_owner_boundary,
        test_clean_source_bound_receipt_passes,
        test_mutated_proof_blocks,
        test_open_visual_findings_block,
        test_incomplete_coverage_blocks,
        test_blocked_upstream_result_blocks,
        test_proof_binding_replay_blocks,
    )
    for test in tests:
        test()
    print(f"PASS_VISUAL_EVIDENCE_GATE_V2_TESTS={len(tests)}/{len(tests)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
