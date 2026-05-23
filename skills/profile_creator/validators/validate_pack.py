#!/usr/bin/env python3
import json, sys
from pathlib import Path

REQUIRED_FILES = [
 'SKILL.md','README.md','contracts/main_contract.md','contracts/missing_input_policy.md',
 'schemas/output.schema.json','schemas/missing_input.schema.json','judges/score_rubric.md','judges/mini_judge.md',
 'checklists/preflight_checklist.md','checklists/priority_checklist.md','examples/good_output.json','examples/bad_output.json',
 'examples/self_repair_output.json','fixtures/happy_path/input.json','fixtures/missing_inputs/input.json',
 'fixtures/unsafe_or_blocked/input.json','fixtures/self_repair/bad_output.json','validators/validate_pack.py',
 'evals/eval_matrix.json','handoffs/to_quality_pack.handoff.json','adapters/github_pack_adapter.md','adapters/document_patch_adapter.md'
]

def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    blocking, warnings = [], []
    for rel in REQUIRED_FILES:
        if not (root / rel).exists():
            blocking.append(f'MISSING_REQUIRED_FILE:{rel}')
    if not blocking:
        try:
            good = load_json(root / 'examples/good_output.json')
            repair = load_json(root / 'examples/self_repair_output.json')
            bad = load_json(root / 'examples/bad_output.json')
            for name, obj in [('good', good), ('self_repair', repair)]:
                for field in ['status','profile_pack_id','source_authority','deliverable_created','files_created','evidence_map','blocking_codes','next_gate']:
                    if field not in obj:
                        blocking.append(f'{name.upper()}_MISSING_FIELD:{field}')
            if 'BASIC_PROFILE_OUTPUT_NOT_ACCEPTABLE' not in bad.get('blocking_codes', []):
                blocking.append('BAD_EXAMPLE_MISSING_BASIC_PROFILE_OUTPUT_BLOCKING_CODE')
            else:
                warnings.append('BAD_EXAMPLE_CORRECTLY_SHOWS_PROFILE_ONLY_FAILURE')
        except Exception as exc:
            blocking.append(f'JSON_VALIDATION_ERROR:{exc}')
    result = {
        'status': 'PASS' if not blocking else 'FAIL',
        'blocking_codes': blocking,
        'warnings': warnings,
        'recommended_action': 'READY_FOR_QUALITY_PACK' if not blocking else 'RETURN_TO_WORKER_FOR_SELF_REPAIR'
    }
    print(json.dumps(result, indent=2))
    return 0 if not blocking else 1

if __name__ == '__main__':
    raise SystemExit(main())
