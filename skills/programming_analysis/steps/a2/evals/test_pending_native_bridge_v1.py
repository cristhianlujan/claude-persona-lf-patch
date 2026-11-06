"""Native pending handoff invariants; strictly simulated readback."""
import importlib.util
import unittest
from pathlib import Path
from test_run_business_binding_v1 import bundle

ROOT = Path(__file__).resolve().parents[3]
source = ROOT / 'adapters/native_pending_run_binding_v1.py'
spec = importlib.util.spec_from_file_location('pending_guard', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
verify_pending = module.verify_pending


def sample():
    parent, invocation, child = bundle()
    parent['target_type'] = 'PERFIL'
    parent['manifest']['router_profile_handoff']['router_authorization_receipt']['effect_authority'] = False
    invocation['status'] = 'IN_PROGRESS'
    child['target_type'] = 'SKILL'
    child['manifest']['business'] = 'LF'
    child['manifest']['profile_handoff']['business'] = 'LF'
    child['manifest']['skill_source'] = {'path':'skills/programming_analysis/SKILL.md',
                                         'commit_sha':'c'*40,'blob_sha':'d'*40}
    step0 = {'execution_id':child['execution_id'],'step_id':'init_execution','step_order':0,
             'status':'STEP_PASS_WITH_EVIDENCE',
             'evidence_payload':{'execution_id_created':True,
                                 'mini_judge_code':'JUDGE-EJECUCION-SKILL-LF-v0.1'}}
    return parent, invocation, child, step0

class PendingBridge(unittest.TestCase):
    def check(self, edit, code):
        p,i,c,s = sample()
        edit(p,i,c,s)
        r=verify_pending(p,i,c,s,p['execution_id'])
        self.assertEqual(r['blocking_codes'],[code])
        self.assertFalse(r['a3_allowed'])
    def test_pending_consistent_not_trusted(self):
        p,i,c,s=sample()
        r=verify_pending(p,i,c,s,p['execution_id'])
        self.assertEqual(r['status'],'CANDIDATE_PENDING_RUN_CONSISTENT')
        self.assertFalse(r['readback_authenticated'])
        self.assertFalse(r['native_judge_verified'])
        self.assertFalse(r['a3_allowed'])
    def test_completed_invocation_rejected(self):
        self.check(lambda p,i,c,s:i.update(status='COMPLETED'),
                   'PENDING_INVOCATION_NOT_EXACT_OR_PREMATURELY_CLOSED')
    def test_other_business_rejected(self):
        self.check(lambda p,i,c,s:c['manifest'].update(business='SALY'),
                   'PENDING_CHILD_CROSS_BUSINESS')
    def test_wrong_skill_rejected(self):
        self.check(lambda p,i,c,s:c.update(target_code='ACT-0057'),
                   'PENDING_CHILD_RUN_MISMATCH')
    def test_step0_missing_rejected(self):
        p,i,c,s=sample()
        self.assertEqual(verify_pending(p,i,c,None,p['execution_id'])['blocking_codes'],
                         ['PENDING_READBACK_REQUIRED'])
    def test_wrong_step0_judge_rejected(self):
        self.check(lambda p,i,c,s:s['evidence_payload'].update(mini_judge_code='OTHER'),
                   'PENDING_INIT_STEP_NOT_CLEAN')
    def test_source_drift_rejected(self):
        self.check(lambda p,i,c,s:c['manifest']['skill_source'].update(blob_sha='wrong'),
                   'PENDING_CURRENT_SOURCE_NOT_BOUND')
    def test_wrong_actor_rejected(self):
        p,i,c,s=sample()
        self.assertEqual(verify_pending(p,i,c,s,'OTHER')['blocking_codes'],
                         ['PENDING_PARENT_ACTOR_MISMATCH'])
