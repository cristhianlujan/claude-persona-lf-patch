import importlib.util
import unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('g',Path(__file__).with_name('edge_pg01_oidc_environment_gate_v1.py'))
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
class GateTests(unittest.TestCase):
 def setUp(self):
  self.good={'name':'lf-edge-deploy','can_admins_bypass':False,'protection_rules':[{'type':'branch_policy'},{'type':'required_reviewers','reviewers':[{'reviewer':{'id':42,'login':'reviewer'}}]}]}
 def test_positive(self):self.assertIsNone(g.qualify(self.good))
 def test_no_reviewers(self):self.assertEqual(g.qualify({**self.good,'protection_rules':[{'type':'branch_policy'}]}),'REQUIRED_REVIEWERS_NOT_CONFIGURED')
 def test_admin_bypass(self):self.assertEqual(g.qualify({**self.good,'can_admins_bypass':True}),'ADMIN_BYPASS_ENABLED_OR_UNKNOWN')
 def test_unknown_bypass(self):self.assertEqual(g.qualify({k:v for k,v in self.good.items() if k!='can_admins_bypass'}),'ADMIN_BYPASS_ENABLED_OR_UNKNOWN')
 def test_empty_reviewers(self):self.assertEqual(g.qualify({**self.good,'protection_rules':[{'type':'required_reviewers','reviewers':[]}]}),'REVIEWER_IDENTITIES_MISSING')
 def test_bad_name(self):self.assertEqual(g.qualify({**self.good,'name':'other'}),'ENVIRONMENT_IDENTITY_MISMATCH')
if __name__=='__main__':unittest.main()
