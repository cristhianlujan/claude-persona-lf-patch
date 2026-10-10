import unittest
from source_candidate_discovery_v1 import discover_sources, adapt_for_targeted_evidence

# SYNTHETIC UNIT FIXTURES ONLY; not canonical LF test cases or operational policy.
POLICY = {'authority':'SUPABASE','snapshot_verified':True,'max_candidates':12,
          'ranking_weights':{'label':4,'columns':1,'description':2},
          'stop_terms':['subi','una','no','aparece','mi','la','el','en','es','quiero']}
DATA = {'origin':'SUPABASE','snapshot_ref':'supabase://metadata/probe/ephemeral',
        'sources':[{'source_ref':'s://A','label':'cargas lotes','columns':['estado','empresa_id'], 'relation_refs':['s://B']},
                   {'source_ref':'s://B','label':'cargas archivos','columns':['archivo','nombre'], 'relation_refs':['s://A']},
                   {'source_ref':'s://C','label':'pagos pagos','columns':['importe','estado']} ]}

class TestDiscovery(unittest.TestCase):
    def test_two_relevant_without_source_names_in_request(self):
        out=discover_sources({'objective':'Subí una carga y no aparece'},DATA,POLICY)
        self.assertEqual(out['discovery_state'],'CANDIDATES_FOUND')
        self.assertEqual({x['source_ref'] for x in out['candidate_sources']},{'s://A','s://B'})
        self.assertFalse(out['data_access_granted'])
    def test_unrelated_not_selected(self):
        out=discover_sources({'objective':'pagos pendientes'},DATA,POLICY)
        self.assertEqual([x['source_ref'] for x in out['candidate_sources']],['s://C'])
    def test_rename_works_when_metadata_semantics_preserved(self):
        metadata={'origin':'SUPABASE','snapshot_ref':'supabase://metadata/probe/2',
                  'sources':[{'source_ref':'s://renamed','label':'registro_x3','columns':['carga_id','estado']}]}
        out=discover_sources({'objective':'carga'},metadata,POLICY)
        self.assertEqual(out['candidate_sources'][0]['source_ref'],'s://renamed')
    def test_empty_is_not_exhausted(self):
        out=discover_sources({'objective':'desconocido'},DATA,POLICY)
        self.assertEqual(out['discovery_state'],'NO_MATCH_IN_SCOPE')
        self.assertFalse(out['discovery_exhausted'])
    def test_policy_is_mandatory(self):
        out=discover_sources({'objective':'carga'},DATA,{})
        self.assertEqual(out['discovery_state'],'ERROR_FAIL_CLOSED')
    def test_metadata_is_mandatory(self):
        out=discover_sources({'objective':'carga'},{'sources':DATA['sources']},POLICY)
        self.assertEqual(out['discovery_state'],'ERROR_FAIL_CLOSED')
    def test_d2_no_fabricated_authorization(self):
        d=discover_sources({'objective':'carga'},DATA,POLICY)
        out=adapt_for_targeted_evidence(d,['LOCATE_SOURCE'],'run1',{})
        self.assertEqual(out['state'],'DISCOVER_MORE')
    def test_d2_verified_contract_only(self):
        d=discover_sources({'objective':'carga'},DATA,POLICY)
        receipt={'s://A':{'authority':'SUPABASE','authorization_verified':True,'currentness_verified':True,
                         'admission_receipt_ref':'supabase://receipt/abc','covers_reasons':['LOCATE_SOURCE'],
                         'acquisition_cost_rank':1,'material_verified':True}}
        out=adapt_for_targeted_evidence(d,['LOCATE_SOURCE'],'run1',receipt)
        self.assertEqual(out['state'],'PLANNER_INPUT_READY')
        self.assertEqual(out['payload']['candidates'][0]['candidate_ref'],'supabase://receipt/abc')
        self.assertFalse(out['data_access_granted'])
    def test_d2_denied_does_not_admit(self):
        d=discover_sources({'objective':'carga'},DATA,POLICY)
        receipt={'s://A':{'authority':'SUPABASE','authorization_verified':False,'currentness_verified':True,
                         'admission_receipt_ref':'supabase://receipt/abc','covers_reasons':['LOCATE_SOURCE'],
                         'acquisition_cost_rank':1,'material_verified':True}}
        self.assertEqual(adapt_for_targeted_evidence(d,['LOCATE_SOURCE'],'run1',receipt)['state'],'DISCOVER_MORE')
    def test_d2_exhausted_can_return_empty_for_existing_planner(self):
        out=adapt_for_targeted_evidence({'discovery_state':'DISCOVERY_EXHAUSTED','candidate_sources':[]},
                                        ['LOCATE_SOURCE'],'run1',{})
        self.assertEqual(out['state'],'PLANNER_INPUT_READY')
        self.assertEqual(out['payload']['candidates'],[])

if __name__=='__main__': unittest.main()
