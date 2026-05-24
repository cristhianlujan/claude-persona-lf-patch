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
    'validators/validate_pack.py',
    'evals/eval_matrix.json',
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


def load_json(path: Path):
    with open(path, 'r', encoding='utf-8') as handle:
        return json.load(handle)


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    blocking = []
    warnings = []

    for rel in REQUIRED_FILES:
        if not (root / rel).exists():
            blocking.append(f'MISSING_REQUIRED_FILE:{rel}')

    if not blocking:
        try:
            good = load_json(root / 'examples/good_output.json')
            bad = load_json(root / 'examples/bad_output.json')
            repair = load_json(root / 'examples/self_repair_output.json')
            eval_matrix = load_json(root / 'evals/eval_matrix.json')

            for name, obj in [('good', good), ('bad', bad), ('self_repair', repair)]:
                for field in REQUIRED_OUTPUT_FIELDS:
                    if field not in obj:
                        blocking.append(f'{name.upper()}_MISSING_FIELD:{field}')
                status = obj.get('status')
                if status not in ALLOWED_STATUSES:
                    blocking.append(f'{name.upper()}_INVALID_STATUS:{status}')

            if good.get('status') != 'LEARNING_CARD_CANDIDATE_CREATED':
                blocking.append('GOOD_EXAMPLE_MUST_CREATE_LEARNING_CARD_CANDIDATE')
            if bad.get('status') != 'BLOCK_PIPELINE':
                blocking.append('BAD_EXAMPLE_MUST_BLOCK_PIPELINE')
            if repair.get('status') != 'RETURN_TO_WORKER_FOR_SELF_REPAIR':
                blocking.append('SELF_REPAIR_EXAMPLE_MUST_RETURN_TO_WORKER')
            if 'MOTHER_RULE_CONSOLIDATION_REQUIRED' not in repair.get('blocking_codes', []):
                blocking.append('SELF_REPAIR_EXAMPLE_MISSING_MOTHER_RULE_BLOCKING_CODE')
            if 'OFFICIAL_IMPACT_WITHOUT_APPROVAL' not in bad.get('blocking_codes', []):
                blocking.append('BAD_EXAMPLE_MISSING_OFFICIAL_IMPACT_BLOCKING_CODE')

            cases = eval_matrix.get('cases', [])
            if len(cases) < 5:
                blocking.append('EVAL_MATRIX_REQUIRES_MINIMUM_5_CASES')
            expected_statuses = {case.get('expected_status') for case in cases}
            for required in [
                'LEARNING_CARD_CANDIDATE_CREATED',
                'RETURN_TO_ORCHESTRATOR',
                'BLOCK_PIPELINE',
                'RETURN_TO_WORKER_FOR_SELF_REPAIR',
                'HANDOFF_TO_ACT_0045',
            ]:
                if required not in expected_statuses:
                    blocking.append(f'EVAL_MATRIX_MISSING_EXPECTED_STATUS:{required}')

            warnings.append('LEARNING_ENGINE_PACK_VALIDATED_STRUCTURALLY')
        except Exception as exc:
            blocking.append(f'JSON_VALIDATION_ERROR:{exc}')

    result = {
        'status': 'PASS' if not blocking else 'FAIL',
        'blocking_codes': blocking,
        'warnings': warnings,
        'recommended_action': 'READY_FOR_QUALITY_PACK' if not blocking else 'RETURN_TO_WORKER_FOR_SELF_REPAIR',
    }
    print(json.dumps(result, indent=2))
    return 0 if not blocking else 1


if __name__ == '__main__':
    raise SystemExit(main())
