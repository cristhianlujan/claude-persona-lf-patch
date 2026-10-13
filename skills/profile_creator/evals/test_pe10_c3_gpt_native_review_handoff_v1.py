#!/usr/bin/env python3
"""Deterministic negative controls for PE10 C3 handoff (no model call)."""
import importlib.util
import unittest
from copy import deepcopy
from pathlib import Path

p=Path(__file__).with_name("pe10_c3_gpt_native_review_handoff_v1.py")
spec=importlib.util.spec_from_file_location("handoff",p)
h=importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.source={"request":{"subject":{"subject_ref":h.SUBJECT,"required_dimensions":h.DIMS},
          "review_execution_id":h.REVIEW,"review_next_step":"semantic_review",
          "review_result_state":"IN_PROGRESS","dispatch_receipt_state":"ISSUED_EXACT_ORCHESTRATOR_DISPATCH",
          "producer_receipt_state":"VERIFIED_PROVIDER_BOUND_SUBJECT",
          "source_producer_execution_id":"PRODUCER",
          "subject_sha256":"a"*64,"source_head_sha":"b"*64,
          "capability_manifest_sha256":"c"*64,
          "subject_receipt_id":"src","review_dispatch_receipt_id":"disp"}}
        self.packet=h.prepare(self.source)
        self.reply={"packet_sha256":self.packet["packet_sha256"],
          "review_execution_id":h.REVIEW,"subject_sha256":"a"*64,
          "verdict":"FAIL","reviewer_execution_id":"SEPARATE_REVIEWER",
          "rationale_summary":"Independent contradictory findings",
          "evidence_refs":["source:1"],"review_context":"INDEPENDENT_OPERATION_CONTEXT",
          "utility_dimensions_checked":h.DIMS,
          "independence_measure":{"state":"INDEPENDENT",**{d+"_dimension":{"state":"INDEPENDENT"} for d in h.DIMS}}}
    def test_positive_shape_never_admits(self):
        r=h.intake(self.packet,self.reply)
        self.assertFalse(r["db_write_authorized"])
        self.assertFalse(r["independent_assurance_admitted"])
    def _positive_with_matched_behavior(self):
        r=deepcopy(self.reply)
        r["verdict"]="PASS"
        r["evidence_refs"]=["original:case01","evolved:case01","judge:case01"]
        r["semantic_behavior_basis"]={
          "schema":"PE10_C3_MATCHED_BEHAVIOR_BASIS_V1",
          "critical_regressions":0,
          "matched_pairs":[{"case_id":"CASE-01",
            "baseline_raw_ref":"original:case01",
            "candidate_raw_ref":"evolved:case01",
            "review_evidence_ref":"judge:case01",
            "outcome":"IMPROVED","critical":False}],
        }
        return r
    def test_positive_semantics_bound_still_not_admitted(self):
        r=self._positive_with_matched_behavior()
        x=h.intake(self.packet,r)
        self.assertEqual(x["semantic_basis_state"],"REVIEWER_CLAIM_PAIRED_BASIS_PRESENT_UNATTESTED")
        self.assertFalse(x["db_write_authorized"])
        self.assertFalse(x["independent_assurance_admitted"])
    def test_positive_without_matched_behavior_rejected(self):
        r=self._positive_with_matched_behavior()
        del r["semantic_behavior_basis"]
        with self.assertRaisesRegex(ValueError,"SEMANTIC_BEHAVIOR_BASIS_MISSING"):
            h.intake(self.packet,r)
    def test_unbound_raw_rejected(self):
        r=self._positive_with_matched_behavior()
        r["semantic_behavior_basis"]["matched_pairs"][0]["candidate_raw_ref"]="fabricated:uri"
        with self.assertRaisesRegex(ValueError,"SEMANTIC_PAIR_REF_UNBOUND"):
            h.intake(self.packet,r)
    def test_duplicate_or_self_comparison_rejected(self):
        r=self._positive_with_matched_behavior()
        r["semantic_behavior_basis"]["matched_pairs"][0]["candidate_raw_ref"]="original:case01"
        with self.assertRaisesRegex(ValueError,"SEMANTIC_PAIR_ARMS_NOT_DISTINCT"):
            h.intake(self.packet,r)
    def test_regression_not_greenwashed(self):
        r=self._positive_with_matched_behavior()
        p=r["semantic_behavior_basis"]["matched_pairs"][0]
        p["outcome"]="REGRESSION";p["critical"]=True
        with self.assertRaisesRegex(ValueError,"SEMANTIC_CRITICAL_REGRESSION_FOUND"):
            h.intake(self.packet,r)
    def test_no_observed_gain_rejected(self):
        r=self._positive_with_matched_behavior()
        r["semantic_behavior_basis"]["matched_pairs"][0]["outcome"]="PRESERVED"
        with self.assertRaisesRegex(ValueError,"SEMANTIC_NO_OBSERVED_IMPROVEMENT"):
            h.intake(self.packet,r)
    def test_fail_verdict_still_can_be_recorded(self):
        x=h.intake(self.packet,self.reply)
        self.assertEqual(x["semantic_basis_state"],"NOT_REQUIRED_FOR_NEGATIVE_VERDICT")
    def test_packet_tampered(self):
        p=deepcopy(self.packet);p["subject_sha256"]="f"*64
        with self.assertRaisesRegex(ValueError,"PACKET_TAMPERED"):h.intake(p,self.reply)
    def test_same_producer(self):
        r=deepcopy(self.reply);r["reviewer_execution_id"]="PRODUCER"
        with self.assertRaisesRegex(ValueError,"SELF_REVIEW"):h.intake(self.packet,r)
    def test_data_dimension_unproven(self):
        r=deepcopy(self.reply);r["independence_measure"]["data_dimension"]["state"]="UNPROVEN"
        with self.assertRaisesRegex(ValueError,"INDEPENDENCE_DATA_UNPROVEN"):h.intake(self.packet,r)
    def test_mismatched_subject(self):
        r=deepcopy(self.reply);r["subject_sha256"]="0"*64
        with self.assertRaisesRegex(ValueError,"REVIEW_SUBJECT_MISMATCH"):h.intake(self.packet,r)
    def test_missing_dispatch(self):
        s=deepcopy(self.source);s["request"]["dispatch_receipt_state"]="MISSING"
        with self.assertRaisesRegex(ValueError,"DISPATCH_MISSING"):h.prepare(s)

if __name__=="__main__":unittest.main()