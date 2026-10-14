#!/usr/bin/env python3
"""Tests for the A15Q_C1 refreeze confirmation verifier (fixtures are test data, never evidence)."""
import copy
import json
import unittest

import analysis_a15q_c1_refreeze_confirmation_v1 as m


def good(p, e):
    refs = {"BUNDLE_BYTES_MATCH_MANIFEST": [e[0]["sha256"], p["files"][0]["declared_blob"]],
            "REFREEZE_REASON_CONSISTENT": ["PROGRAMMING_ENTRY_CONTRACT_AND_WAVE1_VALIDATOR_CHANGED_AFTER_FIRST_FREEZE", "analysis_decision_context_adr_contract_v1.json"],
            "NO_OVERCLAIM": ["\"merge_performed\": false", "\"story_retirement_authorized\": false"]}
    return {"schema_version": m.SCHEMA,
            "files": [dict(x, matches_declared_blob=True) for x in e],
            "checks": [{"code": c, "result": "PASS", "evidence_refs": refs[c], "note": "x" * 50} for c in m.CHECKS],
            "verdict": "CONFIRM", "rationale": "y" * 50}


class T(unittest.TestCase):
    def setUp(self):
        self.p, self.e = m.build_packet()
        self.g = good(self.p, self.e)

    def v(self, d, raw=None):
        return m.verify_confirmation(raw if raw is not None else json.dumps(d), self.p, self.e)

    def test_positive(self):
        self.assertEqual(self.v(self.g), "CONFIRMED")

    def test_files_match_current_blobs(self):
        for f, x in zip(self.p["files"], self.e):
            self.assertEqual(f["declared_blob"], x["git_blob_sha1"])

    def mut(self, fn):
        d = copy.deepcopy(self.g); fn(d); return self.v(d)

    def test_negatives(self):
        cases = {
            "wrong_sha": lambda d: d["files"][3].__setitem__("sha256", "0" * 64),
            "wrong_blob": lambda d: d["files"][0].__setitem__("git_blob_sha1", "0" * 40),
            "missing_file": lambda d: d["files"].pop(),
            "not_matching_flag": lambda d: d["files"][2].__setitem__("matches_declared_blob", False),
            "check_fail": lambda d: d["checks"][1].__setitem__("result", "FAIL"),
            "confirm_with_fail_reject_verdict": lambda d: d.__setitem__("verdict", "REJECT"),
            "fabricated_ref": lambda d: d["checks"][2].__setitem__("evidence_refs", ["texto inventado uno", "texto inventado dos"]),
            "one_ref": lambda d: d["checks"][0].__setitem__("evidence_refs", [self.e[0]["sha256"]]),
            "short_note": lambda d: d["checks"][0].__setitem__("note", "ok"),
            "bad_schema": lambda d: d.__setitem__("schema_version", "X"),
            "extra_key": lambda d: d.__setitem__("extra", 1),
            "code_order": lambda d: d["checks"].reverse(),
        }
        for name, fn in cases.items():
            self.assertTrue(self.mut(fn).startswith("REJECTED"), name)

    def test_prose_wrapped(self):
        self.assertTrue(self.v(None, "Aquí va:\n" + json.dumps(self.g)).startswith("REJECTED"))
        self.assertTrue(self.v(None, "```json\n" + json.dumps(self.g) + "\n```").startswith("REJECTED"))

    def test_drift_detected_by_fresh_packet(self):
        p2 = copy.deepcopy(self.p); p2["files"][1]["content"] += " "
        e2 = [dict(x, sha256=m.sha256(f["content"].encode()), git_blob_sha1=m.git_blob(f["content"].encode())) for f, x in zip(p2["files"], self.e)]
        self.assertEqual(m.verify_confirmation(json.dumps(self.g), p2, e2)[:9], "REJECTED:")


if __name__ == "__main__":
    unittest.main()
