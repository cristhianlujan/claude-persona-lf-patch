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

import validate_lf_unified_execution_task_v1 as validator

SCHEMA_PATH = ROOT / "gobernanza/contratos/lf_unified_execution_task_v1.schema.json"


def valid_envelope() -> dict:
    return {
        "schema": "LF_UNIFIED_EXECUTION_TASK_V1",
        "execution_id": "EXEC-G03-TEST-001",
        "operation_code": "PILOT_SRCR_UNIFIED_EXECUTION_V1",
        "operation_spec_digest": "a" * 64,
        "task_id": "TASK-G03-001",
        "step_id": "STEP-001",
        "attempt_no": 1,
        "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
        "profile_source_sha": "b" * 40,
        "executor_binding_id": "EXECUTOR-BINDING-GENERIC-001",
        "executor_binding_digest": "c" * 64,
        "required_capabilities": ["model_call"],
        "input_refs": ["supabase://example/input/1"],
        "evidence_refs": [],
        "lease_required": True,
    }


def expected_identity(envelope: dict) -> dict:
    return {field: envelope[field] for field in validator.IDENTITY_FIELDS}


class G03TaskEnvelopeCandidateTests(unittest.TestCase):
    def test_schema_contract_is_frozen(self):
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        self.assertEqual(validator.validate_schema_contract(schema), [])
        authority = schema["x-lf-authority"]
        self.assertEqual(authority["g01_contract_head"], "ae1bcbb3c443396347805f38037556bce9e7f88b")
        self.assertEqual(authority["g02_candidate_head"], "6dea45eea313b46cfc3afed3cb369deab43dcab1")
        self.assertEqual(authority["next_task_owner"], "advance_execution")
        self.assertFalse(authority["executor_selects_next_task"])

    def test_valid_envelope_matches_frozen_execution_identity(self):
        envelope = valid_envelope()
        self.assertEqual(validator.validate_task_envelope(envelope, expected_identity(envelope)), [])

    def test_missing_required_field_fails_closed(self):
        envelope = valid_envelope()
        del envelope["task_id"]
        self.assertIn("TASK_ENVELOPE_MISSING_TASK_ID", validator.validate_task_envelope(envelope))

    def test_attempt_zero_fails_closed(self):
        envelope = valid_envelope()
        envelope["attempt_no"] = 0
        self.assertIn("TASK_ENVELOPE_INVALID_ATTEMPT_NO", validator.validate_task_envelope(envelope))

    def test_boolean_attempt_is_not_integer_attempt(self):
        envelope = valid_envelope()
        envelope["attempt_no"] = True
        self.assertIn("TASK_ENVELOPE_INVALID_ATTEMPT_NO", validator.validate_task_envelope(envelope))

    def test_lease_is_mandatory(self):
        envelope = valid_envelope()
        envelope["lease_required"] = False
        self.assertIn("TASK_ENVELOPE_LEASE_REQUIRED_MUST_BE_TRUE", validator.validate_task_envelope(envelope))

    def test_reference_carriers_must_be_arrays(self):
        for field in validator.ARRAY_FIELDS:
            envelope = valid_envelope()
            envelope[field] = "not-an-array"
            self.assertIn(f"TASK_ENVELOPE_INVALID_{field.upper()}_TYPE", validator.validate_task_envelope(envelope))

    def test_identity_mismatch_fails_closed(self):
        envelope = valid_envelope()
        identity = expected_identity(envelope)
        identity["profile_source_sha"] = "d" * 40
        self.assertIn(
            "TASK_ENVELOPE_IDENTITY_MISMATCH:profile_source_sha",
            validator.validate_task_envelope(envelope, identity),
        )

    def test_partial_expected_identity_cannot_bypass_binding(self):
        envelope = valid_envelope()
        identity = expected_identity(envelope)
        del identity["executor_binding_digest"]
        errors = validator.validate_task_envelope(envelope, identity)
        self.assertTrue(any(x.startswith("EXPECTED_EXECUTION_IDENTITY_INCOMPLETE:") for x in errors))

    def test_executor_routing_fields_are_forbidden(self):
        for field in ("next_step", "next_task", "selected_next_task", "route", "routing"):
            envelope = copy.deepcopy(valid_envelope())
            envelope[field] = "SHOULD-NOT-BE-HERE"
            self.assertIn(
                f"TASK_ENVELOPE_FORBIDDEN_ROUTING_FIELD:{field}",
                validator.validate_task_envelope(envelope),
            )

    def test_digest_formats_fail_closed(self):
        envelope = valid_envelope()
        envelope["operation_spec_digest"] = "bad"
        envelope["profile_source_sha"] = "bad"
        envelope["executor_binding_digest"] = "bad"
        errors = validator.validate_task_envelope(envelope)
        self.assertIn("TASK_ENVELOPE_INVALID_OPERATION_SPEC_DIGEST", errors)
        self.assertIn("TASK_ENVELOPE_INVALID_PROFILE_SOURCE_SHA", errors)
        self.assertIn("TASK_ENVELOPE_INVALID_EXECUTOR_BINDING_DIGEST", errors)


if __name__ == "__main__":
    result = unittest.main(verbosity=2, exit=False).result
    print(
        "G03_TASK_ENVELOPE_REGRESSION_EXECUTED=1 "
        f"TEST_COUNT={result.testsRun} "
        f"RESULT={'PASS' if result.wasSuccessful() else 'FAIL'} "
        "MODEL_CALLS=0"
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
