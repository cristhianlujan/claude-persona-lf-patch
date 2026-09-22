from __future__ import annotations

import inspect
import json
import tempfile
import unittest
from pathlib import Path

from profile_runtime_api.engine import ProfileRuntimeEngine
from profile_runtime_api.models import ProfileTask
from profile_runtime_api.repository import RepositoryBindings, RepositoryError
from profile_runtime_api.validation import OutputGates


class GenericRuntimeBindingTest(unittest.TestCase):
    def _repo(self) -> tuple[tempfile.TemporaryDirectory, Path, RepositoryBindings]:
        tmp=tempfile.TemporaryDirectory(); root=Path(tmp.name)
        (root/'profiles/p/contracts').mkdir(parents=True)
        (root/'profiles/p/schemas').mkdir(parents=True)
        (root/'profiles/p/validators').mkdir(parents=True)
        (root/'profiles/p/SKILL.md').write_text('# P\n## Purpose\nVisible purpose.\n## Internal\nOMIT_ME\n')
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




    def test_external_evidence_manifest_is_forwarded_to_validator_and_utility(self):
        tmp,root,repo=self._repo()
        try:
            (root/'profiles/p/validators/runtime_validate.py').write_text(
                'def validate(payload, evidence_manifest=None):\n'
                '    if not isinstance(evidence_manifest, dict) or evidence_manifest.get("marker") != "trusted":\n'
                '        return ["MANIFEST_NOT_DELIVERED_TO_VALIDATOR"]\n'
                '    return []\n'
            )
            (root/'profiles/p/validators/runtime_semantic_utility.py').write_text(
                'def evaluate(payload, contract_gate, evidence_manifest=None):\n'
                '    ok = isinstance(evidence_manifest, dict) and evidence_manifest.get("marker") == "trusted"\n'
                '    return {"status":"PASS" if ok else "FAIL","blocking_codes":[] if ok else ["MANIFEST_NOT_DELIVERED_TO_UTILITY"]}\n'
            )
            gates=OutputGates(repo)
            schema=repo.runtime_schema('p')
            manifest={'marker':'trusted','evidence':[{'evidence_id':'EV-1'}]}
            contract,payload=gates.contract(
                profile_slug='p',
                raw_output='{"answer":"good"}',
                schema=schema,
                evidence_manifest=manifest,
            )
            self.assertEqual(contract['status'],'PASS')
            semantic=gates.semantic_utility(
                profile_slug='p',
                payload=payload,
                contract_gate=contract,
                evidence_manifest=manifest,
            )
            self.assertEqual(semantic['status'],'PASS')

            missing,_=gates.contract(
                profile_slug='p',
                raw_output='{"answer":"good"}',
                schema=schema,
            )
            self.assertEqual(missing['status'],'FAIL')
            self.assertIn('MANIFEST_NOT_DELIVERED_TO_VALIDATOR',missing['blocking_codes'])
        finally:
            tmp.cleanup()

    def test_profile_task_carries_external_manifest_but_rejects_empty_manifest(self):
        task=ProfileTask(
            request_id='REQ-1',
            profile_code='PERFIL-P',
            profile_slug='p',
            profile_source_paths=['profiles/p/SKILL.md'],
            input_literal='test',
            evidence_manifest={'manifest_version':'TEST','evidence':[]},
        )
        self.assertEqual(task.evidence_manifest['manifest_version'],'TEST')
        with self.assertRaises(ValueError):
            ProfileTask(
                request_id='REQ-2',
                profile_code='PERFIL-P',
                profile_slug='p',
                profile_source_paths=['profiles/p/SKILL.md'],
                input_literal='test',
                evidence_manifest={},
            )

    def test_engine_forwards_profile_task_manifest_to_both_output_gates(self):
        queue_source=inspect.getsource(ProfileRuntimeEngine._execute_queue_profile)
        artifact_source=inspect.getsource(ProfileRuntimeEngine._execute_profile)
        for source in (queue_source,artifact_source):
            self.assertIn('evidence_manifest=task.evidence_manifest',source)
            self.assertGreaterEqual(source.count('evidence_manifest=task.evidence_manifest'),2)


    def test_declared_model_context_partition_and_materialization(self):
        tmp,root,repo=self._repo()
        try:
            path=root/'profiles/p/contracts/runtime_binding.json'
            data=json.loads(path.read_text())
            data['model_context']={
                'full_source_to_model':False,
                'source_projection':{'mode':'MARKDOWN_SECTIONS','include_sections':['Purpose'],'max_chars':1000},
            }
            data['execution_partition']={
                'schema':'LF_PROFILE_EXECUTION_PARTITION_V1',
                'field_classes':{'answer':'DETERMINISTIC'},
                'deterministic_materialization':{'answer':{'source':'literal','value':'runtime-owned'}},
                'generation_limits':{'default_string_max_length':80,'fields':{}},
            }
            data['execution_budget']={
                'resource_class':'STANDARD','max_prompt_tokens':1024,'max_output_tokens':256,
                'min_available_memory_mb':0,'max_swap_used_pct':100,
            }
            path.write_text(json.dumps(data))
            canonical=repo.profile_sources('p',['profiles/p/SKILL.md'])
            projected=repo.profile_model_sources('p',canonical)
            self.assertIn('Visible purpose.',projected[0]['content'])
            self.assertNotIn('OMIT_ME',projected[0]['content'])
            schema=repo.runtime_schema('p')
            generation=repo.model_generation_schema('p',schema.payload)
            self.assertEqual(generation['properties'],{})
            self.assertEqual(generation['required'],[])
            materialized,added=repo.materialize_partitioned_output('p',{})
            self.assertEqual(materialized,{'answer':'runtime-owned'})
            self.assertEqual(added,['answer'])
        finally: tmp.cleanup()


    def test_canonical_quality_binding_is_exposed_and_fail_closed(self):
        tmp,root,repo=self._repo()
        try:
            profile_root=root/'profiles/p'
            (profile_root/'judges').mkdir(parents=True)
            (profile_root/'judges/mini.md').write_text('# judge\n')
            (profile_root/'judges/semantic.md').write_text('# semantic\n')
            (profile_root/'schemas/quality.json').write_text('{"type":"object"}')
            (profile_root/'validators/semantic_result.py').write_text('def evaluate(payload):\n    return {"status":"PASS","blocking_codes":[]}\n')
            (profile_root/'validators/quality_receipt.py').write_text('def validate_quality_receipt(*args):\n    return {"status":"PASS","blocking_codes":[]}\n')
            path=profile_root/'contracts/runtime_binding.json'
            data=json.loads(path.read_text())
            data['canonical_quality']={
                'required_for_profile_pack_ids':['PACK-V1'],
                'judge_path':'judges/mini.md',
                'semantic_judge_path':'judges/semantic.md',
                'semantic_result_validator':{'path':'validators/semantic_result.py','callable':'evaluate'},
                'quality_receipt_schema':'schemas/quality.json',
                'quality_receipt_validator':{'path':'validators/quality_receipt.py','callable':'validate_quality_receipt'},
                'deterministic_floors_can_accept_quality':False,
                'receipt_required_for_pass_to_quality_pack':True,
            }
            path.write_text(json.dumps(data))
            binding=repo.runtime_binding('p')
            self.assertIsNotNone(binding)
            self.assertEqual(binding.canonical_quality['required_for_profile_pack_ids'],['PACK-V1'])
            self.assertFalse(binding.canonical_quality['deterministic_floors_can_accept_quality'])
            self.assertTrue(binding.canonical_quality['receipt_required_for_pass_to_quality_pack'])

            data['canonical_quality']['deterministic_floors_can_accept_quality']=True
            path.write_text(json.dumps(data))
            with self.assertRaises(RepositoryError) as cm:
                repo.runtime_binding('p')
            self.assertEqual(cm.exception.code,'PROFILE_RUNTIME_CANONICAL_QUALITY_INVALID')
        finally:
            tmp.cleanup()



    def test_canonical_quality_gate_consumes_bound_semantic_and_receipt_validators(self):
        tmp,root,repo=self._repo()
        try:
            profile_root=root/'profiles/p'
            (profile_root/'judges').mkdir(parents=True)
            (profile_root/'judges/mini.md').write_text('# judge\n')
            (profile_root/'judges/semantic.md').write_text('# semantic\n')
            (profile_root/'schemas/quality.json').write_text(
                json.dumps({
                    '$schema':'https://json-schema.org/draft/2020-12/schema',
                    'type':'object',
                    'required':['decision'],
                    'properties':{'decision':{'const':'PASS'}},
                    'additionalProperties':False,
                })
            )
            (profile_root/'validators/semantic_result.py').write_text(
                'def evaluate(payload):\n'
                '    return {"status":"PASS","blocking_codes":[]} if payload.get("verdict")=="PASS" else {"status":"FAIL","blocking_codes":["SEMANTIC_BAD"]}\n'
            )
            (profile_root/'validators/quality_receipt.py').write_text(
                'def validate_quality_receipt(receipt,candidate,evidence_manifest,semantic_result):\n'
                '    ok = receipt.get("decision")=="PASS" and candidate.get("profile_pack_id")=="PACK-V1" and evidence_manifest.get("marker")=="trusted" and semantic_result.get("verdict")=="PASS"\n'
                '    return {"status":"PASS" if ok else "FAIL","blocking_codes":[] if ok else ["RECEIPT_BAD"]}\n'
            )
            path=profile_root/'contracts/runtime_binding.json'
            data=json.loads(path.read_text())
            data['canonical_quality']={
                'required_for_profile_pack_ids':['PACK-V1'],
                'judge_path':'judges/mini.md',
                'semantic_judge_path':'judges/semantic.md',
                'semantic_result_validator':{'path':'validators/semantic_result.py','callable':'evaluate'},
                'quality_receipt_schema':'schemas/quality.json',
                'quality_receipt_validator':{'path':'validators/quality_receipt.py','callable':'validate_quality_receipt'},
                'deterministic_floors_can_accept_quality':False,
                'receipt_required_for_pass_to_quality_pack':True,
            }
            path.write_text(json.dumps(data))
            gates=OutputGates(repo)
            result=gates.canonical_quality(
                profile_slug='p',
                candidate={'profile_pack_id':'PACK-V1'},
                evidence_manifest={'marker':'trusted'},
                semantic_result={'verdict':'PASS'},
                quality_receipt={'decision':'PASS'},
            )
            self.assertEqual(result['status'],'PASS')
            self.assertTrue(result['canonical_quality_accepted'])
            self.assertFalse(result['downstream_authorized'])

            bad=gates.canonical_quality(
                profile_slug='p',
                candidate={'profile_pack_id':'PACK-V1'},
                evidence_manifest={'marker':'trusted'},
                semantic_result={'verdict':'FAIL'},
                quality_receipt={'decision':'PASS'},
            )
            self.assertEqual(bad['status'],'FAIL')
            self.assertIn('SEMANTIC_BAD',bad['blocking_codes'])
        finally:
            tmp.cleanup()


    def test_weak_governance_fails_closed(self):
        tmp,root,repo=self._repo()
        try:
            path=root/'profiles/p/contracts/runtime_binding.json'; data=json.loads(path.read_text()); data['governance']['fail_closed']=False; path.write_text(json.dumps(data))
            with self.assertRaises(RepositoryError) as cm: repo.runtime_binding('p')
            self.assertEqual(cm.exception.code,'PROFILE_RUNTIME_BINDING_GOVERNANCE_WEAK')
        finally: tmp.cleanup()


if __name__=='__main__': unittest.main()
