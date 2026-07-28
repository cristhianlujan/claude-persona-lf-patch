"""Compute the binary execution ledger completion percent. Section 6.4 of source v0.1."""
import sys

from lf_common import argv_path, emit, load

BIT_ONE = "PASS_WITH_EVIDENCE"
EXCLUDED = "N/A_APPROVED"


def main():
    ledger = load(argv_path(1))
    steps = ledger.get("steps", [])
    evaluable = [s for s in steps if s.get("status") != EXCLUDED
                 and (s.get("required") or s.get("applicable"))]
    bits = sum(1 for s in evaluable if s.get("status") == BIT_ONE
               and s.get("compliance_bit") == 1)
    total = len(evaluable)
    percent = round((bits / total) * 100, 2) if total else 0.0
    critical_zero = [s.get("step_id") for s in evaluable
                     if s.get("critical") and s.get("compliance_bit") != 1]
    no_evidence = [s.get("step_id") for s in evaluable if not s.get("evidence_refs")]
    judges_pending = [s.get("step_id") for s in evaluable if not s.get("judge_result")]
    failed = []
    if percent != 100.0:
        failed.append("completion_percent=%s" % percent)
    if critical_zero:
        failed.append("critical_steps_with_bit_zero=%d" % len(critical_zero))
    if no_evidence:
        failed.append("steps_without_evidence=%d" % len(no_evidence))
    if judges_pending:
        failed.append("judges_pending=%d" % len(judges_pending))
    evidence = {
        "steps_evaluables": total,
        "compliance_bits": bits,
        "completion_percent": percent,
        "critical_steps_with_bit_zero": critical_zero,
        "judges_pending": judges_pending,
    }
    return emit("J13_INTEGRATION_CLOSE", failed, evidence)


if __name__ == "__main__":
    sys.exit(main())
