#!/usr/bin/env python3
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import s30c_harness as h


class S30CHarnessTests(unittest.TestCase):
    def setUp(self):
        self.corpus = json.loads((HERE / "replay_corpus.json").read_text(encoding="utf-8"))

    def test_r09_required_case_matrix_and_first_hop(self):
        self.assertGreaterEqual(len(self.corpus["cases"]), 27)
        categories = {c["category"] for c in self.corpus["cases"]}
        self.assertEqual(categories, {
            "DB/schema", "EKB/process", "Data-access", "Imports/dependencies",
            "CI/wiring", "Evidence/handoff", "Freeze/currentness", "Tool/API arguments",
            "Execution-authority",
        })
        for case in self.corpus["cases"]:
            self.assertTrue(case["machine_detectable"])
            self.assertEqual(case["expected_stage_of_failure"], h.PRE_MATERIAL)
            self.assertTrue(case["expected_first_bad_hop"])

    def test_r09_replay_has_zero_preventable_first_hop_escapes(self):
        result = h.replay_corpus(self.corpus)
        self.assertEqual(result["build_replay_status"], "PASS")
        self.assertEqual(result["metrics"]["PREVENTABLE_FIRST_HOP_ESCAPE_COUNT"], 0)
        self.assertTrue(all(v == 0 for v in result["metrics"].values()))
        self.assertEqual(result["final_r09_acceptance"], "NOT_RUN_DEFERRED_TO_S30_D")

    def test_new_execution_authority_replays_are_pre_model(self):
        cases = [c for c in self.corpus["cases"] if c["category"] == "Execution-authority"]
        self.assertGreaterEqual(len(cases), 6)
        for case in cases:
            result = h.replay_case(case)
            self.assertEqual(result["decision"], "BLOCK")
            self.assertEqual(result["observed_stage"], h.PRE_MATERIAL)
            self.assertEqual(result["model_calls"], 0)

    def test_r06_e2e_artifact_path_core_probes(self):
        result = h.run_artifact_e2e()
        self.assertEqual(result["reconciliation"], "PASS")
        self.assertTrue(all(result["probes"].values()))
        self.assertTrue(result["quality_receipt"]["review_completed"])
        self.assertEqual(result["quality_receipt"]["execution_mode"], "CLEAN_INDEPENDENT_CONTEXT")
        self.assertEqual(result["quality_receipt"]["network_mode"], "OFF")
        self.assertEqual(result["quality_receipt"]["model_calls"], 0)

    def test_r06_tampered_payload_fails_hash_recompute(self):
        with tempfile.TemporaryDirectory(prefix="s30c_negative_tamper_") as td:
            work = Path(td)
            bundle, _ = h.create_frozen_bundle(work)
            broken = work / "broken"
            shutil.copytree(bundle, broken)
            (broken / "artifact_payload.json").write_text('{"tampered":true}\n', encoding="utf-8")
            with self.assertRaises(h.HarnessFailure):
                h.independent_review(broken)

    def test_r06_missing_contract_fails_clean_reviewer(self):
        with tempfile.TemporaryDirectory(prefix="s30c_negative_missing_contract_") as td:
            work = Path(td)
            bundle, _ = h.create_frozen_bundle(work)
            broken = work / "broken"
            shutil.copytree(bundle, broken)
            (broken / "upstream_contract.json").unlink()
            with self.assertRaises(h.HarnessFailure):
                h.independent_review(broken)

    def _freeze(self, phase, run_id, hash_value="a" * 64):
        idx = h.PHASES.index(phase)
        return {
            "phase": phase,
            "version_run_id": run_id,
            "input_identities": {"main_sha": "2b6f2f918c4d6c3d66226cc1933728d61cbfe4cb"},
            "hashes": {"contract": hash_value},
            "expected_output_contract": {"receipt": "v1"},
            "allowed_mutations": ["evidence_append_only"],
            "invalidation_triggers": ["input_hash_change"],
            "next_phase": h.PHASES[idx + 1] if idx + 1 < len(h.PHASES) else None,
        }

    def test_r07_valid_transition_is_accepted(self):
        prev = self._freeze("CONTRACT_AND_PREFLIGHT", "run-003")
        cur = self._freeze("HARNESS_AND_GUARDS", "run-003")
        cur["prior_freeze_sha256"] = h.freeze_record_sha(prev)
        h.validate_freeze_transition(prev, cur)

    def test_r07_cross_gate_mutation_is_rejected(self):
        prev = self._freeze("CONTRACT_AND_PREFLIGHT", "run-003")
        cur = self._freeze("HARNESS_AND_GUARDS", "run-003", hash_value="b" * 64)
        cur["prior_freeze_sha256"] = h.freeze_record_sha(prev)
        with self.assertRaisesRegex(h.HarnessFailure, "GATE_CROSS_MUTATION_HASH"):
            h.validate_freeze_transition(prev, cur)

    def test_r07_run_identity_mutation_is_rejected(self):
        prev = self._freeze("CONTRACT_AND_PREFLIGHT", "run-003")
        cur = self._freeze("HARNESS_AND_GUARDS", "run-004")
        cur["prior_freeze_sha256"] = h.freeze_record_sha(prev)
        with self.assertRaisesRegex(h.HarnessFailure, "FREEZE_RUN_ID_CHANGED"):
            h.validate_freeze_transition(prev, cur)

    def test_persisted_freeze_chain_is_valid(self):
        chain = json.loads((HERE / "freeze_records.json").read_text(encoding="utf-8"))
        result = h.validate_freeze_chain(chain)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["last_phase"], "HARNESS_AND_GUARDS")

    def test_ci_wiring_uses_generic_s30_discovery(self):
        result = h.workflow_wiring(ROOT / ".github/workflows/validate-lf-packs.yml")
        self.assertTrue(result["wired"], result["missing"])
        self.assertEqual(result["mode"], "GENERIC_S30_DISCOVERY")

    def test_dependency_import_closure_is_stdlib_only(self):
        result = h.import_closure([HERE / "s30c_harness.py", HERE / "test_s30c_harness.py"])
        self.assertTrue(result["complete"], result["unresolved"])

    def test_source_manifest_is_frozen_to_current_main_and_upstreams(self):
        manifest = json.loads((HERE / "source_manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["frozen_main"]["sha"], "2b6f2f918c4d6c3d66226cc1933728d61cbfe4cb")
        self.assertEqual(manifest["supabase"]["strategy_snapshot"]["id"], 35)
        self.assertEqual(manifest["execution_policy"]["model_calls_expected_for_s30_c_build"], 0)
        self.assertIn("S30-A", manifest["upstream_frozen_receipts"])
        self.assertIn("S30-B", manifest["upstream_frozen_receipts"])
        self.assertFalse(manifest["scope_guards"]["touch_s26"])
        self.assertFalse(manifest["scope_guards"]["modify_s30_a_or_b"])

    def test_upstream_a_b_receipts_are_hash_bound_and_closed(self):
        result = h.upstream_receipt_binding(ROOT)
        self.assertEqual(result["status"], "PASS", result)
        self.assertTrue(all(result["checks"].values()))

    def test_unknown_path_is_blocked_not_false_na(self):
        case = next(c for c in self.corpus["cases"] if c["fault_kind"] == "unknown_path_false_na")
        result = h.replay_case(case)
        self.assertEqual(result["decision"], "BLOCK")
        self.assertEqual(result["observed_stage"], h.PRE_MATERIAL)

    def test_invented_tool_argument_is_blocked_before_call(self):
        case = next(c for c in self.corpus["cases"] if c["fault_kind"] == "invented_argument")
        result = h.replay_case(case)
        self.assertEqual(result["decision"], "BLOCK")
        self.assertEqual(result["first_bad_hop"], "TOOL_ARGUMENT_BINDING")


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(S30CHarnessTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if result.wasSuccessful():
        print(f"S30_C_REGRESSION_EXECUTED=1 TEST_COUNT={result.testsRun} RESULT=PASS MODEL_CALLS=0")
        raise SystemExit(0)
    print(f"S30_C_REGRESSION_EXECUTED=1 TEST_COUNT={result.testsRun} RESULT=FAIL MODEL_CALLS=0")
    raise SystemExit(1)
