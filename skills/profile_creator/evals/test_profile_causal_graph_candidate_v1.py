import unittest
from profile_causal_graph_candidate_v1 import assess_paths


def g():
    return ['start','a','b','end'],[
        dict(edge_id='e1',source='start',target='a',state='VERIFIED',evidence_ref='receipt://e1'),
        dict(edge_id='e2',source='a',target='end',state='BROKEN',evidence_ref='receipt://e2'),
        dict(edge_id='e3',source='start',target='b',state='VERIFIED',evidence_ref='receipt://e3'),
        dict(edge_id='e4',source='b',target='end',state='VERIFIED',evidence_ref='receipt://e4')]

class Checks(unittest.TestCase):
    def test_alternate(self):
        n,e=g();r=assess_paths(n,e,'start','end')
        self.assertEqual(r['status'],'ALTERNATE_VERIFIED_PATH_PRESENT')
        self.assertEqual(r['first_broken_edges'],['e2'])
        self.assertEqual(r['verified_paths'],1)
        self.assertFalse(r['root_cause_certified'])
    def test_all_broken(self):
        n,e=g();e[3]['state']='UNKNOWN'
        r=assess_paths(n,e,'start','end')
        self.assertEqual(r['status'],'OBSERVED_BOUNDARY_GAPS')
        self.assertEqual(r['first_unknown_edges'],['e4'])
    def test_all_verified(self):
        n,e=g();e[1]['state']='VERIFIED'
        self.assertEqual(assess_paths(n,e,'start','end')['status'],'ALL_PATHS_OBSERVED_VERIFIED')
    def test_missing_proof(self):
        n,e=g();e[0]['evidence_ref']=''
        self.assertEqual(assess_paths(n,e,'start','end')['reason'],'EDGE_PROVENANCE_MISSING')
    def test_cycle(self):
        n,e=g();e.append(dict(edge_id='e5',source='end',target='start',state='UNKNOWN',evidence_ref='receipt://e5'))
        self.assertEqual(assess_paths(n,e,'start','end')['reason'],'CYCLIC_GRAPH_UNSUPPORTED')
    def test_missing_route(self):
        n,e=g();self.assertEqual(assess_paths(n,e,'end','a')['status'],'NO_OBSERVED_TOPOLOGICAL_PATH')
    def test_budget(self):
        n,e=g();self.assertEqual(assess_paths(n,e,'start','end',max_paths=1)['reason'],'PATH_BUDGET_EXHAUSTED')
    def test_duplicate(self):
        n,e=g();e[0]['edge_id']='e2'
        self.assertEqual(assess_paths(n,e,'start','end')['reason'],'EDGE_ID_DUPLICATE')

if __name__=='__main__': unittest.main()
