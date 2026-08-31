#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import re

import run_c3_core_cases as core

base = core.base
SCORE_KEYS = core.SCORE_KEYS

# Preserve one immutable object-item template. Per-case tuple binding mutates the
# shared runtime schema, so reading component_tree['items'] on the next case would
# return the previous tuple/list instead of the original object schema.
_COMPONENT_ITEM_TEMPLATE = copy.deepcopy(
    base.C3_RUNTIME_SCHEMA['properties']['deliverable_created']['properties']['component_tree']['items']
)

# The canonical validator allows lf_system_fidelity=5 only when both token_map
# and risk_controls carry evidence. The pilot must not invent a risk control just
# to earn a perfect self-score, so cap this self-rating at 4 at generation time.
base.C3_RUNTIME_SCHEMA['properties']['score']['properties']['lf_system_fidelity'] = {
    'type': 'integer',
    'minimum': 0,
    'maximum': 4,
}

# Constrain score evidence refs to canonical, stable refs. The validator accepts
# deliverable sibling keys, component IDs, handoff_to_next and self_verdict. The
# generation grammar cannot know dynamic component IDs in advance, so use the
# canonical sibling refs for each criterion. Mirror the canonical validator's
# substantive-summary boundary in generation rather than weakening validation.
SAFE_EVIDENCE_REFS = {
    'layout_precision': ['layout_grid', 'spacing_typography'],
    'visual_hierarchy': ['visual_hierarchy'],
    'lf_system_fidelity': ['token_map', 'risk_controls'],
    'state_mapping': ['state_map'],
    'handoff_quality': ['handoff_to_next'],
}
_evidence_schema = (
    base.C3_RUNTIME_SCHEMA['properties']['score']['properties']['evidence_by_criterion']['properties']
)
for _criterion, _refs in SAFE_EVIDENCE_REFS.items():
    _evidence_schema[_criterion]['properties']['refs']['items'] = {
        'type': 'string',
        'enum': _refs,
    }
    _evidence_schema[_criterion]['properties']['refs']['minItems'] = 1
    _evidence_schema[_criterion]['properties']['refs']['maxItems'] = len(_refs)
    _evidence_schema[_criterion]['properties']['summary']['minLength'] = 12


def _bullets(input_text: str) -> list[str]:
    return [
        line.strip()[2:].strip()
        for line in input_text.splitlines()
        if line.strip().startswith('- ') and line.strip()[2:].strip()
    ]


_original_guard_for_input = core._guard_for_input


def _guard_for_input(input_text: str) -> str:
    bullets = _bullets(input_text)
    count = len(bullets)
    labeled = '\n'.join(f'REQ-{idx}: {bullet}' for idx, bullet in enumerate(bullets, 1))
    return (
        _original_guard_for_input(input_text)
        + f'''

CORE REQUIREMENT MATERIALIZATION — fail closed
There are exactly {count} authoritative requirement bullets. Treat this mapping as authoritative:
{labeled}

Create exactly one component_tree entry for every REQ-N. Do not spend a component slot on a decorative/title-only component. A requirement component's content must preserve the concrete nouns and all material qualifiers from its REQ-N: exact numbers/cardinalities, named channels/media, required/optional qualifiers, alternatives, and temporal/ordering/conditional relations. Copying the requirement verbatim is preferred to replacing it with a broader category label.
Each requirement component must have its own unique component_id; never reuse a component_id across two REQ-N entries.
A generic title/container such as "Identity Information", "Offer Details", "Documents Required" or "Payment" does NOT satisfy a detailed requirement.
When a requirement contains state/order/temporal/conditional semantics, preserve those semantics in component_tree.content and/or the matching state_map.behavior.
Do not count screen_definition, token_map, prompt_constraints, score, handoff or self_verdict as requirement coverage.
Do not emit unresolved bracket placeholders such as [expiration date] or [document type]. When a concrete value was intentionally not supplied, express only the authorized concept (for example, vigencia/expiración without inventing a date).
Score evidence refs are restricted as follows: layout_precision -> layout_grid or spacing_typography; visual_hierarchy -> visual_hierarchy; lf_system_fidelity -> token_map or risk_controls; state_mapping -> state_map; handoff_quality -> handoff_to_next.
Every score evidence summary must be substantive (at least 12 characters) and describe the evidence in its allowed refs; nominal labels such as ok/pass/valid are not evidence.
score.total MUST equal the arithmetic sum of the five criterion scores.
Canonical PASS scoring is evidence-bound: never emit self_verdict PASS with score.total below 20 or handoff_quality=0. Rate each criterion only from evidence actually present in its allowed refs; do not inflate a score to obtain PASS. If the produced evidence supports a passing deliverable, reflect that evidence consistently in the five criterion scores before returning.
Before returning, verify REQ-1 through REQ-{count} one by one against component_tree/state_map and repair any missing material fact.
'''
    ).strip()


core._guard_for_input = _guard_for_input

_original_run = base.run


def _normalize_derived_score(result: dict) -> dict:
    """Normalize arithmetic score and fail closed on an internally inconsistent PASS."""
    if not result.get('json_ok'):
        return result
    try:
        data = json.loads(result['governed_output'])
    except Exception:
        return result
    score = data.get('score')
    if not isinstance(score, dict):
        return result
    values = [score.get(key) for key in SCORE_KEYS]
    if any(isinstance(value, bool) or not isinstance(value, int) for value in values):
        return result
    score['total'] = sum(values)

    # Do not inflate self-scores to manufacture green. If the model emits PASS
    # while its own evidence-bound score is below the canonical PASS threshold,
    # downgrade only the verdict so the canonical validator can evaluate the
    # deliverable consistently. Content, evidence and criterion scores are kept.
    pass_verdicts = {'PASS_TO_QUALITY_PACK_CANDIDATE', 'PASS_TO_QUALITY_PACK', 'PASS'}
    if data.get('self_verdict') in pass_verdicts and (
        score['total'] < 20 or score.get('handoff_quality') == 0
    ):
        data['self_verdict'] = 'NEEDS_ADJUSTMENT'

    rendered = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    result['governed_output'] = rendered
    result['output_bytes'] = len(rendered.encode('utf-8'))
    return result


def _run(label: str, source: str, *, constrained: bool = False) -> dict:
    if constrained:
        bullets = _bullets(base.INPUT)
        component_tree = (
            base.C3_RUNTIME_SCHEMA['properties']['deliverable_created']['properties']['component_tree']
        )
        # Bind each authoritative requirement to one deterministic array position.
        # Always rebuild from the immutable object template so sequential cases do
        # not inherit the previous case's tuple/list schema. Bind a deterministic
        # component_id per position so the canonical duplicate-ID guard is enforced
        # by generation instead of repaired after the fact.
        tuple_items = []
        for idx, bullet in enumerate(bullets, 1):
            item = copy.deepcopy(_COMPONENT_ITEM_TEMPLATE)
            item['properties']['component_id'] = {
                'type': 'string',
                'enum': [f'req_{idx}'],
            }
            item['properties']['content'] = {
                'type': 'string',
                'enum': [bullet],
            }
            tuple_items.append(item)
        if tuple_items:
            component_tree.pop('minItems', None)
            component_tree.pop('maxItems', None)
            component_tree['items'] = tuple_items
        else:
            component_tree['minItems'] = 1
            component_tree['maxItems'] = 1
            item = copy.deepcopy(_COMPONENT_ITEM_TEMPLATE)
            item['properties']['content'] = {'type': 'string', 'enum': ['']}
            component_tree['items'] = item
    result = _original_run(label, source, constrained=constrained)
    if constrained:
        result = _normalize_derived_score(result)
    return result


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
    unresolved_placeholder = bool(re.search(r'\[[^\]\n]{2,80}\]', materialized))
    vector = {
        'json_ok': bool(result.get('json_ok')),
        'canonical_pass': canonical_pass,
        'structural_pass': bool(result.get('structural_pass')),
        'bounded_pass': bool(result.get('bounded_pass')),
        'requirements_pass': all(requirements.values()),
        'no_fences': not bool(result.get('fence')) and not bool(result.get('raw_fence')),
        'placeholder_pass': bool(result.get('placeholder_pass')) and not unresolved_placeholder,
        'authority_pass': authority_pass,
    }
    return {
        'vector': vector,
        'pass': all(vector.values()),
        'requirements': requirements,
        'canonical_errors': canonical_errors,
        'authority_detail': authority_detail,
        'unresolved_placeholder': unresolved_placeholder,
    }


core._quality = _quality

if __name__ == '__main__':
    raise SystemExit(core.main())
