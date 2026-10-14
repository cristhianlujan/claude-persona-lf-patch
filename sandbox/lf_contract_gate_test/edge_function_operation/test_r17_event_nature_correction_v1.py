"""R17 factual preflight contract must not use Skill artifact acceptance validation."""
from pathlib import Path
import re
import unittest

MIGRATIONS = Path(__file__).resolve().parents[3] / "supabase/migrations"
MATCHES = list(MIGRATIONS.glob("*_lf_ig_m105_r17_event_nature_correction_v1.sql"))
if len(MATCHES) != 1:
    raise RuntimeError("R17_NATURE_MIGRATION_MISSING_OR_AMBIGUOUS")
S = MATCHES[0].read_text()

def valid(text: str) -> bool:
    required=(
        "c_event_type constant text := 'RUNTIME_PREFLIGHT'",
        "private.fn_create_lf_event_type_contract_request_v2",
        "private.fn_approve_lf_event_type_contract_request_v2",
        "private.fn_apply_lf_event_type_contract_change_v2",
        "'contract_mode','OPERATIONAL'",
        "'allowed_evidence_schemas',jsonb_build_array('operational-event/v2')",
        "contract_version=2",
        "R17_NATURE_CORRECTION_PRESTATE_DRIFT",
        "a.write_allowed=false",
    )
    if any(s not in text for s in required):
        return False
    for forbidden in (
      r"\b(?:insert\s+into|update|delete\s+from)\s+private\.lf_event_type_contracts_v2",
      r"\b(?:insert\s+into|update|delete\s+from)\s+public\.lf_capability_current",
      r"\bupdate\s+public\.lf_router_action_registry",
      r"\b(?:insert\s+into|update|delete\s+from)\s+public\.lf_operation_effect_guard",
      r"\binsert\s+into\s+public\.lf_eventos\s*\([^)]*\)\s*values\s*\(\s*[\'\"]RUNTIME_PREFLIGHT",
    ):
        if re.search(forbidden,text,re.I|re.S):
            return False
    return True

class R17NatureTests(unittest.TestCase):
    def test_positive(self): self.assertTrue(valid(S))
    def test_forged_old_contract(self):
        self.assertFalse(valid(S.replace("'contract_mode','OPERATIONAL'","'contract_mode','VALIDATION_ACCEPTANCE'")))
    def test_uncorrected_skill_schema(self):
        self.assertFalse(valid(S.replace("'allowed_evidence_schemas',jsonb_build_array('operational-event/v2')",
                                           "'allowed_evidence_schemas',jsonb_build_array('test-evidence/v2')")))
    def test_direct_mutation(self):
        self.assertFalse(valid(S+"\nUPDATE public.lf_router_action_registry SET write_allowed=true;"))
    def test_cannot_persist_r17_receipt_in_schema_fix(self):
        self.assertFalse(valid(S+"\nINSERT INTO public.lf_eventos(evento_tipo) VALUES('RUNTIME_PREFLIGHT');"))

if __name__=="__main__":
    unittest.main()
