#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import profile_audit
profile_audit.CONFIG['A40']={'path':'perfiles/PERFIL_STORY_TEST_DERIVER_LF.md','agent':'agents/test-deriver.md','judges':['J10_TEST_COVERAGE'],'writes':['tests','test_coverage','evidence'],'quality':['acceptance_criteria_without_test','critical_rule_without_test','permission_without_negative_test','tenant_rule_without_cross_tenant_test','state_transition_without_state_test','idempotent_action_without_duplicate_test','critical_error_without_test','mutable_shared_resource_without_concurrency_test','tests_without_exact_fixture','tests_without_expected_result','tests_without_traceability_ref','orphan_tests','vacuous_pass_count']}
if __name__=='__main__':raise SystemExit(profile_audit.run('A40','runtime',Path('audit-results')))
