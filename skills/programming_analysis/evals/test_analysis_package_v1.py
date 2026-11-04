import json
from pathlib import Path
import unittest
P=Path(__file__).resolve().parents[1]
REPO=P.parents[1]
M=json.loads((P/'contracts/analysis_skill_manifest_v1.json').read_text(encoding='utf-8'))
class AnalysisStagePackage(unittest.TestCase):
 def test_single_skill(self):
  self.assertEqual(M['skill_code'],'PROGRAMMING_ANALYSIS_LF')
  self.assertEqual(M['external_invocations'],1)
  self.assertFalse(M['standalone_a1_registration_allowed'])
 def test_15_steps(self):
  self.assertEqual([x['step_id'] for x in M['steps']],[f'A{i}' for i in range(1,16)])
 def test_internal_a1(self):
  self.assertTrue((P/'steps/a1/STEP.md').is_file())
  self.assertFalse((P/'steps/a1/SKILL.md').exists())
  self.assertFalse((REPO/'skills/programming_analysis_a1/SKILL.md').exists())
  self.assertEqual(M['steps'][0]['module_entrypoint'],'steps/a1/validators/run.py:run')
 def test_canonical_sources(self):
  for s in M['steps']:
   with self.subTest(step=s['step_id']):self.assertTrue((REPO/s['source_contract']).is_file(),s['source_contract'])
 def test_non_operational(self):
  self.assertEqual(M['status'],'CANDIDATE_SOURCE_ONLY_NOT_REGISTERED')
  self.assertTrue(all(not s['operationally_verified'] for s in M['steps']))
  self.assertFalse(M['real_model_receipts'])
  self.assertFalse(M['independent_judge_receipts'])
 def test_no_parallel_engine(self):
  self.assertTrue(M['no_router_to_skill_direct'])
  self.assertTrue(M['no_internal_parallel_runner'])
 def test_procedure_parity(self):
  src=json.loads((REPO/M['procedure_source']).read_text(encoding='utf-8'))
  self.assertEqual([s['source_contract'] for s in M['steps'][:9]],[s['source_contract'] for s in src['steps']])
 def test_a2_to_a15_are_not_fake_executors(self):
  self.assertTrue(all(s['module_entrypoint'] is None for s in M['steps'][1:]))
 def test_exactly_one_skill_file(self):
  self.assertEqual([x.relative_to(P).as_posix() for x in P.rglob('SKILL.md')],['SKILL.md'])
 def test_a1_step_envelope_identifies_parent(self):
  schema=json.loads((P/'steps/a1/schemas/output.schema.json').read_text(encoding='utf-8'))
  self.assertEqual(schema['properties']['skill_code']['const'],M['skill_code'])
  self.assertEqual(schema['properties']['schema_version']['const'],'A1_INTERNAL_STEP_CANDIDATE_RESULT_V1')
  self.assertEqual(schema['properties']['step_code']['const'],'A1')
 def test_operation_steps_are_not_analysis_steps(self):
  self.assertEqual(M['operation_code'],'EJECUCION_SKILL_LF')
  self.assertEqual(M['internal_step_count'],15)
  self.assertNotEqual(M['internal_step_count'],9)
if __name__=='__main__':unittest.main()
