"""Owner Step70 clean-context mode: parser/validator only; no judge or host call."""
import importlib.util
import os
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
os.environ.setdefault("LF_PROFILE_EDGE_URL","https://test-only.invalid")
mod_path=ROOT/"scripts/lf_profile_native_resume.py"
spec=importlib.util.spec_from_file_location("native_resume_clean_eval_contract",mod_path)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def case():
    checks={}
    for key in mod.SEMANTIC_CHECKS:
        if key=="router_direct_consistency":
            checks[key]={"reason":"No direct route is permitted by ACT-0001",
                         "source_refs":["router://authoritative"],"result":"not_applicable",
                         "applicability":"ROUTER_ONLY"}
        else:
            checks[key]={"reason":"Reviewed from frozen candidate and source-bounded evidence",
                         "source_refs":["github://trusted/source"],"result":True}
    return {"review_mode":"INDEPENDENT_EVAL_CONTEXT",
        "verdict":"PASS_INDEPENDENT_SEMANTIC",
        "reviewer_is_producer":False,
        "producer_context_available":False,
        "producer_independence_proven":True,
        "model_call_count":None,
        "reviewer_context_ref":"context://isolated-eval-2",
        "candidate_sha256":"a"*64,"scope_packet_sha256":"b"*64,
        "decision_checks":checks,"router_direct_consistency":"NOT_TESTED",
        "counterfactual_result":"PASS","unsupported_claims":[],
        "blocking_codes":[],"source_refs":["github://trusted/source"],
        "resolved_context_refs":["github://trusted/frozen-review-bundle"]}

class NativeCleanEval(unittest.TestCase):
    def test_structural_valid_but_not_independent_until_sql_chain(self):
        review=case()
        mod.validate_independent_semantic_review(review)
        receipt=mod.build_semantic_receipt(review)
        self.assertEqual(receipt["review_mode"],"INDEPENDENT_EVAL_CONTEXT")
        self.assertIsNone(receipt["model_call_count"])
        self.assertIs(receipt["reviewer_is_producer"],False)
        self.assertEqual(receipt["content_findings"],[])
        # This fixture is NOT an independently recorded Step70 or a judge call.
    def test_self_review_refused(self):
        for attr,value in (("reviewer_is_producer",True),
                           ("producer_context_available",True),
                           ("producer_independence_proven",False),
                           ("model_call_count",1),
                           ("reviewer_context_ref","")):
            r=case();r[attr]=value
            with self.subTest(attr=attr),self.assertRaises(ValueError):
                mod.validate_independent_semantic_review(r)
    def test_unattested_legacy_independent_mode_still_blocked(self):
        r=case();r["review_mode"]="INDEPENDENT_SEMANTIC";r["model_call_count"]=1
        with self.assertRaises(ValueError):
            mod.validate_independent_semantic_review(r)

if __name__=="__main__":unittest.main()
