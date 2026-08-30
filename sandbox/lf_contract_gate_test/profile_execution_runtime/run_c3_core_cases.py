#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import re
from pathlib import Path

import run_c3_context_selector_pilot_v2 as v2

base = v2.base
ROOT = base.ROOT
VALIDATOR_PATH = ROOT / 'profiles/ui_architect/validators/validate_ui_architect_output.py'

SCORE_KEYS = [
    'layout_precision',
    'visual_hierarchy',
    'lf_system_fidelity',
    'state_mapping',
    'handoff_quality',
]

EVIDENCE_ITEM = {
    'type': 'object',
    'additionalProperties': False,
    'properties': {
        'refs': {'type': 'array', 'maxItems': 2, 'items': {'type': 'string'}},
        'summary': {'type': 'string'},
    },
    'required': ['refs', 'summary'],
}

# Align the pilot-only generation boundary to the canonical validator without
# modifying profiles/ui_architect/SKILL.md or the canonical runtime schema.
base.C3_RUNTIME_SCHEMA['properties']['score']['properties']['evidence_by_criterion'] = {
    'type': 'object',
    'additionalProperties': False,
    'properties': {key: EVIDENCE_ITEM for key in SCORE_KEYS},
    'required': SCORE_KEYS,
}

BASE_OUTPUT_GUARD = '''
RUNTIME OUTPUT GUARD — deterministic materialization
Return one compact JSON object only; no Markdown fences or prose.
Root keys exactly: worker, output_type, deliverable_created, score, handoff_to_next, self_verdict.
output_type must be PRODUCTION_UI_SPEC. screen_definition.task_mode must be CREATE_NEW.
deliverable_created sibling keys exactly: screen_definition, component_tree, layout_grid, visual_hierarchy, state_map, token_map, spacing_typography, density_rules, risk_controls, prompt_constraints.
component_tree is flat and bounded; content is terminal text; relationships use IDs only.
visual_hierarchy is a flat array of {parent_id:string, child_ids:[string,...]}; child_ids NEVER contains objects.
For generic key/value metadata use {entries:[{key:string,value:string}, ...]}.
state_map uses {entries:[{component_id:string,state:string,behavior:string}, ...]}.
Keep every section minimal and factual. Do not repeat supplied facts merely to fill fields.
score.evidence_by_criterion is an object with exactly: layout_precision, visual_hierarchy, lf_system_fidelity, state_mapping, handoff_quality.
Each criterion value is {refs:[...],summary:string}; refs must name actual deliverable sibling keys, component IDs, handoff_to_next, or self_verdict. Use short substantive summaries, not nominal words like ok/pass.
Use layout_grid for layout_precision evidence, visual_hierarchy for visual_hierarchy, token_map or risk_controls for lf_system_fidelity, state_map for state_mapping, and handoff_to_next for handoff_quality when applicable.
self_verdict must use a canonical validator value such as PASS, NEEDS_ADJUSTMENT, RETURN_TO_WORKER_FOR_SELF_REPAIR, RETURN_TO_ORCHESTRATOR, BLOCK_PIPELINE or BLOCKED.
Never invent amounts, dates, eligibility criteria, legal effects, payment states, channels, options, conditions or requirements not supplied.
'''.strip()


def _requirement_capsule(input_text: str) -> str:
    """Copy user-supplied bullet requirements without semantic rewriting."""
    bullets = []
    for line in input_text.splitlines():
        stripped = line.strip()
        if stripped.startswith('- '):
            value = stripped[2:].strip()
            if value:
                bullets.append(value)
    return '\n'.join(f'- {value}' for value in bullets)


def _guard_for_input(input_text: str) -> str:
    capsule = _requirement_capsule(input_text)
    return (
        BASE_OUTPUT_GUARD
        + '''

AUTHORITATIVE REQUIREMENT CAPSULE — deterministic copy from the user input
'''
        + capsule
        + '''

MATERIALIZATION GATE — mandatory before self_verdict
Every capsule bullet is atomic authority. The final component_tree/state_map must visibly and unambiguously encode every bullet; a generic category label does NOT satisfy a detailed bullet.
Preserve exact numbers/cardinalities and named values. Preserve every supplied alternative/option instead of collapsing them into a parent category.
Preserve every named channel or medium. Preserve required/optional qualifiers. Preserve temporal, ordering and conditional relations such as before/after/only-when/until; naming only the affected object is insufficient.
When one bullet contains multiple atomic facts, all of those facts must remain explicit in component content and/or state_map behavior.
Before returning, compare the final JSON against every capsule bullet and repair any missing fact. Do not add new domain truth while doing so.
'''
    ).strip()


CASES = [
    {
        'key': 'CASE1',
        'mode': 'PILOT',
        'allowed_currency': {'8000', '3200', '4800'},
        'input': '''Define una nueva pantalla de oferta de deuda.

Datos autorizados:
- Deuda original: S/ 8,000
- Oferta: S/ 3,200
- Ahorro: S/ 4,800
- Formas de pago: contado o cuotas
- Debe existir un CTA principal.

Modo operativo: PILOT.
Especialidades activas: financial UX y trust clarity.

Conserva todos los requisitos suministrados.
No inventes información financiera, legal o de elegibilidad no proporcionada.''',
    },
    {
        'key': 'CASE2',
        'mode': 'EXPERT',
        'allowed_currency': set(),
        'input': '''Define una nueva pantalla para gestión de pago en cuotas.

Requisitos autorizados y obligatorios:
- Deben existir exactamente 3 cuotas.
- Debe ser visible el concepto de vencimiento de cada cuota, sin inventar fechas concretas.
- Medio de pago: tarjeta.
- Debe existir manejo visible de fallo y reintento.
- Debe existir comprobante.
- La carta de no adeudo solo puede mostrarse como disponible después de completar todas las cuotas.

Modo operativo: EXPERT.
Especialidades activas: payments recovery, trust clarity y documents evidence.

Conserva todos los requisitos suministrados.
No inventes montos, fechas concretas, efectos legales ni estados de pago no proporcionados.''',
    },
    {
        'key': 'CASE3',
        'mode': 'FULL',
        'allowed_currency': set(),
        'input': '''Define una nueva pantalla de identidad, consentimiento y oferta.

Requisitos autorizados y obligatorios:
- DNI requerido.
- OTP requerido.
- Consentimiento explícito para contacto por WhatsApp y correo electrónico.
- Debe mostrarse el concepto de vigencia o expiración de la oferta sin inventar una fecha concreta.
- Debe existir un mensaje de elegibilidad sin inventar criterios de elegibilidad.
- La carga de documento es opcional.

Modo operativo: FULL.
Especialidades activas: identity consent privacy, offers campaigns, trust clarity y documents evidence.

Conserva todos los requisitos suministrados.
No inventes importes, criterios de elegibilidad, urgencia, fechas concretas ni efectos legales.''',
    },
]


def _load_validator():
    spec = importlib.util.spec_from_file_location('ui_architect_validator', VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError('CANONICAL_VALIDATOR_IMPORT_FAILED')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


VALIDATOR = _load_validator()


def _has(text: str, *terms: str) -> bool:
    low = text.casefold()
    return any(term.casefold() in low for term in terms)


def _requirement_checks(case_key: str, text: str) -> dict[str, bool]:
    low = text.casefold()
    if case_key == 'CASE1':
        return {
            'debt': '8000' in low or '8,000' in low,
            'offer': '3200' in low or '3,200' in low,
            'savings': '4800' in low or '4,800' in low,
            'cash': _has(text, 'contado', 'cash', 'single payment', 'one-time'),
            'installments': _has(text, 'cuota', 'installment'),
            'cta': _has(text, 'cta', 'button', 'botón', 'continuar', 'pagar'),
        }
    if case_key == 'CASE2':
        clearance = _has(text, 'carta de no adeudo', 'constancia de no adeudo', 'clearance letter')
        completion = _has(
            text,
            'después de completar todas las cuotas', 'despues de completar todas las cuotas',
            'al completar todas las cuotas', 'después del pago final', 'despues del pago final',
            'after all installments', 'after completion', 'after final payment',
        )
        return {
            'three_installments': bool(re.search(r'\b3\s+(?:cuotas|installments)\b', low)),
            'due_dates': _has(text, 'vencimiento', 'due date'),
            'card': _has(text, 'tarjeta', 'card'),
            'failure': _has(text, 'fallo', 'error de pago', 'payment failure', 'failed payment'),
            'retry': _has(text, 'reintento', 'reintentar', 'retry'),
            'receipt': _has(text, 'comprobante', 'receipt'),
            'clearance_after_completion': clearance and completion,
        }
    if case_key == 'CASE3':
        return {
            'dni': _has(text, 'dni'),
            'otp': _has(text, 'otp'),
            'whatsapp': _has(text, 'whatsapp'),
            'email': _has(text, 'correo', 'email'),
            'explicit_consent': _has(text, 'consentimiento explícito', 'consentimiento explicito', 'explicit consent', 'consentimiento'),
            'offer_expiry': _has(text, 'vigencia', 'expiración', 'expiracion', 'vence', 'expiry', 'expiration'),
            'eligibility': _has(text, 'elegibilidad', 'eligibility'),
            'document_upload': _has(text, 'documento', 'document', 'upload', 'carga'),
            'optional_document': _has(text, 'opcional', 'optional'),
        }
    raise ValueError(case_key)


def _authority(case: dict, text: str) -> tuple[bool, dict]:
    allowed = set(case['allowed_currency'])
    currency_values = [
        re.sub(r'[^0-9]', '', value)
        for value in re.findall(r'S/\s*([0-9][0-9.,]*)', text, flags=re.I)
    ]
    invented_currency = sorted({v for v in currency_values if v and v not in allowed})
    concrete_dates = sorted(set(re.findall(r'\b\d{2}[/-]\d{2}(?:[/-]\d{2,4})?\b', text)))
    month_dates = sorted(set(re.findall(
        r'\b\d{1,2}\s+de\s+(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)(?:\s+de\s+\d{4})?\b',
        text.casefold(),
    )))
    banned = []
    low = text.casefold()
    common_claims = ['garantizado', 'garantizada', 'obligatorio por ley', 'legalmente asegurado']
    for term in common_claims:
        if term in low:
            banned.append(term)
    if case['key'] == 'CASE3':
        for term in ['ingreso mínimo', 'ingreso minimo', 'edad mínima', 'edad minima', 'score crediticio', 'historial crediticio', 'central de riesgo', 'salario mínimo', 'salario minimo']:
            if term in low:
                banned.append(term)
    detail = {
        'invented_currency': invented_currency,
        'invented_dates': concrete_dates + month_dates,
        'invented_claim_terms': sorted(set(banned)),
    }
    return not any(detail.values()), detail


def _canonical(result: dict) -> tuple[bool, list[dict]]:
    if not result.get('json_ok'):
        return False, [{'code': 'JSON_INVALID', 'detail': result.get('json_error')}]
    try:
        data = json.loads(result['governed_output'])
    except Exception as exc:
        return False, [{'code': 'JSON_REPARSE_FAILED', 'detail': str(exc)}]
    errors = VALIDATOR.validate(data)
    return not errors, errors


def _quality(case: dict, result: dict) -> dict:
    text = result['governed_output']
    requirements = _requirement_checks(case['key'], text)
    canonical_pass, canonical_errors = _canonical(result)
    authority_pass, authority_detail = _authority(case, text)
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


def _metrics(result: dict) -> dict:
    return {
        'runtime_seconds': result['runtime_seconds'],
        'profile_context_bytes': result['profile_context_bytes'],
        'output_bytes': result['output_bytes'],
        'raw_output_bytes': result['raw_output_bytes'],
        'llm_calls': result['llm_calls'],
        'round_trips': result['round_trips'],
        'max_output_tokens': result['max_output_tokens'],
    }


def main() -> int:
    full = base.SKILL.read_text(encoding='utf-8')
    c3 = base.select_c3(full)
    all_results = []

    for case in CASES:
        base.INPUT = case['input']
        base.ALLOWED_CURRENCY_AMOUNTS = set(case['allowed_currency'])
        # Both variants receive the same deterministic authority capsule so the
        # experiment still isolates full-vs-selected profile context.
        base.OUTPUT_GUARD = _guard_for_input(case['input'])
        a = base.run(f"A_FULL_{case['key']}", full, constrained=False)
        c = base.run(f"C3_SELECTED_{case['key']}", c3, constrained=True)
        qa = _quality(case, a)
        qc = _quality(case, c)
        not_worse = all((not qa['vector'][k]) or qc['vector'][k] for k in qc['vector'])
        perf = {
            'context_reduction_pct': round((1 - c['profile_context_bytes'] / a['profile_context_bytes']) * 100, 2),
            'runtime_change_pct': round((c['runtime_seconds'] / a['runtime_seconds'] - 1) * 100, 2) if a['runtime_seconds'] else None,
            'output_change_pct': round((c['output_bytes'] / a['output_bytes'] - 1) * 100, 2) if a['output_bytes'] else None,
            'llm_calls_change': c['llm_calls'] - a['llm_calls'],
            'round_trips_change': c['round_trips'] - a['round_trips'],
        }
        case_pass = bool(qc['pass'] and not_worse)
        summary = {
            'case': case['key'],
            'mode': case['mode'],
            'pass': case_pass,
            'quality_c3_not_worse': not_worse,
            'A_quality': qa,
            'C3_quality': qc,
            'A_metrics': _metrics(a),
            'C3_metrics': _metrics(c),
            'performance': perf,
        }
        all_results.append(summary)
        print('C3_CORE_CASE=' + json.dumps(summary, ensure_ascii=False, sort_keys=True))
        print(f"C3_CORE_{case['key']}_GOVERNED_BEGIN")
        print(c['governed_output'])
        print(f"C3_CORE_{case['key']}_GOVERNED_END")

    core_pass = all(item['pass'] for item in all_results)
    result = {
        'core_cases_passed': sum(1 for item in all_results if item['pass']),
        'core_cases_total': len(all_results),
        'core_pass': core_pass,
        'replication_unlocked': core_pass,
    }
    print('C3_CORE_SUMMARY=' + json.dumps(result, ensure_ascii=False, sort_keys=True))
    print('C3_CORE_VERDICT=' + ('CORE_3_OF_3_PASS' if core_pass else 'NO_MASSIFY'))
    return 0 if core_pass else 2


if __name__ == '__main__':
    raise SystemExit(main())
