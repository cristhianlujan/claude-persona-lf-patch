"""IG P2: Step60 source-bound per-output-mode schema. No RUN/DB writes."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
RUNNER=ROOT/"skills/profile_creator/validators/run_bound_profile_output_validator_v1.py"
SPEC=importlib.util.spec_from_file_location("p2_bound_runner", RUNNER)
M=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)
BIND=ROOT/"profiles/product_director_lf/contracts/runtime_binding.json"
PROFILE=ROOT/"profiles/product_director_lf"
VALIDATOR=PROFILE/"validators/validate_product_director_output.py"
SHA=lambda b:hashlib.sha256(b).hexdigest()

def missing():
 return {"worker":"product_director_lf","output_type":"PRODUCT_MISSING_INPUT_STATE",
  "self_verdict":"NEEDS_INPUT","deliverable_created":{
  "missing_fields":["current eligibility policy"],
  "why_blocking":"Material eligibility cannot be inferred from evidence.",
  "next_input_needed":"Current authoritative policy for target account."}}

def risk():
 return {"worker":"product_director_lf","output_type":"BLOCKED_PRODUCT_RISK",
  "self_verdict":"BLOCKED_PRODUCT_RISK","deliverable_created":{
  "blockers":["Missing official authorization for protected state"]}}

class P2ProductOutputModes(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(prefix=".lf-p2-step60-",dir=ROOT)
  self.addCleanup(self.tmp.cleanup)
  self.raw=Path(self.tmp.name)/"candidate.json"
  self.bind=json.loads(BIND.read_text(encoding="utf8"))
 def packet(self, raw, mode, schema_override=None):
  self.raw.write_text(json.dumps(raw,sort_keys=True),encoding="utf8")
  rel=(schema_override or self.bind["runtime_schema"]["output_modes"][mode])
  schema=PROFILE/rel
  return {"schema":"PROFILE_OUTPUT_VALIDATION_BINDING_V1",
    "operation_code":"EJECUCION_PERFIL_LF",
    "profile_slug":"product_director_lf","validator_transport":"STDIN_JSON",
    "expected_valid":True,"runtime_binding_sha256":SHA(BIND.read_bytes()),
    "output_type":mode,
    "schema_ref":str(schema.relative_to(ROOT)),
    "schema_sha256":SHA(schema.read_bytes()),
    "validator_ref":str(VALIDATOR.relative_to(ROOT)),
    "validator_sha256":SHA(VALIDATOR.read_bytes()),
    "raw_output_ref":str(self.raw.relative_to(ROOT)),
    "raw_output_sha256":SHA(self.raw.read_bytes())}
 def test_valid_missing_input_no_longer_rejected_by_spec(self):
  p=self.packet(missing(),"PRODUCT_MISSING_INPUT_STATE")
  result=M.validate_bound_output(ROOT,p)
  self.assertEqual(result["status"],"CANDIDATE_OUTPUT_PARITY_OBSERVED",result)
  self.assertTrue(result["structural_check_executed"])
  self.assertTrue(result["profile_validator_executed"])
  self.assertTrue(result["source_readback_matched"])
 def test_valid_blocked_risk_uses_exact_blocked_schema(self):
  p=self.packet(risk(),"BLOCKED_PRODUCT_RISK")
  result=M.validate_bound_output(ROOT,p)
  self.assertEqual(result["status"],"CANDIDATE_OUTPUT_PARITY_OBSERVED",result)
 def test_missing_input_cannot_impersonate_direction_spec(self):
  p=self.packet(missing(),"PRODUCT_DIRECTION_SPEC")
  result=M.validate_bound_output(ROOT,p)
  self.assertIn("RUNTIME_OUTPUT_MODE_CANDIDATE_MISMATCH",result["blocking_codes"])
 def test_schema_forgery_rejected_even_with_valid_missing(self):
  p=self.packet(missing(),"PRODUCT_MISSING_INPUT_STATE",
    "schemas/product_direction_spec.schema.json")
  result=M.validate_bound_output(ROOT,p)
  self.assertIn("RUNTIME_BINDING_SOURCE_NOT_CANONICAL",result["blocking_codes"])
 def test_unregistered_mode_rejected(self):
  p=self.packet(missing(),"PRODUCT_MISSING_INPUT_STATE")
  p["output_type"]="UNREGISTERED_MODE"
  result=M.validate_bound_output(ROOT,p)
  self.assertIn("RUNTIME_OUTPUT_MODE_UNSUPPORTED",result["blocking_codes"])
 def test_invalid_missing_input_remains_blocked(self):
  raw=missing();raw["deliverable_created"]["missing_fields"]=[]
  p=self.packet(raw,"PRODUCT_MISSING_INPUT_STATE")
  result=M.validate_bound_output(ROOT,p)
  self.assertIn("OUTPUT_SHAPE_INVALID",result["blocking_codes"])

if __name__=="__main__":unittest.main()
