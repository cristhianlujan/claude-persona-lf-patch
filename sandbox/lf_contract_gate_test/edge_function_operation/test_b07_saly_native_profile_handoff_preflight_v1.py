"""B07 SALY create-profile native request gate audit. Pure source/JSON checks only."""
import json, pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[3]
PACK=ROOT/"profiles/saly_product_director"
DOC=ROOT/"docs/input-governance/b07_parent_child_candidate"
WORKFLOW=ROOT/".github/workflows/lf-customer-profile-creator-governance-caller.yml"
CALLER=ROOT/"supabase/functions/lf-profile-creator-governance-caller-v1/index.ts"
RUNTIME=ROOT/"supabase/functions/run-creacion-perfil-lf/index.ts"
GATE2=ROOT/"sandbox/lf_contract_gate_test/profile_execution_runtime/lf_profile_begin_payload.py"

class SalyNativeProfilePreflight(unittest.TestCase):
 def test_owner_and_profile_are_separate_and_non_productive(self):
  m=json.loads((PACK/"manifest.json").read_text())
  self.assertEqual(m["profile_pack_id"],"PERFIL-PRODUCT-DIRECTOR-SALY")
  self.assertEqual(m["operation"],"CREACION_PERFIL_LF")
  self.assertFalse(m["identity_verified"])
  self.assertFalse(m["production_authorized"])
  self.assertEqual(m["operational_status"],"READ_ONLY")
  self.assertEqual(m["runtime"],"NO_HABILITADO")
  self.assertEqual(m["automatic_impact"],"BLOQUEADO")
  self.assertNotIn("PERFIL-PRODUCT-DIRECTOR-LF",(PACK/"manifest.json").read_text())
  for f in m["required_files"]: self.assertTrue((PACK/f).exists(),f)
 def test_frozen_request_is_not_submittable(self):
  j=json.loads((DOC/"13_saly_native_request_pending_gate2_v1.json").read_text())
  self.assertEqual(j["schema_version"],"LF_B07_SALY_PROFILE_CREATION_REQUEST_DRAFT_V1")
  self.assertIsNone(j["executor_request_template"]["router_context"])
  self.assertIsNone(j["creator_caller_template"]["caller_request_id"])
  self.assertFalse(j["live_request_sent"])
  self.assertFalse(j["identity_verified"])
  self.assertFalse(j["production_authorized"])
  self.assertEqual(j["target_code"],"PERFIL-PRODUCT-DIRECTOR-SALY")
  self.assertEqual(j["original_owner_decision_literal"],"Si me designo")
  self.assertTrue(all(v is False for v in j["preconditions"].values()))
 def test_hard_authority_boundary_visible_and_unaltered(self):
  caller=CALLER.read_text()
  workflow=WORKFLOW.read_text()
  runtime=RUNTIME.read_text()
  begin=GATE2.read_text()
  self.assertIn("CUSTOMER_PROFILE_TARGET_NOT_ALLOWED",caller)
  self.assertIn('const TARGETS: Record<string, string>',caller)
  self.assertNotIn('"PERFIL-PRODUCT-DIRECTOR-SALY": "saly_product_director"',caller)
  # Real gate: preserve true ONLY for the old Customer cases and deny SALY.
  self.assertIn('const salyTarget = targetCode === "PERFIL-PRODUCT-DIRECTOR-SALY"',runtime)
  self.assertIn('production_authorized: !salyTarget',runtime)
  self.assertIn('customer_profile_scope: !salyTarget',runtime)
  self.assertIn('body.production_authorized !== false',runtime)
  self.assertIn('if (!salyTarget && caller.method !== CUSTOMER_CALLER_METHOD)',runtime)
  self.assertIn('lf-profile-update-governed',workflow)
  self.assertIn("PROFILE_NATIVE_BEGIN_GATE2_INVALID",begin)
  self.assertIn("s.get('negocio_codigo') != 'LF'",begin)
  doc=(DOC/"12_saly_native_profile_creation_route_v1.md").read_text()
  self.assertIn("CREACION_PERFIL_LF",doc)
  self.assertIn("lf-profile-resume-governed",doc)
  self.assertIn("B. Crear materialmente",doc)
  print("PASS_B07_SALY_NATIVE_PROFILE_CREATION_DRAFT_FAIL_CLOSED")

if __name__=="__main__": unittest.main()
