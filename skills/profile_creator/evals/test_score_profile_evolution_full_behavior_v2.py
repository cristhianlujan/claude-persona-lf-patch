import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("scorev2",ROOT/"score_profile_evolution_full_behavior_v2.py")
s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
old_spec=importlib.util.spec_from_file_location("scorev1",ROOT/"score_profile_evolution_full_behavior_v1.py")
old=importlib.util.module_from_spec(old_spec);old_spec.loader.exec_module(old)
protocol=json.loads((ROOT/"profile_evolution_full_behavior_protocol_v2.json").read_text())

class SpecializeContractTests(unittest.TestCase):
    def setUp(self):
        case_data=json.loads((ROOT/"profile_evolution_full_behavior_generation_inputs_v1.json").read_text())["cases"]
        raw=json.loads((ROOT/"results/profile_evolution_full_behavior_raw_fb1.json").read_text())["rows"]
        self.case=next(c for c in case_data if c["case_id"]=="PEB2-004")
        self.row=next(r for r in raw if r["case_id"]=="PEB2-004")
    def _case(self):
        return copy.deepcopy(self.case),copy.deepcopy(self.row)
    def _explicit_reason(self,row):
        contract=row["candidate"]["evolution_contract"]
        contract["capability_composition_decision"]={
            "state":"NO_ADDITIONAL_CAPABILITY_NEEDED",
            "reason":"Verified existing core covers the task and the selector needs no optional capability.",
            "evidence_refs":[contract["evidence_refs"][0]],
        }
    def test_explicit_empty_is_valid(self):
        c,r=self._case();self._explicit_reason(r)
        self.assertTrue(s.candidate_checks(r,c,protocol)["MODE_CONTRACT_COMPLETE"])
    def test_unexplained_empty_is_rejected(self):
        c,r=self._case()
        self.assertFalse(s.candidate_checks(r,c,protocol)["MODE_CONTRACT_COMPLETE"])
    def test_required_capability_must_not_disappear(self):
        c,r=self._case();self._explicit_reason(r)
        c["frozen_decision"]["selected_capabilities"]=["CAUSAL_EFFECT_LINEAGE"]
        self.assertFalse(s.candidate_checks(r,c,protocol)["MODE_CONTRACT_COMPLETE"])
    def test_fake_or_unbound_evidence_rejected(self):
        c,r=self._case();self._explicit_reason(r)
        r["candidate"]["evolution_contract"]["capability_composition_decision"]["evidence_refs"]=["evidence://not-attested"]
        self.assertFalse(s.candidate_checks(r,c,protocol)["MODE_CONTRACT_COMPLETE"])
    def test_nonempty_capabilities_preserve_old_behavior(self):
        c,r=self._case()
        c["frozen_decision"]["selected_capabilities"]=["X"]
        r["candidate"]["evolution_contract"]["capabilities_applied"]=["X"]
        self.assertTrue(s.candidate_checks(r,c,protocol)["MODE_CONTRACT_COMPLETE"])
    def test_historical_v1_unchanged(self):
        c,r=self._case();self._explicit_reason(r)
        v1protocol=json.loads((ROOT/"profile_evolution_full_behavior_protocol_v1.json").read_text())
        self.assertFalse(old.candidate_checks(r,c,v1protocol)["MODE_CONTRACT_COMPLETE"])
    def test_missing_or_empty_reason_rejected(self):
        c,r=self._case();self._explicit_reason(r)
        r["candidate"]["evolution_contract"]["capability_composition_decision"]["reason"]=" "
        self.assertFalse(s.candidate_checks(r,c,protocol)["MODE_CONTRACT_COMPLETE"])

if __name__=="__main__": unittest.main()