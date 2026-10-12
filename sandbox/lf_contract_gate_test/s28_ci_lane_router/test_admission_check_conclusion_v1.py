#!/usr/bin/env python3
"""Offline gate verification against the same jq expression used by the Train."""
import json
import pathlib
import re
import subprocess
import unittest

WF = pathlib.Path(__file__).resolve().parents[3] / ".github/workflows/lf-migration-merge-train.yml"

def evaluate(conclusion, summary):
    text = WF.read_text()
    line = next(s for s in text.splitlines() if 'bad="$(printf' in s)
    expr = re.search(r"\| jq '(.+)'\)", line).group(1)
    payload = {"check_runs":[{"name":"lf-independent-change-admission",
                              "status":"completed","conclusion":conclusion,
                              "output":{"summary":summary}}]}
    process = subprocess.run(["jq",expr],input=json.dumps(payload),text=True,
                             capture_output=True,check=True)
    return int(process.stdout.strip())

class AdmissionTests(unittest.TestCase):
    def test_skipped_fails(self): self.assertEqual(evaluate("skipped",""),1)
    def test_neutral_fails(self): self.assertEqual(evaluate("neutral",""),1)
    def test_explicit_not_applicable_passes(self):
        self.assertEqual(evaluate("success","RESULT=NOT_APPLICABLE\n"),0)
    def test_missing_output_fails(self): self.assertEqual(evaluate("success",""),1)
    def test_applicable_success_passes(self):
        self.assertEqual(evaluate("success","RESULT=APPLICABLE_PASS\n"),0)
    def test_failed_job_with_spoofed_output_fails(self):
        self.assertEqual(evaluate("failure","RESULT=NOT_APPLICABLE\n"),1)

if __name__=="__main__": unittest.main()
