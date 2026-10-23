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
from run_bound_profile_output_validator_v1 import validate_bound_output, validate_with_bounded_producer_repair


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

    def test_generic_preventive_review_reuses_existing_steps(self):
        gate=candidate_output_gate("future_generic_profile","PATCH",True,[])
        review=gate["preventive_gap_review"]
        self.assertEqual(review["execution_state"],"NOT_EXECUTED_IN_READ_ONLY_PLANNER")
        self.assertTrue(review["not_an_additional_operation_or_checkpoint"])
        self.assertEqual([x["at"] for x in review["reviews"]],
                         ["baseline_read","method_selection","pre_write_execution_binding_gate",
                          "deterministic_validation","regression_after","semantic_judge","report_output"])
        self.assertEqual(gate["prewrite_check_owner"],"pre_write_execution_binding_gate")
        self.assertEqual(gate["postwrite_readback_check_owner"],"deterministic_validation")
        self.assertEqual(review["post_write_mismatch"],"BLOCK_AND_RESTART_NEW_GOVERNED_CHANGESET")
        self.assertTrue(review["no_semantic_self_attestation"])
        self.assertEqual(review["max_producer_repair_cycles_per_evidenced_defect"],1)
        self.assertFalse(review["new_operation_steps_required"])

    def test_v02_prewrite_does_not_require_future_github_head(self):
        contract=json.loads((ROOT/"skills/profile_creator/contracts/profile_update_evolved_routing_candidate_v1.json").read_text(encoding="utf-8"))
        gate=contract["output_contract_gate"]
        pre=gate["pre_write_check"]
        post=gate["post_write_check"]
        self.assertEqual(gate["existing_step_id"],"deterministic_validation")
        self.assertEqual(pre["existing_step_id"],"pre_write_execution_binding_gate")
        self.assertEqual(post["existing_step_id"],"deterministic_validation")
        self.assertNotIn("candidate_head_sha",pre["requires"])
        self.assertNotIn("positive_receipt_id",pre["requires"])
        self.assertNotIn("negative_receipt_id",pre["requires"])
        self.assertIn("candidate_head_sha",post["requires"])
        self.assertIn("positive_receipt_id",post["requires"])
        self.assertIn("negative_receipt_id",post["requires"])
        self.assertTrue(pre["candidate_pass_is_not_admission"])
        self.assertTrue(post["no_in_place_mutation_or_implicit_repair"])
        self.assertFalse(gate["does_not_authorize_cutover"] is False)

    def test_update_candidate_repair_is_not_assigned_after_github_write(self):
        g=candidate_output_gate("future_generic_profile","PATCH",True,[])
        reviews=g["preventive_gap_review"]["reviews"]
        repair=[x for x in reviews if x["on_gap"].startswith("RETURN_TO_GOVERNED_PRODUCER")]
        self.assertEqual([x["at"] for x in repair],["pre_write_execution_binding_gate"])
        self.assertEqual(g["prewrite_repair_allowed_only_before"],"github_write")
        post=[x for x in reviews if x["at"]=="deterministic_validation"][0]
        self.assertEqual(post["on_gap"],"STOP_NO_IN_PLACE_POST_WRITE_REPAIR")
        self.assertFalse(g["source_write_authorized"])

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

    def test_bounded_repair_local_positive_runs_once_and_revalidates(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            calls=[]
            def producer(working_root, before_packet, directive):
                calls.append((before_packet["raw_output_sha256"], directive["defect_code"]))
                repaired=p.with_name('repaired_output.json')
                repaired.write_text(json.dumps({"deliverable_created":{"authority_status":"SUPPORTED"},
                                         "self_verdict":"PASS"}))
                return {**before_packet, "raw_output_ref":repaired.relative_to(root).as_posix(), "raw_output_sha256": hashlib.sha256(repaired.read_bytes()).hexdigest()}
            result=validate_with_bounded_producer_repair(root,packet,producer)
            self.assertEqual(result["status"],"LOCAL_REPAIRED_REVALIDATED_AWAITING_GOVERNED_EVIDENCE")
            self.assertEqual(result["before"]["status"],"FAIL")
            self.assertEqual(result["after"]["status"],"CANDIDATE_OUTPUT_PARITY_OBSERVED")
            self.assertEqual(result["producer_attempts"],1)
            self.assertEqual(len(calls),1)
            self.assertTrue(result["producer_adapter_invoked"])
            self.assertTrue(result["producer_repair_executed"])
            self.assertTrue(result["source_authority_unchanged"])
            self.assertTrue(result["local_deterministic_revalidation"])
            self.assertTrue(result["original_raw_preserved_local"])
            self.assertIsNone(result["original_raw_durable_receipt"])
            self.assertNotEqual(result["repaired_output_ref"],packet["raw_output_ref"])
            self.assertFalse(result["independent_review_executed"])
            self.assertFalse(result["admission_authorized"])

    def test_bounded_repair_wrong_negative_fixture_revalidates_rejection(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            packet["expected_valid"]=False
            def producer(working_root, before_packet, directive):
                self.assertEqual(directive["target"],"NEGATIVE_FIXTURE_ONLY")
                repaired=p.with_name('repaired_output.json')
                repaired.write_text(json.dumps({"deliverable_created":{"authority_status":"CONFLICT_RESOLVED"},
                                         "self_verdict":"PASS"}))
                return {**before_packet, "raw_output_ref":repaired.relative_to(root).as_posix(), "raw_output_sha256":hashlib.sha256(repaired.read_bytes()).hexdigest()}
            result=validate_with_bounded_producer_repair(root,packet,producer)
            self.assertEqual(result["status"],"LOCAL_REPAIRED_REVALIDATED_AWAITING_GOVERNED_EVIDENCE")
            self.assertEqual(result["after"]["status"],"EXPECTED_NEGATIVE_REJECTED_BY_VALIDATOR")
            self.assertFalse(result["admission_authorized"])

    def test_bounded_repair_does_not_retry_unsolved_defect(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            invoked=[]
            def producer(working_root, before_packet, directive):
                invoked.append(1)
                repaired=p.with_name('repaired_output.json')
                repaired.write_text(json.dumps({"deliverable_created":{"authority_status":"UNATTESTED"},
                                         "self_verdict":"PASS"}))
                return {**before_packet, "raw_output_ref":repaired.relative_to(root).as_posix(), "raw_output_sha256":hashlib.sha256(repaired.read_bytes()).hexdigest()}
            result=validate_with_bounded_producer_repair(root,packet,producer)
            self.assertEqual(result["status"],"STOP_REPAIR_NOT_VALIDATED")
            self.assertEqual(result["after"]["status"],"FAIL")
            self.assertEqual(result["producer_attempts"],1)
            self.assertEqual(len(invoked),1)
            self.assertTrue(result["producer_adapter_invoked"])
            self.assertFalse(result["producer_repair_executed"])

    def test_bounded_repair_never_runs_on_stale_authority(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            packet["schema_sha256"]="0"*64
            invoked=[]
            result=validate_with_bounded_producer_repair(root,packet,lambda *args:invoked.append(1))
            self.assertEqual(result["status"],"NO_CORRECTABLE_OUTPUT_DEFECT")
            self.assertEqual(invoked,[])
            self.assertEqual(result["producer_attempts"],0)

    def test_bounded_repair_may_not_change_validator_authority(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            def producer(working_root, before_packet, directive):
                repaired=p.with_name('repaired_output.json')
                repaired.write_text(json.dumps({"deliverable_created":{"authority_status":"SUPPORTED"},
                                         "self_verdict":"PASS"}))
                return {**before_packet, "raw_output_ref":repaired.relative_to(root).as_posix(), "validator_sha256":"0"*64,
                        "raw_output_sha256":hashlib.sha256(repaired.read_bytes()).hexdigest()}
            result=validate_with_bounded_producer_repair(root,packet,producer)
            self.assertEqual(result["status"],"STOP_REPAIR_AUTHORITY_CHANGED")
            self.assertIsNone(result["after"])

    def test_bounded_repair_change_to_validator_blob_is_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            def producer(working_root,before_packet,directive):
                repaired=p.with_name('repaired_output.json')
                repaired.write_text(json.dumps({"deliverable_created":{"authority_status":"SUPPORTED"},
                                         "self_verdict":"PASS"}))
                validator=root/before_packet["validator_ref"]
                validator.write_text(validator.read_text()+"\\n# unauthorized mutation")
                return {**before_packet, "raw_output_ref":repaired.relative_to(root).as_posix(),"raw_output_sha256":hashlib.sha256(repaired.read_bytes()).hexdigest()}
            result=validate_with_bounded_producer_repair(root,packet,producer)
            self.assertEqual(result["status"],"STOP_POST_VALIDATION_SOURCE_MUTATED")
            self.assertEqual(result["after"]["blocking_codes"],["SOURCE_SHA_MISMATCH:validator"])
            self.assertFalse(result["source_authority_unchanged"])
            self.assertFalse(result["producer_repair_executed"])

    def test_bounded_repair_checks_source_after_initial_validator(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{"authority_status":"CONFLICT_RESOLVED"},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            validator=root/packet["validator_ref"]
            validator.write_text(
                validator.read_text() + "\nfrom pathlib import Path\n"
                + "if not valid:\n    v=Path(__file__)\n    v.write_text(v.read_text()+'\\n# tampered-initial')\n",
                encoding="utf-8",
            )
            packet["validator_sha256"]=hashlib.sha256(validator.read_bytes()).hexdigest()
            calls=[]
            result=validate_with_bounded_producer_repair(
                root,packet,lambda *args:calls.append(1))
            self.assertEqual(result["before"]["blocking_codes"],["CANONICAL_VALIDATOR_RESULT_UNEXPECTED"])
            self.assertTrue(result["before"]["profile_validator_executed"])
            self.assertEqual(result["status"],"BLOCKED_SOURCE_MUTATED_DURING_INITIAL_VALIDATION")
            self.assertEqual(result["producer_attempts"],0)
            self.assertFalse(result["producer_adapter_invoked"])
            self.assertEqual(calls,[])
            self.assertFalse(result["admission_authorized"])

    def test_bounded_repair_rechecks_validator_source_after_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            validator=root/packet["validator_ref"]
            # A validator may print a valid response then mutate its own file;
            # source SHA readback must be repeated AFTER subprocess execution.
            validator.write_text(
                validator.read_text() + "\nfrom pathlib import Path\n"
                + "if valid:\n    v=Path(__file__)\n    v.write_text(v.read_text()+'\\n# tampered')\n",
                encoding="utf-8",
            )
            packet["validator_sha256"]=hashlib.sha256(validator.read_bytes()).hexdigest()
            def producer(working_root, before_packet, directive):
                repaired=p.with_name("repaired_output.json")
                repaired.write_text(json.dumps({
                    "deliverable_created":{"authority_status":"SUPPORTED"},
                    "self_verdict":"PASS"
                }))
                return {
                    **before_packet,
                    "raw_output_ref":repaired.relative_to(root).as_posix(),
                    "raw_output_sha256":hashlib.sha256(repaired.read_bytes()).hexdigest()
                }
            result=validate_with_bounded_producer_repair(root,packet,producer)
            self.assertEqual(result["after"]["status"],"CANDIDATE_OUTPUT_PARITY_OBSERVED")
            self.assertEqual(result["status"],"STOP_POST_VALIDATION_SOURCE_MUTATED")
            self.assertFalse(result["source_authority_unchanged"])
            self.assertFalse(result["producer_repair_executed"])
            self.assertFalse(result["admission_authorized"])

    def test_bounded_repair_rejects_original_raw_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            def producer(working_root,before_packet,directive):
                p.write_text(json.dumps({"deliverable_created":{"authority_status":"SUPPORTED"},
                                         "self_verdict":"PASS"}))
                return {**before_packet,"raw_output_sha256":hashlib.sha256(p.read_bytes()).hexdigest()}
            result=validate_with_bounded_producer_repair(root,packet,producer)
            self.assertEqual(result["status"],"STOP_ORIGINAL_RAW_MUTATED")
            self.assertFalse(result["original_raw_preserved_local"])
            self.assertFalse(result["producer_repair_executed"])

    def test_bounded_repair_failure_without_producer_cannot_change_raw(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            original=p.read_bytes()
            def producer(*args):
                raise RuntimeError("producer unavailable")
            result=validate_with_bounded_producer_repair(root,packet,producer)
            self.assertEqual(result["status"],"STOP_PRODUCER_REPAIR_FAILED")
            self.assertEqual(result["producer_attempts"],1)
            self.assertFalse(result["producer_repair_executed"])
            self.assertTrue(result["original_raw_preserved_local"])
            self.assertEqual(p.read_bytes(),original)

    def test_bounded_repair_cannot_pretend_to_change_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root,packet,p=self.make_bound_fixture(directory)
            p.write_text(json.dumps({"deliverable_created":{},"self_verdict":"PASS"}))
            packet["raw_output_sha256"]=hashlib.sha256(p.read_bytes()).hexdigest()
            result=validate_with_bounded_producer_repair(root,packet,lambda _,q,d: q)
            self.assertEqual(result["status"],"STOP_REPAIR_NO_OUTPUT_DELTA")
            self.assertEqual(result["producer_attempts"],1)

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
