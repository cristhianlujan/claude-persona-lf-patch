#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import unittest
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = ROOT / "gobernanza/contratos/pilot_srcr_g11_failure_injection_247_acceptance_v1.json"
ACCEPTANCE = ROOT / "sandbox/lf_contract_gate_test/s30_pilot_srcr_g11/g11_247_acceptance_readback.json"
PROFILE_MANIFEST = ROOT / "profiles/systemic_root_cause_repair_lf/manifest.json"
G06 = ROOT / "supabase/migrations/20260923213500_lf_pilot_srcr_unified_execution_g06_submit_result_v1.sql"
G07 = ROOT / "supabase/migrations/20261001214000_lf_pilot_srcr_unified_execution_g07_advance_execution_v1.sql"
G08 = ROOT / "sandbox/lf_contract_gate_test/s30_pilot_srcr_g08/test_g08_checkpoint_existing_authority.py"
G09 = ROOT / "supabase/migrations/20261002064500_lf_pilot_srcr_unified_execution_g09_terminality_v1.sql"
G10 = ROOT / "supabase/migrations/20261002071500_lf_pilot_srcr_unified_execution_g10_retry_policy_v1.sql"

ALLOWED = {"MET", "PARTIAL", "MISSED", "NOT_APPLICABLE"}
QUALIFIED_V06_HEAD = "1e5dad487c30a37b68120940a3ecc3518f733a84"
CANDIDATE = "6ef37503ee1a41c84edca57faa163092eceb95184c609c23ea7bcbe9fb312f16"
EVIDENCE = "feb2f9b6598ea7759fa79402d3bdfc1d6f0104ccf49016b1c7ad0fe23200e0cb"
SCOPE = "49f647de508052d7bb16cd17b7052ba75321b787fcbf80373197a5665b2b768f"


def validate_247_acceptance(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    results = payload.get("step_results")
    if not isinstance(results, list):
        return ["STEP_RESULTS_REQUIRED"]
    if len(results) != 247:
        errors.append("STEP_COUNT_NOT_247")
    ids, statuses = [], []
    for row in results:
        if not isinstance(row, dict):
            errors.append("STEP_RESULT_INVALID")
            continue
        step_id, status = row.get("step_id"), row.get("status")
        if not isinstance(step_id, int):
            errors.append("STEP_ID_INVALID")
        else:
            ids.append(step_id)
        if status not in ALLOWED:
            errors.append("STEP_STATUS_INVALID")
        else:
            statuses.append(status)
    if sorted(ids) != list(range(1, 248)):
        errors.append("STEP_ID_COVERAGE_INVALID")
    aggregate = payload.get("aggregate")
    counts = Counter(statuses)
    if not isinstance(aggregate, dict):
        errors.append("AGGREGATE_REQUIRED")
    else:
        for status in ALLOWED:
            if aggregate.get(status) != counts.get(status, 0):
                errors.append(f"AGGREGATE_MISMATCH_{status}")
    judge = payload.get("semantic_judge")
    if not isinstance(judge, dict):
        errors.append("INDEPENDENT_SEMANTIC_JUDGE_REQUIRED")
    else:
        for field in ("candidate_digest","evidence_bundle_digest","scope_packet_digest","producer_execution_id","reviewer_execution_id","producer_actor","reviewer_actor","verdict"):
            if not isinstance(judge.get(field), str) or not judge[field].strip():
                errors.append(f"JUDGE_FIELD_REQUIRED_{field}")
        if judge.get("producer_execution_id") == judge.get("reviewer_execution_id"):
            errors.append("JUDGE_EXECUTION_NOT_INDEPENDENT")
        if judge.get("producer_actor") == judge.get("reviewer_actor"):
            errors.append("JUDGE_ACTOR_NOT_INDEPENDENT")
        for field in ("candidate_digest","evidence_bundle_digest","scope_packet_digest"):
            if judge.get(field) != payload.get(field):
                errors.append(f"JUDGE_BINDING_MISMATCH_{field}")
    receipt = payload.get("quality_receipt")
    if not isinstance(receipt, dict) or not isinstance(receipt.get("receipt_id"), str) or not receipt["receipt_id"].strip():
        errors.append("QUALITY_RECEIPT_REQUIRED")
    elif isinstance(judge, dict) and receipt.get("judge_verdict") != judge.get("verdict"):
        errors.append("QUALITY_RECEIPT_JUDGE_MISMATCH")
    return sorted(set(errors))


class G11Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = json.loads(CONTRACT.read_text())
        cls.acceptance = json.loads(ACCEPTANCE.read_text())
        cls.profile_manifest = json.loads(PROFILE_MANIFEST.read_text())
        cls.sources = [p.read_text() for p in (G06,G07,G08,G09,G10)]

    def test_exact_stack_and_qualified_v06_binding(self) -> None:
        self.assertEqual(self.contract["base_candidate_head_sha"], "01796b4dc0e8a28b179ec81503e93afe15408e49")
        self.assertEqual(self.contract["pilot_profile_source_sha"], QUALIFIED_V06_HEAD)
        self.assertEqual(self.contract["profile_pack_id"], "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6")
        self.assertEqual(self.profile_manifest["profile_pack_id"], "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6")

    def test_architecture_failure_injection_matrix(self) -> None:
        cases = self.contract["architecture_acceptance"]["failure_injection_cases"]
        self.assertEqual(len(cases), 13)
        self.assertEqual(len({x["case_id"] for x in cases}), 13)
        joined = "\n".join(self.sources).lower()
        for token in ("stale_or_missing_lease_fence","result_task_identity_mismatch","replay_accepted_result","frozen_operation_spec_digest_mismatch","replay_accepted_advance","checkpoint_non_monotonic","executable_current_task_remains","retry_backoff_not_elapsed","retry_attempts_exhausted"):
            self.assertIn(token, joined)

    def test_real_247_readback_is_complete_and_consistent(self) -> None:
        self.assertEqual(validate_247_acceptance(self.acceptance), [])
        self.assertEqual(self.acceptance["suite_id"], "TS-SRCR-V06-LIFECYCLE-247-V1")
        self.assertEqual(self.acceptance["source_profile_revision"], QUALIFIED_V06_HEAD)
        self.assertEqual(self.acceptance["source_replay"]["row_count"], 247)
        self.assertEqual(self.acceptance["aggregate"], {"MET":246,"PARTIAL":0,"MISSED":1,"NOT_APPLICABLE":0})
        missed = [x for x in self.acceptance["step_results"] if x["status"] == "MISSED"]
        self.assertEqual([x["step_id"] for x in missed], [187])
        self.assertEqual(missed[0]["source_step_id"], "D45_LF_CONTRACT_CHECK_EXACT_HEAD")

    def test_real_quality_bindings_are_exact(self) -> None:
        self.assertEqual(self.acceptance["candidate_digest"], CANDIDATE)
        self.assertEqual(self.acceptance["evidence_bundle_digest"], EVIDENCE)
        self.assertEqual(self.acceptance["scope_packet_digest"], SCOPE)
        judge = self.acceptance["semantic_judge"]
        self.assertEqual(judge["verdict"], "PASS_INDEPENDENT_SEMANTIC")
        self.assertNotEqual(judge["producer_execution_id"], judge["reviewer_execution_id"])
        self.assertNotEqual(judge["producer_actor"], judge["reviewer_actor"])
        receipt = self.acceptance["quality_receipt"]
        self.assertTrue(receipt["canonical_quality_accepted"])
        self.assertEqual(receipt["open_proof_obligations"], [])

    def test_historical_miss_is_not_hidden_or_relabelled(self) -> None:
        self.assertTrue(self.acceptance["safety"]["historical_missed_step_preserved"])
        self.assertFalse(self.acceptance["safety"]["old_pase_rerun"])
        self.assertEqual(self.acceptance["verdict_separation"]["profile_quality"], "MEASURED_WITH_1_MISSED_STEP")
        self.assertEqual(self.acceptance["verdict_separation"]["standard_eligibility"], "NOT_DECIDED_BY_G11")

    def test_missing_step_fails(self) -> None:
        x = copy.deepcopy(self.acceptance)
        x["step_results"] = x["step_results"][:-1]
        x["aggregate"]["MET"] -= 1
        self.assertIn("STEP_COUNT_NOT_247", validate_247_acceptance(x))
        self.assertIn("STEP_ID_COVERAGE_INVALID", validate_247_acceptance(x))

    def test_hidden_missed_fails(self) -> None:
        x = copy.deepcopy(self.acceptance)
        x["aggregate"]["MET"] = 247
        x["aggregate"]["MISSED"] = 0
        errors = validate_247_acceptance(x)
        self.assertIn("AGGREGATE_MISMATCH_MET", errors)
        self.assertIn("AGGREGATE_MISMATCH_MISSED", errors)

    def test_missing_judge_fails(self) -> None:
        x = copy.deepcopy(self.acceptance); x.pop("semantic_judge")
        self.assertIn("INDEPENDENT_SEMANTIC_JUDGE_REQUIRED", validate_247_acceptance(x))

    def test_same_judge_identity_fails(self) -> None:
        x = copy.deepcopy(self.acceptance)
        x["semantic_judge"]["reviewer_execution_id"] = x["semantic_judge"]["producer_execution_id"]
        self.assertIn("JUDGE_EXECUTION_NOT_INDEPENDENT", validate_247_acceptance(x))

    def test_digest_drift_fails(self) -> None:
        x = copy.deepcopy(self.acceptance); x["semantic_judge"]["candidate_digest"] = "other"
        self.assertIn("JUDGE_BINDING_MISMATCH_candidate_digest", validate_247_acceptance(x))

    def test_receipt_is_mandatory_and_bound(self) -> None:
        x = copy.deepcopy(self.acceptance); x.pop("quality_receipt")
        self.assertIn("QUALITY_RECEIPT_REQUIRED", validate_247_acceptance(x))
        x = copy.deepcopy(self.acceptance); x["quality_receipt"]["judge_verdict"] = "FAIL"
        self.assertIn("QUALITY_RECEIPT_JUDGE_MISMATCH", validate_247_acceptance(x))

    def test_verdict_separation_contract(self) -> None:
        s = self.contract["verdict_separation"]
        self.assertTrue(s["architecture_verdict_independent"])
        self.assertTrue(s["profile_quality_verdict_independent"])
        self.assertFalse(s["profile_quality_decides_standard_eligibility"])


if __name__ == "__main__":
    run = unittest.main(verbosity=2, exit=False).result
    print("G11_FAILURE_INJECTION_247_ACCEPTANCE_REGRESSION_EXECUTED=1 " f"TEST_COUNT={run.testsRun} RESULT={'PASS' if run.wasSuccessful() else 'FAIL'} " "REAL_247_EVIDENCE_BOUND=1 MET=246 MISSED=1 SEMANTIC_JUDGE_REUSED=1 QUALITY_RECEIPT_REUSED=1 " "MODEL_CALLS=0 PROD_MUTATIONS=0 OLD_PASE_RERUN=0")
    raise SystemExit(0 if run.wasSuccessful() else 1)
