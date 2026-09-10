#!/usr/bin/env python3
import json
import sys
from pathlib import Path

REQUIRED_FILES = [
    'SKILL.md',
    'README.md',
    'contracts/main_contract.md',
    'contracts/missing_input_policy.md',
    'schemas/output.schema.json',
    'schemas/missing_input.schema.json',
    'judges/score_rubric.md',
    'judges/mini_judge.md',
    'checklists/preflight_checklist.md',
    'checklists/priority_checklist.md',
    'examples/good_output.json',
    'examples/bad_output.json',
    'examples/self_repair_output.json',
    'fixtures/happy_path/input.json',
    'fixtures/missing_inputs/input.json',
    'fixtures/unsafe_or_blocked/input.json',
    'fixtures/self_repair/bad_output.json',
    'fixtures/profile_card_handoff/input.json',
    'fixtures/trace_without_target_eval/input.json',
    'fixtures/handoff_without_executable_receiver/input.json',
    'fixtures/handoff_layered_receiver_evidence/input.json',
    'fixtures/handoff_outcome/input.json',
    'fixtures/handoff_outcome/producer_actual.json',
    'fixtures/handoff_outcome/quality_review_actual.json',
    'fixtures/handoff_outcome/receipt.json',
    'fixtures/cross_pack_profile_creator_handoff/producer_snapshot.json',
    'fixtures/cross_pack_profile_creator_handoff/quality_review_actual.json',
    'fixtures/cross_pack_profile_creator_handoff/receipt.json',
    'fixtures/cross_pack_profile_creator_handoff/remediation_snapshot.json',
    'validators/validate_pack.py',
    'evals/eval_matrix.json',
    'evals/handoff_outcome_matrix.json',
    'handoffs/to_quality_pack.handoff.json',
    'adapters/github_pack_adapter.md',
    'adapters/document_patch_adapter.md',
    'adapters/supabase_log_adapter.md',
]

REQUIRED_OUTPUT_FIELDS = [
    'status',
    'learning_candidate_id',
    'classification',
    'source_authority',
    'evidence_map',
    'proposed_next_action',
    'handoff_target',
    'blocking_codes',
    'next_gate',
]

ALLOWED_STATUSES = {
    'LEARNING_CARD_CANDIDATE_CREATED',
    'HANDOFF_TO_ACT_0045',
    'RETURN_TO_ORCHESTRATOR',
    'RETURN_TO_WORKER_FOR_SELF_REPAIR',
    'BLOCK_PIPELINE',
}
ALLOWED_EVAL_TYPES = {'REGRESSION_EVAL', 'CAPABILITY_EVAL'}
ASSISTED_RESULT = 'ARTIFACT_CONSUMABILITY_DEMONSTRATED_BEHAVIORAL_NOT_PROVEN'
NO_EXECUTABLE_RECEIVER = 'BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER'
SEMANTIC_REVIEW_PENDING = 'SEMANTIC_QUALITY_REVIEW_NOT_EXECUTED'


def load_json(path: Path):
    with open(path, 'r', encoding='utf-8') as handle:
        return json.load(handle)


def candidate_artifact_is_consistent(output: dict) -> bool:
    candidate = output.get('candidate_artifact')
    if not isinstance(candidate, dict):
        return False
    if not candidate.get('artifact_id') or not candidate.get('artifact_type'):
        return False
    if not isinstance(candidate.get('content'), dict) or not candidate.get('content'):
        return False
    return candidate.get('artifact_id') == output.get('learning_candidate_id')


def validate_handoff_matrix(root: Path, matrix: dict):
    blocking = []
    observed_results = {}
    historical_gaps = []
    historical_blocks = []

    if matrix.get('general_behavioral_eval_status') != 'NOT_CLAIMED':
        blocking.append('HANDOFF_MATRIX_FALSE_GENERAL_BEHAVIORAL_CLAIM')

    cases = matrix.get('cases', [])
    if len(cases) < 2:
        blocking.append('HANDOFF_MATRIX_REQUIRES_MINIMUM_2_CASES')
        return blocking, observed_results, historical_gaps, historical_blocks

    seen = set()
    for case in cases:
        case_id = case.get('id')
        if not case_id:
            blocking.append('HANDOFF_MATRIX_CASE_MISSING_ID')
            continue
        if case_id in seen:
            blocking.append(f'HANDOFF_MATRIX_DUPLICATE_CASE:{case_id}')
        seen.add(case_id)

        for key in ['producer_output_ref', 'receiver_output_ref', 'receipt_ref', 'expected_result']:
            if not case.get(key):
                blocking.append(f'HANDOFF_MATRIX_CASE_MISSING_{key.upper()}:{case_id}')

        missing = False
        for key in ['producer_output_ref', 'receiver_output_ref', 'receipt_ref']:
            rel = case.get(key)
            if rel and not (root / rel).exists():
                blocking.append(f'HANDOFF_MATRIX_FILE_NOT_FOUND:{case_id}:{rel}')
                missing = True
        remediation_ref = case.get('remediation_snapshot_ref')
        if remediation_ref and not (root / remediation_ref).exists():
            blocking.append(f'HANDOFF_MATRIX_REMEDIATION_NOT_FOUND:{case_id}:{remediation_ref}')
            missing = True
        if missing:
            continue

        receipt = load_json(root / case['receipt_ref'])
        actual_result = receipt.get('result')
        expected_result = case.get('expected_result')
        observed_results[case_id] = actual_result
        if actual_result != expected_result:
            blocking.append(f'HANDOFF_MATRIX_RESULT_MISMATCH:{case_id}:{expected_result}:{actual_result}')
        if receipt.get('general_behavioral_eval_status') != 'NOT_CLAIMED':
            blocking.append(f'HANDOFF_MATRIX_CASE_FALSE_GENERAL_CLAIM:{case_id}')

        if expected_result == ASSISTED_RESULT:
            observed = receipt.get('observed_outcome', {})
            if case.get('receiver_execution_target') is not None:
                blocking.append(f'HANDOFF_MATRIX_ASSISTED_CASE_HAS_EXECUTABLE_TARGET:{case_id}')
            if receipt.get('target_outcome_status') != 'NOT_PROVEN':
                blocking.append(f'HANDOFF_MATRIX_ASSISTED_CASE_FALSE_TARGET_PASS:{case_id}')
            if receipt.get('behavioral_eval_status') != 'BLOCKED_NO_EXECUTABLE_RECEIVER':
                blocking.append(f'HANDOFF_MATRIX_ASSISTED_CASE_BEHAVIORAL_STATUS_INVALID:{case_id}')
            if NO_EXECUTABLE_RECEIVER not in receipt.get('behavioral_blocking_codes', []):
                blocking.append(f'HANDOFF_MATRIX_ASSISTED_CASE_MISSING_BLOCK_CODE:{case_id}')
            if observed.get('assisted_rubric_review_completed') is not True:
                blocking.append(f'HANDOFF_MATRIX_ASSISTED_REVIEW_NOT_COMPLETED:{case_id}')
            if observed.get('receiver_agent_execution_completed') is not False:
                blocking.append(f'HANDOFF_MATRIX_FALSE_RECEIVER_EXECUTION:{case_id}')
            historical_blocks.append({'case_id': case_id, 'blocking_code': NO_EXECUTABLE_RECEIVER})

        if expected_result == 'HANDOFF_GAP_DETECTED':
            gap_code = case.get('expected_gap_code')
            if not gap_code:
                blocking.append(f'HANDOFF_MATRIX_GAP_CASE_MISSING_EXPECTED_CODE:{case_id}')
            elif receipt.get('gap_code') != gap_code:
                blocking.append(f'HANDOFF_MATRIX_GAP_CODE_MISMATCH:{case_id}')
            else:
                historical_gaps.append({'case_id': case_id, 'gap_code': gap_code})

            observed = receipt.get('observed_outcome', {})
            if observed.get('receiver_required_invention') is not True:
                blocking.append(f'HANDOFF_MATRIX_HISTORICAL_GAP_INVENTION_NOT_RECORDED:{case_id}')
            if observed.get('receiver_completed_assigned_gate') is not False:
                blocking.append(f'HANDOFF_MATRIX_HISTORICAL_GAP_GATE_SHOULD_BE_INCOMPLETE:{case_id}')

            if remediation_ref:
                remediation = load_json(root / remediation_ref)
                if remediation.get('baseline_gap', {}).get('gap_code') != gap_code:
                    blocking.append(f'HANDOFF_MATRIX_REMEDIATION_BASELINE_GAP_MISMATCH:{case_id}')
                producer_fix = remediation.get('producer_side_remediation', {})
                if producer_fix.get('created_candidate_materialized') is not True:
                    blocking.append(f'HANDOFF_MATRIX_REMEDIATION_ARTIFACT_NOT_MATERIALIZED:{case_id}')
                if producer_fix.get('artifact_ref_resolvable') is not True:
                    blocking.append(f'HANDOFF_MATRIX_REMEDIATION_ARTIFACT_NOT_RESOLVABLE:{case_id}')
                if remediation.get('target_outcome_status') != 'NOT_PROVEN':
                    blocking.append(f'HANDOFF_MATRIX_REMEDIATION_FALSE_TARGET_PASS:{case_id}')
                historical_blocks.append({'case_id': case_id, 'blocking_code': NO_EXECUTABLE_RECEIVER})

    return blocking, observed_results, historical_gaps, historical_blocks


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    blocking = []
    warnings = []
    historical_behavioral_blocks = []
    current_behavioral_blocks = []
    artifact_consumability_demonstrated = False
    handoff_matrix_results = {}
    handoff_gaps = []
    layered_status = None

    for rel in REQUIRED_FILES:
        if not (root / rel).exists():
            blocking.append(f'MISSING_REQUIRED_FILE:{rel}')

    if not blocking:
        try:
            good = load_json(root / 'examples/good_output.json')
            bad = load_json(root / 'examples/bad_output.json')
            repair = load_json(root / 'examples/self_repair_output.json')
            eval_matrix = load_json(root / 'evals/eval_matrix.json')
            handoff_contract = load_json(root / 'handoffs/to_quality_pack.handoff.json')
            handoff_matrix = load_json(root / 'evals/handoff_outcome_matrix.json')

            for name, obj in [('good', good), ('bad', bad), ('self_repair', repair)]:
                for field in REQUIRED_OUTPUT_FIELDS:
                    if field not in obj:
                        blocking.append(f'{name.upper()}_MISSING_FIELD:{field}')
                if obj.get('status') not in ALLOWED_STATUSES:
                    blocking.append(f'{name.upper()}_INVALID_STATUS:{obj.get("status")}')

            if good.get('status') != 'LEARNING_CARD_CANDIDATE_CREATED':
                blocking.append('GOOD_EXAMPLE_MUST_CREATE_LEARNING_CARD_CANDIDATE')
            elif not candidate_artifact_is_consistent(good):
                blocking.append('GOOD_EXAMPLE_CREATED_STATE_REQUIRES_CONSUMABLE_CANDIDATE_ARTIFACT')
            if good.get('handoff_target') != handoff_contract.get('to'):
                blocking.append('GOOD_EXAMPLE_HANDOFF_TARGET_CONFLICTS_WITH_HANDOFF_CONTRACT')
            action = str(good.get('proposed_next_action', '')).strip().lower()
            if action.startswith('create ') and 'candidate' in action:
                blocking.append('GOOD_EXAMPLE_NEXT_ACTION_RECREATES_ALREADY_CREATED_CANDIDATE')

            if bad.get('status') != 'BLOCK_PIPELINE':
                blocking.append('BAD_EXAMPLE_MUST_BLOCK_PIPELINE')
            if repair.get('status') != 'RETURN_TO_WORKER_FOR_SELF_REPAIR':
                blocking.append('SELF_REPAIR_EXAMPLE_MUST_RETURN_TO_WORKER')
            if 'MOTHER_RULE_CONSOLIDATION_REQUIRED' not in repair.get('blocking_codes', []):
                blocking.append('SELF_REPAIR_EXAMPLE_MISSING_MOTHER_RULE_BLOCKING_CODE')
            if 'OFFICIAL_IMPACT_WITHOUT_APPROVAL' not in bad.get('blocking_codes', []):
                blocking.append('BAD_EXAMPLE_MISSING_OFFICIAL_IMPACT_BLOCKING_CODE')

            if eval_matrix.get('validation_scope') != 'STRUCTURAL_ONLY':
                blocking.append('EVAL_MATRIX_VALIDATION_SCOPE_MUST_BE_STRUCTURAL_ONLY')
            if eval_matrix.get('behavioral_eval_status') != 'NOT_EXECUTED':
                blocking.append('EVAL_MATRIX_MUST_NOT_CLAIM_BEHAVIORAL_EXECUTION')

            cases = eval_matrix.get('cases', [])
            if len(cases) < 9:
                blocking.append('EVAL_MATRIX_REQUIRES_MINIMUM_9_CASES')

            seen_ids = set()
            eval_types = set()
            regression_statuses = set()
            trace_gate = None
            no_receiver_gate = None
            layered_gate = None
            handoff_outcome_case = None

            for case in cases:
                case_id = case.get('id')
                if not case_id:
                    blocking.append('EVAL_CASE_MISSING_ID')
                    continue
                if case_id in seen_ids:
                    blocking.append(f'EVAL_CASE_DUPLICATE_ID:{case_id}')
                seen_ids.add(case_id)

                eval_type = case.get('eval_type')
                if eval_type not in ALLOWED_EVAL_TYPES:
                    blocking.append(f'EVAL_CASE_INVALID_TYPE:{case_id}:{eval_type}')
                else:
                    eval_types.add(eval_type)

                fixture = case.get('fixture')
                if not fixture or not (root / fixture).exists():
                    blocking.append(f'EVAL_CASE_FIXTURE_NOT_FOUND:{case_id}:{fixture}')
                if case.get('expected_status') not in ALLOWED_STATUSES:
                    blocking.append(f'EVAL_CASE_INVALID_EXPECTED_STATUS:{case_id}:{case.get("expected_status")}')
                if eval_type == 'REGRESSION_EVAL':
                    regression_statuses.add(case.get('expected_status'))

                if case_id == 'trace_without_target_eval':
                    trace_gate = case
                elif case_id == 'handoff_without_executable_receiver':
                    no_receiver_gate = case
                elif case_id == 'handoff_layered_receiver_evidence':
                    layered_gate = case
                elif case_id == 'learning_engine_to_quality_pack_handoff_outcome':
                    handoff_outcome_case = case

            if 'REGRESSION_EVAL' not in eval_types:
                blocking.append('EVAL_MATRIX_MISSING_REGRESSION_EVAL')
            if 'CAPABILITY_EVAL' not in eval_types:
                blocking.append('EVAL_MATRIX_MISSING_CAPABILITY_EVAL')

            if not trace_gate or trace_gate.get('expected_blocking_code') != 'TARGET_EVAL_REQUIRED':
                blocking.append('EVAL_MATRIX_MISSING_TRACE_TARGET_EVAL_GATE')
            if not no_receiver_gate or no_receiver_gate.get('expected_blocking_code') != NO_EXECUTABLE_RECEIVER:
                blocking.append('EVAL_MATRIX_MISSING_EXECUTABLE_RECEIVER_GATE')
            if not layered_gate:
                blocking.append('EVAL_MATRIX_MISSING_LAYERED_RECEIVER_EVIDENCE_GATE')
            else:
                if layered_gate.get('eval_type') != 'CAPABILITY_EVAL':
                    blocking.append('LAYERED_RECEIVER_GATE_MUST_BE_CAPABILITY_EVAL')
                if layered_gate.get('expected_status') != 'RETURN_TO_ORCHESTRATOR':
                    blocking.append('LAYERED_RECEIVER_GATE_MUST_RETURN_TO_ORCHESTRATOR')
                if layered_gate.get('expected_blocking_code') != SEMANTIC_REVIEW_PENDING:
                    blocking.append('LAYERED_RECEIVER_GATE_MISSING_SEMANTIC_REVIEW_BLOCK')
                if layered_gate.get('forbidden_blocking_code') != NO_EXECUTABLE_RECEIVER:
                    blocking.append('LAYERED_RECEIVER_GATE_MUST_FORBID_STALE_NO_RECEIVER_BLOCK')
                if set(layered_gate.get('expected_evidence_layers', [])) != {
                    'DETERMINISTIC_INTAKE', 'SEMANTIC_REVIEW', 'FULL_HANDOFF_OUTCOME'
                }:
                    blocking.append('LAYERED_RECEIVER_GATE_LAYER_SET_INVALID')

                if not blocking:
                    layered_fixture = load_json(root / layered_gate['fixture'])
                    source = layered_fixture.get('source_evidence', {})
                    intake = source.get('deterministic_intake_execution', {})
                    semantic = source.get('semantic_quality_review', {})
                    expected = layered_fixture.get('expected_classification', {})
                    if intake.get('status') != 'PASS':
                        blocking.append('LAYERED_RECEIVER_INTAKE_PASS_NOT_RECORDED')
                    if intake.get('cases_passed') != intake.get('cases_total') or intake.get('cases_total', 0) < 4:
                        blocking.append('LAYERED_RECEIVER_INTAKE_CASES_NOT_ALL_PASS')
                    if set(intake.get('real_producers', [])) != {222, 225}:
                        blocking.append('LAYERED_RECEIVER_REAL_PRODUCERS_NOT_RECORDED')
                    if semantic.get('status') != 'NOT_EXECUTED':
                        blocking.append('LAYERED_RECEIVER_SEMANTIC_STATUS_INVALID')
                    if expected.get('behavioral_blocking_code') != SEMANTIC_REVIEW_PENDING:
                        blocking.append('LAYERED_RECEIVER_EXPECTED_BLOCK_INVALID')
                    if layered_fixture.get('forbidden_blocking_code') != NO_EXECUTABLE_RECEIVER:
                        blocking.append('LAYERED_RECEIVER_FORBIDDEN_BLOCK_INVALID')
                    if not blocking:
                        layered_status = {
                            'DETERMINISTIC_INTAKE': expected.get('deterministic_intake_status'),
                            'SEMANTIC_REVIEW': expected.get('semantic_review_status'),
                            'FULL_HANDOFF_OUTCOME': expected.get('full_handoff_outcome_status'),
                            'source_pr': source.get('quality_pack_pr'),
                            'source_head': source.get('quality_pack_head'),
                            'exact_head_ci_status': intake.get('exact_head_ci_status'),
                        }
                        current_behavioral_blocks.append(SEMANTIC_REVIEW_PENDING)
                        warnings.append('DETERMINISTIC_RECEIVER_INTAKE_PASS_RECORDED')
                        warnings.append('SEMANTIC_QUALITY_REVIEW_NOT_EXECUTED')

            for required in [
                'LEARNING_CARD_CANDIDATE_CREATED',
                'RETURN_TO_ORCHESTRATOR',
                'BLOCK_PIPELINE',
                'RETURN_TO_WORKER_FOR_SELF_REPAIR',
                'HANDOFF_TO_ACT_0045',
            ]:
                if required not in regression_statuses:
                    blocking.append(f'REGRESSION_EVALS_MISSING_EXPECTED_STATUS:{required}')

            if handoff_outcome_case is None:
                blocking.append('EVAL_MATRIX_MISSING_HANDOFF_OUTCOME_CAPABILITY_CASE')
            else:
                if handoff_outcome_case.get('eval_type') != 'CAPABILITY_EVAL':
                    blocking.append('HANDOFF_OUTCOME_CASE_MUST_REMAIN_CAPABILITY_EVAL')
                for key in ['producer_output', 'receiver_output', 'receipt']:
                    rel = handoff_outcome_case.get(key)
                    if not rel or not (root / rel).exists():
                        blocking.append(f'HANDOFF_OUTCOME_{key.upper()}_NOT_FOUND:{rel}')
                if not blocking:
                    producer = load_json(root / handoff_outcome_case['producer_output'])
                    receiver = load_json(root / handoff_outcome_case['receiver_output'])
                    receipt = load_json(root / handoff_outcome_case['receipt'])
                    if producer.get('status') != handoff_outcome_case.get('expected_status'):
                        blocking.append('HANDOFF_OUTCOME_PRODUCER_STATUS_MISMATCH')
                    if not candidate_artifact_is_consistent(producer):
                        blocking.append('HANDOFF_OUTCOME_PRODUCER_CANDIDATE_NOT_OBSERVABLE')
                    if producer.get('handoff_target') != handoff_contract.get('to'):
                        blocking.append('HANDOFF_OUTCOME_TARGET_CONFLICTS_WITH_HANDOFF_CONTRACT')
                    if receiver.get('review_mode') != 'ASSISTED_RUBRIC_REVIEW':
                        blocking.append('HANDOFF_HISTORICAL_REVIEW_MODE_INVALID')
                    if receiver.get('receiver_execution_status') != 'NOT_EXECUTED':
                        blocking.append('HANDOFF_HISTORICAL_FALSE_RECEIVER_EXECUTION')
                    if receipt.get('result') != ASSISTED_RESULT:
                        blocking.append('HANDOFF_HISTORICAL_RECEIPT_RESULT_INVALID')
                    if receipt.get('target_outcome_status') != 'NOT_PROVEN':
                        blocking.append('HANDOFF_HISTORICAL_FALSE_TARGET_PASS')
                    if not blocking:
                        artifact_consumability_demonstrated = True
                        historical_behavioral_blocks.append({
                            'case_id': 'learning_engine_to_quality_pack_historical_assisted_review',
                            'blocking_code': NO_EXECUTABLE_RECEIVER,
                        })

            matrix_blocking, handoff_matrix_results, handoff_gaps, matrix_historical_blocks = validate_handoff_matrix(
                root, handoff_matrix
            )
            blocking.extend(matrix_blocking)
            for item in matrix_historical_blocks:
                if item not in historical_behavioral_blocks:
                    historical_behavioral_blocks.append(item)

            warnings.append('LEARNING_ENGINE_PACK_STRUCTURAL_VALIDATION_ONLY')
            warnings.append('LEARNING_ENGINE_GENERAL_BEHAVIORAL_EVAL_NOT_EXECUTED')
            if artifact_consumability_demonstrated:
                warnings.append('HISTORICAL_ASSISTED_ARTIFACT_CONSUMABILITY_PRESERVED')
            if handoff_gaps:
                warnings.append('HISTORICAL_CROSS_PACK_HANDOFF_GAP_PRESERVED')
            if layered_status and layered_status.get('exact_head_ci_status') == 'PENDING':
                warnings.append('QUALITY_PACK_INTAKE_EXACT_HEAD_CI_PENDING')

        except Exception as exc:
            blocking.append(f'JSON_VALIDATION_ERROR:{exc}')

    structural_pass = not blocking
    result = {
        'status': 'STRUCTURAL_PASS' if structural_pass else 'FAIL',
        'validation_scope': 'STRUCTURAL_ONLY',
        'behavioral_eval_status': 'NOT_EXECUTED',
        'handoff_capability_evidence_status': (
            'DETERMINISTIC_INTAKE_DEMONSTRATED_SEMANTIC_PENDING'
            if structural_pass and layered_status else (
                ASSISTED_RESULT if structural_pass and artifact_consumability_demonstrated else 'NOT_PROVEN'
            )
        ),
        'receiver_evidence_layers': layered_status,
        'verified_handoff_case': None,
        'handoff_matrix_results': handoff_matrix_results,
        'detected_handoff_gaps': handoff_gaps,
        'historical_behavioral_blocks': historical_behavioral_blocks,
        'behavioral_blocking_codes': current_behavioral_blocks,
        'observed_handoff_outcome': (
            'Deterministic Quality Pack intake executed successfully for preserved real producer artifacts from PR #222 and PR #225; semantic Quality Pack review remains unexecuted, so the full handoff outcome is not proven.'
            if structural_pass and layered_status else None
        ),
        'remaining_gap': (
            'Deterministic receiver intake is demonstrated in sandbox. Exact-head CI for the Quality Pack intake PR must be verified, then the semantic Quality Pack review must execute before any full handoff behavioral PASS or semantic capability-to-regression promotion.'
            if structural_pass and layered_status else None
        ),
        'blocking_codes': blocking,
        'warnings': warnings,
        'recommended_action': (
            'Verify exact-head CI for Quality Pack PR #227; then execute SEMANTIC_QUALITY_REVIEW on the preserved producer artifacts and capture actual semantic output, trace and next state. Preserve deterministic intake evidence independently.'
            if structural_pass and layered_status
            else ('RETURN_TO_WORKER_FOR_SELF_REPAIR' if not structural_pass else 'READY_FOR_NEXT_CONTROLLED_EVAL')
        ),
    }
    print(json.dumps(result, indent=2))
    return 0 if structural_pass else 1


if __name__ == '__main__':
    raise SystemExit(main())
