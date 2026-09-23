#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "gobernanza/judges"))

import validate_lf_unified_execution_result_v1 as validator

SCHEMA_PATH = ROOT / "gobernanza/contratos/lf_unified_execution_result_v1.schema.json"


def valid_result() -> dict:
    return {
        "schema": "LF_UNIFIED_EXECUTION_RESULT_V1",
        "execution_id": "EXEC-G04-TEST-001",
        "task_id": "TASK-G04-001",
        "step_id": "STEP-001",
        "attempt_no": 1,
        "lease_owner": "executor-generic-001",
        "lease_fence": 7,
        "outcome": "SUCCEEDED",
        "result_digest": "digest:result:001",
        "evidence_refs": ["supabase://example/evidence/1"],
    }


def expected_task_identity(result: dict) -> dict:
    return {field: result[field] for field in validator.TASK_IDENTITY_FIELDS}


def expected_lease(result: dict) -> dict:
    return {field: result[field] for field in validator.LEASE_IDENTITY_FIELDS}


class G04ResultEnvelopeCandidateTests(unittest.TestCase):
    def test_schema_contract_is_frozen(self):
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        self.assertEqual(validator.validate_schema_contract(schema), [])
        authority = schema["x-lf-authority"]
        self.assertEqual(authority["g01_contract_head"], "ae1bcbb3c443396347805f38037556bce9e7f88b")
        self.assertEqual(authority["g03_candidate_head"], "6e5166f16253a63a6b6341d1bd681ed876571903")
        self.assertEqual(authority["current_lease_authority"], "public.lf_operation_execution")
        self.assertFalse(authority["executor_can_advance_execution_state"])

    def test_valid_result_matches_claimed_task_and_current_lease(self):
        result = valid_result()
        self.assertEqual(
            validator.validate_result_envelope(result, expected_task_identity(result), expected_lease(result)),
            [],
        )

    def test_missing_required_field_fails_closed(self):
        result = valid_result()
        del result["result_digest"]
        self.assertIn("RESULT_ENVELOPE_MISSING_RESULT_DIGEST", validator.validate_result_envelope(result))

    def test_attempt_zero_and_boolean_fail_closed(self):
        for value in (0, True):
            result = valid_result()
            result["attempt_no"] = value
            self.assertIn("RESULT_ENVELOPE_INVALID_ATTEMPT_NO", validator.validate_result_envelope(result))

    def test_negative_and_boolean_fence_fail_closed(self):
        for value in (-1, True):
            result = valid_result()
            result["lease_fence"] = value
            self.assertIn("RESULT_ENVELOPE_INVALID_LEASE_FENCE", validator.validate_result_envelope(result))

    def test_outcome_enum_is_exact(self):
        result = valid_result()
        result["outcome"] = "PASS"
        self.assertIn("RESULT_ENVELOPE_INVALID_OUTCOME", validator.validate_result_envelope(result))

    def test_evidence_refs_must_be_array(self):
        result = valid_result()
        result["evidence_refs"] = "not-an-array"
        self.assertIn("RESULT_ENVELOPE_INVALID_EVIDENCE_REFS_TYPE", validator.validate_result_envelope(result))

    def test_claimed_task_identity_mismatch_fails_closed(self):
        result = valid_result()
        identity = expected_task_identity(result)
        identity["attempt_no"] = 2
        self.assertIn(
            "RESULT_ENVELOPE_TASK_IDENTITY_MISMATCH:attempt_no",
            validator.validate_result_envelope(result, identity),
        )

    def test_partial_task_identity_cannot_bypass_binding(self):
        result = valid_result()
        identity = expected_task_identity(result)
        del identity["step_id"]
        errors = validator.validate_result_envelope(result, identity)
        self.assertTrue(any(x.startswith("EXPECTED_TASK_IDENTITY_INCOMPLETE:") for x in errors))

    def test_current_lease_mismatch_fails_closed(self):
        result = valid_result()
        lease = expected_lease(result)
        lease["lease_fence"] = 8
        self.assertIn(
            "RESULT_ENVELOPE_CURRENT_LEASE_MISMATCH:lease_fence",
            validator.validate_result_envelope(result, expected_current_lease=lease),
        )

    def test_partial_current_lease_cannot_bypass_binding(self):
        result = valid_result()
        lease = {"lease_owner": result["lease_owner"]}
        errors = validator.validate_result_envelope(result, expected_current_lease=lease)
        self.assertTrue(any(x.startswith("EXPECTED_CURRENT_LEASE_INCOMPLETE:") for x in errors))

    def test_executor_state_and_routing_fields_are_forbidden(self):
        for field in (
            "next_task",
            "selected_next_step",
            "advance_execution",
            "canonical_state",
            "execution_state",
            "execution_status",
        ):
            result = copy.deepcopy(valid_result())
            result[field] = "SHOULD-NOT-BE-HERE"
            self.assertIn(
                f"RESULT_ENVELOPE_FORBIDDEN_STATE_FIELD:{field}",
                validator.validate_result_envelope(result),
            )

    def test_blank_result_digest_and_lease_owner_fail_closed(self):
        result = valid_result()
        result["result_digest"] = " "
        result["lease_owner"] = ""
        errors = validator.validate_result_envelope(result)
        self.assertIn("RESULT_ENVELOPE_INVALID_RESULT_DIGEST", errors)
        self.assertIn("RESULT_ENVELOPE_INVALID_LEASE_OWNER", errors)


if __name__ == "__main__":
    result = unittest.main(verbosity=2, exit=False).result
    print(
        "G04_RESULT_ENVELOPE_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={result.testsRun} "
        f"RESULT={'PASS' if result.wasSuccessful() else 'FAIL'} "
        "MODEL_CALLS=0"
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
