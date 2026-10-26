"""Run: python3 -m unittest test_a9_snapshot_assembler_v1 (from folder B)."""
import copy
import unittest
from a9_snapshot_assembler_v1 import (A9AssemblyError, DIGEST, SNAPSHOT_FIELDS,
    assemble_a9_snapshot, build_asof_record_input)
from validate_wave1_boundary_contracts_v1 import validate_programming_snapshot_payload_v1


def fixture():
    candidate = {'schema_version':'ANALYSIS_IMPLEMENTATION_PACKAGE_V1','candidate_only':True,
      'request_context':{'intent':'Change login label','target_ref':'ui/login'},
      'classification':{'target_granularity':'SCREEN','depth':'L1','authority_state':'UNKNOWN','implementation_state':'UNKNOWN'},
      'stage_trace':[{'stage':f'A{i}','outcome':'DONE','source_refs':[]} for i in range(1,10)],
      'material_unknowns':[], 'decisions_pending':[], 'requirements':[], 'material_fronts':[],
      'scope_proposals':[{'scope_id':'S1','readiness_candidate':'READY_CANDIDATE','material_front_refs':['F1'],'blockers':[]}],
      'research_stop':{'decision':'STOP','decision_stable':True,'all_material_fronts_accounted':True,'unresolved_decision_changing_questions':[]},
      'package_readiness_candidate':'READY_CANDIDATE'}
    front = {'front_id':'F1','front_kind':'UI','status':'REQUIRED','closure':'CLOSED',
       'source_signal_refs':['SIG1'],'scope_refs':['S1'],'authority_refs':['AR1'],
       'evidence_refs':['EV1'],'currentness_refs':['CR1'],'blockers':[], 'reason':'verified'}
    artifacts = {
      'A3':{'schema_version':'TARGETED_EVIDENCE_SET_V1','authority_state':'EXISTING','implementation_state':'EXISTING','authority_binding_refs':['canonical://binding/1'],'target_resolution':{'exact_target_ref':'ui/login'},'source_refs':['SRC3']},
      'A4':{'schema_version':'SHARED_CHANGE_IMPACT_MAP_V1','unresolved_material_impacts':[], 'source_refs':['SRC4']},
      'A5':{'schema_version':'ANALYSIS_DECISION_CONTEXT_V1','decisions':[{'decision_id':'D1','scope_refs':['S1'],'status':'STABLE'}], 'unresolved_questions':[],'source_refs':['SRC5']},
      'A6':{'schema_version':'IMPLEMENTABILITY_SCHEMA_V1', 'requirements':[], 'canonical_implementation_bindings':[{'binding_id':'B1','canonical_ref':'canonical://binding/1','currentness_ref':'CR1'}], 'scope_definitions':[{'scope_id':'S1','scope_kind':'INDEPENDENT','material_front_refs':['F1'],'depends_on_scope_ids':[],'authority_refs':['AR1'],'blockers':[]}], 'unresolved_material_items':[], 'source_refs':['SRC6']},
      'A7':{'schema_version':'MATERIAL_FRONT_COVERAGE_V1','material_fronts':[front], 'front_candidate_refs':[], 'unmapped_material_signals':[], 'source_refs':['SRC7'], 'currentness_refs':['CR1'], 'coverage_fingerprint_sha256':'a'*64,'all_material_fronts_accounted':True},
      'A8':{'schema_version':'ANALYSIS_STOP_RULE_V1','decision':'STOP','decision_stable':True,'all_material_fronts_accounted':True,'unresolved_decision_changing_questions':[], 'additional_available_evidence_capable_of_changing_material_decision':[], 'source_refs':['SRC8']}
    }
    auth={'target_identity':{'repo_full_name':'org/repo','base_head_sha':'b'*40},
          'product_rules':[{'code':'RULE1','status':'CANDIDATO','canonical_ref':'policy://one'}],
          'currentness_receipts':['CR1'], 'applicable_invariants':[], 'preserve':[],
          'source_refs':['SOURCE_CANONICAL'], 'independent_execution_boundary_verified':False,
          'transversal_blockers_affect_ready':False}
    return candidate,artifacts,auth


def build(f=None):
    c,a,v=fixture() if f is None else f
    return assemble_a9_snapshot(c,a,v,entry_contract_digest=DIGEST)


class Tests(unittest.TestCase):
    def assert_error(self, code, f, digest=DIGEST):
        with self.assertRaises(A9AssemblyError) as ex:
            assemble_a9_snapshot(*f,entry_contract_digest=digest)
        self.assertEqual(ex.exception.code,code)

    def test_complete_and_validator(self):
        s,report=build()
        self.assertEqual(s['package_readiness'],'READY')
        self.assertEqual(s['scope_readiness'][0]['status'],'READY')
        self.assertTrue(set(SNAPSHOT_FIELDS).issubset(s))
        self.assertEqual(validate_programming_snapshot_payload_v1(s)['state'],'PASS')
        self.assertIn('field_sources',report)

    def test_missing_artifacts_and_version(self):
        for stage in ('A5','A7'):
            f=fixture(); del f[1][stage]
            self.assert_error(f'A9_STAGE_ARTIFACT_MISSING:{stage}',f)
        f=fixture(); f[1]['A6']['schema_version']='WRONG'
        self.assert_error('A9_STAGE_ARTIFACT_VERSION:A6',f)

    def test_target_and_digest(self):
        f=fixture(); del f[2]['target_identity']; self.assert_error('A9_AUTHORITY_INPUT_MISSING:target_identity',f)
        f=fixture(); f[2]['target_identity']['base_head_sha']='abc'
        self.assert_error('A9_AUTHORITY_INPUT_INVALID:base_head_sha',f)
        self.assert_error('A9_ENTRY_CONTRACT_DIGEST_MISMATCH',fixture(),'0'*64)

    def test_blocked_front_prevents_ready(self):
        f=fixture(); f[1]['A7']['material_fronts'][0].update(closure='BLOCKED', blockers=['UNRESOLVED'])
        s,_=build(f)
        self.assertNotEqual(s['scope_readiness'][0]['status'],'READY')
        self.assertNotEqual(s['package_readiness'],'READY')

    def test_unresolved_a5(self):
        f=fixture(); f[1]['A5']['decisions'][0]['status']='UNRESOLVED'
        s,_=build(f)
        self.assertNotEqual(s['scope_readiness'][0]['status'],'READY')

    def test_explicit_empty_invariants(self):
        f=fixture(); del f[2]['applicable_invariants']
        self.assert_error('A9_AUTHORITY_INPUT_MISSING:applicable_invariants',f)
        s,_=build(); self.assertEqual(s['applicable_invariants'],[])

    def test_candidate_rule_not_promoted(self):
        s,_=build(); self.assertEqual(s['applicable_rules'][0]['status'],'CANDIDATO')

    def test_forbidden_strategy(self):
        f=fixture(); f[0]['chosen_endpoint_design']='/api/login'
        self.assert_error('A9_TECHNICAL_STRATEGY_FORBIDDEN',f)

    def test_determinism(self):
        a,_=build(); b,_=build()
        self.assertEqual(a,b)
        self.assertEqual(a['source_snapshot_sha256'],b['source_snapshot_sha256'])
        self.assertEqual(a['authority_fingerprint_sha256'],b['authority_fingerprint_sha256'])

    def test_asof_wrapper(self):
        s,_=build()
        kw=dict(decision_ref='A9-1',consumer_code='PROGRAMMING',subject_ref='ui/login',subject_version='v1',
            actor_authority={'actor_ref':'actor','authority_ref':'ref','authority_version':'v1','authority_sha256':'a'*64},
            governing={'policy_ref':'policy','policy_version':'v1','policy_sha256':'b'*64,
                       'terms_ref':'terms','terms_version':'v1','terms_sha256':'c'*64},
            decided_at='2026-10-26T12:00:00Z',effective_at='2026-10-26T12:00:00Z',
            authority_refs=[{'capability_code':c,'version':'1','manifest_sha256':'a'*64,'authority_ref':'r'} for c in
                ('CURRENTNESS_AUTHORITY','CAPABILITY_VERSION_COMPATIBILITY','TYPED_EVIDENCE_REGISTRY')])
        payload=build_asof_record_input(s,**kw)
        self.assertEqual(payload['extensions']['programming_context_snapshot'],s)
        self.assertNotIn('context_sha256',payload)
        bad=copy.deepcopy(kw); bad['authority_refs']=bad['authority_refs'][:-1]
        with self.assertRaisesRegex(A9AssemblyError,'A9_ASOF_INPUT_INVALID:authority_refs'):
            build_asof_record_input(s,**bad)
        bad=copy.deepcopy(kw); bad['governing']['policy_payload']={'x':1}
        with self.assertRaisesRegex(A9AssemblyError,'A9_ASOF_INPUT_INVALID:governing'):
            build_asof_record_input(s,**bad)

    def test_unscoped_open_items_block_every_scope(self):
        f=fixture(); f[1]['A8']['unresolved_decision_changing_questions']=['Is the label final?']
        s,_=build(f)
        self.assertNotEqual(s['scope_readiness'][0]['status'],'READY')
        self.assertNotEqual(s['package_readiness'],'READY')
        f=fixture(); f[1]['A7']['unmapped_material_signals']=['SIG-X']
        s,_=build(f)
        self.assertNotEqual(s['scope_readiness'][0]['status'],'READY')

    def test_validator_error_keeps_code(self):
        f=fixture(); f[1]['A7']['coverage_fingerprint_sha256']='bad'
        self.assert_error('SNAPSHOT_COVERAGE_PROVENANCE',f)

if __name__=='__main__': unittest.main()
