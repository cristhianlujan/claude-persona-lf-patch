from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from profile_runtime_api.repository import RepositoryBindings, RepositoryError
from profile_runtime_api.validation import OutputGates


class GenericRuntimeBindingTest(unittest.TestCase):
    def _repo(self) -> tuple[tempfile.TemporaryDirectory, Path, RepositoryBindings]:
        tmp=tempfile.TemporaryDirectory(); root=Path(tmp.name)
        (root/'profiles/p/contracts').mkdir(parents=True)
        (root/'profiles/p/schemas').mkdir(parents=True)
        (root/'profiles/p/validators').mkdir(parents=True)
        (root/'sandbox/lf_contract_gate_test/profile_execution_runtime').mkdir(parents=True)
        (root/'sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3').mkdir(parents=True)
        (root/'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_runner.py').write_text('x=1\n')
        (root/'sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/structural_context_resolver_v3.py').write_text('x=1\n')
        schema={"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["answer"],"properties":{"answer":{"type":"string"}},"additionalProperties":False}
        (root/'profiles/p/schemas/output.schema.json').write_text(json.dumps(schema))
        (root/'profiles/p/schemas/alt.schema.json').write_text(json.dumps(schema))
        (root/'profiles/p/validators/runtime_validate.py').write_text('def validate(payload):\n    return [] if payload.get("answer") != "bad" else ["BAD_ANSWER"]\n')
        (root/'profiles/p/validators/runtime_semantic_utility.py').write_text('def evaluate(payload, contract_gate):\n    return {"status":"PASS","blocking_codes":[]} if len(payload.get("answer", "")) >= 3 else {"status":"FAIL","blocking_codes":["ANSWER_TOO_SHALLOW"]}\n')
        binding={
          "schema":"LF_PROFILE_RUNTIME_BINDING_V1","profile_slug":"p","profile_code":"PERFIL-P",
          "runtime_schema":{"default":"schemas/output.schema.json","output_modes":{"ALT":"schemas/alt.schema.json"}},
          "canonical_validator":{"path":"validators/runtime_validate.py","callable":"validate"},
          "semantic_utility":{"path":"validators/runtime_semantic_utility.py","callable":"evaluate"},
          "governance":{"source_first_required":True,"schema_invention_allowed":False,"fail_closed":True,"exact_head_evidence_required":True,"post_update_baseline_required":True}
        }
        (root/'profiles/p/contracts/runtime_binding.json').write_text(json.dumps(binding))
        return tmp,root,RepositoryBindings(root,max_prompt_chars=10000)

    def test_generic_binding_schema_identity_and_plugins(self):
        tmp,root,repo=self._repo()
        try:
            repo.validate_profile_identity('p','PERFIL-P')
            with self.assertRaises(RepositoryError) as cm: repo.validate_profile_identity('p','WRONG')
            self.assertEqual(cm.exception.code,'PROFILE_RUNTIME_IDENTITY_BINDING_MISMATCH')
            self.assertTrue(repo.runtime_schema('p').source_refs[0].endswith('profiles/p/schemas/output.schema.json'))
            self.assertTrue(repo.runtime_schema('p','ALT').source_refs[0].endswith('profiles/p/schemas/alt.schema.json'))
            with self.assertRaises(RepositoryError) as cm2: repo.runtime_schema('p','UNKNOWN')
            self.assertEqual(cm2.exception.code,'RUNTIME_OUTPUT_MODE_UNSUPPORTED')
            gates=OutputGates(repo)
            schema=repo.runtime_schema('p')
            contract,payload=gates.contract(profile_slug='p',raw_output='{"answer":"good"}',schema=schema)
            self.assertEqual(contract['status'],'PASS')
            self.assertEqual(gates.semantic_utility(profile_slug='p',payload=payload,contract_gate=contract)['status'],'PASS')
            contract_bad,_=gates.contract(profile_slug='p',raw_output='{"answer":"bad"}',schema=schema)
            self.assertEqual(contract_bad['status'],'FAIL')
            self.assertIn('BAD_ANSWER',contract_bad['blocking_codes'])
            contract_short,payload_short=gates.contract(profile_slug='p',raw_output='{"answer":"ok"}',schema=schema)
            self.assertEqual(contract_short['status'],'PASS')
            semantic=gates.semantic_utility(profile_slug='p',payload=payload_short,contract_gate=contract_short)
            self.assertEqual(semantic['status'],'FAIL')
            self.assertIn('ANSWER_TOO_SHALLOW',semantic['blocking_codes'])
        finally: tmp.cleanup()

    def test_weak_governance_fails_closed(self):
        tmp,root,repo=self._repo()
        try:
            path=root/'profiles/p/contracts/runtime_binding.json'; data=json.loads(path.read_text()); data['governance']['fail_closed']=False; path.write_text(json.dumps(data))
            with self.assertRaises(RepositoryError) as cm: repo.runtime_binding('p')
            self.assertEqual(cm.exception.code,'PROFILE_RUNTIME_BINDING_GOVERNANCE_WEAK')
        finally: tmp.cleanup()


if __name__=='__main__': unittest.main()
