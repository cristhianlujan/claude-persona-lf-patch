"""Static fail-closed checks for DRAFT B09 official writer; NOT a PG or E2E PASS."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
MIG=(ROOT/"supabase/migrations/20261113235500_lf_b09_official_oidc_nonce_writer_v1.sql").read_text(encoding="utf-8")
DOWN=(ROOT/"sandbox/lf_contract_gate_test/input_governance_lifecycle/rollback_lf_b09_official_oidc_nonce_writer_v1.sql").read_text(encoding="utf-8")
EDGE=(ROOT/"supabase/functions/lf-profiles-governance-caller-v1/profile_continuation.ts").read_text(encoding="utf-8")
CALLER=(ROOT/"supabase/functions/lf-profiles-governance-caller-v1/caller.ts").read_text(encoding="utf-8")
RUNNER=(ROOT/"scripts/lf_profile_native_resume.py").read_text(encoding="utf-8")

class B09OfficialNonceDocumentaryCandidate(unittest.TestCase):
    def test_authority_existing_canonical_only(self):
        self.assertIn("CREATE OR REPLACE FUNCTION public.lf_record_profile_execution_step_v1(",MIG)
        self.assertIn("public.lf_record_operation_step_core_v1(",MIG)
        self.assertIn("lf_profile_execution_trust_validation_v2(",MIG)
        self.assertIn("'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT'",MIG)
        self.assertNotIn("CREATE FUNCTION public.lf_ig_native_chat_receipt_register",MIG)
        self.assertNotIn("CREATE OR REPLACE FUNCTION public.lf_ig_native_chat_receipt_register",MIG)
        self.assertNotIn("GRANT INSERT",MIG)
        self.assertNotIn('rest/v1/lf_ig_native_chat_receipt_v1',EDGE)
        self.assertIn('"lf_record_profile_execution_step_v1"',EDGE)

    def test_oidc_identity_is_not_user_supplied(self):
        self.assertIn("GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1",MIG)
        self.assertIn("GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1",EDGE)
        self.assertIn("PROFILE_B09_WRITER_ACTION",EDGE)
        self.assertIn("PROFILE_CONTINUATION_ACTIONS",CALLER)
        self.assertIn("callerIdentity.run_id",EDGE)
        self.assertIn("_verified_oidc: callerIdentity",EDGE)
        self.assertNotIn("_verified_oidc: body",EDGE)
        self.assertIn("LF_PROFILE_NATIVE_B09_WRITER_REQUEST_V1",RUNNER)
        self.assertIn("lf-profile-resume-governed",RUNNER)

    def test_nonce_is_bound_one_time_and_expires(self):
        self.assertIn("nonce text NOT NULL UNIQUE",MIG)
        self.assertIn("B09_NONCE_REPLAY_OR_ALREADY_ISSUED",MIG)
        self.assertIn("B09_EVENT_SEQUENCE_OR_REPLAY",MIG)
        self.assertIn("B09_NONCE_EXPIRED",MIG)
        self.assertIn("B09_BINDING_NONCE_EXPIRED",MIG)
        self.assertGreaterEqual(MIG.count("interval '24 hours'"),2)
        self.assertIn("lf_ig_native_chat_nonce_no_mutation_v1",MIG)
        self.assertIn("lf_ig_native_chat_receipt_immutable_guard_v1",MIG)
        self.assertIn("B09_NONCE_ROLLBACK_DURABLE_RECEIPTS_PRESENT",DOWN)

    def test_sha_never_attests_model_or_grants_effects(self):
        self.assertIn("'OFFICIAL_OIDC_WRITER_NONCE_CHAIN_BOUND'",MIG)
        self.assertIn("'SHA256_CHAIN_VERIFIED_DOCUMENTAL_PROVENANCE_UNATTESTED'",MIG)
        self.assertIn("'identity_verified',false",MIG)
        self.assertIn("'reviewer_model_independence_proven',false",MIG)
        self.assertIn("'effect_authority',false",MIG)
        self.assertNotIn("CRYPTOGRAPHICALLY_VERIFIED",MIG)
        self.assertNotIn("PASS_INDEPENDENT_SEMANTIC",MIG)

    def test_rollback_restores_exact_source_not_mixed_history(self):
        self.assertIn("SECURITY INVOKER",DOWN)
        self.assertIn("7cf717887006e278356a716f3fd80182",DOWN)
        self.assertIn("IF EXISTS (SELECT 1 FROM public.lf_ig_native_chat_nonce_v1)",DOWN)
        self.assertIn("DROP FUNCTION public.lf_ig_native_chat_official_writer_binding_receipt_v1",DOWN)
        self.assertIn("DROP TABLE public.lf_ig_native_chat_nonce_v1",DOWN)

if __name__=="__main__":
    unittest.main()
