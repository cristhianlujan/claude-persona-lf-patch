"""P2 Step60: canonical mode dispatch and fail-closed negative cases (no external RUN)."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import shutil

ROOT=Path(__file__).resolve().parents[3]
SCRIPT=ROOT/"scripts/lf_profile_native_resume.py"
PROFILE=ROOT/"profiles/product_director_lf"

class ProductDirectorOutputModes(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        for rel in (
            "contracts/runtime_binding.json",
            "schemas/product_direction_spec.schema.json",
            "schemas/product_missing_input.schema.json",
            "schemas/product_blocked_risk.schema.json",
            "validators/validate_product_director_output.py",
        ):
            dst=self.root/"profiles/product_director_lf"/rel
            dst.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(PROFILE/rel,dst)
        spec=importlib.util.spec_from_file_location("lf_p2_resume",SCRIPT)
        mod=importlib.util.module_from_spec(spec)
        with patch.dict(os.environ,{"LF_PROFILE_EDGE_URL":"https://invalid.example.test"},clear=False):
            spec.loader.exec_module(mod)
        self.fn=mod.run_bound_validator
        self.target="profiles/product_director_lf/SKILL.md"
        self.profile="PERFIL-PRODUCT-DIRECTOR-LF"

    def run_case(self,raw):
        receipt={
            "status":"CANDIDATE_OUTPUT_PARITY_OBSERVED",
            "structural_check_executed":True,
            "profile_validator_executed":True,
            "source_readback_matched":True,
            "blocking_codes":[]
        }
        from unittest.mock import Mock
        with patch.dict(os.environ,{"GITHUB_REPOSITORY":"test-owner/test-repo"},clear=False), \
             patch.object(Path,"cwd",return_value=self.root), \
             patch.object(self.fn.__globals__["subprocess"],"run",
               return_value=Mock(returncode=0,stdout=json.dumps(receipt).encode(),stderr=b"")):
            output=self.fn(self.target,self.profile,raw)
        bound=json.loads((self.root/"profile-native-validation-binding.json").read_text())
        return bound,output

    def test_missing_input_uses_canonical_missing_schema(self):
        raw={"worker":"product_director_lf","output_type":"PRODUCT_MISSING_INPUT_STATE",
             "self_verdict":"NEEDS_INPUT",
             "deliverable_created":{"missing_fields":["policy"],"why_blocking":"No policy authority",
                                    "next_input_needed":"Current canonical policy"}}
        binding,result=self.run_case(raw)
        self.assertEqual(binding["schema_ref"],"profiles/product_director_lf/schemas/product_missing_input.schema.json")
        self.assertEqual(result[0]["status"],"CANDIDATE_OUTPUT_PARITY_OBSERVED")

    def test_product_spec_uses_product_spec_schema(self):
        bound,_=self.run_case({"output_type":"PRODUCT_DIRECTION_SPEC"})
        self.assertEqual(bound["schema_ref"],"profiles/product_director_lf/schemas/product_direction_spec.schema.json")

    def test_blocked_product_risk_uses_blocked_schema(self):
        bound,_=self.run_case({"output_type":"BLOCKED_PRODUCT_RISK"})
        self.assertEqual(bound["schema_ref"],"profiles/product_director_lf/schemas/product_blocked_risk.schema.json")

    def test_unknown_mode_fails_closed_at_selector(self):
        with patch.object(Path,"cwd",return_value=self.root):
            with self.assertRaisesRegex(ValueError,"PROFILE_OUTPUT_MODE_UNDECLARED"):
                self.fn(self.target,self.profile,{"output_type":"SOME_UNDECLARED_MODE"})

    def test_absent_mode_selects_declared_default_but_schema_rejects_missing_type(self):
        # The shared selector deliberately resolves AUTO/absent form to default.
        # Absence is rejected by the canonical schema, not by mode dispatch.
        from jsonschema import Draft202012Validator
        import importlib.util

        binding=json.loads((self.root/"profiles/product_director_lf/contracts/runtime_binding.json").read_text())
        selector_path=ROOT/"services/profile_runtime_api/profile_runtime_api/runtime_schema_selection.py"
        spec=importlib.util.spec_from_file_location("lf_p2_real_selector",selector_path)
        selector=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(selector)
        selected=selector.select_schema_relative(binding["runtime_schema"],payload={})
        self.assertEqual(selected,"schemas/product_direction_spec.schema.json")
        schema=json.loads((self.root/"profiles/product_director_lf"/selected).read_text())
        missing=list(Draft202012Validator(schema).iter_errors({}))
        self.assertTrue(missing)
        self.assertTrue(any("output_type" in err.message for err in missing))

    def test_actual_canonical_json_schema_positive_and_negative(self):
        from jsonschema import Draft202012Validator
        raw={"worker":"product_director_lf","output_type":"PRODUCT_MISSING_INPUT_STATE",
             "self_verdict":"NEEDS_INPUT",
             "deliverable_created":{"missing_fields":["policy"],"why_blocking":"Missing authority",
                                    "next_input_needed":"Canonical owner policy"}}
        schema=json.loads((PROFILE/"schemas/product_missing_input.schema.json").read_text())
        wrong=json.loads((PROFILE/"schemas/product_direction_spec.schema.json").read_text())
        self.assertFalse(list(Draft202012Validator(schema).iter_errors(raw)))
        self.assertTrue(list(Draft202012Validator(wrong).iter_errors(raw)))
        invalid={**raw,"self_verdict":"PASS"}
        self.assertTrue(list(Draft202012Validator(schema).iter_errors(invalid)))

if __name__=="__main__":unittest.main()
