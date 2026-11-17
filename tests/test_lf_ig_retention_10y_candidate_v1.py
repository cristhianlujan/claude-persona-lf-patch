"""Static contract of owner 08:17 IG retention candidate; not PostgreSQL PASS."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
M = (ROOT / "supabase/migrations/20261117084800_lf_ig_retention_10y_parameter_candidate_v1.sql").read_text()
H = (ROOT / "sandbox/lf_contract_gate_test/input_governance/retention_10y_candidate_rollback_v1.sql").read_text()
D = (ROOT / "docs/ig/retention_10y_governance_design_v1.md").read_text()
S = (ROOT / "sandbox/lf_contract_gate_test/input_governance/compose_retention_10y_pg_rollback_v1.sh").read_text()

class CandidateSource(unittest.TestCase):
    def test_central_parameters_only(self):
        self.assertIn("('LF_RECORD_RETENTION_DAYS',1,3650,'DAYS','CANDIDATO'", M)
        self.assertIn("('LF_RETENTION_HOT_MONTHS',1,12,'MONTHS','CANDIDATO'", M)
        self.assertEqual(M.count("'LF_RECORD_RETENTION_DAYS',1,3650"), 1)
    def test_fail_closed_no_active_no_grants(self):
        self.assertIn("LF_IG_RETENTION_ACTIVE_WRITER_NOT_AUTHORIZED", M)
        self.assertIn("LF_IG_RETENTION_NO_OWNER_APPROVED_ACTIVE_PARAMETER", M)
        self.assertIn("REVOKE ALL ON TABLE private.lf_ig_parameters_v1", M)
        self.assertNotIn("GRANT EXECUTE", M)
    def test_audit_and_append_only(self):
        self.assertIn("lf_ops.auditoria_eventos", M)
        self.assertIn("LF_IG_RETENTION_APPEND_ONLY_NO_UPDATE_OR_DELETE", M)
        self.assertIn("owner_approval_verified',false", M)
    def test_legacy_read_not_mutated(self):
        self.assertIn("'REG_AUD_003','LEGAL-RECLAMOS-04'", M)
        for x in ("UPDATE lf_ops.reglas", "INSERT INTO lf_ops.reglas", "DELETE FROM lf_ops.reglas"):
            self.assertNotIn(x, M)
    def test_rollback_harness_not_fake_pass(self):
        self.assertIn("print('BEGIN;')", S)
        self.assertIn("print('ROLLBACK;')", S)
        self.assertIn("LF_PG_ISOLATED_TEST", S)
        self.assertNotIn("\\ir", H)
        self.assertIn("PASS_IG_RETENTION_CANDIDATE_PARAMETERS_2_AUDIT_2_FAIL_CLOSED", H)
        self.assertIn("NOT_EXECUTED", H)
    def test_historical_protection(self):
        for x in ("3650", "12 meses", "conteo", "checksum", "aprobación", "OTP"):
            self.assertIn(x, D)
if __name__=="__main__":
    unittest.main()
