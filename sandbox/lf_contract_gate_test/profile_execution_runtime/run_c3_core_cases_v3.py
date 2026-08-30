#!/usr/bin/env python3
from __future__ import annotations

import json
import re

import run_c3_core_cases_v2 as c3v2

core = c3v2.core
base = c3v2.base

_original_guard_for_input = core._guard_for_input


def _guard_for_input(input_text: str) -> str:
    return (
        _original_guard_for_input(input_text)
        + '''

MONETARY AUTHORITY GATE — fail closed
Every monetary amount in the final JSON must appear literally in the authoritative user input.
Do not calculate, derive, infer, normalize, estimate or synthesize a new monetary amount from supplied amounts.
A mathematically derivable difference, subtotal, savings amount, installment amount, percentage-equivalent amount, or S/ 0 sentinel is still NEW financial authority unless that exact amount was supplied.
If the input authorizes only a concept such as ahorro calculado but supplies no numeric value for it, preserve the concept without materializing a number.
Before returning, scan the entire JSON: any S/ amount not present in the user input requires repair by removing the invented number, never by changing an authorized requirement.
'''
    ).strip()


core._guard_for_input = _guard_for_input

# Prompt guidance is not a sufficient authority boundary. Enforce the same rule
# deterministically on every string leaf before canonical/authority evaluation.
# Only unauthorized monetary tokens are removed; authorized literals, requirement
# text, structure, scores, validator thresholds and assertions are untouched.
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
    return result


base.run = _run

if __name__ == '__main__':
    raise SystemExit(core.main())
