#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "lf_contract_check.py"
spec = importlib.util.spec_from_file_location("lf_contract_check_candidate_receipt", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)

RECEIPT_PATH = "sandbox/lf_contract_gate_test/receipts/candidate-demo.json"
TARGET = "profiles/demo/SKILL.md"
CODE_HEAD = "a" * 40
BLOB = "b" * 40

def fake_fail(code, message):
    raise RuntimeError(code)

def make_run_git(*, contamination=False, blob=BLOB, ancestor=True):
    def run_git(args):
        if args[:2] == ["merge-base", "--is-ancestor"]:
            if not ancestor:
                import subprocess
                raise subprocess.CalledProcessError(1, args)
            return ""
        if args[:2] == ["diff", "--name-only"]:
            rows = [RECEIPT_PATH]
            if contamination:
                rows.append(TARGET)
            return "\n".join(rows) + "\n"
        if args[:3] == ["ls-files", "-s", "--"]:
            path = args[3]
            return f"100644 {blob} 0\t{path}\n"
        raise AssertionError(args)
    return run_git

BASE = {
    "receipt_type": "LF_OPERATION_CANDIDATE_RECEIPT",
    "receipt_version": "v1",
    "issued_by": "operation_judge",
    "operation_code": "ACTUALIZACION_PERFIL_LF",
    "execution_id": "EXEC-DEMO-001",
    "result": "PASS_CANDIDATE",
    "all_pre_merge_required_steps_pass": True,
    "pre_merge_terminal_step": "regression_after",
    "contract_sha": "c" * 64,
    "judge_sha": "d" * 64,
    "source_sha_list": [CODE_HEAD, BLOB],
    "target_paths": [TARGET],
    "target_blob_sha_by_path": {TARGET: BLOB},
    "blocking_codes": [],
    "issued_at": "2026-09-20T00:00:00Z",
    "candidate_code_head": CODE_HEAD,
    "operation_status_at_issue": "IN_PROGRESS",
    "next_gate": "MERGE_AND_POST_MERGE_RECONCILE",
}

mod.fail = fake_fail

def expect_pass(receipt, run_git):
    mod.run_git = run_git
    mod.validate_candidate_receipt_shape(RECEIPT_PATH, receipt, [TARGET])

def expect_fail(code, receipt, run_git):
    mod.run_git = run_git
    try:
        mod.validate_candidate_receipt_shape(RECEIPT_PATH, receipt, [TARGET])
    except RuntimeError as exc:
        assert str(exc) == code, (code, exc)
        return
    raise AssertionError(f"expected {code}")

expect_pass(copy.deepcopy(BASE), make_run_git())

bad = copy.deepcopy(BASE); bad["operation_status_at_issue"] = "COMPLETED"
expect_fail("FAIL_CANDIDATE_RECEIPT_FINALITY_CONFUSION", bad, make_run_git())

bad = copy.deepcopy(BASE); bad["all_pre_merge_required_steps_pass"] = False
expect_fail("FAIL_CANDIDATE_RECEIPT_INCOMPLETE_PRE_MERGE", bad, make_run_git())

expect_fail("FAIL_CANDIDATE_RECEIPT_POST_HEAD_CONTAMINATION", copy.deepcopy(BASE), make_run_git(contamination=True))
expect_fail("FAIL_CANDIDATE_RECEIPT_BLOB_MISMATCH", copy.deepcopy(BASE), make_run_git(blob="e"*40))
expect_fail("FAIL_CANDIDATE_RECEIPT_CODE_HEAD_NOT_ANCESTOR", copy.deepcopy(BASE), make_run_git(ancestor=False))

bad = copy.deepcopy(BASE); bad["target_paths"] = ["profiles/other/*"]
expect_fail("FAIL_CANDIDATE_RECEIPT_TARGET_MISMATCH", bad, make_run_git())

print("PASS_CANDIDATE_RECEIPT_CONTRACT=7/7")
