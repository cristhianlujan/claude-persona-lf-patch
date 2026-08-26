#!/usr/bin/env python3
import json
import sys
from pathlib import Path

REQUIRED_FILES = [
    'SKILL.md','README.md','contracts/main_contract.md','contracts/missing_input_policy.md',
    'schemas/output.schema.json','schemas/missing_input.schema.json','judges/score_rubric.md','judges/mini_judge.md',
    'checklists/preflight_checklist.md','checklists/priority_checklist.md','examples/good_output.json','examples/bad_output.json',
    'examples/self_repair_output.json','fixtures/happy_path/input.json','fixtures/missing_inputs/input.json',
    'fixtures/unsafe_or_blocked/input.json','fixtures/self_repair/bad_output.json',
    'fixtures/handoff_outcome/input.json','fixtures/handoff_outcome/baseline_producer.json',
    'fixtures/handoff_outcome/baseline_quality_review.json','fixtures/handoff_outcome/baseline_receipt.json',
    'fixtures/handoff_outcome/candidate_pack.json','fixtures/handoff_outcome/candidate_producer.json',
    'fixtures/handoff_outcome/candidate_quality_review.json','fixtures/handoff_outcome/candidate_receipt.json',
    'fixtures/handoff_outcome/deterministic_intake_execution.json',
    'validators/validate_pack.py','evals/eval_matrix.json','handoffs/to_quality_pack.handoff.json',
    'adapters/github_pack_adapter.md','adapters/document_patch_adapter.md'
]

ALLOWED_STATUSES = {
    'PROFILE_PACK_CREATED','RETURN_TO_ORCHESTRATOR',
    'RETURN_TO_WORKER_FOR_SELF_REPAIR','BLOCK_PIPELINE'
}
ALLOWED_EVAL_TYPES = {'REGRESSION_EVAL','CAPABILITY_EVAL'}
HISTORICAL_BLOCK_CODE = 'BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER'
SEMANTIC_REVIEW_PENDING = 'SEMANTIC_QUALITY_REVIEW_NOT_EXECUTED'


def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def validate_created_artifact(root, producer, prefix, blocking):
    if producer.get('status') != 'PROFILE_PACK_CREATED':
        blocking.append(f'{prefix}_STATUS_MUST_BE_PROFILE_PACK_CREATED')
        return None
    if producer.get('deliverable_created') is not True:
        blocking.append(f'{prefix}_DELIVERABLE_CREATED_MUST_BE_TRUE')
    ref = producer.get('deliverable_artifact_ref')
    if not ref:
        blocking.append(f'{prefix}_CREATED_ARTIFACT_REF_MISSING')
        return None
    path = root / ref
    if not path.exists():
        blocking.append(f'{prefix}_CREATED_ARTIFACT_REF_NOT_FOUND:{ref}')
        return None
    artifact = load_json(path)
    if artifact.get('profile_pack_id') != producer.get('profile_pack_id'):
        blocking.append(f'{prefix}_ARTIFACT_PROFILE_PACK_ID_MISMATCH')
    files = artifact.get('files')
    if not isinstance(files, dict):
        blocking.append(f'{prefix}_ARTIFACT_FILES_MISSING')
        return artifact
    for rel in producer.get('files_created', []):
        content = files.get(rel)
        if not isinstance(content, str) or not content.strip():
            blocking.append(f'{prefix}_DECLARED_COMPONENT_NOT_DELIVERED:{rel}')
    return artifact


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    blocking, warnings = [], []
    target_eval_status = 'NOT_PROVEN'
    behavioral_blocking_codes = []
    historical_behavioral_blocks = []
    receiver_evidence_layers = None

    for rel in REQUIRED_FILES:
        if not (root / rel).exists():
            blocking.append(f'MISSING_REQUIRED_FILE:{rel}')

    if not blocking:
        try:
            good = load_json(root / 'examples/good_output.json')
            repair = load_json(root / 'examples/self_repair_output.json')
            bad = load_json(root / 'examples/bad_output.json')
            matrix = load_json(root / 'evals/eval_matrix.json')

            required_output_fields = [
                'status','profile_pack_id','source_authority','deliverable_created',
                'files_created','evidence_map','blocking_codes','next_gate'
            ]
            for name, obj in [('good',good),('self_repair',repair)]:
                for field in required_output_fields:
                    if field not in obj:
                        blocking.append(f'{name.upper()}_MISSING_FIELD:{field}')
                if obj.get('status') not in ALLOWED_STATUSES:
                    blocking.append(f'{name.upper()}_INVALID_STATUS:{obj.get("status")}')

            if good.get('status') != 'PROFILE_PACK_CREATED':
                blocking.append('GOOD_EXAMPLE_MUST_CREATE_PROFILE_PACK')
            else:
                validate_created_artifact(root, good, 'GOOD_EXAMPLE', blocking)

            if repair.get('status') != 'RETURN_TO_WORKER_FOR_SELF_REPAIR':
                blocking.append('SELF_REPAIR_EXAMPLE_MUST_RETURN_TO_WORKER')
            if 'BASIC_PROFILE_OUTPUT_NOT_ACCEPTABLE' not in repair.get('blocking_codes',[]):
                blocking.append('SELF_REPAIR_EXAMPLE_MISSING_BASIC_PROFILE_BLOCKING_CODE')
            if repair.get('next_gate') != 'SELF_REPAIR_THEN_QUALITY_PACK':
                blocking.append('SELF_REPAIR_EXAMPLE_INVALID_NEXT_GATE')
            if 'BASIC_PROFILE_OUTPUT_NOT_ACCEPTABLE' not in bad.get('blocking_codes',[]):
                blocking.append('BAD_EXAMPLE_MISSING_BASIC_PROFILE_OUTPUT_BLOCKING_CODE')
            else:
                warnings.append('BAD_EXAMPLE_CORRECTLY_SHOWS_PROFILE_ONLY_FAILURE')

            if matrix.get('validation_scope') != 'STRUCTURAL_ONLY':
                blocking.append('EVAL_MATRIX_VALIDATION_SCOPE_MUST_BE_STRUCTURAL_ONLY')
            if matrix.get('behavioral_eval_status') != 'NOT_EXECUTED':
                blocking.append('EVAL_MATRIX_MUST_NOT_CLAIM_GENERAL_BEHAVIORAL_EXECUTION')

            cases = matrix.get('cases',[])
            if len(cases) < 5:
                blocking.append('EVAL_MATRIX_REQUIRES_MINIMUM_5_CASES')
            regression_statuses, seen = set(), set()
            target_case = None
            for case in cases:
                case_id = case.get('id')
                if not case_id:
                    blocking.append('EVAL_CASE_MISSING_ID')
                    continue
                if case_id in seen:
                    blocking.append(f'EVAL_CASE_DUPLICATE_ID:{case_id}')
                seen.add(case_id)
                eval_type = case.get('eval_type')
                if eval_type not in ALLOWED_EVAL_TYPES:
                    blocking.append(f'EVAL_CASE_INVALID_TYPE:{case_id}:{eval_type}')
                if eval_type == 'REGRESSION_EVAL':
                    regression_statuses.add(case.get('expected_status'))
                fixture = case.get('fixture')
                if not fixture or not (root / fixture).exists():
                    blocking.append(f'EVAL_CASE_FIXTURE_NOT_FOUND:{case_id}:{fixture}')
                if case.get('expected_status') not in ALLOWED_STATUSES:
                    blocking.append(f'EVAL_CASE_INVALID_EXPECTED_STATUS:{case_id}:{case.get("expected_status")}')
                if case_id == 'profile_creator_to_quality_pack_handoff_outcome':
                    target_case = case

            for status in ['PROFILE_PACK_CREATED','RETURN_TO_ORCHESTRATOR','BLOCK_PIPELINE','RETURN_TO_WORKER_FOR_SELF_REPAIR']:
                if status not in regression_statuses:
                    blocking.append(f'REGRESSION_EVALS_MISSING_EXPECTED_STATUS:{status}')

            if target_case is None:
                blocking.append('HANDOFF_TARGET_EVAL_MISSING')
            else:
                if target_case.get('eval_type') != 'CAPABILITY_EVAL':
                    blocking.append('HANDOFF_TARGET_EVAL_MUST_REMAIN_CAPABILITY_UNTIL_FULL_HANDOFF_PROVEN')
                for key in [
                    'baseline_producer','baseline_receiver','baseline_receipt',
                    'candidate_producer','candidate_artifact','candidate_receiver','candidate_receipt',
                    'deterministic_intake_execution'
                ]:
                    rel = target_case.get(key)
                    if not rel or not (root / rel).exists():
                        blocking.append(f'HANDOFF_TARGET_EVAL_MISSING_{key.upper()}')

                if not blocking:
                    baseline_producer = load_json(root / target_case['baseline_producer'])
                    baseline_receiver = load_json(root / target_case['baseline_receiver'])
                    baseline_receipt = load_json(root / target_case['baseline_receipt'])
                    candidate_producer = load_json(root / target_case['candidate_producer'])
                    candidate_receiver = load_json(root / target_case['candidate_receiver'])
                    candidate_receipt = load_json(root / target_case['candidate_receipt'])
                    intake_execution = load_json(root / target_case['deterministic_intake_execution'])

                    # Historical baseline must remain reproducible.
                    if baseline_producer.get('status') != 'PROFILE_PACK_CREATED' or baseline_producer.get('deliverable_created') is not True:
                        blocking.append('HANDOFF_BASELINE_PRODUCER_STATE_MISMATCH')
                    if 'deliverable_artifact_ref' in baseline_producer:
                        blocking.append('HANDOFF_BASELINE_NO_LONGER_REPRODUCES_MISSING_ARTIFACT')
                    if baseline_receiver.get('verdict') != 'RETURN_TO_WORKER_FOR_SELF_REPAIR':
                        blocking.append('HANDOFF_BASELINE_RECEIVER_MUST_REJECT')
                    if 'CREATED_ARTIFACT_NOT_DELIVERED' not in baseline_receiver.get('blocking_codes',[]):
                        blocking.append('HANDOFF_BASELINE_GAP_CODE_MISSING')
                    if baseline_receipt.get('result') != 'TARGET_CAPABILITY_GAP_REPRODUCED' or baseline_receipt.get('candidate_patch_applied') is not False:
                        blocking.append('HANDOFF_BASELINE_RECEIPT_INVALID')

                    # Historical producer-side remediation and assisted review remain evidence, not execution.
                    validate_created_artifact(root, candidate_producer, 'HANDOFF_CANDIDATE', blocking)
                    if candidate_producer.get('deliverable_artifact_ref') != target_case.get('candidate_artifact'):
                        blocking.append('HANDOFF_CANDIDATE_ARTIFACT_REF_MISMATCH')
                    if candidate_receiver.get('reviewed_artifact') != target_case.get('candidate_artifact'):
                        blocking.append('HANDOFF_ASSISTED_REVIEW_ARTIFACT_MISMATCH')
                    if candidate_receiver.get('review_mode') != 'ASSISTED_RUBRIC_REVIEW':
                        blocking.append('HANDOFF_HISTORICAL_REVIEW_MODE_INVALID')
                    if candidate_receiver.get('receiver_execution_status') != 'NOT_EXECUTED':
                        blocking.append('HANDOFF_HISTORICAL_FALSE_RECEIVER_EXECUTION')
                    if HISTORICAL_BLOCK_CODE not in candidate_receiver.get('blocking_codes',[]):
                        blocking.append('HANDOFF_HISTORICAL_REVIEW_MISSING_BLOCK_CODE')
                    if candidate_receiver.get('score_breakdown',{}).get('handoff_readiness') != 5:
                        blocking.append('HANDOFF_HISTORICAL_CONSUMABILITY_NOT_DEMONSTRATED')

                    observed = candidate_receipt.get('observed_outcome',{})
                    if candidate_receipt.get('candidate_result') != target_case.get('historical_candidate_result'):
                        blocking.append('HANDOFF_HISTORICAL_RECEIPT_RESULT_MISMATCH')
                    if candidate_receipt.get('candidate_patch_applied') is not True:
                        blocking.append('HANDOFF_CANDIDATE_PATCH_FLAG_MISMATCH')
                    if observed.get('created_pack_materialized') is not True or observed.get('artifact_ref_resolvable') is not True:
                        blocking.append('HANDOFF_CANDIDATE_ARTIFACT_CONSUMABILITY_NOT_DEMONSTRATED')
                    if observed.get('assisted_rubric_review_completed') is not True:
                        blocking.append('HANDOFF_CANDIDATE_ASSISTED_REVIEW_NOT_RECORDED')
                    if observed.get('receiver_agent_execution_completed') is not False:
                        blocking.append('HANDOFF_HISTORICAL_FALSE_RECEIVER_EXECUTION_CLAIM')
                    if candidate_receipt.get('target_outcome_status') != 'NOT_PROVEN':
                        blocking.append('HANDOFF_HISTORICAL_TARGET_OUTCOME_MUST_REMAIN_NOT_PROVEN')
                    if candidate_receipt.get('behavioral_eval_status') != 'BLOCKED_NO_EXECUTABLE_RECEIVER':
                        blocking.append('HANDOFF_HISTORICAL_BEHAVIORAL_STATUS_INVALID')
                    if HISTORICAL_BLOCK_CODE not in candidate_receipt.get('behavioral_blocking_codes',[]):
                        blocking.append('HANDOFF_HISTORICAL_RECEIPT_MISSING_BLOCK_CODE')
                    historical_behavioral_blocks.append(HISTORICAL_BLOCK_CODE)

                    # Current executable receiver evidence is layered.
                    real_case = intake_execution.get('real_profile_creator_case',{})
                    if intake_execution.get('execution_result') != 'PASS':
                        blocking.append('HANDOFF_DETERMINISTIC_INTAKE_NOT_PASS')
                    if intake_execution.get('cases_passed') != intake_execution.get('cases_total') or intake_execution.get('cases_total',0) < 4:
                        blocking.append('HANDOFF_DETERMINISTIC_INTAKE_CASES_INCOMPLETE')
                    if real_case.get('source_pr') != 225:
                        blocking.append('HANDOFF_DETERMINISTIC_INTAKE_WRONG_PROFILE_SOURCE')
                    if real_case.get('intake_status') != target_case.get('expected_deterministic_intake_status'):
                        blocking.append('HANDOFF_DETERMINISTIC_INTAKE_STATUS_MISMATCH')
                    if real_case.get('next_gate') != 'SEMANTIC_QUALITY_REVIEW':
                        blocking.append('HANDOFF_DETERMINISTIC_INTAKE_NEXT_GATE_MISMATCH')
                    if intake_execution.get('semantic_quality_review_status') != target_case.get('expected_semantic_review_status'):
                        blocking.append('HANDOFF_SEMANTIC_REVIEW_STATUS_MISMATCH')
                    if intake_execution.get('full_handoff_outcome_status') != target_case.get('expected_full_handoff_outcome_status'):
                        blocking.append('HANDOFF_FULL_OUTCOME_STATUS_MISMATCH')
                    if intake_execution.get('historical_behavioral_blocking_code') != target_case.get('historical_behavioral_blocking_code'):
                        blocking.append('HANDOFF_HISTORICAL_BLOCK_REFERENCE_MISMATCH')
                    if intake_execution.get('current_behavioral_blocking_code') != target_case.get('behavioral_blocking_code'):
                        blocking.append('HANDOFF_CURRENT_BEHAVIORAL_BLOCK_MISMATCH')
                    if target_case.get('behavioral_blocking_code') != SEMANTIC_REVIEW_PENDING:
                        blocking.append('HANDOFF_TARGET_CASE_MUST_BLOCK_ON_SEMANTIC_REVIEW')

                    if not blocking:
                        target_eval_status = 'DETERMINISTIC_INTAKE_DEMONSTRATED_SEMANTIC_PENDING'
                        behavioral_blocking_codes.append(SEMANTIC_REVIEW_PENDING)
                        receiver_evidence_layers = {
                            'DETERMINISTIC_INTAKE': 'PASS',
                            'SEMANTIC_REVIEW': 'NOT_EXECUTED',
                            'FULL_HANDOFF_OUTCOME': 'NOT_PROVEN',
                            'source_pr': intake_execution.get('source_pr'),
                            'source_head': intake_execution.get('source_head'),
                            'exact_head_ci_status': intake_execution.get('exact_head_ci_status')
                        }
                        warnings.append('CREATED_ARTIFACT_CONSUMABILITY_DEMONSTRATED')
                        warnings.append('DETERMINISTIC_QUALITY_PACK_INTAKE_EXECUTED')
                        warnings.append('SEMANTIC_QUALITY_REVIEW_NOT_EXECUTED')
                        warnings.append('HISTORICAL_NO_EXECUTABLE_RECEIVER_BLOCK_PRESERVED_ONLY_AS_HISTORY')

            warnings.append('PROFILE_CREATOR_PACK_STRUCTURAL_VALIDATION_ONLY')
            warnings.append('GENERAL_BEHAVIORAL_EVAL_NOT_EXECUTED')
        except Exception as exc:
            blocking.append(f'JSON_VALIDATION_ERROR:{exc}')

    result = {
        'status': 'STRUCTURAL_PASS' if not blocking else 'FAIL',
        'validation_scope': 'STRUCTURAL_ONLY',
        'behavioral_eval_status': 'NOT_EXECUTED',
        'handoff_target_eval_status': target_eval_status,
        'target_outcome': 'QUALITY_PACK_CAN_REVIEW_CREATED_PROFILE_PACK_WITHOUT_INVENTING',
        'receiver_evidence_layers': receiver_evidence_layers,
        'historical_behavioral_blocks': historical_behavioral_blocks,
        'blocking_codes': blocking,
        'behavioral_blocking_codes': behavioral_blocking_codes,
        'warnings': warnings,
        'recommended_action': (
            'EXECUTE_SEMANTIC_QUALITY_REVIEW'
            if not blocking and target_eval_status == 'DETERMINISTIC_INTAKE_DEMONSTRATED_SEMANTIC_PENDING'
            else 'RETURN_TO_WORKER_FOR_SELF_REPAIR'
        )
    }
    print(json.dumps(result,indent=2))
    return 0 if not blocking else 1

if __name__ == '__main__':
    raise SystemExit(main())
