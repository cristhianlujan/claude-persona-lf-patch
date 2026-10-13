"""Static source-admission checks only; NOT a Supabase rollback test.

Live admission additionally needs BEGIN/ROLLBACK against current DB, exact
merged-source Train ledger parity, runtime parity, and checkpoint readback.
"""
from pathlib import Path
import re
import unittest

SQL = Path(__file__).resolve().parents[4] / "supabase/migrations/20261013170000_ig_m102_engineering_gate_alignment_v1.sql"
CODES = (
    "BINDING_ASIS", "REUSE_CAPABILITY_CUTOVER", "SWITCH_ONLY_MIGRATION",
    "RUNTIME_PREFLIGHT", "NEG_REVERSE", "SWITCH_READBACK",
)
PROTECTED = re.compile(
    r"\b(?:UPDATE|INSERT\s+INTO|DELETE\s+FROM|TRUNCATE)\s+"
    r"(?:public\.lf_capability_(?:current|version_registry|binding)"
    r"|programacion\.(?:human_decisions|promotions))\b",
    re.IGNORECASE,
)

class M102Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = SQL.read_text(encoding="utf-8")

    def test_no_unsafe_mutation_and_no_fake_pass(self):
        self.assertIsNone(PROTECTED.search(self.sql))
        for forbidden in ("PERFORM public.fn_lf_capability_promote_v1",
                          "INSERT INTO programacion.engineering_work_checkpoints",
                          "UPDATE programacion.engineering_work_checkpoints SET status",
                          "UPDATE public.lf_capability_current SET"):
            self.assertNotIn(forbidden, self.sql)
        self.assertIn("'activation_performed',false", self.sql)
        self.assertIn("'no_checkpoint_transitions',true", self.sql)
        self.assertIn("BLOCK_GENUINE_ASSERTION_UNTIL_EXECUTED", self.sql)

    def test_prestate_binding_and_provenance(self):
        for expected in (
            "M102_PREFLIGHT_UNIT_PRESTATE_DRIFT",
            "M102_PREFLIGHT_WORK_OR_CHECKPOINT_DRIFT",
            "M102_PREFLIGHT_CURRENT_OR_CANDIDATE_DRIFT",
            "M102_PREFLIGHT_REUSE_EVIDENCE_MISSING",
            "M102_POSTSTATE_FAIL_CLOSED",
            "v_registered<>1",
            "v_m92_done<>6 OR v_m100_done<>7",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, self.sql)

    def test_all_checkpoint_contracts_and_real_sourcepack(self):
        for cp in CODES:
            with self.subTest(cp=cp):
                self.assertIn("'{" + cp + "}'", self.sql)
                self.assertIn("'{checkpoint_inputs," + cp, self.sql)
        self.assertIn("'schema_version','ENGINEERING_ACTION_SPEC_V3'", self.sql)
        self.assertIn("'action_kind','READBACK_ONCE'", self.sql)
        self.assertIn("'verification_queries'", self.sql)
        self.assertIn("'{checkpoint_inputs,BINDING_ASIS,missing_typed}'", self.sql)

    def test_semantic_phase_separation(self):
        for expected in (
            "'phase','CONSTRUCTION_SANDBOX'",
            "'candidate_status','ABSENT_NOT_FABRICATED'",
            "'operational_gate','BLOCKED_PENDING_REGISTERED_CANDIDATE_AND_GOVERNED_AUTHORITY'",
            "'product_owner','NONE_TRANSVERSAL'",
            "public.fn_lf_capability_promote_v1",
            "M9.2:SWITCH_REVERT_SANDBOX",
            "BLOCK_REGISTERED_CANDIDATE_AND_AUTHORITY_REQUIRED",
            "BLOCK_DEPLOYED_EDGE_SOURCE_PARITY_UNVERIFIED",
            "'runtime_activation','FORBIDDEN_IN_CONSTRUCTION_SANDBOX'",
            "'db_targets_exact',jsonb_build_array('public.lf_capability_current')",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, self.sql)

    def test_negative_mutant_rejected(self):
        mutant = self.sql + "\nUPDATE public.lf_capability_current SET version='1.0.1';"
        self.assertIsNotNone(PROTECTED.search(mutant))
        self.assertIsNone(PROTECTED.search(self.sql))

if __name__ == "__main__":
    unittest.main()
