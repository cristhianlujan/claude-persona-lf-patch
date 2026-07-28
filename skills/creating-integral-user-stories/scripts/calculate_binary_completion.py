"""Compute binary completion and enforce J13 close conditions."""
from __future__ import annotations

from lf_common import (
    add_common_input, emit, failure, load_json, main_guard, parser,
    require_object, result_object,
)

JUDGE = "J13_INTEGRATION_CLOSE"


def run() -> int:
    cli = parser(__doc__)
    add_common_input(cli, "Execution ledger JSON file")
    cli.add_argument("--retry-count", type=int, default=0)
    args = cli.parse_args()
    ledger = require_object(load_json(args.input), "execution_ledger")
    steps = ledger.get("steps")
    if not isinstance(steps, list) or not steps:
        return emit(result_object(
            JUDGE, [], {"steps_count": 0},
            args.evidence_ref or [f"file:{args.input}"],
            blocking_assertions=["execution_steps_missing = true"],
            retry_count=args.retry_count,
            forced_result="BLOCKED",
        ))

    evaluable = [
        step for step in steps
        if isinstance(step, dict)
        and step.get("applicable") is not False
        and (step.get("required") is True or step.get("applicable") is True)
    ]
    passed = [
        step for step in evaluable
        if step.get("status") == "PASS_WITH_EVIDENCE"
        and step.get("compliance_bit") == 1
        and step.get("evidence_refs")
        and step.get("judge_result") == "PASS_WITH_EVIDENCE"
    ]
    total = len(evaluable)
    percent = round((len(passed) / total) * 100, 2) if total else 0.0
    critical_zero = [
        step.get("step_id") for step in evaluable
        if step.get("critical") and step.get("compliance_bit") != 1
    ]
    no_evidence = [
        step.get("step_id") for step in evaluable if not step.get("evidence_refs")
    ]
    judges_pending = [
        step.get("step_id") for step in evaluable
        if step.get("judge_result") != "PASS_WITH_EVIDENCE"
    ]
    failed_assertions_open = sum(
        len(step.get("failed_assertions", []))
        for step in evaluable if isinstance(step.get("failed_assertions"), list)
    )
    failures = {}
    if percent != 100.0:
        failures["completion_percent"] = f"Calculated {percent}, required 100."
    if critical_zero:
        failures["critical_steps_with_bit_zero"] = str(critical_zero)
    if no_evidence:
        failures["steps_without_evidence"] = str(no_evidence)
    if judges_pending:
        failures["judges_pending"] = str(judges_pending)
    if failed_assertions_open:
        failures["failed_assertions_open"] = str(failed_assertions_open)

    failed = [
        f"{key}={len(value) if isinstance(value, list) else value}"
        for key, value in (
            ("completion_percent", percent if percent != 100.0 else None),
            ("critical_steps_with_bit_zero", critical_zero),
            ("steps_without_evidence", no_evidence),
            ("judges_pending", judges_pending),
            ("failed_assertions_open", failed_assertions_open if failed_assertions_open else None),
        )
        if value
    ]
    repairs = [
        failure(key, "steps", instruction)
        for key, instruction in failures.items()
    ]
    evidence = {
        "steps_evaluable": total,
        "steps_passed_with_evidence": len(passed),
        "completion_percent": percent,
        "critical_steps_with_bit_zero": critical_zero,
        "steps_without_evidence": no_evidence,
        "judges_pending": judges_pending,
        "failed_assertions_open": failed_assertions_open,
        "input_path": str(args.input),
    }
    return emit(result_object(
        JUDGE, failed, evidence, args.evidence_ref or [f"file:{args.input}"],
        repairs, retry_count=args.retry_count,
    ))


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, run))
