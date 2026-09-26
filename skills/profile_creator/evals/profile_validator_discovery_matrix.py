#!/usr/bin/env python3
import ast
import json
from pathlib import Path

VALIDATOR = Path(__file__).resolve().parents[1] / 'validators' / 'validate_pack.py'
source = VALIDATOR.read_text(encoding='utf-8')
tree = ast.parse(source)

function_names = {
    node.name
    for node in ast.walk(tree)
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
}
string_literals = [
    node.value
    for node in ast.walk(tree)
    if isinstance(node, ast.Constant) and isinstance(node.value, str)
]
checks_append_calls = [
    node
    for node in ast.walk(tree)
    if isinstance(node, ast.Call)
    and isinstance(node.func, ast.Attribute)
    and isinstance(node.func.value, ast.Name)
    and node.func.value.id == 'checks'
    and node.func.attr == 'append'
]

cases = [
    {
        'id': 'no_cross_profile_discovery_function',
        'passed': 'discover_profile_validators' not in function_names,
    },
    {
        'id': 'no_dynamic_cross_pack_check_append',
        'passed': len(checks_append_calls) == 0,
    },
    {
        'id': 'no_dynamic_profile_pack_check_namespace',
        'passed': all('PROFILE_PACK::' not in value for value in string_literals),
    },
    {
        'id': 'declares_local_pack_scope',
        'passed': "'validation_scope': 'PROFILE_CREATOR_PACK_ONLY'" in source,
    },
    {
        'id': 'declares_transversal_discovery_not_executed',
        'passed': "'transversal_pack_discovery_executed': False" in source,
    },
    {
        'id': 'declares_transversal_execution_not_executed',
        'passed': "'transversal_pack_execution_executed': False" in source,
    },
    {
        'id': 'delegates_transversal_owner',
        'passed': "'transversal_pack_owner': 'PACK_VALIDATION'" in source,
    },
]

passed = all(case['passed'] for case in cases)
print(json.dumps({
    'passed': passed,
    'case_count': len(cases),
    'legacy_filename_note': 'This historical eval filename is retained for compatibility; its contract now enforces the profile_creator local-pack boundary.',
    'owner': 'PROFILE_CREATOR',
    'transversal_pack_owner': 'PACK_VALIDATION',
    'cases': cases,
}, indent=2))
raise SystemExit(0 if passed else 1)
