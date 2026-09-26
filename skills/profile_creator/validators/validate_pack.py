#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

def run(command):
    completed = subprocess.run(command, text=True, capture_output=True)
    if completed.stdout:
        print(completed.stdout, end='' if completed.stdout.endswith('\n') else '\n')
    if completed.stderr:
        print(completed.stderr, end='' if completed.stderr.endswith('\n') else '\n', file=sys.stderr)
    return completed.returncode

def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    checks = [
        ('PROFILE_CREATOR_CORE', [sys.executable, str(root/'validators/validate_pack_core.py'), str(root)]),
        ('GENERATED_PROFILE_MANIFEST', [sys.executable, str(root/'validators/validate_generated_profile_manifest.py'), str(root)]),
        ('CANDIDATE_DEPTH_SELF_TEST', [sys.executable, str(root/'validators/validate_candidate_depth.py'), '--self-test', str(root)]),
        ('GOV021_CHAMPION_CHALLENGER', [sys.executable, str(root/'validators/champion_challenger_depth.py'), str(root)]),
        ('PROFILE_PACK_LOCAL_BOUNDARY', [sys.executable, str(root/'evals/profile_validator_discovery_matrix.py')]),
        ('PROFILE_OPERATION_GENERIC_RESUMER', [sys.executable, str(root/'evals/batch_resume_contract.py')]),
        ('PROFILE_RESOLVER_DISPATCH_CONTRACT', [sys.executable, str(root/'evals/resolver_dispatch_contract.py')]),
        ('UPDATE_RECORDER_READINESS', [sys.executable, str(root/'evals/update_recorder_readiness_contract.py')]),
        ('PROFILE_OPERATION_COMMON_RECORDER', [sys.executable, str(root/'evals/profile_operation_common_recorder_contract.py')]),
        ('UPDATE_REVISION_CONTINUITY', [sys.executable, str(root/'evals/update_revision_continuity_contract.py')]),
        ('UPDATE_SERVER_TRUST_CONTEXT', [sys.executable, str(root/'evals/update_server_trust_context_contract.py')]),
        ('UPDATE_STEP60_JUDGE_REBASELINE', [sys.executable, str(root/'evals/update_step60_judge_rebaseline_contract.py')]),
        ('PROFILE_OPERATION_BLOCKED_EVIDENCE', [sys.executable, str(root/'evals/profile_operation_blocked_evidence_contract.py')]),
        ('RUNTIME_UPDATE_OPERATION_DISPOSITION', [sys.executable, str(root/'evals/runtime_update_operation_disposition_contract.py')]),
        ('PROFILE_EXECUTION_RESEARCH_BASELINE', [sys.executable, str(root/'evals/profile_execution_research_baseline_contract.py')]),
        ('S26_PROFILE_BASELINE_MATRIX', [sys.executable, str(root/'evals/s26_profile_baseline_matrix.py')]),
        ('S26_LEARNING_PREFLIGHT_MATRIX', [sys.executable, str(root/'evals/s26_learning_preflight_matrix.py')]),
    ]
    specification_only = [
        'evals/existing_artifact_remediation_contract.py',
        'evals/update_revision_continuity_matrix.py',
        'evals/update_server_trust_context_behavior.py',
    ]
    failed = []
    for name, command in checks:
        if run(command) != 0:
            failed.append(name)
    result = {
        'status': 'PASS' if not failed else 'FAIL',
        'validation_scope': 'PROFILE_CREATOR_PACK_ONLY',
        'checks_executed': [name for name, _ in checks],
        'specification_only_not_validation': specification_only,
        'evidence_ladder_note': 'Self-referential models are specification/rung-1 only and cannot satisfy validation or runtime proof.',
        'transversal_pack_discovery_executed': False,
        'transversal_pack_execution_executed': False,
        'transversal_pack_owner': 'PACK_VALIDATION',
        'failed_checks': failed,
        'runtime_authorized': False,
        'automatic_impact_authorized': False,
        'semantic_quality_review_authorized': False
    }
    print(json.dumps(result, indent=2))
    return 0 if not failed else 1

if __name__ == '__main__':
    raise SystemExit(main())
