"""SALY B07 documentary authority + fail-closed official migration static admission.
No credential, auth, direct writer, or Supabase access used by tests.
"""
import json
import pathlib
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[3]
PACK=ROOT/"profiles/saly_product_director"
SQL=ROOT/"supabase/migrations/20261113190500_lf_ig_b07_saly_operation_owner_register_v1.sql"
EVIDENCE=ROOT/"docs/input-governance/b07_parent_child_candidate/10_owner_saly_decision_20261113.json"

class TestB07SalyRegistration(unittest.TestCase):
 def test_profile_pr_is_independent_and_native_gate_is_required(self):
  doc=(ROOT/"docs/input-governance/b07_parent_child_candidate/07_saly_operation_owner_governed_registration_plan.md").read_text(encoding="utf-8")
  self.assertIn("PR #3835",doc)
  self.assertIn("CREACION_PERFIL_LF",doc)
  self.assertIn("B07_SALY_PROFILE_NATIVE_CREATION_RECEIPT_REQUIRED",doc)
  self.assertNotIn("INSERT INTO public.lf_activos",doc)

 def test_literal_decision_is_not_verified_auth(self):
  d=json.loads(EVIDENCE.read_text(encoding="utf-8"))
  self.assertEqual(d["literal"],"Si me designo")
  self.assertEqual(d["owner_name"],"Cristhian Luján")
  self.assertEqual(d["proyecto"],"SALY")
  self.assertEqual(d["identity_mode"],"UNVERIFIED_CHAT_DECLARATION")
  self.assertFalse(d["identity_verified"])
  self.assertFalse(d["production_authorized"])

 def test_official_train_rejects_missing_profile_and_provenance(self):
  s=SQL.read_text(encoding="utf-8")
  self.assertEqual(s.count("\nBEGIN;\n"),1)
  self.assertEqual(s.count("\nCOMMIT;\n"),1)
  self.assertIn("B07_SALY_PROFILE_NATIVE_CREATION_RECEIPT_REQUIRED",s)
  self.assertIn("B07_SALY_EXACT_OFFICIAL_TRAIN_REQUIRED",s)
  self.assertIn("B07_SALY_OFFICIAL_BOOTSTRAP_FAILED",s)
  self.assertIn("B07_SALY_REGISTER_READBACK_FAILED",s)
  self.assertIn("public.fn_lf_operation_reserve_execution_v1",s)
  self.assertIn("operation_code='CREACION_PERFIL_LF'",s)
  self.assertIn("e.status='COMPLETED'",s)
  self.assertIn("a.created_by_execution_id=v_native_profile.execution_id",s)
  self.assertNotIn("INSERT INTO public.lf_activos",s)
  self.assertNotIn("CREATE FUNCTION",s)
  self.assertNotIn("CREATE OR REPLACE FUNCTION",s)
  self.assertIn("'CANDIDATO_READ_ONLY'",s)
  self.assertIn("false,false,'NO_WRITE'",s)
  self.assertIn("'PROPOSED'",s)
  self.assertIn("'UNVERIFIED_CHAT_DECLARATION'",s)
  self.assertNotIn("PERFIL-PRODUCT-DIRECTOR-LF",s)
  self.assertNotIn("public.lf_ig_asset_owner_apply_v2",s)
  print("PASS_B07_SALY_GOVERNED_REGISTRATION_CONTRACT_NO_LIVE_WRITERS")

if __name__=="__main__":
 unittest.main()
