"""Source-level regression for PE10 v0.2 governed staging (NOT DB admission).

Use the actual repository bytes. For material SQL execution, use a disposable
PostgreSQL instance with the real provenance/sha triggers and ROLLBACK.
"""
import hashlib
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
STAGING = ROOT / "skills/profile_creator/contracts/profile_update_v02_governed_stage_rollback_candidate_v1.sql"
JUDGE = ROOT / "skills/profile_creator/contracts/profile_update_evolution_step_guard_candidate_v1.sql"
EXPECTED_OPERATION = "ACTUALIZACION_PERFIL_LF"
EXPECTED_PR = "2619"


class StageCandidate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = STAGING.read_text(encoding="utf-8")
        cls.digest = hashlib.sha256(JUDGE.read_bytes()).hexdigest()

    def test_exact_judge_source_digest(self):
        self.assertRegex(self.digest, r"^[a-f0-9]{64}$")
        # Two candidates share the SAME step-dispatch guard source; both must
        # bind to its raw exact bytes, not to the Git blob SHA-1.
        self.assertEqual(self.sql.count(f"'{self.digest}'"), 3)
        self.assertEqual(
            self.sql.count(
                "'skills/profile_creator/contracts/profile_update_evolution_step_guard_candidate_v1.sql',"
            ),
            2,
        )

    def test_actor_is_bound_to_scoped_execution_not_any_historical_run(self):
        for field in (
            "operation_code=v_op",
            "status='IN_PROGRESS'",
            "manifest->>'governance_scope'='PE10_V02_GOVERNED_REGISTRATION'",
            "manifest->>'governance_target'=v_op",
            f"manifest->>'governance_pr'='{EXPECTED_PR}'",
        ):
            self.assertIn(field, self.sql)
        self.assertIn("PE10_V02_GOVERNED_ACTOR_REQUIRED", self.sql)
        self.assertIn("current_setting('lf.pe10_governed_actor_execution_id',true)", self.sql)

    def test_super_admin_authority_is_distinct_from_execution_provenance(self):
        # Named owner is a governance role, never proof from a caller string.
        for field in (
            "'governance_owner_role','SUPER_ADMIN'",
            "'governance_authority_domain','LF_GOVERNANCE'",
            "'governance_reviewer_role','SUPER_ADMIN_GOVERNANCE'",
            "'governance_authority_ref','contract://LF_GOVERNANCE_SUPER_ADMIN_V1'",
            "'governance_authority_receipt_state','PENDING_VERIFIED_RECEIPT'",
            "'proposed_operation_version','v0.2','activation_authorized',false",
        ):
            self.assertIn(field, self.sql)
        self.assertIn("created_by_execution_id is technical provenance", self.sql)
        self.assertIn("Do not use the product B2B_ADMIN_LF", self.sql)

    def test_no_activation_or_durable_migration(self):
        self.assertEqual(len(re.findall(r"\bBEGIN;", self.sql)), 1)
        self.assertEqual(len(re.findall(r"\bROLLBACK;", self.sql)), 1)
        self.assertNotRegex(self.sql, r"\bCOMMIT\s*;")
        self.assertNotRegex(self.sql, r"(?i)\bUPDATE\s+public\.lf_operation_registry\b")
        self.assertIn("true,false", self.sql)
        self.assertIn("'CANDIDATO_READ_ONLY'", self.sql)
        self.assertIn("'CANDIDATE'", self.sql)
        self.assertIn("'v1.4-evolved-routing-candidate'", self.sql)

    def test_governed_foreign_keys_and_evidence_sha(self):
        for table in (
            "public.lf_operation_steps",
            "public.lf_operation_judges",
            "public.lf_operation_step_contracts",
            "public.lf_operation_step_judge_bindings",
            "public.lf_policy_versions",
        ):
            self.assertIn(f"INSERT INTO {table}", self.sql)
        self.assertIn("extensions.digest(convert_to(v_policy::text,'UTF8'),'sha256')", self.sql)
        self.assertIn("PE10_V02_STAGE_READBACK_FAILED", self.sql)
        self.assertIn("PE10_V02_STAGE_READONLY_HELPERS_NOT_INSTALLED", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
