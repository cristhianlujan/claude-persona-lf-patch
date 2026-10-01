#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "visual_source_analysis_v1.py"
spec = importlib.util.spec_from_file_location("visual_source_analysis_v1_test_subject", MODULE_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_VISUAL_SOURCE_ANALYSIS_TEST_LOAD")
M = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = M
spec.loader.exec_module(M)


def check(condition: bool, code: str) -> None:
    if not condition:
        raise AssertionError(code)


def noop(*args, **kwargs):
    return None


def fake_pass_engine(**kwargs):
    return {
        "result": "PASS_P0_V4_CLOSED_LOOP",
        "human_review_ready": True,
        "convergence_receipt": {
            "schema_version": "p0-convergence-receipt-v4/v2",
            "source_sha256": kwargs["expected_source_sha256"],
            "code_head_sha": kwargs["code_head_sha"],
            "configuration_sha256": kwargs["configuration_sha256"],
            "result": "PASS_P0_V4_CLOSED_LOOP",
        },
    }


def fake_block_engine(**kwargs):
    return {"result": "BLOCKED_DISCOVERY_COVERAGE", "human_review_ready": False}


def fake_invalid_pass_engine(**kwargs):
    return {"result": "PASS_P0_V4_CLOSED_LOOP", "human_review_ready": True}


def call(runner):
    return M.analyze_source(
        source_path="screen.png",
        expected_source_sha256="1" * 64,
        full_reader=noop,
        remediator=noop,
        targeted_reread=noop,
        code_head_sha="2" * 40,
        configuration_id="cfg",
        configuration_sha256="3" * 64,
        regression_proof={"p": 1},
        adversarial_proof={"p": 2},
        artifact_hash_proof={"p": 3},
        engine_runner=runner,
    )


def test_owner_boundary_and_inventory() -> None:
    result = M.self_test()
    check(result["control_id"] == "VISUAL_SOURCE_ANALYSIS", "BAD_CONTROL_ID")
    check(result["producer_regression_count"] == 19, "BAD_PRODUCER_COUNT")
    check(result["foreign_command_count"] == 5, "BAD_FOREIGN_COUNT")
    check(result["ownership"]["visual_source_analysis"] is True, "PRODUCER_OWNER_MISSING")
    check(result["ownership"]["producer_regressions"] is True, "REGRESSION_OWNER_MISSING")
    for key in (
        "applicability",
        "path_admission",
        "visual_evidence_gate",
        "human_review",
        "durable_evidence_persistence",
        "premerge_release_governance",
        "p0_5_benchmark_annotation",
        "runtime_or_production_authorization",
    ):
        check(result["ownership"][key] is False, f"FOREIGN_OWNER:{key}")


def test_pass_delegates_without_human_decision() -> None:
    result = call(fake_pass_engine)
    check(result["result"] == "PASS", "PASS_NOT_PROPAGATED")
    check(result["control_id"] == "VISUAL_SOURCE_ANALYSIS", "BAD_PASS_OWNER")
    check(isinstance(result["evidence_receipt"], dict), "RECEIPT_NOT_EXPOSED")
    check("human_review_ready" not in result, "HUMAN_REVIEW_STATE_LEAKED_TO_OWNER_ENVELOPE")


def test_block_is_fail_closed() -> None:
    result = call(fake_block_engine)
    check(result["result"] == "BLOCKED", "BLOCK_NOT_PROPAGATED")
    check(result["upstream_result"] == "BLOCKED_DISCOVERY_COVERAGE", "BLOCK_REASON_LOST")
    check(result["evidence_receipt"] is None, "BLOCK_EXPOSED_RECEIPT")


def test_pass_without_receipt_rejected() -> None:
    try:
        call(fake_invalid_pass_engine)
    except M.VisualSourceAnalysisError as exc:
        check(str(exc) == "FAIL_VISUAL_SOURCE_ANALYSIS_PASS_WITHOUT_RECEIPT", "WRONG_MISSING_RECEIPT_ERROR")
        return
    raise AssertionError("PASS_WITHOUT_RECEIPT_ALLOWED")


def test_foreign_historical_commands_are_not_producer_regressions() -> None:
    labels = {label for label, _ in M.PRODUCER_REGRESSION_COMMANDS}
    check(not labels.intersection(M.FOREIGN_HISTORICAL_COMMANDS), "FOREIGN_COMMAND_IN_PRODUCER_INVENTORY")
    check(M.FOREIGN_HISTORICAL_COMMANDS["human-binding-selftest"] == "HUMAN_REVIEW_AUTHORITY", "HUMAN_OWNER_DRIFT")
    check(M.FOREIGN_HISTORICAL_COMMANDS["v4-durable-state"] == "EVIDENCE_PERSISTENCE_STATE", "DURABLE_OWNER_DRIFT")
    check(M.FOREIGN_HISTORICAL_COMMANDS["p0-5-blind-annotation-contract"] == "P0_5_BENCHMARK_ANNOTATION", "P05_OWNER_DRIFT")


def main() -> int:
    tests = (
        test_owner_boundary_and_inventory,
        test_pass_delegates_without_human_decision,
        test_block_is_fail_closed,
        test_pass_without_receipt_rejected,
        test_foreign_historical_commands_are_not_producer_regressions,
    )
    for test in tests:
        test()
    print(f"PASS_VISUAL_SOURCE_ANALYSIS_TESTS={len(tests)}/{len(tests)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
