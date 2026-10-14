"""Static guards for the R17 exact event-type registration, no runtime effect."""
import pathlib
import re
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[4]
M=ROOT/"supabase/migrations/20261014062500_lf_ig_m105_r17_event_type_governed_v1.sql"

def check_migration(s:str)->bool:
    required=(
        "c_event_type constant text := 'RUNTIME_PREFLIGHT'",
        "c_actor constant text",
        "'contract_mode','VALIDATION_ACCEPTANCE'",
        "'allowed_evidence_schemas',jsonb_build_array('test-evidence/v2')",
        "fn_create_lf_event_type_contract_request_v2",
        "EVENT_TYPE_CONTRACT_CHANGE_APPROVED",
        "fn_approve_lf_event_type_contract_request_v2",
        "fn_apply_lf_event_type_contract_change_v2",
        "v_lf_event_type_contract_audit_v2",
        "R17_EVENT_TYPE_REGISTRATION_READBACK_FAILED",
        "route.write_allowed=false",
    )
    if any(x not in s for x in required):
        return False
    forbidden=(
        re.compile(r"\b(?:insert\s+into|update|delete\s+from)\s+private\.lf_event_type_contracts_v2\b",re.I),
        re.compile(r"\b(?:update|delete\s+from)\s+public\.lf_router_action_registry\b",re.I),
        re.compile(r"\b(?:insert\s+into|update|delete\s+from)\s+public\.lf_capability_current\b",re.I),
        re.compile(r"\b(?:insert\s+into|update|delete\s+from)\s+public\.lf_operation_effect_guard\b",re.I),
        re.compile(r"\bsupabase\s+functions\s+deploy\b",re.I),
        re.compile(r"['\"]RUNTIME_PREFLIGHT['\"]\s*,\s*['\"]EXECUTION['\"]",re.I),
    )
    return not any(p.search(s) for p in forbidden)

class R17EventTypeGovernanceTests(unittest.TestCase):
    def test_exact_authority_and_no_effect(self):
        self.assertTrue(check_migration(M.read_text()))
    def test_no_direct_contract_insertion(self):
        s=M.read_text()+ "\nINSERT INTO private.lf_event_type_contracts_v2 VALUES (...);"
        self.assertFalse(check_migration(s))
    def test_no_route_activation(self):
        s=M.read_text()+ "\nUPDATE public.lf_router_action_registry SET write_allowed=true;"
        self.assertFalse(check_migration(s))
    def test_cannot_change_validation_contract_to_operational(self):
        s=M.read_text().replace("'contract_mode','VALIDATION_ACCEPTANCE'","'contract_mode','OPERATIONAL'")
        self.assertFalse(check_migration(s))
    def test_no_event_writer_as_preflight_pass(self):
        s=M.read_text()+"\nINSERT INTO public.lf_eventos VALUES('RUNTIME_PREFLIGHT','EXECUTION');"
        self.assertFalse(check_migration(s))
    def test_no_capability_release(self):
        s=M.read_text()+"\nUPDATE public.lf_capability_current SET version='1.0.1';"
        self.assertFalse(check_migration(s))

if __name__=="__main__":
    unittest.main()
