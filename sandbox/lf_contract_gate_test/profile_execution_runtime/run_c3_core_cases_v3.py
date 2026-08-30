#!/usr/bin/env python3
from __future__ import annotations

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

if __name__ == '__main__':
    raise SystemExit(core.main())
