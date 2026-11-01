"""Governed Profile Updater amendment regression — uses the existing edge-operation CI lane."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]


class CandidateAmendmentTest(unittest.TestCase):
    def test_verified_github_amendment_module_real_node_suite(self):
        result = subprocess.run(
            ["node", "--experimental-strip-types", "--test",
             "supabase/functions/run-creacion-perfil-lf/verified_write_evidence.test.mjs"],
            cwd=ROOT, capture_output=True, text=True, timeout=90)
        self.assertEqual(result.returncode, 0,
                         "Node 24 TypeScript runtime tests FAILED:\n" + result.stdout[-10000:] +
                         "\n" + result.stderr[-6000:])
        self.assertIn("candidate amendment", result.stdout)

    def test_existing_issue_dispatch_python_suite(self):
        result = subprocess.run(
            ["python3", "-m", "unittest", "discover", "-s",
             "sandbox/lf_contract_gate_test/profile_execution_runtime",
             "-p", "test_profile_update_issue_request.py", "-v"],
            cwd=ROOT, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout[-2500:] + result.stderr[-9000:])

    def test_append_only_sql_guards_in_same_existing_ledger(self):
        sql = (ROOT / "supabase/migrations/20261031041500_lf_profile_update_candidate_amendment_v1.sql").read_text()
        for required in (
            "FROM public.lf_operation_execution WHERE execution_id = p_execution_id FOR UPDATE",
            "v_write.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'",
            "v_readback.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'",
            "step_order >= 90",
            "PROFILE_AMEND_STALE_PREDECESSOR",
            "PROFILE_AMEND_SERVER_PROOF_INVALID",
            "manifest=jsonb_set(manifest,'{candidate_amendments}'",
            "REVOKE ALL ON FUNCTION public.lf_profile_update_candidate_amend_v1",
            "GRANT EXECUTE ON FUNCTION public.lf_profile_update_candidate_amend_v1",
        ):
            with self.subTest(required=required):
                self.assertIn(required, sql)
        # The pre-existing step receipts cannot be overwritten by this RPC.
        self.assertNotIn("UPDATE public.lf_operation_execution_steps", sql)
        self.assertNotIn("DELETE FROM public.lf_operation_execution_steps", sql)

    def test_step90_reads_append_only_revision_and_does_not_weaken_proof_verifier(self):
        server = (ROOT / "supabase/functions/run-creacion-perfil-lf/index.ts").read_text()
        verified = (ROOT / "supabase/functions/run-creacion-perfil-lf/verified_proof_evidence.ts").read_text()
        self.assertIn("latest?.candidate_commit ?? write.evidence_payload", server)
        self.assertIn("verifyEvolutionProofRun({ repository: REPOSITORY, mode: \"compare\"", server)
        self.assertIn("PROOF_COMPARISON_NOT_DEMONSTRATED", verified)
        self.assertIn("operationalImprovement(proof)", verified)


if __name__ == "__main__":
    unittest.main()
