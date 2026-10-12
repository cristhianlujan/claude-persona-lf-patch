"""Offline contract tests: test doubles never qualify an IG canary closure."""
from __future__ import annotations
import os
import sys
import unittest
from pathlib import Path
HERE = Path(__file__).resolve().parent
RCV = HERE.parents[2] / "transversal_assets" / "reversible_candidate_verification"
sys.path.insert(0, str(RCV))
sys.path.insert(0, str(HERE))
from reversible_candidate_verification_v1 import CandidateIdentity, RollbackContract
from false_pass_runtime_adapter_v1 import IgM99FalsePassFlowAdapter

CAND = CandidateIdentity(
    "git://candidate", "a"*64,
    {"canary_run_ref": "M99-CANARY-01", "baseline_manifest_sha256": "b"*64}
)

def n9(_):
    return {"verdict": "NO_BLOCKING_FINDINGS", "baseline": {"assessment_digest": "same"},
            "candidate": {"assessment_digest": "same"}, "findings": []}

def mocked_readback(candidate, prior):
    # STRUCTURAL FIXTURE ONLY. Not an issued, signed or stored live receipt.
    return {
      "readback_authority": "CANONICAL_PROVENANCE_DB",
      "canary_gate_readback": {
        "action":"ROLLBACK_REQUIRED","readback_only":True,
        "reason_codes":["FALSE_PASS"],"subject_sha256":"b"*64,
        "receipt_sha256":"1"*64,"receipt_id":1},
      "independent_oracle_readback": {
        "verification_status":"VERIFIED","case_code":"FALSE_PASS",
        "producer_decision":"PASS","independent_decision":"FAIL",
        "independence_state":"INDEPENDENT","run_ref":"M99-CANARY-01",
        "candidate_sha256":"a"*64,"receipt_sha256":"2"*64},
      "rollback_action_readback": {
        "verification_status":"VERIFIED","issuer_channel":"EVIDENCE_VERIFIER_V1",
        "case_code":"FALSE_PASS","run_ref":"M99-CANARY-01",
        "candidate_sha256":"a"*64,"baseline_manifest_sha256":"b"*64,
        "executed_automatically":True,"rollback_executed":True,
        "pre_state_digest":"before","post_state_digest":"before",
        "material_residue_count":0,"receipt_sha256":"3"*64,"receipt_id":2}
    }

class M99FalsePassContractTests(unittest.TestCase):
    def adapter(self, reader, *, after="before", residue=0, producer=n9):
        measurements=iter(("before",after))
        return IgM99FalsePassFlowAdapter(
            producer, lambda: next(measurements), lambda:residue, reader
        )

    def outcome(self, reader, **kw):
        return self.adapter(reader,**kw).run_rollback_only(CAND,RollbackContract())

    def test_digest_equality_without_provenance_never_proves_rollback(self):
        r=self.outcome(lambda *_:{})
        self.assertEqual(r["rollback"]["status"],"UNVERIFIED_AUTOMATIC_ROLLBACK")
        self.assertFalse(r["m99_false_pass_proof"]["automatic_rollback_verified"])

    def test_candidate_self_reported_rollback_is_not_evidence(self):
        def spoof(c):
            return {**n9(c),"rollback_executed":True,"false_pass_detected":True}
        r=self.outcome(lambda *_:{},producer=spoof)
        self.assertIn("AUTOMATIC_ROLLBACK_RECEIPT_REQUIRED",
                      r["m99_false_pass_proof"]["findings"])

    def test_canonical_readback_error_blocks(self):
        def failure(*_): raise RuntimeError("test error")
        r=self.outcome(failure)
        self.assertIn("CANONICAL_READBACK_FAILED",r["m99_false_pass_proof"]["findings"])

    def test_only_complete_mocked_structure_passes_local_unit_contract(self):
        r=self.outcome(mocked_readback)
        self.assertEqual(r["rollback"]["status"],"ROLLED_BACK")
        # No external verifier or actual rollback is invoked by this unit test.

    def test_manual_rollback_does_not_qualify(self):
        def read(c,n):
            e=mocked_readback(c,n);e["rollback_action_readback"]["executed_automatically"]=False
            return e
        r=self.outcome(read)
        self.assertIn("AUTOMATIC_ROLLBACK_RECEIPT_REQUIRED",
                      r["m99_false_pass_proof"]["findings"])

    def test_wrong_independent_oracle_blocks(self):
        def read(c,n):
            e=mocked_readback(c,n);e["independent_oracle_readback"]["independent_decision"]="PASS"
            return e
        r=self.outcome(read)
        self.assertIn("INDEPENDENT_LIVE_ORACLE_REQUIRED",r["m99_false_pass_proof"]["findings"])

    def test_nonzero_residue_blocks_even_with_equal_digests(self):
        r=self.outcome(mocked_readback,residue=1)
        self.assertIn("POSTSTATE_OR_RESIDUE_MISMATCH",r["m99_false_pass_proof"]["findings"])

    def test_changed_poststate_blocks(self):
        r=self.outcome(mocked_readback,after="different")
        self.assertIn("POSTSTATE_OR_RESIDUE_MISMATCH",r["m99_false_pass_proof"]["findings"])

    def test_missing_baseline_pin_blocks(self):
        c=CandidateIdentity("git://candidate","a"*64,
                             {"canary_run_ref":"M99-CANARY-01","baseline_manifest_sha256":"bad"})
        r=self.adapter(mocked_readback).run_rollback_only(c,RollbackContract())
        self.assertIn("BASELINE_MANIFEST_PIN_REQUIRED",r["m99_false_pass_proof"]["findings"])

    def test_cross_run_rollback_receipt_blocks(self):
        def read(c,n):
            e=mocked_readback(c,n);e["rollback_action_readback"]["run_ref"]="M99-OTHER"
            return e
        r=self.outcome(read)
        self.assertIn("AUTOMATIC_ROLLBACK_RECEIPT_REQUIRED",
                      r["m99_false_pass_proof"]["findings"])

    def test_nonfalsepass_gate_rejected(self):
        def read(c,n):
            e=mocked_readback(c,n);e["canary_gate_readback"]["reason_codes"]=["TIMEOUT"]
            return e
        r=self.outcome(read)
        self.assertIn("VERIFIED_FALSE_PASS_DECISION_MISSING",
                      r["m99_false_pass_proof"]["findings"])

if __name__ == "__main__":
    unittest.main()
