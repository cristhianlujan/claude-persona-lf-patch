import json, pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[3]
FILE=ROOT/"audits/login-policy19-act0001/01_positive_negative_scope_v1.json"
EXPECTED=("admin_minimum_strength","admin_phishing_resistant_requirement",
"phishing_resistant_option_required","admin_primary_method","admin_identity_provider",
"admin_sso_protocol","admin_provider_configuration_status","factor_selection_status")
class TestPolicy19ACT0001Design(unittest.TestCase):
    def test_positive_negative_contract_is_narrow_and_route_only(self):
        p=json.loads(FILE.read_text(encoding="utf-8"))
        self.assertEqual(p["status"],"DESIGN_ONLY_NO_AUTHORITY_RECEIPT")
        self.assertEqual(p["router"],"ACT-0001")
        self.assertEqual(p["operation_code"],"ACTUALIZACION_DB_LF")
        self.assertFalse(p["effect_authority"])
        self.assertFalse(p["downstream_execution_allowed"])
        self.assertEqual(p["allowed"]["table"],"lf_ops.politicas_seguridad")
        self.assertEqual(p["allowed"]["predicate"]["security_policy_id"],19)
        self.assertEqual(p["allowed"]["predicate"]["status"],"CANDIDATO")
        self.assertEqual(set(p["allowed"]["columns"]),{"description","policy_config","parameter_provenance","updated_at"})
        self.assertEqual(set(p["allowed"]["policy_config_changed_keys"]),set(EXPECTED))
        self.assertEqual(set(p["allowed"]["provenance_changed_keys"]),set(EXPECTED))
        self.assertEqual(p["denied"]["all_other_policy_config_keys"],"DENY")
        self.assertIn("status",p["denied"]["columns"])
        self.assertEqual(p["receipt_contract"]["persistence"],"public.lf_router_scope_receipt_v1")
        self.assertFalse(p["receipt_contract"]["effect_authority"])
        self.assertEqual(p["receipt_contract"]["issuer_existing"],"public.lf_router_scope_bind_v1(text)")
        self.assertEqual(p["receipt_contract"]["consumer_existing"],"public.lf_router_scope_receipt_consume_v2(text,text)")
        print("PASS_POLICY19_SCOPE_DESIGN_ONLY_ALLOW_DENY_EXACT_NO_FAKE_RECEIPT",flush=True)
