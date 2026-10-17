"""New C5/C6 bridge tests. Callbacks are TEST DOUBLES, never ledger receipts."""
import hashlib
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from profile_updater_native_material_bridge_v02 import (
    verify_native_material_candidate, MaterialBridgeBlocked, _sha,
)


def fixture():
    src = b'# Repair profile\nPreserve source evidence'
    digest = hashlib.sha256(src).hexdigest()
    h = dict(schema='LF_PE10_V02_SAME_CHAT_NATIVE_HANDOFF_V1',
             run_id='RUN-1', profile_slug='repair', executor_mode='GPT_NATIVE',
             current_chat_surface='CHATGPT_CURRENT_CONVERSATION',
             conversation_scope='EXISTING_CONVERSATION_ONLY',
             session_creation=False, api_invocation=False,
             evolution_mode='ADAPT', selected_method_ids=['CAUSAL_ANALYSIS', 'SELF_REFINE'],
             source_manifest=[{'ref': 'profiles/repair/SKILL.md', 'sha256': digest}],
             cutover_eligible=False)
    h['source_manifest_sha256'] = _sha(h['source_manifest'])
    h['handoff_sha256'] = _sha(h)
    raw = dict(run_id='RUN-1', evolution_mode='ADAPT',
               methods_applied=['CAUSAL_ANALYSIS', 'SELF_REFINE'],
               deliverable={'causal_chain':['A causes B'], 'self_refinement': {'revised_hypothesis': 'B'}})
    c = dict(schema='LF_PE10_V02_SAME_CHAT_RAW_CAPTURE_V1',
             executor_mode='GPT_NATIVE', run_id='RUN-1',
             conversation_scope='EXISTING_CONVERSATION_ONLY',
             handoff_sha256=h['handoff_sha256'], raw_output=raw,
             raw_output_sha256=_sha(raw), runtime_provider_attested=False,
             method_execution_certified=False, cutover_eligible=False,
             production_activated=False)
    c['capture_sha256'] = _sha(c)
    review = dict(receipt_id='LEDGER-REVIEW-1', verification_state='VERIFIED',
                  verdict='PASS', subject_raw_sha256=c['raw_output_sha256'],
                  handoff_sha256=h['handoff_sha256'], profile_slug='repair',
                  run_id='RUN-1', capture_sha256=c['capture_sha256'],
                  source_manifest_sha256=h['source_manifest_sha256'],
                  reviewer_execution_id='REVIEWER-2',
                  positive_controls_passed=True, negative_controls_passed=True)
    def test_bridge(hh=h, cc=c, sr=lambda ref: src, rr=lambda rid: review):
        return verify_native_material_candidate(handoff=hh, capture=cc,
            expected_current_surface='CHATGPT_CURRENT_CONVERSATION',
            trusted_source_readback=sr, trusted_review_readback=rr,
            review_receipt_id='LEDGER-REVIEW-1')
    return h, c, review, test_bridge


class NativeMaterialBridgeTest(unittest.TestCase):
    def test_positive_pre_admission_only(self):
        _, _, _, run = fixture()
        result = run()
        self.assertEqual(result['status'], 'NATIVE_MATERIAL_REVIEWED_PRE_ADMISSION')
        self.assertFalse(result['external_method_execution_certified'])
        self.assertFalse(result['canonical_steps_recorded'])
        self.assertFalse(result['cutover_eligible'])

    def test_tamper_raw_blocked(self):
        _, c, _, run = fixture()
        c['raw_output']['deliverable']['causal_chain'].append('invented')
        with self.assertRaisesRegex(MaterialBridgeBlocked,'CAPTURE_DIGEST_INVALID'):
            run()

    def test_provider_spoof_blocked(self):
        _, c, _, run = fixture()
        c['runtime_provider_attested'] = True
        c['capture_sha256'] = _sha({k:v for k,v in c.items() if k!='capture_sha256'})
        with self.assertRaisesRegex(MaterialBridgeBlocked,'FORGED_EXECUTION_AUTHORITY'):
            run()

    def test_forged_cross_chat_blocked(self):
        h,c,_,run = fixture()
        h['current_chat_surface']='CLAUDE_CURRENT_CONVERSATION'
        h['handoff_sha256']=_sha({k:v for k,v in h.items() if k!='handoff_sha256'})
        c['handoff_sha256']=h['handoff_sha256']
        c['capture_sha256']=_sha({k:v for k,v in c.items() if k!='capture_sha256'})
        with self.assertRaisesRegex(MaterialBridgeBlocked,'NATIVE_CHAT_CONTEXT_INVALID'):
            run()

    def test_review_unverified_blocked(self):
        _,_,review,run = fixture()
        review['verification_state']='PENDING'
        with self.assertRaisesRegex(MaterialBridgeBlocked,'INDEPENDENT_MATERIAL_REVIEW_UNVERIFIED'):
            run()

    def test_self_review_blocked(self):
        _,_,review,run = fixture()
        review['reviewer_execution_id']='RUN-1'
        with self.assertRaisesRegex(MaterialBridgeBlocked,'INDEPENDENT_MATERIAL_REVIEW_UNVERIFIED'):
            run()

    def test_review_digest_mismatch_blocked(self):
        _,_,review,run = fixture()
        review['subject_raw_sha256']='0'*64
        with self.assertRaisesRegex(MaterialBridgeBlocked,'INDEPENDENT_MATERIAL_REVIEW_UNVERIFIED'):
            run()

    def test_missing_trusted_source_blocked(self):
        _,_,_,run = fixture()
        with self.assertRaisesRegex(MaterialBridgeBlocked,'SOURCE_CURRENTNESS_UNVERIFIED'):
            run(sr=lambda ref: None)

    def test_missing_positive_controls_blocked(self):
        _,_,review,run = fixture()
        review['positive_controls_passed']=False
        with self.assertRaisesRegex(MaterialBridgeBlocked,'INDEPENDENT_MATERIAL_REVIEW_UNVERIFIED'):
            run()

    def test_missing_negative_controls_blocked(self):
        _,_,review,run = fixture()
        review['negative_controls_passed']=False
        with self.assertRaisesRegex(MaterialBridgeBlocked,'INDEPENDENT_MATERIAL_REVIEW_UNVERIFIED'):
            run()

if __name__=='__main__':
    unittest.main()
