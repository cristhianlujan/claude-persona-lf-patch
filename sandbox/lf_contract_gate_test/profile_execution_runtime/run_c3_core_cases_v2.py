#!/usr/bin/env python3
from __future__ import annotations

import json

import run_c3_core_cases as core

base = core.base

# The canonical validator allows lf_system_fidelity=5 only when both token_map
# and risk_controls carry evidence. The pilot must not invent a risk control just
# to earn a perfect self-score, so cap this self-rating at 4 at generation time.
base.C3_RUNTIME_SCHEMA['properties']['score']['properties']['lf_system_fidelity'] = {
    'type': 'integer',
    'minimum': 0,
    'maximum': 4,
}


def _bullets(input_text: str) -> list[str]:
    return [
        line.strip()[2:].strip()
        for line in input_text.splitlines()
        if line.strip().startswith('- ') and line.strip()[2:].strip()
    ]


_original_guard_for_input = core._guard_for_input


def _guard_for_input(input_text: str) -> str:
    count = len(_bullets(input_text))
    return (
        _original_guard_for_input(input_text)
        + f'''

CORE REQUIREMENT MATERIALIZATION — fail closed
There are exactly {count} authoritative requirement bullets above. Create at least {count} distinct component_tree entries so no detailed requirement can disappear inside a generic category label.
Each authoritative bullet must be materially represented by one or more component_tree.content values and, when the bullet contains state/order/temporal/conditional semantics, by the corresponding state_map.behavior as needed.
Do not count screen_definition, token_map, prompt_constraints, score, handoff or self_verdict as requirement coverage.
Exact cardinalities such as "3 cuotas" must remain explicit. Temporal conditions such as a document being available only after completion must remain explicit. A generic label such as "payment" or "documents" is insufficient.
'''
    ).strip()


core._guard_for_input = _guard_for_input

_original_run = base.run


def _run(label: str, source: str, *, constrained: bool = False) -> dict:
    if constrained:
        count = len(_bullets(base.INPUT))
        component_tree = (
            base.C3_RUNTIME_SCHEMA['properties']['deliverable_created']['properties']['component_tree']
        )
        component_tree['minItems'] = max(1, count)
    return _original_run(label, source, constrained=constrained)


base.run = _run


def _materialized_text(result: dict) -> str:
    if not result.get('json_ok'):
        return ''
    try:
        data = json.loads(result['governed_output'])
    except Exception:
        return ''
    deliverable = data.get('deliverable_created')
    if not isinstance(deliverable, dict):
        return ''
    parts: list[str] = []
    tree = deliverable.get('component_tree')
    if isinstance(tree, list):
        for component in tree:
            if not isinstance(component, dict):
                continue
            for key in ('component_type', 'role', 'content', 'state'):
                value = component.get(key)
                if isinstance(value, str):
                    parts.append(value)
    state_map = deliverable.get('state_map')
    if isinstance(state_map, dict):
        entries = state_map.get('entries')
        if isinstance(entries, list):
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                for key in ('state', 'behavior'):
                    value = entry.get(key)
                    if isinstance(value, str):
                        parts.append(value)
    return '\n'.join(parts)


def _quality(case: dict, result: dict) -> dict:
    materialized = _materialized_text(result)
    requirements = core._requirement_checks(case['key'], materialized)
    canonical_pass, canonical_errors = core._canonical(result)
    authority_pass, authority_detail = core._authority(case, result['governed_output'])
    vector = {
        'json_ok': bool(result.get('json_ok')),
        'canonical_pass': canonical_pass,
        'structural_pass': bool(result.get('structural_pass')),
        'bounded_pass': bool(result.get('bounded_pass')),
        'requirements_pass': all(requirements.values()),
        'no_fences': not bool(result.get('fence')) and not bool(result.get('raw_fence')),
        'placeholder_pass': bool(result.get('placeholder_pass')),
        'authority_pass': authority_pass,
    }
    return {
        'vector': vector,
        'pass': all(vector.values()),
        'requirements': requirements,
        'canonical_errors': canonical_errors,
        'authority_detail': authority_detail,
    }


core._quality = _quality

if __name__ == '__main__':
    raise SystemExit(core.main())
