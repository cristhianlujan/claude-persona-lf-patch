#!/usr/bin/env python3
"""PR-I: exact patch/delta and NO false V2 evidence or migration claims."""
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
DOC=ROOT/"docs/input-governance/PR_I_AUTH020_SOURCE_BOUND_PATCH_20261118.json"
HARNESS=ROOT/"sandbox/lf_contract_gate_test/input_governance/pr_i_auth020_projection_rollback.sql"
RUNNER=ROOT/"sandbox/lf_contract_gate_test/input_governance/run_pr_i_auth020_projection_pg17_v1.py"
EXPECTED_REMOVED={
    "hold_hours","human_approval_count_required",
    "current_authorized_recovery_profile_ids"
}
REQUIRED_FLAGS={
    "temporary_key_one_time_use":True,
    "temporary_key_reissue_invalidates_prior":True,
    "temporary_key_expiry_requires_new_identity_check":True,
    "new_password_required_before_operational_session":True,
    "change_email_after_new_password":True,
    "recovery_completion_atomic":True,
    "temporary_key_may_create_authenticated_session":False,
    "production_authorized":False,
}
class PRISource(unittest.TestCase):
 def setUp(self):
  self.d=json.loads(DOC.read_text())
  self.p=self.d["governed_rule_patch"]
 def test_auth020_only_source_and_no_legacy_controls(self):
  self.assertEqual(self.d["status"],"DRAFT_NOT_REGISTERED_NO_AUTH020_DB_WRITE")
  self.assertEqual(self.d["source"]["rule_id"],439)
  self.assertEqual(self.d["source"]["rule_code"],"B2B-RULE-AUTH-020")
  self.assertEqual(self.p["change_kind"],"FUNCTIONAL")
  vals=self.p["changes"]["valor_config"]
  self.assertEqual(len(self.d["source_full_row_for_isolated_pg17_fixture"]["valor_config"]),50)
  self.assertEqual(len(vals),65)
  self.assertTrue(EXPECTED_REMOVED.isdisjoint(vals.keys()))
  self.assertEqual(set(self.d["delta"]["value_config_removed_keys"]),EXPECTED_REMOVED)
  for key,value in REQUIRED_FLAGS.items():self.assertEqual(vals[key],value)
  self.assertEqual(vals["temporary_key_ttl_config_ref"],"AUTH/TEMP_KEY_TTL_HOURS")
  self.assertEqual(vals["recovery_operator_permission_id"],38)
  self.assertNotIn("48 horas",self.p["changes"]["descripcion"])
  self.assertEqual(self.d["patch_sha256"],
   "adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02")
  self.assertEqual(self.d["candidate_snapshot_sha256"],
   "16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061")
 def test_policy20_only_candidate_and_provenance_update_required(self):
  p=self.d["policy20_candidate_proposal"]
  self.assertEqual(p["expected_status"],"CANDIDATO")
  self.assertEqual(p["expected_source_md5"],"97dbf5ff2e9da91da0ab33d6a837d4c2")
  self.assertEqual(p["policy_code"],"SEC-B2B-MFA-RECOVERY")
  self.assertFalse(p["applied"])
  self.assertEqual(len(p["changed_policy_config_keys"]),20)
  self.assertNotIn("current_authorized_recovery_profile_ids",
    p["proposed_policy_config"])
  self.assertEqual(p["proposed_policy_config"]["temporary_key_ttl_config_ref"],
    "AUTH/TEMP_KEY_TTL_HOURS")
  self.assertEqual(self.d["ttl_readback"]["value_type"],"INTEGER")
  self.assertEqual(self.d["ttl_readback"]["value_status"],"REAL")
 def test_admissibility_fail_closed_no_fabrication(self):
  pr=self.d["prerequisites"]
  for name in ("owner_decision_id","functional_evidence_row","train_run_id","train_event_id"):
   self.assertTrue(pr[name] in ("NOT_CREATED","ABSENT","NOT_ASSIGNED"))
  for name in ("pg_rollback_status","functional_checks_status","negative_checks_status"):
   self.assertEqual(pr[name],"NOT_TESTED_FOR_REAL_LOGIN_RUNTIME")
  self.assertEqual(pr["permission_38_effective"],"NO_VIGENTE_ASSIGNMENT")
  h=HARNESS.read_text()
  self.assertEqual(h.splitlines().count("BEGIN;"),1)
  self.assertEqual(h.splitlines().count("ROLLBACK;"),1)
  self.assertEqual(h.splitlines().count("COMMIT;"),0)
  self.assertNotIn("INSERT INTO public.lf_ig_owner_decision_v2",h)
  self.assertNotIn("INSERT INTO public.lf_ig_rule_change_v2",h)
 def test_runner_explicitly_disclaims_runtime_and_requires_local_pg(self):
  r=RUNNER.read_text()
  for token in ("PASS_CONFIG_ONLY","actual_login_runtime_functional_checks",
                "NOT_TESTED","is_pr_h_functional_evidence","PR_I_EXACT_HEAD",
                "PR_I_EPHEMERAL_PG_GUARD","remote_db_writes"):
   self.assertIn(token,r)
  for name in ("PR_I_BASELINE_PASS","PR_I_CONFIG_PROJECTION_PASS",
               "PR_I_REAL_POST_ROLLBACK_PASS"):
   self.assertIn(name,HARNESS.read_text())

if __name__=="__main__":
 result=unittest.TextTestRunner(verbosity=2).run(
    unittest.defaultTestLoader.loadTestsFromTestCase(PRISource))
 if result.wasSuccessful():print("PR_I_AUTH020_STATIC_PASS 4/4")
 raise SystemExit(0 if result.wasSuccessful() else 1)
