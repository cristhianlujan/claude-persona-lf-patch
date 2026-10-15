#!/usr/bin/env python3
"""Deterministic regression for the generic creation/updater contract boundary.

No model calls, profile-local code imports, provider claims or DB writes.
"""
import copy
import json
import sys
import hashlib
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/"skills/profile_creator/validators"))

from profile_output_shape_preflight_v1 import validate_shape, candidate_output_gate
from validate_candidate_depth import validate_candidate
from run_bound_profile_output_validator_v1 import validate_bound_output


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

    def test_updater_candidate_never_auto_admitted(self):
        gate = candidate_output_gate("new_future_profile", "SPECIALIZE", True, [])
        self.assertEqual(gate["status"], "REQUIRED_BEFORE_ADMISSION")
        self.assertFalse(gate["executed"])
        self.assertFalse(gate["candidate_admitted"])
        self.assertFalse(gate["source_write_authorized"])
        self.assertIsNone(gate["passing_receipt"])
        self.assertTrue(gate["validator_execution_required_before_admission"])

    def test_updater_no_change_no_unneeded_round(self):
        gate = candidate_output_gate("new_future_profile", "NO_CHANGE", False, [])
        self.assertEqual(gate["status"], "NOT_APPLICABLE_NO_CHANGE")
        self.assertFalse(gate["executed"])

    def test_updater_blocked_authority_never_bypassed(self):
        gate = candidate_output_gate("new_future_profile", "PATCH", False,
                                     ["METHOD_AND_ASSESSMENT_AUTHORITY_UNRESOLVED"])
        self.assertEqual(gate["status"], "BLOCKED_UPSTREAM")
        self.assertFalse(gate["candidate_admitted"])

    def make_bound_fixture(self, folder, mode="STDIN_JSON"):
        root=Path(folder)
        slug="future_generic_profile"
        schema_path=root/f"profiles/{slug}/schemas/output.schema.json"
        val_path=root/f"profiles/{slug}/validators/validate_output.py"
        output_path=root/"evidence/output.json"
        for path in (schema_path,val_path,output_path):
            path.parent.mkdir(parents=True,exist_ok=True)
        schema={
            "type":"object","required":["deliverable_created","self_verdict"],
            "properties":{
                "deliverable_created":{"type":"object","required":["authority_status"],
                    "properties":{"authority_status":{"enum":["SUPPORTED","CONFLICT_RESOLVED"]}}},
                "self_verdict":{"enum":["PASS","BLOCKED"]},
            }
        }
        schema_path.write_text(json.dumps(schema),encoding="utf-8")
        program='''import sys,json
from pathlib import Path
obj=json.loads(Path(sys.argv[1]).read_text() if len(sys.argv)>1 else sys.stdin.read())
valid=obj.get("deliverable_created",{}).get("authority_status")=="SUPPORTED" and obj.get("self_verdict")=="PASS"
print(json.dumps({"valid":valid,"errors":[] if valid else [{"code":"AUTHORITY_UNVERIFIED"}]}))
'''
        val_path.write_text(program,encoding="utf-8")
        output_path.write_text(json.dumps({"deliverable_created":{"authority_status":"SUPPORTED"},
                                          "self_verdict":"PASS"}),encoding="utf-8")
        packet={"schema":"PROFILE_OUTPUT_VALIDATION_BINDING_V1",
                "operation_code":"ACTUALIZACION_PERFIL_LF","profile_slug":slug,
                "validator_transport":mode,"expected_valid":True}
        for key,path in (("schema",schema_path),("validator",val_path),("raw_output",output_path)):
            packet[key+"_ref"]=path.relative_to(root).as_posix()
            packet[key+"_sha256"]=hashlib.sha256(path.read_bytes()).hexdigest()
        return root,packet,output_path

    def test_updater_executes_generic_stdin_profile_validator(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,_=self.make_bound_fixture(directory,"STDIN_JSON")
            result=validate_bound_output(root,packet)
            self.assertEqual(result["status"],"CANDIDATE_OUTPUT_PARITY_OBSERVED",result)
            self.assertTrue(result["profile_validator_executed"])
            self.assertFalse(result["admission_authorized"])
            self.assertFalse(result["provider_attested"])

    def test_updater_executes_generic_file_argument_validator(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,_=self.make_bound_fixture(directory,"JSON_FILE_ARGUMENT")
            result=validate_bound_output(root,packet)
            self.assertEqual(result["status"],"CANDIDATE_OUTPUT_PARITY_OBSERVED",result)

    def test_updater_missing_required_field_rejected_before_validator(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            r=validate_bound_output(root,packet)
            self.assertEqual(r["status"],"FAIL")
            self.assertIn("OUTPUT_SHAPE_INVALID",r["blocking_codes"])
            self.assertFalse(r["profile_validator_executed"])

    def test_updater_frozen_negative_validator_rejects(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{"authority_status":"CONFLICT_RESOLVED"},
                                     "self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            packet["expected_valid"]=False
            r=validate_bound_output(root,packet)
            self.assertEqual(r["status"],"EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR",r)
            self.assertTrue(r["profile_validator_executed"])

    def test_generic_updater_self_repair_is_bounded_and_not_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            result=validate_bound_output(root,packet)
            directive=result["remediation"]
            self.assertEqual(result["status"],"FAIL")
            self.assertEqual(directive["classification"],"CANDIDATE_OUTPUT_DEFECT")
            self.assertEqual(directive["action"],"RETURN_TO_GOVERNED_PRODUCER_ONCE")
            self.assertEqual(directive["target"],"CANDIDATE_OUTPUT_ONLY")
            self.assertEqual(directive["max_repair_cycles"],1)
            self.assertEqual(directive["attempts_executed"],0)
            self.assertFalse(directive["producer_repair_executed"])
            self.assertFalse(directive["may_change_canonical_schema_or_validator"])
            self.assertFalse(result["admission_authorized"])

    def test_generic_updater_validator_rejection_requests_one_repair(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{"authority_status":"CONFLICT_RESOLVED"},
                                     "self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            result=validate_bound_output(root,packet)
            self.assertEqual(result["blocking_codes"],["CANONICAL_VALIDATOR_RESULT_UNEXPECTED"])
            self.assertEqual(result["remediation"]["action"],"RETURN_TO_GOVERNED_PRODUCER_ONCE")
            self.assertTrue(result["remediation"]["must_rerun_same_bound_canonical_schema_and_validator"])
            self.assertTrue(result["profile_validator_executed"])

    def test_generic_updater_bad_negative_repair_targets_fixture_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,_=self.make_bound_fixture(directory)
            packet["expected_valid"]=False
            result=validate_bound_output(root,packet)
            self.assertEqual(result["blocking_codes"],["CANONICAL_VALIDATOR_RESULT_UNEXPECTED"])
            self.assertEqual(result["remediation"]["target"],"NEGATIVE_FIXTURE_ONLY")
            self.assertFalse(result["admission_authorized"])

    def test_generic_updater_missing_authority_does_not_self_repair(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,_=self.make_bound_fixture(directory)
            packet["validator_sha256"]="0"*64
            result=validate_bound_output(root,packet)
            self.assertEqual(result["blocking_codes"],["SOURCE_SHA_MISMATCH:validator"])
            self.assertEqual(result["remediation"]["max_repair_cycles"],0)
            self.assertEqual(result["remediation"]["action"],"RETURN_TO_EVIDENCE_OR_AUTHORITY")

    def test_updater_stale_raw_hash_prevents_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            r=validate_bound_output(root,packet)
            self.assertEqual(r["status"],"FAIL")
            self.assertIn("SOURCE_SHA_MISMATCH:raw_output",r["blocking_codes"])
            self.assertFalse(r["profile_validator_executed"])

    def test_updater_rejects_validator_outside_profile_scope(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            packet["validator_ref"]="profiles/other_profile/validators/validate_output.py"
            r=validate_bound_output(root,packet)
            self.assertEqual(r["status"],"FAIL")
            self.assertFalse(r["profile_validator_executed"])

    def test_negative_bad_status_rejected(self):
        s={"type":"object","required":["self_verdict"],"properties":{"self_verdict":{"enum":["PASS","NEEDS_INPUT","BLOCKED"]}}}
        self.assertEqual(validate_shape(s,{"self_verdict":"NEEDS_VALIDATION"})["blocking_codes"][0]["code"],"ENUM_MISMATCH")


if __name__ == "__main__":
    unittest.main()
