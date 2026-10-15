#!/usr/bin/env python3
"""Deterministic regression for the generic creation/updater contract boundary.

No model calls, profile-local code imports, provider claims or DB writes.
"""
import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/"skills/profile_creator/validators"))

from profile_output_shape_preflight_v1 import validate_shape
from validate_candidate_depth import validate_candidate


class OutputShapeParitiyChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = json.loads(
            (ROOT/"skills/profile_creator/fixtures/semantic_depth/positive_candidate_pack.json")
            .read_text(encoding="utf-8")
        )
        cls.schema = json.loads(cls.pack["files"]["schemas/output.schema.json"])
        cls.example = json.loads(cls.pack["files"]["examples/good_output.json"])

    def test_creation_positive_fixture_is_valid(self):
        result = validate_shape(self.schema, self.example)
        self.assertEqual(result["status"], "PASS", result["blocking_codes"])
        self.assertFalse(result["provider_attestation"])
        self.assertFalse(result["full_json_schema_validation"])
        self.assertFalse(result["cutover_authorized"])

    def test_creation_depth_positive_accepts_existing_fixture(self):
        errors, _ = validate_candidate(self.pack)
        self.assertEqual(errors, [])

    def test_creation_depth_rejects_missing_required_nested_field(self):
        broken = copy.deepcopy(self.pack)
        schema = json.loads(broken["files"]["schemas/output.schema.json"])
        schema["properties"]["findings"]["items"]["required"].append("authority_status")
        broken["files"]["schemas/output.schema.json"] = json.dumps(schema)
        errors, _ = validate_candidate(broken)
        self.assertTrue(
            any("GOOD_OUTPUT_CONTRACT_DRIFT:$.findings[0]:REQUIRED_MISSING:authority_status" in e for e in errors),
            errors
        )

    def test_evolution_generic_missing_authority_is_rejected(self):
        schema = {
            "type":"object", "required":["worker","deliverable_created","self_verdict"],
            "properties":{
                "worker":{"type":"string"},
                "deliverable_created":{
                    "type":"object", "required":["authority_status"],
                    "properties":{"authority_status":{"enum":["SUPPORTED","CONFLICT_RESOLVED"]}}
                },
                "self_verdict":{"enum":["PASS","BLOCKED"]}
            }
        }
        candidate = {"worker":"any_future_profile","deliverable_created":{}, "self_verdict":"PASS"}
        errors = validate_shape(schema,candidate)["blocking_codes"]
        self.assertEqual(errors,[{"code":"REQUIRED_MISSING:authority_status","path":"$.deliverable_created"}])
        candidate["deliverable_created"]["authority_status"]="SUPPORTED"
        self.assertEqual(validate_shape(schema,candidate)["status"],"PASS")
        candidate["deliverable_created"]["authority_status"]="UNATTESTED"
        self.assertEqual(validate_shape(schema,candidate)["blocking_codes"][0]["code"],"ENUM_MISMATCH")

    def test_does_not_confuse_boolean_with_integer(self):
        r = validate_shape({"type":"integer"}, True)
        self.assertEqual(r["status"],"FAIL")

    def test_fail_closed_on_unsupported_complex_schema(self):
        r = validate_shape({"oneOf":[{"type":"string"},{"type":"number"}]}, "example")
        self.assertEqual(r["status"],"FAIL")
        self.assertIn("REQUIRES_CANONICAL_SCHEMA_VALIDATOR:oneOf",
                      [x["code"] for x in r["blocking_codes"]])

    def test_output_boundary_does_not_execute_profile_code(self):
        result=validate_shape({"type":"object","required":["decision"]},{"decision":"P"})
        self.assertFalse(result["profile_local_validator_executed"])
        self.assertFalse(result["semantic_review_executed"])
        self.assertFalse(result["provider_attestation"])

    def test_negative_bad_status_rejected(self):
        s={"type":"object","required":["self_verdict"],"properties":{"self_verdict":{"enum":["PASS","NEEDS_INPUT","BLOCKED"]}}}
        self.assertEqual(validate_shape(s,{"self_verdict":"NEEDS_VALIDATION"})["blocking_codes"][0]["code"],"ENUM_MISMATCH")


if __name__ == "__main__":
    unittest.main()
