import importlib.util
from pathlib import Path
import unittest
p=Path(__file__).with_name('edge_pg01_oidc_first_install_gate_v1.py')
spec=importlib.util.spec_from_file_location('first_install',p)
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)

def sample():
    return dict(slug=mod.SLUG,project_ref=mod.PROJECT,
                predeploy_readback='AUTHENTICATED_404',baseline_version=None,
                governance_authority='SIGNED_INDEPENDENT_VERIFIED',
                operation_status='OP_OPERATIONAL',effect_guard='RESERVED_EXACT',
                r17_preflight='CANONICAL_PASS',
                source_parity='EXACT_MAIN_BUNDLE_VERIFIED',
                failure_remediation='GOVERNED_DISABLE_AND_READBACK_VERIFIED')
class Tests(unittest.TestCase):
    def test_invalid_packet(self):
        self.assertEqual(mod.assess(None)['blockers'],['SNAPSHOT_INVALID'])
    def test_complete_claim_is_not_permission(self):
        r=mod.assess(sample());self.assertEqual(r['decision'],'ELIGIBLE_FOR_INDEPENDENT_REVIEW')
        self.assertFalse(r['deploy_authorized']);self.assertFalse(r['effect_executed'])
    def test_unknown_baseline(self):
        x=sample();x['baseline_version']=1
        self.assertIn('FIRST_INSTALL_BASELINE_MUST_BE_NULL',mod.assess(x)['blockers'])
    def test_unproved_absence(self):
        x=sample();x['predeploy_readback']='PREDEPLOY_ABSENT'
        self.assertIn('FIRST_INSTALL_ABSENCE_UNPROVEN',mod.assess(x)['blockers'])
    def test_missing_authority(self):
        x=sample();x['governance_authority']='CI_PASS'
        self.assertIn('SIGNED_INDEPENDENT_AUTHORITY_MISSING',mod.assess(x)['blockers'])
    def test_candidate_operation(self):
        x=sample();x['operation_status']='OP_CANDIDATE'
        self.assertIn('OPERATION_NOT_OPERATIONAL',mod.assess(x)['blockers'])
    def test_missing_guard(self):
        x=sample();x['effect_guard']=None
        self.assertIn('EFFECT_RESERVATION_MISSING',mod.assess(x)['blockers'])
    def test_no_recovery(self):
        x=sample();x['failure_remediation']='PRINT_ERROR'
        self.assertIn('FIRST_INSTALL_RECOVERY_NOT_VERIFIED',mod.assess(x)['blockers'])
    def test_wrong_target(self):
        x=sample();x['slug']='other'
        self.assertIn('TARGET_SCOPE_MISMATCH',mod.assess(x)['blockers'])
    def test_wrong_source(self):
        x=sample();x['source_parity']='SHA_UNVERIFIED'
        self.assertIn('EXACT_SOURCE_UNVERIFIED',mod.assess(x)['blockers'])
    def test_missing_r17(self):
        x=sample();x['r17_preflight']=None
        self.assertIn('R17_CANONICAL_PREFLIGHT_MISSING',mod.assess(x)['blockers'])
if __name__=='__main__':unittest.main()
