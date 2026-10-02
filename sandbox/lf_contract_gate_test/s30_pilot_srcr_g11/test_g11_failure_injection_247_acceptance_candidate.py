#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = ROOT / "gobernanza/contratos/pilot_srcr_g11_failure_injection_247_acceptance_v1.json"
PROFILE_MANIFEST = ROOT / "profiles/systemic_root_cause_repair_lf/manifest.json"
PROFILE_CONTRACT = ROOT / "profiles/systemic_root_cause_repair_lf/contracts/main_contract.md"
G06 = ROOT / "supabase/migrations/20260923213500_lf_pilot_srcr_unified_execution_g06_submit_result_v1.sql"
G07 = ROOT / "supabase/migrations/20261001214000_lf_pilot_srcr_unified_execution_g07_advance_execution_v1.sql"
G08 = ROOT / "sandbox/lf_contract_gate_test/s30_pilot_srcr_g08/test_g08_checkpoint_existing_authority.py"
G09 = ROOT / "supabase/migrations/20261002064500_lf_pilot_srcr_unified_execution_g09_terminality_v1.sql"
G10 = ROOT / "supabase/migrations/20261002071500_lf_pilot_srcr_unified_execution_g10_retry_policy_v1.sql"

ALLOWED = {"MET", "PARTIAL", "MISSED", "NOT_APPLICABLE"}


def validate_247_acceptance(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    results = payload.get("step_results")
    if not isinstance(results, list):
        return ["STEP_RESULTS_REQUIRED"]
    if len(results) != 247:
        errors.append("STEP_COUNT_NOT_247")

    ids: list[int] = []
    statuses: list[str] = []
    for row in results:
        if not isinstance(row, dict):
            errors.append("STEP_RESULT_INVALID")
            continue
        step_id = row.get("step_id")
        status = row.get("status")
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

    counts = Counter(statuses)
    aggregate = payload.get("aggregate")
    if not isinstance(aggregate, dict):
        errors.append("AGGREGATE_REQUIRED")
    else:
        for status in sorted(ALLOWED):
            if aggregate.get(status) != counts.get(status, 0):
                errors.append(f"AGGREGATE_MISMATCH_{status}")

    judge = payload.get("semantic_judge")
    if not isinstance(judge, dict):
        errors.append("INDEPENDENT_SEMANTIC_JUDGE_REQUIRED")
    else:
        for field in (
            "candidate_digest",
            "evidence_bundle_digest",
            "scope_packet_digest",
            "producer_execution_id",
            "reviewer_execution_id",
            "producer_actor",
            "reviewer_actor",
            "verdict",
        ):
            if not isinstance(judge.get(field), str) or not judge[field].strip():
                errors.append(f"JUDGE_FIELD_REQUIRED_{field}")
        if judge.get("producer_execution_id") == judge.get("reviewer_execution_id"):
            errors.append("JUDGE_EXECUTION_NOT_INDEPENDENT")
        if judge.get("producer_actor") == judge.get("reviewer_actor"):
            errors.append("JUDGE_ACTOR_NOT_INDEPENDENT")
        for field in ("candidate_digest", "evidence_bundle_digest", "scope_packet_digest"):
            if judge.get(field) != payload.get(field):
                errors.append(f"JUDGE_BINDING_MISMATCH_{field}")

    receipt = payload.get("quality_receipt")
    if not isinstance(receipt, dict) or not isinstance(receipt.get("receipt_id"), str) or not receipt["receipt_id"].strip():
        errors.append("QUALITY_RECEIPT_REQUIRED")
    elif isinstance(judge, dict) and receipt.get("judge_verdict") != judge.get("verdict"):
        errors.append("QUALITY_RECEIPT_JUDGE_MISMATCH")

    return sorted(set(errors))


def positive_247_payload() -> dict[str, Any]:
    results = [{"step_id": i, "status": "MET", "evidence_refs": [f"evidence://step/{i}"]} for i in range(1, 248)]
    return {
        "suite_id": "TS-SRCR-V06-LIFECYCLE-247-V1",
        "candidate_digest": "sha256:candidate",
        "evidence_bundle_digest": "sha256:evidence",
        "scope_packet_digest": "sha256:scope",
        "step_results": results,
        "aggregate": {"MET": 247, "PARTIAL": 0, "MISSED": 0, "NOT_APPLICABLE": 0},
        "semantic_judge": {
            "candidate_digest": "sha256:candidate",
            "evidence_bundle_digest": "sha256:evidence",
            "scope_packet_digest": "sha256:scope",
            "producer_execution_id": "EXEC-PRODUCER-001",
            "reviewer_execution_id": "EXEC-JUDGE-001",
            "producer_actor": "gpt-native-producer",
            "reviewer_actor": "independent-semantic-judge",
            "verdict": "PASS",
        },
        "quality_receipt": {
            "receipt_id": "QR-G11-001",
            "judge_verdict": "PASS",
        },
    }


class G11FailureInjectionAnd247AcceptanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
        cls.profile_manifest = json.loads(PROFILE_MANIFEST.read_text(encoding="utf-8"))
        cls.profile_contract = PROFILE_CONTRACT.read_text(encoding="utf-8")
        cls.g06 = G06.read_text(encoding="utf-8")
        cls.g07 = G07.read_text(encoding="utf-8")
        cls.g08 = G08.read_text(encoding="utf-8")
        cls.g09 = G09.read_text(encoding="utf-8")
        cls.g10 = G10.read_text(encoding="utf-8")

    def test_contract_is_bound_to_g10_stack_and_v06_profile(self) -> None:
        self.assertEqual(self.contract["gate_id"], "G11")
        self.assertEqual(self.contract["base_candidate_head_sha"], "01796b4dc0e8a28b179ec81503e93afe15408e49")
        self.assertEqual(self.contract["profile_pack_id"], "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6")
        self.assertEqual(self.contract["pilot_profile_source_sha"], "cb455027df2d2e2795ab66d41a539e217a04966f")
        self.assertEqual(self.profile_manifest["profile_pack_id"], "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6")
        self.assertIn("V0.6 control ownership", self.profile_contract)
        self.assertIn("V0.6 pre-freeze schema discipline", self.profile_contract)

    def test_failure_injection_matrix_is_explicit_and_unique(self) -> None:
        cases = self.contract["architecture_acceptance"]["failure_injection_cases"]
        ids = [row["case_id"] for row in cases]
        self.assertGreaterEqual(len(cases), 13)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(
            self.contract["architecture_acceptance"]["invariants"],
            [
                "INV-01 only advance_execution determines next task",
                "INV-02 only a result with current lease_fence may advance state",
                "INV-03 terminal execution implies zero executable pending task",
                "INV-04 operation spec, profile source and executor bindings are frozen at execution start",
            ],
        )

    def test_failure_injection_controls_exist_on_exact_candidate_stack(self) -> None:
        source_expectations = {
            self.g06: (
                "STALE_OR_MISSING_LEASE_FENCE",
                "RESULT_TASK_IDENTITY_MISMATCH",
                "RESULT_IDENTITY_REUSED_WITH_DIFFERENT_PAYLOAD",
                "REPLAY_ACCEPTED_RESULT",
            ),
            self.g07: (
                "FROZEN_OPERATION_SPEC_DIGEST_MISMATCH",
                "ADVANCE_SOURCE_IS_NOT_CURRENT_TASK",
                "REPLAY_ACCEPTED_ADVANCE",
                "ADVANCE_OUTCOME_REQUIRES_RETRY_POLICY",
            ),
            self.g08: (
                "CHECKPOINT_NON_MONOTONIC",
                "CHECKPOINT_SEQ_REUSED_WITH_DIFFERENT_PAYLOAD",
                "STALE_OR_MISSING_LEASE_FENCE",
                "REPLAY_CHECKPOINT",
            ),
            self.g09: (
                "EXECUTABLE_CURRENT_TASK_REMAINS",
                "UNIFIED_EXECUTION_TERMINAL_RECEIPT_REQUIRED",
                "judge_result='PASS'",
                "required_steps_pass=required_steps",
            ),
            self.g10: (
                "retry_requires_new_current_lease_fence",
                "retry_backoff_not_elapsed",
                "retry_attempts_exhausted",
                "advance_outcome_non_retryable_failure",
            ),
        }
        for source, required in source_expectations.items():
            lowered = source.lower()
            for token in required:
                self.assertIn(token.lower(), lowered)

    def test_247_contract_requires_individual_results_and_independent_judge(self) -> None:
        quality = self.contract["profile_quality_acceptance"]
        self.assertEqual(quality["suite_id"], "TS-SRCR-V06-LIFECYCLE-247-V1")
        self.assertEqual(quality["required_step_count"], 247)
        self.assertEqual(set(quality["allowed_step_statuses"]), ALLOWED)
        self.assertTrue(quality["individual_step_results_required"])
        self.assertTrue(quality["aggregate_must_reconcile_to_individual_results"])
        self.assertTrue(quality["no_aggregate_hides_missed"])
        self.assertTrue(quality["independent_semantic_judge_required"])
        self.assertTrue(quality["provisional_without_judge_forbidden"])
        self.assertTrue(quality["quality_receipt_required"])

    def test_complete_247_payload_with_independent_judge_is_structurally_acceptable(self) -> None:
        self.assertEqual(validate_247_acceptance(positive_247_payload()), [])

    def test_missing_or_duplicate_step_cannot_be_hidden_by_aggregate(self) -> None:
        payload = positive_247_payload()
        payload["step_results"] = payload["step_results"][:-1]
        payload["aggregate"]["MET"] = 246
        self.assertIn("STEP_COUNT_NOT_247", validate_247_acceptance(payload))
        self.assertIn("STEP_ID_COVERAGE_INVALID", validate_247_acceptance(payload))

        payload = positive_247_payload()
        payload["step_results"][246]["step_id"] = 246
        self.assertIn("STEP_ID_COVERAGE_INVALID", validate_247_acceptance(payload))

    def test_missed_step_cannot_be_hidden_by_stale_aggregate(self) -> None:
        payload = positive_247_payload()
        payload["step_results"][6]["status"] = "MISSED"
        errors = validate_247_acceptance(payload)
        self.assertIn("AGGREGATE_MISMATCH_MET", errors)
        self.assertIn("AGGREGATE_MISMATCH_MISSED", errors)

    def test_invalid_step_status_is_rejected(self) -> None:
        payload = positive_247_payload()
        payload["step_results"][0]["status"] = "PASS"
        self.assertIn("STEP_STATUS_INVALID", validate_247_acceptance(payload))

    def test_semantic_judge_is_mandatory_and_cannot_share_identity(self) -> None:
        payload = positive_247_payload()
        payload.pop("semantic_judge")
        self.assertIn("INDEPENDENT_SEMANTIC_JUDGE_REQUIRED", validate_247_acceptance(payload))

        payload = positive_247_payload()
        payload["semantic_judge"]["reviewer_execution_id"] = payload["semantic_judge"]["producer_execution_id"]
        payload["semantic_judge"]["reviewer_actor"] = payload["semantic_judge"]["producer_actor"]
        errors = validate_247_acceptance(payload)
        self.assertIn("JUDGE_EXECUTION_NOT_INDEPENDENT", errors)
        self.assertIn("JUDGE_ACTOR_NOT_INDEPENDENT", errors)

    def test_judge_must_bind_exact_candidate_evidence_and_scope(self) -> None:
        payload = positive_247_payload()
        payload["semantic_judge"]["candidate_digest"] = "sha256:other"
        payload["semantic_judge"]["scope_packet_digest"] = "sha256:other-scope"
        errors = validate_247_acceptance(payload)
        self.assertIn("JUDGE_BINDING_MISMATCH_candidate_digest", errors)
        self.assertIn("JUDGE_BINDING_MISMATCH_scope_packet_digest", errors)

    def test_quality_receipt_is_mandatory_and_bound_to_judge_verdict(self) -> None:
        payload = positive_247_payload()
        payload.pop("quality_receipt")
        self.assertIn("QUALITY_RECEIPT_REQUIRED", validate_247_acceptance(payload))

        payload = positive_247_payload()
        payload["quality_receipt"]["judge_verdict"] = "FAIL"
        self.assertIn("QUALITY_RECEIPT_JUDGE_MISMATCH", validate_247_acceptance(payload))

    def test_architecture_and_profile_quality_verdicts_remain_separate(self) -> None:
        separation = self.contract["verdict_separation"]
        self.assertTrue(separation["architecture_verdict_independent"])
        self.assertTrue(separation["profile_quality_verdict_independent"])
        self.assertFalse(separation["profile_quality_decides_standard_eligibility"])


if __name__ == "__main__":
    run = unittest.main(verbosity=2, exit=False).result
    print(
        "G11_FAILURE_INJECTION_247_ACCEPTANCE_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={run.testsRun} "
        f"RESULT={'PASS' if run.wasSuccessful() else 'FAIL'} "
        "MODEL_CALLS=0 PROD_MUTATIONS=0 "
        "SEMANTIC_JUDGE_EXECUTED=0"
    )
    raise SystemExit(0 if run.wasSuccessful() else 1)
