"""Inspect exact model-authored V0.6 RAW bound to execution 100EAF, no external writes."""
import importlib.util
import json
import unittest
from pathlib import Path
from jsonschema import Draft7Validator

ROOT=Path(__file__).resolve().parents[3]
PROFILE=ROOT/"profiles/systemic_root_cause_repair_lf"
CANDIDATE=Path(__file__).with_name("fixtures")/"b2b_srcr_raw_v06_bound_candidate_20261115.json"

def resolve_validator():
    path=PROFILE/"validators/runtime_validate.py"
    spec=importlib.util.spec_from_file_location("b2b_srcr_runtime_validate_current",path)
    module=importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module.validate

class B2BSRCRNativeV06RawContract(unittest.TestCase):
    def test_bound_validator_and_schema_on_exact_raw(self):
        envelope=json.loads(CANDIDATE.read_text(encoding="utf-8"))
        c,m=envelope["candidate"],envelope["evidence_manifest"]
        schema=json.loads((PROFILE/"schemas/output.schema.json").read_text(encoding="utf-8"))
        schema_errors=sorted(Draft7Validator(schema).iter_errors(c),key=lambda e:list(map(str,e.path)))
        result=resolve_validator()(c,m)
        codes=[f"{e.get('code')} @ {e.get('path')}: {e.get('message','')}" for e in result.get("errors",[])]
        print("SRCR_SCHEMA_ERRORS",json.dumps([{"path":".".join(map(str,e.path)),"message":e.message[:250],"nested":[{"path":".".join(map(str,z.path)),"message":z.message[:240]} for z in e.context[:12]]} for e in schema_errors],ensure_ascii=False))
        print("SRCR_RUNTIME_BLOCKING",json.dumps(codes[:125],ensure_ascii=False))
        print("SRCR_RUNTIME_STATUS",result.get("status"),"VALID",result.get("valid"),"COUNT",len(codes))
        self.assertEqual([],schema_errors)
        self.assertEqual([],codes)
        self.assertIs(result.get("valid"),True)
        self.assertEqual("SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6",c["profile_pack_id"])
        self.assertIs(c["repair_execution"]["promotion_performed"],False)
        self.assertEqual("EXECUTED_WITH_READBACK",c["repair_execution"]["mode"])
if __name__=="__main__":
    unittest.main()
