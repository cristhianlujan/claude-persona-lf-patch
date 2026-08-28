#!/usr/bin/env python3
import json
import sys
from pathlib import Path

ALLOWED = {
    'ALLOW_CANDIDATE',
    'RETURN_TO_ORCHESTRATOR',
    'RETURN_TO_WORKER_FOR_SELF_REPAIR',
    'BLOCK_PIPELINE',
}
CEILING_RANK = {
    'STRUCTURAL_ONLY': 0,
    'PROVENANCE_ONLY': 1,
    'SEMANTIC_SUPPORTED': 2,
    'BEHAVIORAL_PROVEN': 3,
}
CLAIM_RANK = {
    'STRUCTURAL_ONLY': 0,
    'PROVENANCE_ONLY': 1,
    'SEMANTIC_PASS': 2,
    'BEHAVIORAL_PASS': 3,
}


def load(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


def judge(fixture: dict):
    effect = fixture.get('correction_effect')
    post = fixture.get('postcondition_effect')
    if effect == 'INCREASES_DEFECT' or post == 'INCREASES_DEFECT':
        return 'RETURN_TO_WORKER_FOR_SELF_REPAIR', 'DEFECT_DIRECTION_INVERTED'
    if effect in (None, 'UNKNOWN') or post in (None, 'UNKNOWN'):
        return 'RETURN_TO_ORCHESTRATOR', 'CORRECTIVE_POSTCONDITION_UNPROVEN'

    if fixture.get('causal_link') == 'UNSUPPORTED':
        return 'RETURN_TO_WORKER_FOR_SELF_REPAIR', 'UNSUPPORTED_CAUSAL_LEAP'

    upstream = fixture.get('upstream', {})
    if upstream.get('required'):
        valid = (
            upstream.get('exists')
            and upstream.get('current')
            and upstream.get('exact_sha_match')
            and upstream.get('validator_status') in {'PASS', 'VALID', 'NOT_APPLICABLE'}
        )
        if not valid:
            return 'RETURN_TO_ORCHESTRATOR', 'UPSTREAM_NOT_VALID'

    provenance = fixture.get('provenance', {})
    if provenance.get('claimed') and not provenance.get('receipt_valid'):
        return 'BLOCK_PIPELINE', 'PROVENANCE_NOT_VERIFIED'

    semantic = fixture.get('semantic', {})
    if semantic.get('claimed_pass'):
        if semantic.get('independent_judge_status') != 'PASS':
            return 'BLOCK_PIPELINE', 'PROVENANCE_IS_NOT_SEMANTIC_PROOF'
        if fixture.get('semantic_oracle') != 'INDEPENDENT':
            return 'BLOCK_PIPELINE', 'SEMANTIC_ORACLE_NOT_INDEPENDENT'

    ceiling = fixture.get('evidence_ceiling', 'STRUCTURAL_ONLY')
    claim = fixture.get('claim_level', 'STRUCTURAL_ONLY')
    if CEILING_RANK.get(ceiling, -1) < CLAIM_RANK.get(claim, 99):
        return 'BLOCK_PIPELINE', 'EVIDENCE_CEILING_EXCEEDED'

    resolved = set(fixture.get('resolved_inputs', []))
    reasked = set(fixture.get('reasked_inputs', []))
    if resolved & reasked:
        return 'RETURN_TO_WORKER_FOR_SELF_REPAIR', 'RESOLVED_INPUT_REASKED'

    coverage = fixture.get('coverage', {})
    required = list(coverage.get('required_obligation_ids', []))
    checks = list(coverage.get('check_ids', []))
    if required:
        complete = (
            coverage.get('manifest_complete')
            and len(required) == len(set(required))
            and len(checks) == len(set(checks))
            and set(required) == set(checks)
        )
        if not complete:
            return 'RETURN_TO_ORCHESTRATOR', 'SEMANTIC_COVERAGE_INCOMPLETE'

    if fixture.get('known_vs_new') == 'NEW_UNPROVEN' and fixture.get('generalized_as_known'):
        return 'RETURN_TO_WORKER_FOR_SELF_REPAIR', 'NEW_CAPABILITY_GENERALIZED_AS_KNOWN'

    if fixture.get('domain_ownership') == 'TAKEN_OVER':
        return 'BLOCK_PIPELINE', 'DOMAIN_OWNERSHIP_VIOLATION'

    return 'ALLOW_CANDIDATE', None


def main() -> int:
    matrix_path = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path(__file__).resolve().parents[1] / 'evals' / 'semantic_support_matrix.json'
    )
    data = load(matrix_path)
    failures = []
    seen = set()
    cases = data.get('cases', [])

    if data.get('validation_scope') != 'DETERMINISTIC_SUPPORT_CONTRACT_ONLY_NOT_BEHAVIORAL':
        failures.append('MATRIX_SCOPE_MUST_BE_DETERMINISTIC_ONLY')
    if data.get('general_behavioral_eval_status') != 'NOT_CLAIMED':
        failures.append('MATRIX_MUST_NOT_CLAIM_GENERAL_BEHAVIOR')
    if len(cases) < 20:
        failures.append('MATRIX_REQUIRES_20_CASES')

    for case in cases:
        case_id = case.get('id')
        if not case_id or case_id in seen:
            failures.append(f'BAD_CASE_ID:{case_id}')
            continue
        seen.add(case_id)
        expected = case.get('expected', {})
        if expected.get('action') not in ALLOWED:
            failures.append(f'BAD_EXPECTED_ACTION:{case_id}')
            continue
        actual_action, actual_code = judge(case.get('fixture', {}))
        if (actual_action, actual_code) != (
            expected.get('action'), expected.get('blocking_code')
        ):
            failures.append(
                f'MISMATCH:{case_id}:expected={expected.get("action")}/'
                f'{expected.get("blocking_code")}:actual={actual_action}/{actual_code}'
            )

    result = {
        'status': 'PASS' if not failures else 'FAIL',
        'cases_passed': len(cases) - len(failures),
        'cases_total': len(cases),
        'failures': failures,
        'scope': 'DETERMINISTIC_SUPPORT_CONTRACT_ONLY_NOT_BEHAVIORAL',
    }
    print(json.dumps(result, indent=2))
    return 0 if not failures else 1


if __name__ == '__main__':
    raise SystemExit(main())
