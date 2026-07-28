"""Shared helpers for creating-integral-user-stories validators.

No side effects. No network. Read-only over JSON evidence files.
"""
import json
import sys

RESULT_VALUES = ("PASS_WITH_EVIDENCE", "RETURN_TO_WORKER", "BLOCKED", "FAIL")


def load(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def emit(judge_code, failed, evidence):
    ok = len(failed) == 0
    out = {
        "judge_code": judge_code,
        "result": "PASS_WITH_EVIDENCE" if ok else "RETURN_TO_WORKER",
        "compliance_bit": 1 if ok else 0,
        "failed_assertions": failed,
        "evidence_refs": evidence,
        "repair_instructions": ["fix: " + f for f in failed],
    }
    print(json.dumps(out, ensure_ascii=False, sort_keys=True))
    return 0 if ok else 1


def argv_path(index=1):
    if len(sys.argv) <= index:
        print(json.dumps({"result": "BLOCKED", "reason": "missing_input_path"}))
        raise SystemExit(2)
    return sys.argv[index]
