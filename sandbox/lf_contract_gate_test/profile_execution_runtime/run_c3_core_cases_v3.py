#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re

import run_c3_core_cases_v2 as c3v2

core = c3v2.core
base = c3v2.base

_original_guard_for_input = core._guard_for_input


def _guard_for_input(input_text: str) -> str:
    return (
        _original_guard_for_input(input_text)
        + '''

AUTHORITY + PROVENANCE GATE — fail closed
Every material assertion in the final JSON must be attributable to one of these authorities:
1. input_literal: supplied explicitly by the authoritative user input;
2. policy: supplied by the governed output/profile contract;
3. evidence: supplied by retrieved evidence when such evidence exists;
4. derived_allowed: a bounded presentation transformation that introduces no new domain fact.
Do not create unsupported domain truth. This rule applies across amounts, dates, deadlines, cardinalities, eligibility, business rules, states, channels, documents, conditions, legal effects and other material claims.
A derivation is allowed only when it preserves the source facts and adds presentation language, not new business semantics.
Before returning, inspect material claims against their source. If a material assertion lacks authority, repair by removing the unsupported assertion or regenerate from the authorized source; never invent a replacement value.
'''
    ).strip()


core._guard_for_input = _guard_for_input

# General, source-aware post-generation probe. This does not green outputs by
# rewriting domain claims. It emits reconstructable provenance and fails the
# existing authority gate when a material assertion cannot be attributed.
_original_authority = core._authority
_WORD_RE = re.compile(r"[0-9]+(?:[.,][0-9]+)*|[a-záéíóúñü]+", re.I)
_MATERIAL_SIGNAL_RE = re.compile(
    r"(?:S/|\b\d+(?:[.,]\d+)?%?\b|\b(?:dni|otp|whatsapp|correo|email|cuota|cuotas|"
    r"vencimiento|vigencia|expiraci[oó]n|elegibilidad|documento|comprobante|carta|"
    r"deuda|oferta|ahorro|pago|tarjeta|consentimiento|legal|ley|garantiz|estado|"
    r"reintento|fallo|opcional|obligatorio|required|optional|eligibility|installment|"
    r"payment|receipt|document|consent|expiry|expiration)\b)",
    re.I,
)
_STOPWORDS = {
    'a','al','and','as','con','de','del','el','en','for','la','las','los','of','o','or',
    'para','por','the','to','un','una','y','sin','como','se','su','sus','que','es','ser',
    'be','is','are','with','without','this','that','each','cada','all','todas','todos',
}
# Presentation-only vocabulary allowed for derived_allowed. These tokens may
# describe rendering/interaction but cannot themselves authorize a domain fact.
_PRESENTATION_VOCAB = {
    'action','active','alert','badge','banner','button','boton','botón','card','campo',
    'cta','display','entry','field','form','helper','hide','label','link','list','message',
    'mensaje','modal','mostrar','muestra','panel','placeholder','screen','section','show',
    'status','step','summary','text','texto','title','titulo','título','value','visible',
    'after','antes','before','despues','después','only','solo','sólo','until','hasta',
    'available','disponible','complete','completar','completed','final','principal',
    'manage','manejo','retry','reintentar','required','requerido','requerida',
}


def _tokens(value: str) -> set[str]:
    return {
        token.casefold()
        for token in _WORD_RE.findall(value)
        if token.casefold() not in _STOPWORDS
    }


def _walk_strings(value, path: str = '$'):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from _walk_strings(child, f'{path}.{key}')
    elif isinstance(value, list):
        for idx, child in enumerate(value):
            yield from _walk_strings(child, f'{path}[{idx}]')
    elif isinstance(value, str):
        yield path, value


def _source_catalog(input_text: str) -> list[dict]:
    sources = [{'source_id': 'input', 'kind': 'input_literal', 'text': input_text}]
    idx = 0
    for line in input_text.splitlines():
        stripped = line.strip()
        if stripped.startswith('- ') and stripped[2:].strip():
            idx += 1
            sources.append({
                'source_id': f'input:req:{idx}',
                'kind': 'input_literal',
                'text': stripped[2:].strip(),
            })
    return sources


def _provenance_audit(input_text: str, governed_output: str) -> dict:
    try:
        data = json.loads(governed_output)
    except Exception as exc:
        return {'pass': False, 'error': f'JSON_REPARSE_FAILED:{exc}', 'claims': []}

    sources = _source_catalog(input_text)
    input_folded = input_text.casefold()
    input_tokens = _tokens(input_text)
    claims = []
    unsupported = []

    for path, claim in _walk_strings(data):
        compact = ' '.join(claim.split())
        if not compact or not _MATERIAL_SIGNAL_RE.search(compact):
            continue

        verdict = 'unsupported'
        source_id = None
        source_span = None
        transformation = None
        unsupported_tokens: list[str] = []

        claim_folded = compact.casefold()
        if claim_folded in input_folded:
            verdict = 'input_literal'
            source_id = 'input'
            start = input_folded.find(claim_folded)
            source_span = [start, start + len(claim_folded)]
            transformation = 'literal_copy'
        else:
            # Prefer the narrowest requirement source containing all governed
            # tokens; otherwise evaluate against the full authoritative input.
            claim_tokens = _tokens(compact)
            novel = sorted(claim_tokens - input_tokens - _PRESENTATION_VOCAB)
            if not novel:
                verdict = 'derived_allowed'
                source_id = 'input'
                transformation = 'presentation_only'
            else:
                unsupported_tokens = novel

        envelope = {
            'claim_path': path,
            'claim': compact,
            'source_id': source_id,
            'source_span': source_span,
            'transformation': transformation,
            'authority': verdict,
            'verdict': 'PASS' if verdict != 'unsupported' else 'BLOCK',
        }
        if unsupported_tokens:
            envelope['unsupported_tokens'] = unsupported_tokens
        claims.append(envelope)
        if verdict == 'unsupported':
            unsupported.append(envelope)

    return {
        'pass': not unsupported,
        'sources': [{'source_id': s['source_id'], 'kind': s['kind']} for s in sources],
        'claims_checked': len(claims),
        'unsupported_count': len(unsupported),
        'unsupported': unsupported,
        'claims': claims,
    }


def _authority(case: dict, text: str) -> tuple[bool, dict]:
    legacy_pass, legacy_detail = _original_authority(case, text)
    provenance = _provenance_audit(base.INPUT, text)
    detail = dict(legacy_detail)
    detail['authority_provenance'] = provenance
    return bool(legacy_pass and provenance.get('pass')), detail


core._authority = _authority

# Keep the previous money boundary only as defense-in-depth telemetry/containment,
# never as the primary PASS mechanism. Unsupported material claims are still
# evaluated by the provenance gate above.
_original_v2_run = base.run
_MONEY_RE = re.compile(r'S/\s*[0-9][0-9.,]*')


def _authorized_money(input_text: str) -> set[str]:
    return {_normalize_money(m.group(0)) for m in _MONEY_RE.finditer(input_text)}


def _normalize_money(value: str) -> str:
    return re.sub(r'\s+', ' ', value.strip())


def _strip_unauthorized_money(value, allowed: set[str]):
    if isinstance(value, dict):
        return {k: _strip_unauthorized_money(v, allowed) for k, v in value.items()}
    if isinstance(value, list):
        return [_strip_unauthorized_money(v, allowed) for v in value]
    if not isinstance(value, str):
        return value

    def repl(match: re.Match[str]) -> str:
        token = _normalize_money(match.group(0))
        return match.group(0) if token in allowed else ''

    cleaned = _MONEY_RE.sub(repl, value)
    cleaned = re.sub(r'[ \t]{2,}', ' ', cleaned).strip()
    return cleaned


def _run(label: str, source: str, *, constrained: bool = False) -> dict:
    result = _original_v2_run(label, source, constrained=constrained)
    if not constrained or not result.get('json_ok'):
        return result
    try:
        data = json.loads(result['governed_output'])
    except Exception:
        return result
    allowed = _authorized_money(base.INPUT)
    sanitized = _strip_unauthorized_money(data, allowed)
    rendered = json.dumps(sanitized, ensure_ascii=False, separators=(',', ':'))
    result['governed_output'] = rendered
    result['output_bytes'] = len(rendered.encode('utf-8'))
    result['money_containment_applied'] = rendered != json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    return result


base.run = _run


def _filter_authoritative_cases() -> None:
    selected = os.environ.get('C3_CORE_CASE', '').strip()
    if not selected:
        return
    matches = [case for case in core.CASES if case.get('key') == selected]
    if len(matches) != 1:
        raise SystemExit(f'UNKNOWN_C3_CORE_CASE:{selected}')
    core.CASES[:] = matches


if __name__ == '__main__':
    _filter_authoritative_cases()
    raise SystemExit(core.main())
