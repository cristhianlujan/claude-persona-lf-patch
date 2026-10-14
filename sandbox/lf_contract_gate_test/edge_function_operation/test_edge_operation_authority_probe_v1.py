"""Authority probe contract tests; fake readers contain no real credentials."""
import unittest
from edge_operation_authority_probe_v1 import (
    ACTION, OPERATION, STEP_IDS, AuthorityUnavailable, build_live_reader, diagnose
)

TARGET="lf-profiles-governance-caller-v1"

def records():
    steps=sorted(STEP_IDS)
    return {
        "lf_operation_registry":[{"operation_code":OPERATION,"status":"CANDIDATO_READ_ONLY","lifecycle_state_code":"OP_CANDIDATE"}],
        "lf_router_action_registry":[{"operation_code":OPERATION,"status":"CANDIDATO_READ_ONLY","write_allowed":False}],
        "lf_operation_contracts":[{"allowed":{"runtime_effect_enabled":False}}],
        "lf_operation_steps":[{"step_id":x} for x in steps],
        "lf_operation_step_contracts":[{"step_id":x} for x in steps],
        "lf_operation_judges":[{"judge_code":"J"+str(i)} for i in range(8)],
        "lf_operation_step_judge_bindings":[{"step_id":x} for x in steps],
        "lf_eventos":[],
        "lf_operation_execution":[],
    }

def call(data=None,target=TARGET):
    source=data or records()
    def read(table,params):
        assert table in source,table
        return source[table]
    return diagnose(read,target)

class EdgeAuthorityProbeTests(unittest.TestCase):
    def test_realistic_candidate_has_exact_blockers(self):
        result=call()
        self.assertEqual(result["step_count"],8)
        self.assertEqual(result["step_contract_count"],8)
        self.assertEqual(result["judge_count"],8)
        self.assertEqual(result["binding_count"],8)
        self.assertFalse(result["can_deploy"])
        self.assertFalse(result["effect_executed"])
        self.assertIn("OPERATION_NOT_OPERATIONAL",result["blockers"])
        self.assertIn("R17_CANONICAL_EVENT_MISSING",result["blockers"])
        self.assertIn("SIGNED_RUNTIME_AUTHORITY_UNVERIFIED",result["blockers"])
    def test_pretend_active_still_fails_closed(self):
        a=records()
        a["lf_operation_registry"][0].update(status="ACTIVE",lifecycle_state_code="OP_OPERATIONAL")
        a["lf_router_action_registry"][0].update(status="ACTIVE",write_allowed=True)
        a["lf_operation_contracts"][0]["allowed"]["runtime_effect_enabled"]=True
        a["lf_operation_execution"]=[{"execution_id":"E-1","target_code":TARGET}]
        a["lf_eventos"]=[{"id":123,"entidad_codigo":TARGET}]
        r=call(a)
        self.assertFalse(r["can_deploy"])
        self.assertIn("R17_CANONICAL_ATTESTATION_UNVERIFIED",r["blockers"])
        self.assertIn("EDGE_MANAGEMENT_CREDENTIAL_UNVERIFIED",r["blockers"])
    def test_missing_a_step_binding_detected(self):
        a=records()
        a["lf_operation_step_judge_bindings"].pop()
        self.assertIn("STEP_AUTHORITY_BINDINGS_INCOMPLETE",call(a)["blockers"])
    def test_duplicate_judge_not_eight(self):
        a=records()
        a["lf_operation_judges"][2]["judge_code"]=a["lf_operation_judges"][1]["judge_code"]
        self.assertIn("STEP_AUTHORITY_BINDINGS_INCOMPLETE",call(a)["blockers"])
    def test_invalid_target_rejected(self):
        with self.assertRaisesRegex(AuthorityUnavailable,"TARGET_SLUG_INVALID"):
            call(target="../../other")
    def test_credentials_not_optional(self):
        with self.assertRaisesRegex(AuthorityUnavailable,"AUTHORITY_READ_CREDENTIAL_MISSING"):
            build_live_reader("https://mhwmirqcgxxukpctffuv.supabase.co","")
    def test_wrong_authority_domain_rejected(self):
        with self.assertRaisesRegex(AuthorityUnavailable,"AUTHORITY_URL_NOT_TRUSTED"):
            build_live_reader("https://evil.example.com","token")
    def test_insecure_authority_url_rejected(self):
        with self.assertRaisesRegex(AuthorityUnavailable,"AUTHORITY_URL_NOT_TRUSTED"):
            build_live_reader("http://mhwmirqcgxxukpctffuv.supabase.co","token")
    def test_never_reports_effect_executed(self):
        for test in (records(),):
            r=call(test)
            self.assertIs(r["effect_executed"],False)
            self.assertIs(r["can_deploy"],False)

if __name__=="__main__":
    unittest.main()
