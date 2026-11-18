#!/usr/bin/env python3
"""PR-H source bounds, old gates unaffected, retimestamp-proof migration."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
MIG_GLOB="*_lf_ig_functional_train_impact_gate_pr_h_v1.sql"
HARNESS=ROOT/"sandbox/lf_contract_gate_test/input_governance/pr_h_functional_train_rollback.sql"
RUNNER=ROOT/"sandbox/lf_contract_gate_test/input_governance/run_pr_h_functional_train_pg17_v1.py"
class PRH(unittest.TestCase):
 def migration(self):
  paths=list((ROOT/"supabase/migrations").glob(MIG_GLOB))
  self.assertEqual(len(paths),1)
  return paths[0].read_text()
 def test_finalizer_only_three_literal_replacements(self):
  s=self.migration()
  self.assertIn("9d1a771fe5dd8b466b76071b582f19fa",s)
  self.assertIn("df1acd69a46b8bc4a6c257d95cc9a47a",s)
  self.assertEqual(s.count("PR_H_FINALIZER_REPLACEMENT_COUNT_"),3)
  for key in ("LF_IG_VIGENTE_FUNCTIONAL_TRAIN_EVIDENCE_MISSING",
              "LF_IG_VIGENTE_FUNCTIONAL_TRAIN_RUN_UNVERIFIED",
              "LF_IG_VIGENTE_FUNCTIONAL_CANDIDATE_HASH_DRIFT",
              "LF_IG_VIGENTE_CHANGE_KIND_INVALID",
              "pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'"):
   self.assertIn(key,s)
 def test_only_new_technical_evidence_storage(self):
  s=self.migration()
  self.assertEqual(s.count("CREATE TABLE public.lf_ig_functional_train_evidence_v1"),1)
  for key in ("FORCE ROW LEVEL SECURITY","ENABLE ROW LEVEL SECURITY",
              "train_event_id bigint NOT NULL REFERENCES public.lf_eventos(id)",
              "pg_rollback_status='PASS'",
              "independent_readback_status='PASS'",
              "functional_checks_status='PASS'",
              "negative_checks_status='PASS'",
              "PRIMARY KEY (rule_code,source_snapshot_sha256,proposal_sha256)"):
   self.assertIn(key,s)
  for forbidden in ("UPDATE lf_ops.reglas","INSERT INTO lf_ops.reglas",
                    "ALTER TABLE public.lf_ig_rule_change_v2",
                    "ALTER TABLE public.lf_ig_owner_decision_v2",
                    "UPDATE public.lf_ig_owner_decision_v2",
                    "DROP FUNCTION", "COMMIT;"):
   self.assertNotIn(forbidden,s)
 def test_rollback_trials_and_negative_controls(self):
  s=HARNESS.read_text()
  self.assertEqual(s.splitlines().count("BEGIN;"),1)
  self.assertEqual(s.splitlines().count("ROLLBACK;"),1)
  self.assertEqual(s.splitlines().count("COMMIT;"),0)
  for key in ("PR_H_FOREIGN_USER_REJECTED_PASS",
              "PR_H_MISSING_CANDIDATE_HASH_REJECTED_PASS",
              "PR_H_MISSING_EVIDENCE_ACCEPTED",
              "PR_H_INVALID_TRAIN_RUN_ACCEPTED",
              "PR_H_WRONG_CANDIDATE_ACCEPTED",
              "PR_H_VALID_FUNCTIONAL_NOT_COMPLETED",
              "PR_H_POST_ROLLBACK_PASS"):
   self.assertIn(key,s)
 def test_runner_fail_closed_real_pg17(self):
  s=RUNNER.read_text()
  for key in ("PR_H_EXACT_HEAD","REAL_POSTGRESQL_17","readback",
              "PRH_RESTORED_0_0_3_ORIGINAL_MD5",
              "remote_supabase_written", "test_fixture_not_real_owner_or_train_receipt"):
   self.assertIn(key,s)
if __name__=="__main__":
 test=unittest.defaultTestLoader.loadTestsFromTestCase(PRH)
 r=unittest.TextTestRunner(verbosity=2).run(test)
 if r.wasSuccessful():print("PR_H_FUNCTIONAL_TRAIN_STATIC_PASS 4/4")
 raise SystemExit(0 if r.wasSuccessful() else 1)
