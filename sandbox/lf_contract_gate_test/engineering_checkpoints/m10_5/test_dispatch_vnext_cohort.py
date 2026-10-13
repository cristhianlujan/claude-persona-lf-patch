#!/usr/bin/env python3
"""Logical transport tests; do not issue Edge calls or CP2 admission receipts."""
import importlib.util
import pathlib
import unittest

SOURCE = pathlib.Path(__file__).with_name("dispatch_vnext_cohort.py")
spec = importlib.util.spec_from_file_location("m105_cp2_dispatch", SOURCE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
SCOPE = {"schema_version": "M105_SCOPE_SNAPSHOT_V1", "screen_ids": list(range(1, 14))}
RELEASE = {"version": "1.1.0", "previous_version": "1.0.0", "manifest_sha256": "a" * 64}

class FakeTransport:
    def __init__(self, statuses=None, cp2="PASS_CP2", bad_run=False, bad_receipt=False):
        self.statuses = statuses or ["READY"]
        self.cp2 = cp2
        self.bad_run = bad_run
        self.bad_receipt = bad_receipt
        self.calls = []
        self.index = 0
    def query(self, route, body=None):
        self.calls.append((route, body))
        if route.startswith("/functions/"):
            status = self.statuses[min(self.index, len(self.statuses)-1)]
            self.index += 1
            return {"result": {"status": status, "run_id": body["pantalla_id"]}}
        if route.endswith("fn_ig_m105_cp2_attest_run_v1"):
            return {"status": "REJECTED" if self.bad_receipt else "PERSISTED_VERIFIED",
                    "run_id": body["p_run_id"], "receipt_id": 567}
        return [{"run_id": 99 if self.bad_run else body["p_pantalla_id"],
                 "cp2_verdict": self.cp2, "technical_verdict": "PASS_TECNICO"}]

class DispatcherTests(unittest.TestCase):
    def test_canonical_cohort(self):
        self.assertEqual(mod.check_scope(SCOPE, RELEASE), "READY_TO_DISPATCH")
    def test_no_vnext(self):
        self.assertEqual(mod.check_scope(SCOPE, dict(RELEASE, previous_version=None)), "NO_GENUINE_VNEXT")
    def test_duplicate_id(self):
        self.assertEqual(mod.check_scope(dict(SCOPE, screen_ids=[1]*13), RELEASE), "INVALID_COHORT")
    def test_missing_scope(self):
        self.assertEqual(mod.check_scope({}, RELEASE), "INVALID_SCOPE")
    def test_no_calls_before_explicit_execution(self):
        t=FakeTransport()
        out=mod.execute(SCOPE, RELEASE, t)
        self.assertEqual(out["attempts"],0)
        self.assertEqual(t.calls,[])
    def test_genuine_return_path_readback(self):
        t=FakeTransport()
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],13)
        self.assertEqual(out["attempts"],13)
    def test_human_review_is_not_execution_error(self):
        t=FakeTransport(statuses=["HUMAN_DECISION_REQUIRED"])
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],13)
    def test_semantic_block_is_not_execution_error(self):
        t=FakeTransport(statuses=["BLOCKED"])
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],13)
    def test_no_verified_provenance_blocks(self):
        t=FakeTransport(cp2="ERROR_PROCEDENCIA")
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],0)
        self.assertTrue(all(x["status"]=="ERROR_PROCEDENCIA" for x in out["results"]))
    def test_unverified_attestation_never_passes(self):
        t=FakeTransport(bad_receipt=True)
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],0)
        self.assertTrue(all(x["status"]=="ERROR_CANONICAL_ATTESTATION" for x in out["results"]))
    def test_every_positive_requires_attestation(self):
        t=FakeTransport()
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],13)
        self.assertEqual(sum(route.endswith("fn_ig_m105_cp2_attest_run_v1")
                             for route, _ in t.calls),13)
    def test_valid_rejection_still_requires_receipt(self):
        t=FakeTransport(statuses=["BLOCKED"],bad_receipt=True)
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],0)
    def test_real_run_must_match_readback(self):
        t=FakeTransport(bad_run=True)
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],0)
        self.assertTrue(all(x["status"]=="ERROR_RUN_ID_MISMATCH" for x in out["results"]))
    def test_pending_continuation_then_terminal(self):
        t=FakeTransport(statuses=["VALIDATOR_RESUME_REQUIRED","READY"])
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],13)
        self.assertEqual(out["results"][0]["attempts"],2)
    def test_incomplete_edge_status(self):
        t=FakeTransport(statuses=["UNRESOLVED"])
        out=mod.execute(SCOPE, RELEASE, t, allowed=True)
        self.assertEqual(out["cp2_pass_count"],0)
        self.assertTrue(all(x["status"]=="ERROR_EDGE_NONTERMINAL" for x in out["results"]))

if __name__=="__main__":
    unittest.main()
