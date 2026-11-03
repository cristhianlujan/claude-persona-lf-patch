"""Negative input/provenance cases for the proposal-only Profile Updater preflight."""
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "skills/profile_creator/validators"))
import profile_updater_io_preflight_v1 as v


def row(step_id, run_id, evidence_payload):
    return {
        "step_id": step_id, "execution_id": run_id,
        "status": "STEP_PASS_WITH_EVIDENCE",
        "evidence_ref": f"proof:{step_id}",
        "evidence_payload": evidence_payload,
    }


class ProfileUpdaterInputPreflight(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads(v.CATALOG.read_text(encoding="utf-8"))
        cls.exec_id = "EXEC-ACTUALIZACION-PERFIL-LF-UNITTEST"

    def fixture(self):
        execution = {
            "execution_id": self.exec_id,
            "operation_code": "ACTUALIZACION_PERFIL_LF",
            "status": "IN_PROGRESS",
        }
        base = "a" * 40
        candidate = "b" * 40
        prior = {
            "pre_write_execution_binding_gate": row(
                "pre_write_execution_binding_gate", self.exec_id,
                {"bound_revision": base,
                 "server_trust_context": {"bound_revision": base}}),
            "github_write": row(
                "github_write", self.exec_id,
                {"commit_sha": candidate,
                 "server_trust_context": {"commit_sha": candidate}}),
            "github_readback": row(
                "github_readback", self.exec_id, {"exact_head": candidate}),
        }
        request = {
            "execution_id": self.exec_id, "step_id": "deterministic_validation",
            "evidence_payload": {"evolution_proof_run_id": "41215027439"},
        }
        return execution, request, prior

    def check(self, execution=None, request=None, prior=None):
        e, r, p = self.fixture()
        return v.check_step(self.catalog, "deterministic_validation",
                            e if execution is None else execution,
                            r if request is None else request,
                            p if prior is None else prior)

    def init_request(self, mode="NOT_REQUIRED", contract=None):
        return {
            "schema_version": "LF_PROFILE_UPDATE_REQUEST_V1",
            "action": "profile_update_init",
            "target_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            "target_path": "profiles/systemic_root_cause_repair_lf/SKILL.md",
            "research_baseline_mode": mode,
            "research_baseline_contract": contract,
        }

    def test_init_is_pre_execution_and_requires_no_existing_run(self):
        result = v.check_init_request(self.catalog, self.init_request())
        self.assertEqual(result["status"], "READY_FOR_GOVERNED_INITIALIZATION")
        self.assertIsNone(result["execution_id"])
        self.assertEqual(result["approval_effect"], "NONE")
        self.assertEqual(len(result["bindings"]), 3)

    def test_init_research_contract_required_only_in_pre_research_mode(self):
        invalid = v.check_init_request(
            self.catalog, self.init_request(mode="PRE_RESEARCH_ALWAYS"))
        self.assertEqual(invalid["status"], "BLOCKED_MISSING_INPUT")
        self.assertIn("research_baseline_contract:INPUT_REQUIRED_FOR_MODE",
                      invalid["missing"])
        valid = v.check_init_request(self.catalog, self.init_request(
            mode="PRE_RESEARCH_ALWAYS",
            contract={"contract_version": "PROFILE_RESEARCH_BASELINE_BINDING_V1"}))
        self.assertEqual(valid["status"], "READY_FOR_GOVERNED_INITIALIZATION")

    def test_init_rejects_unexpected_contract_and_noncanonical_path(self):
        c = self.init_request(contract={"contract_version": "anything"})
        self.assertEqual(
            v.check_init_request(self.catalog, c)["status"],
            "BLOCKED_INCONSISTENT_INPUT")
        c = self.init_request()
        c["target_path"] = "profiles/../admin/SKILL.md"
        result = v.check_init_request(self.catalog, c)
        self.assertIn("INIT_TARGET_PATH_INVALID", result["inconsistent"])

    def test_init_rejects_wrong_schema_or_unapproved_extra_key(self):
        req = self.init_request()
        req["schema_version"] = "LF_OTHER_SCHEMA"
        self.assertIn("INIT_ACTION_OR_SCHEMA_INVALID",
                      v.check_init_request(self.catalog, req)["inconsistent"])
        req = self.init_request()
        req["admin_override"] = True
        self.assertIn("INIT_REQUEST_KEYS_MISMATCH",
                      v.check_init_request(self.catalog, req)["inconsistent"])

    def test_canonical_catalog_has_seventeen_ordered_stage_bindings(self):
        self.assertEqual(v.validate_catalog(self.catalog), [])
        self.assertEqual(len(self.catalog["steps"]), 17)
        self.assertEqual(self.catalog["steps"][11]["step_id"],
                         "deterministic_validation")

    def test_ready_only_for_external_server_verification_not_pass(self):
        result = self.check()
        self.assertEqual(result["status"], "READY_FOR_SERVER_VERIFICATION")
        self.assertEqual(result["approval_effect"], "NONE")
        self.assertEqual(result["server_proof_verification"],
                         "REQUIRED_BY_EXISTING_EDGE")
        self.assertEqual(len(result["bindings"]), 4)

    def test_missing_proof_is_blocked(self):
        e, r, p = self.fixture()
        del r["evidence_payload"]["evolution_proof_run_id"]
        result = self.check(e, r, p)
        self.assertEqual(result["status"], "BLOCKED_MISSING_INPUT")
        self.assertIn("evolution_proof_run_id:INPUT_REQUIRED_MISSING",
                      result["missing"])

    def test_non_numeric_proof_is_rejected(self):
        e, r, p = self.fixture()
        r["evidence_payload"]["evolution_proof_run_id"] = "wrong-run"
        result = self.check(e, r, p)
        self.assertEqual(result["status"], "BLOCKED_INCONSISTENT_INPUT")
        self.assertIn("PROOF_RUN_ID_INVALID", result["inconsistent"])

    def test_candidate_head_mismatch_is_blocked(self):
        e, r, p = self.fixture()
        p["github_readback"]["evidence_payload"]["exact_head"] = "c" * 40
        result = self.check(e, r, p)
        self.assertEqual(result["status"], "BLOCKED_INCONSISTENT_INPUT")
        self.assertIn("CANDIDATE_HEAD_PARITY_FAILED", result["inconsistent"])

    def test_caller_declared_commit_cannot_override_server_context(self):
        e, r, p = self.fixture()
        p["github_write"]["evidence_payload"]["commit_sha"] = "d" * 40
        result = self.check(e, r, p)
        self.assertEqual(result["status"], "BLOCKED_INCONSISTENT_INPUT")
        self.assertIn("CANDIDATE_HEAD_PARITY_FAILED", result["inconsistent"])

    def test_bound_revision_drift_is_blocked(self):
        e, r, p = self.fixture()
        p["pre_write_execution_binding_gate"]["evidence_payload"]["server_trust_context"]["bound_revision"] = "e" * 40
        result = self.check(e, r, p)
        self.assertEqual(result["status"], "BLOCKED_INCONSISTENT_INPUT")
        self.assertIn("BOUND_REVISION_NOT_SERVER_BOUND", result["inconsistent"])

    def test_cross_execution_receipt_is_blocked(self):
        e, r, p = self.fixture()
        p["github_write"]["execution_id"] = "EXEC-OTHER"
        result = self.check(e, r, p)
        self.assertEqual(result["status"], "BLOCKED_INCONSISTENT_INPUT")
        self.assertIn("candidate_commit_sha:CROSS_EXECUTION_RECEIPT",
                      result["inconsistent"])

    def test_missing_or_blocked_previous_receipt(self):
        e, r, p = self.fixture()
        del p["github_readback"]
        self.assertEqual(self.check(e, r, p)["status"], "BLOCKED_MISSING_INPUT")
        e, r, p = self.fixture()
        p["github_readback"]["status"] = "BLOCKED_STEP_NOT_CLEAN"
        result = self.check(e, r, p)
        self.assertEqual(result["status"], "BLOCKED_INCONSISTENT_INPUT")
        self.assertIn("readback_exact_head:PRIOR_RECEIPT_NOT_CLEAN",
                      result["inconsistent"])

    def test_request_other_run_is_blocked(self):
        e, r, p = self.fixture()
        r["execution_id"] = "EXEC-OTHER"
        result = self.check(e, r, p)
        self.assertEqual(result["status"], "BLOCKED")
        self.assertIn("REQUEST_EXECUTION_OR_STEP_MISMATCH",
                      result["inconsistent"])

    def test_catalog_guard_rejects_forward_reference(self):
        c = copy.deepcopy(self.catalog)
        c["steps"][1]["bindings"][0] = {
            "name": "execution_id", "source": "prior_step",
            "step_id": "regression_after", "path": "evidence_ref"
        }
        self.assertIn("CATALOG_FORWARD_OR_UNKNOWN_REFERENCE:router",
                      v.validate_catalog(c))

    def test_35_and_37_required_inputs_preserved(self):
        c = copy.deepcopy(self.catalog)
        c["steps"][4]["input_required"].append("invented")
        self.assertIn("CATALOG_HISTORICAL_35_37_CHANGED",
                      v.validate_catalog(c))

    def test_migration_input_arrays_match_exact_config(self):
        migration = (ROOT / "supabase/migrations"
                     / "20261103030000_lf_profile_updater_input_bindings_v1.sql")
        sql = migration.read_text(encoding="utf-8")
        for item in self.catalog["steps"]:
            canonical = json.dumps(item["input_required"], separators=(",", ":"))
            value = f"('{item['step_id']}', '{canonical}'::jsonb)"
            self.assertIn(value, sql)
        self.assertNotIn("lf_router_pipeline_context", sql)
        self.assertNotIn("GRANT ", sql.upper())
        self.assertNotIn("CREATE OR REPLACE FUNCTION", sql.upper())

    def test_all_inputs_do_not_claim_runtime_attestation(self):
        for stage in self.catalog["steps"]:
            self.assertFalse(any(
                b.get("source") in ("runtime_attestation", "semantic_pass")
                for b in stage["bindings"]))


if __name__ == "__main__":
    unittest.main()
