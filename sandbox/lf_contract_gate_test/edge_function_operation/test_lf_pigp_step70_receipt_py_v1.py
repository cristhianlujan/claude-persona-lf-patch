"""LF-PIGP 03/04/05: material receipt errors fail closed, missing receipt
downgrades to PASS_REVIEWED_CURRENT_CONTEXT, bad source_refs fail evaluation.
Tests deterministic behavior; does not assert external model independence.
"""
import unittest
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"scripts"))
from lf_step70_separate_call_receipt_v1 import normalize_when_unverified
from lf_step70_same_llm_eval_v1 import evaluate,SCHEMA_ID

RUN="EXEC-PROFILE-GATE2-AAAAAAAAAAAAAAAAAAAAAAAA"
OTHER="EXEC-PROFILE-GATE2-BBBBBBBBBBBBBBBBBBBBBBBB"
REQ={
 "schema_version","receipt_ref","execution_id","model_id","model_call_id",
 "producer_call_ref","reviewer_call_ref","prompt_sha256",
 "producer_prompt_sha256","schema_id","producer_schema_id",
 "eval_id","producer_eval_id","eval_status","model_call_count",
 "candidate_sha256","scope_packet_sha256","decision_body","provider_attestation"
}
class PigpStep70Receipt(unittest.TestCase):
 def test_no_receipt_keeps_content_only(self):
  review={"candidate_sha256":"a"*64,"scope_packet_sha256":"b"*64}
  res,ass=normalize_when_unverified(review,execution_id=RUN)
  self.assertEqual(res["verdict"],"PASS_REVIEWED_CURRENT_CONTEXT")
  self.assertEqual(res["review_mode"],"CURRENT_CONTEXT_REVIEW")
  self.assertFalse(ass["producer_independence_proven"])
  self.assertEqual(ass["model_call_count"],0)
 def test_foreign_execution_receipt_fails_closed(self):
  receipt={k:None for k in REQ}
  receipt.update(schema_version="LF_STEP70_SAME_LLM_SEPARATE_CALL_RECEIPT_V1",
                 execution_id=OTHER)
  with self.assertRaisesRegex(ValueError,"^STEP70_RUN_ID_DRIFT$"):
   normalize_when_unverified({"separate_model_call_receipt":receipt},execution_id=RUN)
 def test_material_values_not_downgraded(self):
  from unittest.mock import patch
  import lf_step70_separate_call_receipt_v1 as s
  for code in sorted(s.MATERIAL_CODES):
   with self.subTest(code=code),patch.object(s,"assess_separate_call_receipt",side_effect=ValueError(code)):
    with self.assertRaisesRegex(ValueError,"^"+code+"$"):
     s.normalize_when_unverified({},execution_id=RUN)
 def test_short_ref_fails_eval(self):
  out=evaluate({"schema_id":SCHEMA_ID,"execution_id":RUN,
                "candidate_sha256":"a"*64,"scope_packet_sha256":"b"*64,
                "source_refs":["x"]},RUN,"a"*64,"b"*64)
  self.assertEqual(out["eval_status"],"FAIL")
  self.assertIn("REVIEW_SOURCE_REFS_MISSING",out["errors"])
 def test_native_resume_catches_binding_errors(self):
  content=(ROOT/"scripts/lf_profile_native_resume.py").read_text(encoding="utf-8")
  self.assertIn("normalize_when_unverified(semantic_review, execution_id=execution_id)",content)
  self.assertIn('"phase":"SEMANTIC_REVIEW","code":str(exc)',content)
if __name__=="__main__":unittest.main()
