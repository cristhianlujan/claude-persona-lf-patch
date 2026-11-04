"""Switch semantics must never turn an OFF or fixture into production PASS."""
import unittest
from lf_pg_switchboard_v1 import CHECKPOINTS,default,run,run_tests

class SwitchboardTests(unittest.TestCase):
 def test_all_on_is_synthetic(self):
  r=run(default())
  self.assertEqual((r["stage_count"],r["checkpoint_count"]),(14,78))
  self.assertTrue(r["all_stages_reached"])
  self.assertFalse(r["production_authority"])
  self.assertFalse(r["admission_allowed"])
  self.assertFalse(r["testing_real_invoked"])
  self.assertTrue(all(x["status"]=="SIMULATED_CANDIDATE" for x in r["checkpoints"]))
 def test_off_one_stage_does_not_prevent_diagnostic_continuation(self):
  c=default();c["stage_overrides"]["PG-08"]="OFF";r=run(c)
  self.assertEqual(r["stages"][7]["status"],"DIAGNOSTIC_BYPASS_PRESENT")
  self.assertEqual(r["stages"][8]["status"],"SIMULATED_CANDIDATE")
  self.assertTrue(r["any_bypass"])
  self.assertFalse(r["handoff_allowed"])
 def test_individual_cp_can_be_on_under_off_stage(self):
  c=default();c["stage_overrides"]["PG-09"]="OFF"
  c["checkpoint_overrides"]["PG-09_C1"]="ON";r=run(c)
  rows=[x for x in r["checkpoints"] if x["stage"]=="PG-09"]
  self.assertEqual(rows[0]["status"],"SIMULATED_CANDIDATE")
  self.assertEqual(rows[1]["status"],"BYPASSED_DIAGNOSTIC")
 def test_fault_blocks_rest(self):
  c=default();c["checkpoint_overrides"]["PG-11_C3"]="FAULT";r=run(c)
  self.assertEqual(r["first_blocker"],"PG-11_C3")
  self.assertEqual(r["stages"][-1]["status"],"NOT_REACHED")
 def test_all_off_is_never_pass(self):
  c=default();c["defaults"]="OFF";r=run(c)
  self.assertTrue(r["any_bypass"])
  self.assertTrue(r["all_stages_reached"])
  self.assertFalse(r["checkpoint_closure_allowed"])
 def test_unknown_checkpoint_rejected(self):
  c=default();c["checkpoint_overrides"]["PG-99_C9"]="ON"
  with self.assertRaisesRegex(ValueError,"UNKNOWN_SWITCH"):run(c)
 def test_real_mode_forbidden(self):
  c=default();c["mode"]="REAL_GOVERNED"
  with self.assertRaisesRegex(ValueError,"SYNTHETIC_ONLY"):run(c)
 def test_faked_analysis_authority_forbidden(self):
  c=default();c["fixture"]["analysis_ready_authentic"]=True
  with self.assertRaisesRegex(ValueError,"AUTHORITY_FORBIDDEN"):run(c)
 def test_bypassed_stage_not_tested(self):
  c=default();c["stage_overrides"]["PG-14"]="OFF"
  rows=run_tests(c,"/tmp/does-not-exist")
  self.assertEqual(rows[-1]["reason"],"BYPASS_OR_FAULT_CONFIGURED")
  self.assertEqual(rows[-1]["source_suite_status"],"NOT_RUN")
 def test_trace_changes_by_switch(self):
  a=run(default());c=default();c["checkpoint_overrides"]["PG-07_C5"]="OFF";b=run(c)
  self.assertNotEqual(a["report_sha256"],b["report_sha256"])
  self.assertTrue(all(x["production_authority"] is False for x in b["checkpoints"]))
if __name__=="__main__":unittest.main()
