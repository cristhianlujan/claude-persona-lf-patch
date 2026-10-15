#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import json
import tempfile
import unittest

SOURCE = Path(__file__).with_name("lf_train_required_check_guard.py")
SPEC = importlib.util.spec_from_file_location("train_required_check_guard", SOURCE)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)

HEAD = "a" * 40


def check(name, conclusion="success", *, status="completed", head=HEAD):
    return {"name": name, "conclusion": conclusion, "status": status, "head_sha": head}


def valid_pair():
    return {"check_runs": [
        check("lf-independent-change-admission"),
        check("ig-runtime-candidate-judge"),
    ]}


class RequiredPaseChecksTests(unittest.TestCase):
    def setUp(self):
        self.required = guard.load_required_checks()

    def test_required_checks_are_loaded_from_versioned_file(self):
        self.assertEqual(self.required, (
            "lf-independent-change-admission", "ig-runtime-candidate-judge"
        ))

    def test_success_pair_passes_on_exact_head(self):
        self.assertEqual(guard.evaluate(valid_pair(), HEAD, self.required, final=True),
                         (0, "PASS_TRAIN_REQUIRED_PASE_CHECKS"))

    def test_paginated_check_runs_are_combined(self):
        pages = [
            {"check_runs": [check("lf-independent-change-admission")]},
            {"check_runs": [check("ig-runtime-candidate-judge")]},
        ]
        self.assertEqual(guard.evaluate(pages, HEAD, self.required, final=True),
                         (0, "PASS_TRAIN_REQUIRED_PASE_CHECKS"))

    def test_skipped_blocks_explicitly(self):
        payload = valid_pair()
        payload["check_runs"][0]["conclusion"] = "skipped"
        code, message = guard.evaluate(payload, HEAD, self.required, final=True)
        self.assertEqual(code, guard.BLOCK)
        self.assertIn("FAIL_TRAIN_REQUIRED_CHECK_NOT_SUCCESS", message)
        self.assertIn("conclusion=skipped", message)

    def test_neutral_blocks_explicitly(self):
        payload = valid_pair()
        payload["check_runs"][1]["conclusion"] = "neutral"
        code, message = guard.evaluate(payload, HEAD, self.required, final=True)
        self.assertEqual(code, guard.BLOCK)
        self.assertIn("FAIL_TRAIN_REQUIRED_CHECK_NOT_SUCCESS", message)
        self.assertIn("conclusion=neutral", message)

    def test_missing_check_blocks_explicitly(self):
        payload = {"check_runs": [check("lf-independent-change-admission")]}
        code, message = guard.evaluate(payload, HEAD, self.required, final=True)
        self.assertEqual(code, guard.BLOCK)
        self.assertIn("FAIL_TRAIN_REQUIRED_CHECK_MISSING", message)
        self.assertIn("ig-runtime-candidate-judge", message)

    def test_missing_check_waits_before_final_poll(self):
        payload = {"check_runs": [check("lf-independent-change-admission")]}
        code, message = guard.evaluate(payload, HEAD, self.required)
        self.assertEqual(code, guard.WAIT)
        self.assertIn("WAIT_TRAIN_REQUIRED_CHECK_MISSING", message)

    def test_exact_head_mismatch_blocks(self):
        payload = valid_pair()
        payload["check_runs"][1]["head_sha"] = "b" * 40
        code, message = guard.evaluate(payload, HEAD, self.required, final=True)
        self.assertEqual(code, guard.BLOCK)
        self.assertIn("FAIL_TRAIN_REQUIRED_CHECK_HEAD_MISMATCH", message)

    def test_other_skipped_pase_checks_are_ignored(self):
        payload = valid_pair()
        payload["check_runs"].append(check("PASE", "skipped"))
        payload["check_runs"].append(check("pase-merge-gate", "skipped"))
        self.assertEqual(guard.evaluate(payload, HEAD, self.required, final=True),
                         (0, "PASS_TRAIN_REQUIRED_PASE_CHECKS"))

    def test_pending_check_waits_then_blocks_if_still_pending(self):
        payload = valid_pair()
        payload["check_runs"][0]["status"] = "in_progress"
        self.assertEqual(guard.evaluate(payload, HEAD, self.required)[0], guard.WAIT)
        code, message = guard.evaluate(payload, HEAD, self.required, final=True)
        self.assertEqual(code, guard.BLOCK)
        self.assertIn("FAIL_TRAIN_REQUIRED_CHECK_NOT_COMPLETED", message)

    def test_check_added_to_file_but_absent_from_pr_blocks(self):
        with tempfile.TemporaryDirectory() as temp:
            config = Path(temp) / "required.json"
            config.write_text(json.dumps({
                "schema_version": "lf-train-required-pre-apply-checks/v1",
                "required_checks": [*self.required, "PASE"],
            }), encoding="utf-8")
            required = guard.load_required_checks(config)
        code, message = guard.evaluate(valid_pair(), HEAD, required, final=True)
        self.assertEqual(code, guard.BLOCK)
        self.assertIn("FAIL_TRAIN_REQUIRED_CHECK_MISSING check=PASE", message)


if __name__ == "__main__":
    unittest.main()

