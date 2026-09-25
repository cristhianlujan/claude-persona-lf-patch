#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

WORKFLOW = Path(".github/workflows/lf-contract-check.yml")


def require(text: str, needle: str, code: str) -> None:
    if needle not in text:
        raise SystemExit(code)


def main() -> int:
    text = WORKFLOW.read_text(encoding="utf-8")
    reserve_name = "Reserve governed lf-contract-check plan trace"
    pre_ekb_name = "Persist failed deterministic LF contract diagnostics through PRE_EKB_GATE"
    close_name = "Close governed lf-contract-check plan trace"

    require(text, reserve_name, "FAIL_PLAN_TRACE_WORKFLOW_RESERVE_STEP_MISSING")
    require(text, "id: plan_trace", "FAIL_PLAN_TRACE_WORKFLOW_RESERVE_ID_MISSING")
    require(text, "lf_contract_plan_trace_v1.py", "FAIL_PLAN_TRACE_WORKFLOW_EMITTER_NOT_WIRED")
    require(text, "lf_contract_plan_trace_wiring_v1.py", "FAIL_PLAN_TRACE_WORKFLOW_WIRING_NOT_WIRED")
    require(text, ".lf_ci/lf_contract_plan_trace_v1.json", "FAIL_PLAN_TRACE_WORKFLOW_TRACE_ARTIFACT_MISSING")
    require(text, close_name, "FAIL_PLAN_TRACE_WORKFLOW_CLOSE_STEP_MISSING")

    reserve_pos = text.index(reserve_name)
    controls_pos = text.index("Run CI lane router self-tests with deterministic diagnostics")
    if reserve_pos >= controls_pos:
        raise SystemExit("FAIL_PLAN_TRACE_WORKFLOW_RESERVE_AFTER_CONTROLS")

    pre_pos = text.index(pre_ekb_name)
    close_pos = text.index(close_name)
    if close_pos <= pre_pos:
        raise SystemExit("FAIL_PLAN_TRACE_WORKFLOW_CLOSE_BEFORE_PRE_EKB")

    pre_section = text[pre_pos:close_pos]
    if "fn_lf_operation_reserve_execution_v1" in pre_section:
        raise SystemExit("FAIL_PLAN_TRACE_WORKFLOW_PRE_EKB_SECOND_RESERVATION")
    require(pre_section, "--mode assert", "FAIL_PLAN_TRACE_WORKFLOW_PRE_EKB_REUSE_ASSERT_MISSING")
    require(pre_section, "/tmp/lf_contract_plan_trace_assert.sql", "FAIL_PLAN_TRACE_WORKFLOW_PRE_EKB_REUSE_SQL_MISSING")

    reserve_section = text[reserve_pos:controls_pos]
    if reserve_section.count("fn_lf_operation_reserve_execution_v1") > 0:
        raise SystemExit("FAIL_PLAN_TRACE_WORKFLOW_RESERVE_BYPASSES_EMITTER")
    require(reserve_section, "/tmp/lf_contract_plan_trace_reserve.sql", "FAIL_PLAN_TRACE_WORKFLOW_RESERVE_SQL_MISSING")

    artifact_pos = text.index("Persist unified CI applicability plan")
    artifact_section = text[artifact_pos:pre_pos]
    require(artifact_section, ".lf_ci/lf_contract_plan_trace_v1.json", "FAIL_PLAN_TRACE_WORKFLOW_ARTIFACT_TRACE_MISSING")

    print("PASS_LF_CONTRACT_PLAN_TRACE_WORKFLOW_WIRING_TESTS=12/12")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
