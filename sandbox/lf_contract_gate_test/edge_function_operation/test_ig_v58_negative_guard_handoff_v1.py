"""IG V58 negative-path contract: block RUN, never fabricate a family validation receipt.
Source: 2026-11-14 14:43:35/50 UTC PostgreSQL P0001.
"""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[3]
PATH=ROOT/"supabase/migrations/20261114145300_lf_ig_v58_validator_negative_guard_handoff_v1.sql"
SQL=PATH.read_text(encoding="utf-8")
PREIMAGES={
    "fn_input_governance_validate_v2":"540e43926d2a644ccfb60fdfed2b575f",
    "fn_input_governance_validator_rebind_v1":"99e0ab88b423d340a14ae2130130a925",
}
FUNCTIONS=tuple(PREIMAGES)

class V58NegativeHandoff(unittest.TestCase):
    def test_exact_live_source_guard_and_no_bypass(self):
        self.assertIn("BEGIN;",SQL)
        self.assertTrue(SQL.strip().endswith("COMMIT;"))
        for name,md5 in PREIMAGES.items():
            self.assertIn("SOURCE_STATE_DRIFT:"+name,SQL)
            self.assertIn(md5,SQL)
        self.assertIn("trg_input_family_assessment_00_execution_update",SQL)
        self.assertNotIn("DISABLE TRIGGER",SQL.upper())
        self.assertNotIn("ALTER TABLE",SQL.upper())
        self.assertNotIn("DROP TRIGGER",SQL.upper())
        self.assertNotIn("SET ROLE",SQL.upper())
    def test_both_validator_paths_preserve_negative_durable_run(self):
        for name in FUNCTIONS:
            pat=r"CREATE OR REPLACE FUNCTION programacion\."+name+r"\("
            m=re.search(pat,SQL)
            self.assertIsNotNone(m)
            part=SQL[m.start():]
            start=part.index("IF EXISTS(\n       SELECT 1 FROM jsonb_array_elements(v_assertions)")
            stop=part.index("RETURN jsonb_build_object(",start)
            neg=part[start:stop]
            self.assertIn("j.x->>'result'='NEEDS_RECURATION'",neg)
            self.assertNotIn("UPDATE programacion.input_family_assessments",neg)
            self.assertNotIn("SET validator_outcome='BLOCKED'",neg)
            self.assertIn("validator_outcome='PENDING'",neg)
            self.assertIn("blocked_reason='V58_PARENT_ASSERTION_STALE_REQUIRES_CURATOR:'||a.family_code",neg)
            self.assertIn("SET status='BLOCKED'",neg)
            self.assertIn("V58_NEGATIVE_PENDING_FAMILY_DRIFT",neg)
            receipt=part[stop:stop+750]
            self.assertIn("'status','CURATOR_REEVALUATION_REQUIRED'",receipt)
            self.assertIn("'promotion_authorized',false",receipt)
            self.assertIn("'production_authorized',false",receipt)
    def test_no_unapproved_promotion_or_prod_effect(self):
        self.assertNotIn("UPDATE lf_ops.reglas",SQL)
        self.assertNotIn("SET estado='VIGENTE'",SQL)
        self.assertNotIn("SET status='COMPLETED'\n       WHERE id=p_run_id AND status='VALIDATING';",SQL)

if __name__=="__main__":
    unittest.main()
