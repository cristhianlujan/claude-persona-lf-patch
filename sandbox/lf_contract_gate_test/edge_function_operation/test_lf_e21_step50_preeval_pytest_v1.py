"""E21 Step50 Python/pytest same-code source contract, no model/DB writes."""
import importlib.util
import json
import os
os.environ.setdefault('LF_PROFILE_EDGE_URL','https://test.invalid')
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
SPEC=importlib.util.spec_from_file_location(
    "lf_profile_native_resume_e21", ROOT/"scripts/lf_profile_native_resume.py")
MODULE=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
CHECK=MODULE.require_step50_verified_effect_shape
TARGET="profiles/systemic_root_cause_repair_lf/SKILL.md"

def granted():
    return {"execution_write_mode":"GOVERNED_REPAIR_WRITE",
            "repair_execution_authority":{"promotion_allowed":True,"mode":"GOVERNED_REPAIR_WRITE"}}

def denied():
    return {"execution_write_mode":"GOVERNED_REPAIR_WRITE",
            "repair_execution_authority":{"promotion_allowed":False,"mode":"GOVERNED_REPAIR_WRITE"}}

def effect():
    code="B2B-RULE-AUTH-004"
    ref="supabase://lf_ops.reglas/"+code
    return {"repair_execution":{
      "mode":"EXECUTED_WITH_READBACK",
      "changes":[{"target_ref":ref,"change_type":"MODIFY",
                  "before_ref":ref+"/before","after_ref":ref+"/after"}],
      "rule_receipts":[{
        "rule_code":code,"source_ref":ref,
        "before_sha256":"a"*64,"after_sha256":"b"*64,
        "train_execution_id":"EXEC-DB-TRAIN-PR4100-20261116102000-R44444444",
        "train_pr":4100,"train_run_id":"44444444",
        "migration_version":"20261116102000",
        "migration_name":"lf_e21_fixture_test_only_v1","merge_sha":"c"*40,
      }]
    }}

class Step50PythonTest(unittest.TestCase):
    def expect_code(self, raw, auth, code):
        with self.assertRaisesRegex(ValueError,"^"+code+"$"):
            CHECK(TARGET,raw,auth)

    def test_promotion_false_allows_authorized_not_executed(self):
        raw={"repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED"}}
        self.assertIsNone(CHECK(TARGET,raw,denied()))

    def test_promotion_true_forbids_authorized_not_executed(self):
        raw={"repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED"}}
        self.expect_code(raw,granted(),"STEP50_AUTHORIZED_NOT_EXECUTED_FORBIDDEN")


    def test_readonly_null_repair_authority_accepted_no_effect(self):
        # Positive: SQL READ_ONLY can legitimately omit a repair authority.
        raw={"repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED"}}
        self.assertIsNone(CHECK(TARGET,raw,{
            "execution_write_mode":"READ_ONLY","repair_execution_authority":None
        }))
        self.assertIsNone(CHECK(TARGET,raw,{"execution_write_mode":"READ_ONLY"}))
        self.assertIsNone(CHECK(TARGET,raw,{
            "execution_write_mode":"READ_ONLY",
            "repair_execution_authority":{"promotion_allowed":False}
        }))

    def test_readonly_rejects_effect_and_any_promotion_authority(self):
        # Negative: READ_ONLY must never be turned into a write/promotion lane.
        self.expect_code(effect(),{"execution_write_mode":"READ_ONLY",
             "repair_execution_authority":None},"STEP50_READ_ONLY_EFFECT_FORBIDDEN")
        raw={"repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED",
             "changes":[{"target_ref":"supabase://lf_ops.reglas/B2B-RULE-AUTH-004"}]}}
        self.expect_code(raw,{"execution_write_mode":"READ_ONLY",
             "repair_execution_authority":None},"STEP50_READ_ONLY_EFFECT_FORBIDDEN")
        self.expect_code({"repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED"}},
            {"execution_write_mode":"READ_ONLY",
             "repair_execution_authority":{"promotion_allowed":True}},
            "STEP50_PROMOTION_REPAIR_AUTHORITY_MISMATCH")

    def test_governed_write_still_requires_exact_repair_authority(self):
        self.expect_code(effect(),{"execution_write_mode":"GOVERNED_REPAIR_WRITE",
             "repair_execution_authority":None},"STEP50_SERVER_AUTHORITY_NOT_BOUND")
        self.expect_code({"repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED"}},
            granted(),"STEP50_AUTHORIZED_NOT_EXECUTED_FORBIDDEN")

    def test_missing_before_after_fail_closed(self):
        raw=effect()
        del raw["repair_execution"]["rule_receipts"][0]["before_sha256"]
        self.expect_code(raw,granted(),"STEP50_EFFECT_HASH_PAIR_REQUIRED")
        raw=effect()
        del raw["repair_execution"]["rule_receipts"][0]["after_sha256"]
        self.expect_code(raw,granted(),"STEP50_EFFECT_HASH_PAIR_REQUIRED")

    def test_other_rule_source_ref_fail_closed(self):
        raw=effect()
        raw["repair_execution"]["rule_receipts"][0]["source_ref"] = "supabase://lf_ops.reglas/B2B-RULE-AUTH-049"
        self.expect_code(raw,granted(),"STEP50_RULE_RECEIPT_SOURCE_REF_MISMATCH")

    def test_duplicate_rule_receipt_rejected(self):
        raw=effect()
        raw["repair_execution"]["rule_receipts"] *= 2
        raw["repair_execution"]["changes"] *= 2
        self.expect_code(raw,granted(),"STEP50_RULE_RECEIPT_DUPLICATE")

    def test_trusted_shape_only_not_attestation(self):
        self.assertIsNone(CHECK(TARGET,effect(),granted()))
        # Server's DB-backed guard is REQUIRED before persistence.
        mig=(ROOT/"supabase/migrations")
        matches=list(mig.glob("*_lf_e21_step50_verified_real_effect_v1.sql"))
        self.assertEqual(len(matches),1)
        sql=matches[0].read_text()
        self.assertIn("v_step50_effect:=public.lf_profile_step50_rule_effect_guard_v1(p_execution_id,p_profile_output);",sql)
        self.assertIn("STEP50_EFFECT_NOT_ATTESTED",sql)
        self.assertIn("STEP50_TRAIN_RECEIPT_NOT_VERIFIED",sql)
        self.assertIn("STEP50_EFFECT_AFTER_NOT_CURRENT",sql)

    def test_json_schema_requires_source_bound_train_receipt_fields(self):
        schema=json.loads((ROOT/"profiles/systemic_root_cause_repair_lf/schemas/output.schema.json").read_text())
        field=schema["properties"]["repair_execution"]["anyOf"][1]["properties"]["rule_receipts"]
        needed={"rule_code","source_ref","before_sha256","after_sha256",
                "train_execution_id","train_pr","train_run_id","migration_version","migration_name","merge_sha"}
        self.assertTrue(needed.issubset(field["items"]["required"]))
        self.assertFalse(field["items"]["additionalProperties"])

# Pytest also collects these same positive/negative unittest cases:
# python -m pytest -q sandbox/lf_contract_gate_test/edge_function_operation/test_lf_e21_step50_preeval_pytest_v1.py
if __name__=="__main__":unittest.main()
