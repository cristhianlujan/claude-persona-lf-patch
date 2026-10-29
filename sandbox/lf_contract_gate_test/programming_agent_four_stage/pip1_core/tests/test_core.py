import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from pip1_core.core import (
    SCHEMA,
    Outcome,
    PIPError,
    Pins,
    Receipt,
    RunContract,
    State,
    invalidated_descendants,
    load_inventory,
    material_drift,
    transition,
    verify_closure,
)

COUNTS = [7,5,10,7,5,5,6,8,5,5,5,4,3,3,3,3,3,3,3,4]
EDGES = [(2,1),(3,2),(4,3),(5,4),(6,4),(6,5),(7,6),(8,7),(9,8),(10,1),(11,9),(11,10),(12,11),(13,12),(14,13),(15,14),(16,15),(17,15),(18,16),(18,17),(19,18),(20,19)]
EXPECTED = '0.1.1-candidate'

def fixture():
    core = {'schema':SCHEMA, 'external_prerequisite':{'checkpoints':[{'checkpoint_id':f'PG-00.C{i}'} for i in range(1,12)]}, 'operational_units':[], 'requires_edges':[]}
    for i,count in enumerate(COUNTS,1):
        core['operational_units'].append({'unit_id':f'PG-{i:02}', 'checkpoints':[{'checkpoint_id':f'PG-{i:02}.C{j}', 'status':'REQUIRED'} for j in range(1,count+1)]})
    core['requires_edges'] = [{'from':f'PG-{i:02}', 'requires':f'PG-{j:02}'} for i,j in EDGES]
    digest = hashlib.sha256(json.dumps(core,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
    return {'authority_status':'CANDIDATE_NOT_APPROVED','inventory_version':EXPECTED,'inventory_digest_sha256':digest,'canonicalization':'json utf8 sort_keys true ensure_ascii false separators comma colon; hash over inventory_core only','inventory_core':core,'excluded_proposals':[{'checkpoint_id':'PG-07.C7','reason':'PROPOSED_NOT_REQUIRED'}]+[{'checkpoint_id':i,'reason':'PROPOSED_2026_10_27_C1_NO_OWNER_GO'} for i in ('PG-00.C3','PG-00.C6','PG-04.C5','PG-07.C3','PG-12.C2','PG-17.C2')], 'approval_ref':None,'pg00_certification_ref':None}

def load(obj):
    with tempfile.TemporaryDirectory() as temp:
        p=Path(temp)/'inventory.json'
        p.write_text(json.dumps(obj),encoding='utf8')
        return load_inventory(p,expected_file_sha256=hashlib.sha256(p.read_bytes()).hexdigest())

def amended(obj):
    obj['inventory_digest_sha256']=hashlib.sha256(json.dumps(obj['inventory_core'],sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
    return obj

class CoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory=load(fixture())
        cls.contract=RunContract('PIP-1','0.1.0-candidate','EXEC-FIXTURE','RUN-FIXTURE','EXECUTOR-FIXTURE','SCOPE-FIXTURE',Pins('a'*40,'b'*64,'c'*64,cls.inventory.digest))
    @classmethod
    def receipt(cls, cp, **changes):
        r=Receipt(cls.contract.execution_id,cls.contract.run_id,cp,cls.contract.pins.head_sha,cls.contract.pins.fingerprint(),'fixture://explicit','e'*64,'PASS')
        return replace_receipt(r,**changes)
    def test_T01_valid_inventory(self):
        self.assertEqual(len(self.inventory.all_ids()),108)
        self.assertEqual(sum(len(x) for x in self.inventory.requires.values()),22)
        self.assertEqual(self.inventory.topo_layers()[0],('PG-01',))
        self.assertIn(('PG-16','PG-17'), self.inventory.topo_layers())
    def test_T02_unknown_dependency(self):
        o=fixture()
        o['inventory_core']['requires_edges'][0]['requires']='PG-99'
        with self.assertRaisesRegex(PIPError,'UNKNOWN_DEPENDENCY'):
            load(amended(o))
    def test_T03_cycle(self):
        o=fixture()
        o['inventory_core']['requires_edges'][0]['requires']='PG-20'
        with self.assertRaisesRegex(PIPError,'DAG_CYCLE'):
            load(amended(o))
    def test_T04_missing_predecessor(self):
        with self.assertRaisesRegex(PIPError,'DEPENDENCY_UNSATISFIED'):
            transition(State.PENDING,State.ELIGIBLE,run=self.contract,checkpoint_id='PG-02.C1',inventory=self.inventory,outcomes={})
    def test_T04b_dependency_state_without_receipt(self):
        prior={cp:Outcome(State.SUCCEEDED_ACCREDITED,'PASS','unverified') for cp in self.inventory.checkpoints['PG-01']}
        with self.assertRaisesRegex(PIPError,'PREREQUISITE_EVIDENCE_UNVERIFIED'):
            transition(State.PENDING,State.ELIGIBLE,run=self.contract,checkpoint_id='PG-02.C1',inventory=self.inventory,outcomes=prior)
    def test_T04c_verified_dependency_receipts(self):
        prior={cp:Outcome(State.SUCCEEDED_ACCREDITED,'PASS','fixture',self.receipt(cp)) for cp in self.inventory.checkpoints['PG-01']}
        out=transition(State.PENDING,State.ELIGIBLE,run=self.contract,checkpoint_id='PG-02.C1',inventory=self.inventory,outcomes=prior)
        self.assertEqual(out.state,State.ELIGIBLE)
    def test_T05_required_omitted(self):
        outcomes={cp:Outcome(State.SUCCEEDED_SYNTHETIC,'PASS','fixture',self.receipt(cp)) for cp in self.inventory.operational_ids()}
        del outcomes['PG-03.C1']
        with self.assertRaisesRegex(PIPError,'REQUIRED_CHECKPOINT_MISSING'):
            verify_closure(self.inventory,self.contract,outcomes)
    def test_T06_foreign_head_receipt(self):
        with self.assertRaisesRegex(PIPError,'EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED'):
            transition(State.RUNNING,State.SUCCEEDED_ACCREDITED,run=self.contract,checkpoint_id='PG-01.C1',inventory=self.inventory,outcomes={'PG-01.C1':Outcome(State.RUNNING,'RUNNING','fixture')},receipt=self.receipt('PG-01.C1',source_head_sha='f'*40))
    def test_T07_na_without_justification(self):
        with self.assertRaisesRegex(PIPError,'NA_AUTHORITY_MISSING'):
            transition(State.RUNNING,State.NOT_APPLICABLE_JUSTIFIED,run=self.contract,checkpoint_id='PG-01.C1',inventory=self.inventory,outcomes={'PG-01.C1':Outcome(State.RUNNING,'RUNNING','fixture')})
    def test_T08_illegal_transition(self):
        with self.assertRaisesRegex(PIPError,'CURRENT_STATE_MISMATCH'):
            transition(State.PENDING,State.SUCCEEDED_ACCREDITED,run=self.contract,checkpoint_id='PG-01.C1',inventory=self.inventory,outcomes={'PG-01.C1':Outcome(State.RUNNING,'RUNNING','fixture')},receipt=self.receipt('PG-01.C1'))
    def test_T09_material_drift(self):
        observed=Pins('f'*40,'b'*64,'c'*64,'d'*64)
        self.assertTrue(material_drift(self.contract,observed))
        self.assertIn('PG-20.C1',invalidated_descendants(self.inventory,'PG-01'))
    def test_T10_pending_closure(self):
        outcomes={cp:Outcome(State.SUCCEEDED_SYNTHETIC,'PASS','fixture',self.receipt(cp)) for cp in self.inventory.operational_ids()}
        outcomes['PG-19.C1']=Outcome(State.PENDING,'PENDING','not done')
        with self.assertRaisesRegex(PIPError,'DEPENDENCY_UNSATISFIED'):
            verify_closure(self.inventory,self.contract,outcomes)
    def test_T11_positive_synthetic_closure(self):
        outcomes={cp:Outcome(State.SUCCEEDED_SYNTHETIC,'PASS','fixture',self.receipt(cp)) for cp in self.inventory.operational_ids()}
        result=verify_closure(self.inventory,self.contract,outcomes)
        self.assertEqual(result.code,'SYNTHETIC_CLOSURE')
        self.assertEqual(result.state,State.SYNTHETIC_ONLY)
        with self.assertRaisesRegex(PIPError,'EXTERNAL_CLOSURE_AUTHORITY_NOT_INTEGRATED'):
            verify_closure(self.inventory,self.contract,outcomes,operational=True)
    def test_T12_unapproved_authority(self):
        o=fixture()
        o['approval_ref']='approval'
        with self.assertRaisesRegex(PIPError,'CANDIDATE_AUTHORITY_DRIFT'):
            load(o)
    def test_T13_duplicate_checkpoint(self):
        o=fixture()
        o['inventory_core']['operational_units'][0]['checkpoints'][1]['checkpoint_id']='PG-01.C1'
        with self.assertRaisesRegex(PIPError,'CHECKPOINT_ID_OR_STATUS_INVALID'):
            load(amended(o))
    def test_T14_foreign_run(self):
        with self.assertRaisesRegex(PIPError,'EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED'):
            transition(State.RUNNING,State.SUCCEEDED_ACCREDITED,run=self.contract,checkpoint_id='PG-01.C1',inventory=self.inventory,outcomes={'PG-01.C1':Outcome(State.RUNNING,'RUNNING','fixture')},receipt=self.receipt('PG-01.C1',run_id='OTHER'))
    def test_T15_checksum_tamper(self):
        o=fixture()
        o['inventory_core']['operational_units'][0]['title']='tampered'
        with self.assertRaisesRegex(PIPError,'INVENTORY_DIGEST_MISMATCH'):
            load(o)

def replace_receipt(receipt,**changes):
    from dataclasses import replace
    return replace(receipt,**changes)

if __name__=='__main__':
    unittest.main()
