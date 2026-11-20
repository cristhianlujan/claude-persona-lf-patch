import unittest
from dataclasses import replace
from test_core import fixture, load, amended
from pip1_core.core import (
    Outcome,
    PIPError,
    Pins,
    Receipt,
    RunContract,
    State,
    invalidated_descendants,
    load_inventory,
    transition,
    verify_closure,
)

class D04Adversarial(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inv=load(fixture())
        cls.contract=RunContract('PIP-1','0.1.0-candidate','EXEC-FIXTURE','RUN-FIXTURE','EX-FIXTURE','SCOPE',Pins('a'*40,'b'*64,'c'*64,cls.inv.digest))
    def receipt(self,cp):
        return Receipt(self.contract.execution_id,self.contract.run_id,cp,self.contract.pins.head_sha,self.contract.pins.fingerprint(),'fixture://self','e'*64,'PASS')
    def test_proposed_text_does_not_exclude_required(self):
        self.assertIn('PG-04.C5',self.inv.operational_ids())
        self.assertIn('PG-00.C3',self.inv.pg00)
        self.assertEqual(self.inv.excluded_checkpoint_ids,frozenset({'PG-07.C7'}))
    def test_unauthorized_proposal_exclusion_rejected(self):
        o=fixture()
        o['excluded_proposals'].append({'checkpoint_id':'PG-20.C88','reason':'NEW_PROPOSAL'})
        with self.assertRaisesRegex(PIPError,'EXCLUDED_PROPOSAL_MISMATCH'):
            load(o)
    def test_attempted_operational_provider_spoof_rejected(self):
        r=replace(self.receipt('PG-01.C1'),provenance='PROVIDER_VERIFIED')
        with self.assertRaisesRegex(PIPError,'EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED'):
            transition(State.RUNNING,State.SUCCEEDED_ACCREDITED,run=self.contract,checkpoint_id='PG-01.C1',inventory=self.inv,outcomes={'PG-01.C1':Outcome(State.RUNNING,'RUNNING','fixture')},receipt=r,operational=True)
    def test_operational_closure_never_issued(self):
        outcomes={cp:Outcome(State.SUCCEEDED_SYNTHETIC,'PASS','synthetic',self.receipt(cp)) for cp in self.inv.operational_ids()}
        with self.assertRaisesRegex(PIPError,'EXTERNAL_CLOSURE_AUTHORITY_NOT_INTEGRATED'):
            verify_closure(self.inv,self.contract,outcomes,operational=True)
    def test_loaded_mapping_immutable(self):
        with self.assertRaises(TypeError):
            self.inv.checkpoints['PG-01']=('bad',)
        with self.assertRaises(TypeError):
            self.inv.requires['PG-01']=frozenset()
    def test_duplicate_json_key(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'bad.json'
            p.write_text('{"a":1,"a":2}',encoding='utf8')
            with self.assertRaisesRegex(PIPError,'DUPLICATE_JSON_KEY'):
                load_inventory(p,expected_digest='f'*64)
    def test_missing_dependency_via_realistic_mutation(self):
        o=fixture()
        o['inventory_core']['requires_edges'][1]['requires']='PG-88'
        with self.assertRaisesRegex(PIPError,'UNKNOWN_DEPENDENCY'):
            load(amended(o))
    def test_dup_edge(self):
        o=fixture()
        o['inventory_core']['requires_edges'][1]=dict(o['inventory_core']['requires_edges'][0])
        with self.assertRaisesRegex(PIPError,'DUPLICATE_DEPENDENCY'):
            load(amended(o))
    def test_wrong_run_receipt_and_context(self):
        r=replace(self.receipt('PG-01.C1'),context_fingerprint='f'*64)
        with self.assertRaisesRegex(PIPError,'EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED'):
            transition(State.RUNNING,State.SUCCEEDED_ACCREDITED,run=self.contract,checkpoint_id='PG-01.C1',inventory=self.inv,outcomes={'PG-01.C1':Outcome(State.RUNNING,'RUNNING','fixture')},receipt=r)
    def test_skipped_not_a_state(self):
        self.assertNotIn('SKIPPED',[v.value for v in State])
    def test_na_closure_rejected(self):
        outcomes={cp:Outcome(State.SUCCEEDED_SYNTHETIC,'PASS','s',self.receipt(cp)) for cp in self.inv.operational_ids()}
        outcomes['PG-20.C1']=Outcome(State.NOT_APPLICABLE_JUSTIFIED,'N/A','unverified')
        with self.assertRaisesRegex(PIPError,'NA_CLOSURE_AUTHORITY_NOT_VERIFIABLE'):
            verify_closure(self.inv,self.contract,outcomes)
    def test_transitive_invalidation(self):
        descendants=invalidated_descendants(self.inv,'PG-01')
        self.assertIn('PG-20.C4',descendants)
        self.assertIn('PG-11.C1',descendants)
    def test_nonterminal_unaccepted(self):
        outcomes={cp:Outcome(State.SUCCEEDED_SYNTHETIC,'PASS','s',self.receipt(cp)) for cp in self.inv.operational_ids()}
        outcomes['PG-02.C1']=Outcome(State.FAILED,'FAIL','fixture')
        with self.assertRaisesRegex(PIPError,'DEPENDENCY_UNSATISFIED'):
            verify_closure(self.inv,self.contract,outcomes)
    def test_parallel_convergences(self):
        self.assertEqual(self.inv.requires['PG-11'],frozenset({'PG-09','PG-10'}))
        self.assertEqual(self.inv.requires['PG-18'],frozenset({'PG-16','PG-17'}))
        self.assertEqual(self.inv.requires['PG-05'],frozenset({'PG-04'}))
        self.assertIn(('PG-16','PG-17'),self.inv.topo_layers())

if __name__=='__main__':
    unittest.main()

class InputBoundaryTests(unittest.TestCase):
    def test_maximum_inventory_file_bytes(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'huge.json'
            path.write_bytes(b' ' * 2_000_001)
            with self.assertRaisesRegex(PIPError,'INVENTORY_SIZE_LIMIT'):
                load_inventory(path,expected_digest='f'*64)
    def test_noncanonical_source_rejected(self):
        o=fixture()
        o['canonicalization']='unknown format'
        with self.assertRaisesRegex(PIPError,'CANONICALIZATION_UNRECOGNIZED'):
            load(o)
    def test_receipt_checkpoint_reuse_rejected(self):
        inv=load(fixture())
        run=RunContract('PIP-1','candidate','E','R','EX','S',Pins('a'*40,'b'*64,'c'*64,inv.digest))
        r=Receipt('E','R','PG-01.C1','a'*40,run.pins.fingerprint(),'fixture://self','e'*64,'PASS')
        with self.assertRaisesRegex(PIPError,'CURRENT_STATE_MISMATCH'):
            transition(State.RUNNING,State.SUCCEEDED_ACCREDITED,run=run,checkpoint_id='PG-01.C2',inventory=inv,outcomes={'PG-01.C1':Outcome(State.RUNNING,'RUNNING','fixture')},receipt=r)
