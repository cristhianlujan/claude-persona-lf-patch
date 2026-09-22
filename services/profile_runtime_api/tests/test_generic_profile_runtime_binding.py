from __future__ import annotations

import inspect
import json
import tempfile
import unittest
from pathlib import Path

from profile_runtime_api.engine import ProfileRuntimeEngine, _model_context_readback, _validate_research_execution
from profile_runtime_api.models import ProfileTask
from profile_runtime_api.repository import RepositoryBindings, RepositoryError
from profile_runtime_api.validation import OutputGates
from profile_runtime_api.hashing import canonical_json_sha256
from types import SimpleNamespace


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

    def test_manifest_digest_is_observable_at_validator_and_utility(self):
        tmp,root,repo=self._repo()
        try:
            (root/'profiles/p/validators/runtime_validate.py').write_text(
                'def validate(payload, evidence_manifest=None):\\n    return []\\n'
            )
            (root/'profiles/p/validators/runtime_semantic_utility.py').write_text(
                'def evaluate(payload, contract_gate, evidence_manifest=None):\\n    return {"status":"PASS","blocking_codes":[]}\\n'
            )
            gates=OutputGates(repo)
            schema=repo.runtime_schema('p')
            manifest={'marker':'trusted','evidence':[{'evidence_id':'EV-1'}]}
            expected=canonical_json_sha256(manifest)
            contract,payload=gates.contract(
                profile_slug='p',raw_output='{"answer":"good"}',schema=schema,evidence_manifest=manifest
            )
            semantic=gates.semantic_utility(
                profile_slug='p',payload=payload,contract_gate=contract,evidence_manifest=manifest
            )
            self.assertEqual(contract['evidence_manifest_sha256'],expected)
            self.assertEqual(semantic['evidence_manifest_sha256'],expected)
        finally:
            tmp.cleanup()

    def test_model_context_readback_binds_exact_sources_and_manifest(self):
        sources=[{'ref':'profiles/p/SKILL.md','content':'abc'},{'ref':'profiles/p/contracts/main.md','content':'xyz'}]
        manifest={'bundle_id':'B','evidence':[{'evidence_id':'EV-1'}]}
        readback=_model_context_readback(sources,manifest)
        self.assertEqual(readback['total_chars'],6)
        self.assertEqual(readback['evidence_manifest_sha256'],canonical_json_sha256(manifest))
        self.assertEqual(len(readback['source_manifest']),2)
        self.assertEqual(readback['source_manifest_sha256'],canonical_json_sha256(readback['source_manifest']))

    def test_external_research_resolver_fails_closed_without_trace_or_context_binding(self):
        binding=SimpleNamespace(research_execution={
            'mode':'EXTERNAL_AUTHORITY_RESOLVER','resolver_ref':'contracts/evidence_manifest.schema.json',
            'requires_evidence_manifest':True,'requires_query_trace':True,'requires_resolved_authority_context':True,
        })
        base_manifest={
            'evidence':[{'evidence_id':'EV-1'}],
            'query_trace':[{
                'query_id':'Q1','emitted_evidence_ids':['EV-1']
            }],
        }
        manifest_sha='sha256:'+canonical_json_sha256(base_manifest)
        good_task=SimpleNamespace(
            evidence_manifest=base_manifest,
            governed_operation=SimpleNamespace(context_capsule={
                'resolved_authority_context':{'EV-1':{'fact':'x'}},
                'evidence_manifest_sha256':manifest_sha,
            }),
        )
        readback=_validate_research_execution(good_task,binding)
        self.assertEqual(readback['query_count'],1)
        self.assertEqual(readback['evidence_count'],1)
        self.assertEqual(readback['evidence_manifest_sha256'],manifest_sha)

        no_trace=SimpleNamespace(
            evidence_manifest={'evidence':[{'evidence_id':'EV-1'}]},
            governed_operation=good_task.governed_operation,
        )
        with self.assertRaises(Exception) as cm:
            _validate_research_execution(no_trace,binding)
        self.assertEqual(getattr(cm.exception,'code',None),'SRCR_QUERY_TRACE_REQUIRED_BEFORE_MODEL')

        orphan_manifest={
            'evidence':[{'evidence_id':'EV-1'},{'evidence_id':'EV-2'}],
            'query_trace':[{'query_id':'Q1','emitted_evidence_ids':['EV-1']}],
        }
        orphan=SimpleNamespace(
            evidence_manifest=orphan_manifest,
            governed_operation=SimpleNamespace(context_capsule={
                'resolved_authority_context':{'EV-1':{'fact':'x'}},
                'evidence_manifest_sha256':'sha256:'+canonical_json_sha256(orphan_manifest),
            }),
        )
        with self.assertRaises(Exception) as cm2:
            _validate_research_execution(orphan,binding)
        self.assertEqual(getattr(cm2.exception,'code',None),'SRCR_EVIDENCE_WITHOUT_RECORDED_RETRIEVAL')

        bad_digest=SimpleNamespace(
            evidence_manifest=base_manifest,
            governed_operation=SimpleNamespace(context_capsule={
                'resolved_authority_context':{'EV-1':{'fact':'x'}},
                'evidence_manifest_sha256':'sha256:'+'0'*64,
            }),
        )
        with self.assertRaises(Exception) as cm3:
            _validate_research_execution(bad_digest,binding)
        self.assertEqual(getattr(cm3.exception,'code',None),'SRCR_RESOLVED_AUTHORITY_MANIFEST_DIGEST_MISMATCH')

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
                'required_source_refs':['profiles/p/SKILL.md'],
                'allow_additional_sources':False,
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
            (profile_root/'validators/materialize_quality_receipt.py').write_text('def materialize_quality_receipt(*args, **kwargs):\n    return {"decision":"PASS"}\n')
            path=profile_root/'contracts/runtime_binding.json'
            data=json.loads(path.read_text())
            data['canonical_quality']={
                'required_for_profile_pack_ids':['PACK-V1'],
                'judge_path':'judges/mini.md',
                'semantic_judge_path':'judges/semantic.md',
                'semantic_result_validator':{'path':'validators/semantic_result.py','callable':'evaluate'},
                'quality_receipt_schema':'schemas/quality.json',
                'quality_receipt_validator':{'path':'validators/quality_receipt.py','callable':'validate_quality_receipt'},
                'quality_receipt_materializer':{'path':'validators/materialize_quality_receipt.py','callable':'materialize_quality_receipt'},
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
                '    return {"status":"PASS" if ok else "FAIL","blocking_codes":[] if ok else ["RECEIPT_BAD"],"canonical_quality_accepted":ok}\n'
            )
            (profile_root/'validators/materialize_quality_receipt.py').write_text(
                'def materialize_quality_receipt(*args, **kwargs):\n'
                '    return {"decision":"PASS"}\n'
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
                'quality_receipt_materializer':{'path':'validators/materialize_quality_receipt.py','callable':'materialize_quality_receipt'},
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



    def test_canonical_quality_binding_is_consumed_by_runtime_boundary(self):
        tmp,root,repo=self._repo()
        try:
            (root/'profiles/p/judges').mkdir(parents=True)
            (root/'profiles/p/judges/judge.md').write_text('# Judge\n')
            (root/'profiles/p/judges/semantic.md').write_text('# Semantic\n')
            (root/'profiles/p/schemas/quality.json').write_text(json.dumps({
                '$schema':'https://json-schema.org/draft/2020-12/schema',
                'type':'object',
                'additionalProperties':True,
            }))
            (root/'profiles/p/validators/semantic_result.py').write_text(
                'def evaluate(payload):\n    return {"status":"PASS","blocking_codes":[]}\n'
            )
            (root/'profiles/p/validators/quality_receipt.py').write_text(
                'def validate_quality_receipt(receipt,candidate,evidence,semantic):\n'
                '    return {"status":"PASS","blocking_codes":[]}\n'
            )
            (root/'profiles/p/validators/materialize_quality.py').write_text(
                'def materialize_quality_receipt(*args,**kwargs):\n    return {}\n'
            )
            path=root/'profiles/p/contracts/runtime_binding.json'
            data=json.loads(path.read_text())
            data['canonical_quality']={
                'required_for_profile_pack_ids':['PACK-V1'],
                'judge_path':'judges/judge.md',
                'semantic_judge_path':'judges/semantic.md',
                'semantic_result_validator':{
                    'path':'validators/semantic_result.py',
                    'callable':'evaluate',
                },
                'quality_receipt_schema':'schemas/quality.json',
                'quality_receipt_validator':{
                    'path':'validators/quality_receipt.py',
                    'callable':'validate_quality_receipt',
                },
                'deterministic_floors_can_accept_quality':False,
                'receipt_required_for_pass_to_quality_pack':True,
                'quality_receipt_materializer':{
                    'path':'validators/materialize_quality.py',
                    'callable':'materialize_quality_receipt',
                },
            }
            path.write_text(json.dumps(data))
            gates=OutputGates(repo)
            boundary=gates.canonical_quality_boundary(
                profile_slug='p',
                candidate={'profile_pack_id':'PACK-V1'},
                contract_gate={'status':'PASS','blocking_codes':[]},
                semantic_gate={'status':'PASS','blocking_codes':[]},
            )
            self.assertEqual(boundary['applicability'],'REQUIRED')
            self.assertEqual(boundary['status'],'PENDING_INDEPENDENT_SEMANTIC_REVIEW')
            self.assertFalse(boundary['canonical_quality_accepted'])
            self.assertFalse(boundary['deterministic_floors_can_accept_quality'])
            self.assertTrue(boundary['receipt_required_for_pass_to_quality_pack'])

            blocked=gates.canonical_quality_boundary(
                profile_slug='p',
                candidate={'profile_pack_id':'PACK-V1'},
                contract_gate={'status':'FAIL','blocking_codes':['BAD']},
                semantic_gate={'status':'NOT_EVALUATED','blocking_codes':['PROFILE_CONTRACT_INVALID']},
            )
            self.assertEqual(blocked['status'],'BLOCKED_BY_DETERMINISTIC_FLOORS')
            self.assertIn('BAD',blocked['blocking_codes'])
        finally:
            tmp.cleanup()


    def test_canonical_quality_finalize_binds_candidate_scope_and_independent_receipt(self):
        tmp,root,repo=self._repo()
        try:
            (root/'profiles/p/judges').mkdir(parents=True)
            (root/'profiles/p/judges/judge.md').write_text('# Judge\n')
            (root/'profiles/p/judges/semantic.md').write_text('# Semantic\n')
            (root/'profiles/p/schemas/quality.json').write_text(json.dumps({
                '$schema':'https://json-schema.org/draft/2020-12/schema',
                'type':'object',
                'required':['decision'],
                'properties':{'decision':{'type':'string'}},
                'additionalProperties':True,
            }))
            (root/'profiles/p/validators/semantic_result.py').write_text(
                'def evaluate(payload, scope_packet=None, expected_candidate_sha256=None, expected_scope_packet_sha256=None):\n'
                '    ok = payload.get("candidate_sha256")==expected_candidate_sha256 and payload.get("scope_packet_sha256")==expected_scope_packet_sha256 and isinstance(scope_packet, dict)\n'
                '    return {"status":"PASS" if ok else "FAIL","blocking_codes":[] if ok else ["BINDING_MISMATCH"]}\n'
            )
            (root/'profiles/p/validators/quality_receipt.py').write_text(
                'def validate_quality_receipt(receipt,candidate,evidence,semantic):\n'
                '    accepted = receipt.get("decision")=="PASS_TO_QUALITY_PACK"\n'
                '    return {"status":"PASS","blocking_codes":[],"canonical_quality_accepted":accepted}\n'
            )
            (root/'profiles/p/validators/materialize_quality.py').write_text(
                'def materialize_quality_receipt(candidate,evidence,semantic,**kwargs):\n'
                '    if kwargs.get("producer_execution_id")==kwargs.get("reviewer_execution_id"):\n'
                '        raise ValueError("NOT_INDEPENDENT")\n'
                '    return {"decision":"PASS_TO_QUALITY_PACK","reviewer_execution_id":kwargs.get("reviewer_execution_id")}\n'
            )
            binding_path=root/'profiles/p/contracts/runtime_binding.json'
            data=json.loads(binding_path.read_text())
            data['canonical_quality']={
                'required_for_profile_pack_ids':['PACK-V1'],
                'judge_path':'judges/judge.md',
                'semantic_judge_path':'judges/semantic.md',
                'semantic_result_validator':{'path':'validators/semantic_result.py','callable':'evaluate'},
                'quality_receipt_schema':'schemas/quality.json',
                'quality_receipt_validator':{'path':'validators/quality_receipt.py','callable':'validate_quality_receipt'},
                'deterministic_floors_can_accept_quality':False,
                'receipt_required_for_pass_to_quality_pack':True,
                'quality_receipt_materializer':{'path':'validators/materialize_quality.py','callable':'materialize_quality_receipt'},
            }
            binding_path.write_text(json.dumps(data))

            output_schema_path=root/'profiles/p/schemas/output.schema.json'
            output_schema=json.loads(output_schema_path.read_text())
            output_schema['properties']['profile_pack_id']={'const':'PACK-V1'}
            output_schema_path.write_text(json.dumps(output_schema))
            candidate={'profile_pack_id':'PACK-V1','answer':'good'}
            scope={'packet_version':'TEST','authorized_requirements':[]}
            from profile_runtime_api.hashing import canonical_json_sha256
            semantic={
                'candidate_sha256':canonical_json_sha256(candidate),
                'scope_packet_sha256':canonical_json_sha256(scope),
            }
            result=OutputGates(repo).canonical_quality_finalize(
                profile_slug='p',
                candidate=candidate,
                evidence_manifest={'bundle_id':'B','evidence':[{'evidence_id':'EV-1'}]},
                scope_authority_packet=scope,
                semantic_result=semantic,
                candidate_revision='rev-1',
                semantic_execution_receipt_ref='review://receipt/1',
                producer_execution_id='EXEC-PRODUCER-1',
                reviewer_execution_id='EXEC-REVIEWER-1',
                producer_execution_receipt_ref='producer://receipt/1',
                issued_at='2026-09-22T05:30:00Z',
            )
            self.assertEqual(result['status'],'PASS')
            self.assertTrue(result['canonical_quality_accepted'])
            self.assertEqual(result['quality_receipt']['reviewer_execution_id'],'EXEC-REVIEWER-1')

            tampered=dict(semantic,candidate_sha256='0'*64)
            rejected=OutputGates(repo).canonical_quality_finalize(
                profile_slug='p',
                candidate=candidate,
                evidence_manifest={'bundle_id':'B','evidence':[{'evidence_id':'EV-1'}]},
                scope_authority_packet=scope,
                semantic_result=tampered,
                candidate_revision='rev-1',
                semantic_execution_receipt_ref='review://receipt/1',
                producer_execution_id='EXEC-PRODUCER-1',
                reviewer_execution_id='EXEC-REVIEWER-1',
                producer_execution_receipt_ref='producer://receipt/1',
                issued_at='2026-09-22T05:30:00Z',
            )
            self.assertEqual(rejected['status'],'FAIL')
            self.assertIn('BINDING_MISMATCH',rejected['blocking_codes'])
        finally:
            tmp.cleanup()

    def test_structurally_valid_nonpass_receipt_does_not_accept_quality(self):
        tmp,root,repo=self._repo()
        try:
            (root/'profiles/p/judges').mkdir(parents=True)
            (root/'profiles/p/judges/judge.md').write_text('# Judge\n')
            (root/'profiles/p/judges/semantic.md').write_text('# Semantic\n')
            (root/'profiles/p/schemas/quality.json').write_text(json.dumps({
                '$schema':'https://json-schema.org/draft/2020-12/schema',
                'type':'object','additionalProperties':True,
            }))
            (root/'profiles/p/validators/semantic_result.py').write_text(
                'def evaluate(payload):\n    return {"status":"PASS","blocking_codes":[]}\n'
            )
            (root/'profiles/p/validators/quality_receipt.py').write_text(
                'def validate_quality_receipt(receipt,candidate,evidence,semantic):\n'
                '    return {"status":"PASS","blocking_codes":[],"canonical_quality_accepted":False}\n'
            )
            (root/'profiles/p/validators/materialize_quality.py').write_text(
                'def materialize_quality_receipt(*args,**kwargs):\n    return {}\n'
            )
            binding_path=root/'profiles/p/contracts/runtime_binding.json'
            data=json.loads(binding_path.read_text())
            data['canonical_quality']={
                'required_for_profile_pack_ids':['PACK-V1'],
                'judge_path':'judges/judge.md','semantic_judge_path':'judges/semantic.md',
                'semantic_result_validator':{'path':'validators/semantic_result.py','callable':'evaluate'},
                'quality_receipt_schema':'schemas/quality.json',
                'quality_receipt_validator':{'path':'validators/quality_receipt.py','callable':'validate_quality_receipt'},
                'deterministic_floors_can_accept_quality':False,
                'receipt_required_for_pass_to_quality_pack':True,
                'quality_receipt_materializer':{'path':'validators/materialize_quality.py','callable':'materialize_quality_receipt'},
            }
            binding_path.write_text(json.dumps(data))
            gate=OutputGates(repo).canonical_quality(
                profile_slug='p',
                candidate={'profile_pack_id':'PACK-V1'},
                evidence_manifest={'evidence':[]},
                semantic_result={},
                quality_receipt={},
            )
            self.assertEqual(gate['status'],'PASS')
            self.assertFalse(gate['canonical_quality_accepted'])
        finally:
            tmp.cleanup()


    def test_declared_model_context_requires_bound_source_set(self):
        tmp,root,repo=self._repo()
        try:
            path=root/'profiles/p/contracts/runtime_binding.json'
            data=json.loads(path.read_text())
            data['model_context']={
                'full_source_to_model':False,
                'required_source_refs':['profiles/p/SKILL.md','profiles/p/contracts/runtime_binding.json'],
                'allow_additional_sources':True,
                'source_projection':{'mode':'MARKDOWN_SECTIONS','include_sections':['Purpose'],'max_chars':5000},
            }
            path.write_text(json.dumps(data))
            with self.assertRaises(RepositoryError) as cm:
                repo.profile_sources('p',['profiles/p/SKILL.md'])
            self.assertEqual(cm.exception.code,'PROFILE_RUNTIME_REQUIRED_SOURCE_MISSING')

            sources=repo.profile_sources(
                'p',
                ['profiles/p/SKILL.md','profiles/p/contracts/runtime_binding.json'],
            )
            self.assertEqual(
                {item['ref'] for item in sources},
                {'profiles/p/SKILL.md','profiles/p/contracts/runtime_binding.json'},
            )
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
