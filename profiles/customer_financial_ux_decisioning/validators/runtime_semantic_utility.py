#!/usr/bin/env python3
"""Deterministic pre-quality utility floor (NOT an independent semantic judge)."""
from __future__ import annotations

import re

PRESSURE = re.compile(r"\b(act now|best option|best choice|don'?t miss|last chance|limited time|hurry|only today)\b", re.I)
NORMALIZED = re.compile(r"normali[sz]|non-?comparable|not comparable", re.I)


def _blank(items) -> bool:
    return not isinstance(items, list) or not items or any(not isinstance(x, str) or not x.strip() for x in items)


def evaluate(payload, contract_gate):
    if not isinstance(contract_gate, dict) or contract_gate.get("status") != "PASS":
        return {"status": "FAIL", "blocking_codes": ["CFUX_CONTRACT_REQUIRED_FIRST"], "downstream_authorized": False}
    codes: set[str] = set()
    if not isinstance(payload, dict):
        codes.add("CFUX_OUTPUT_NOT_OBJECT")
    elif payload.get("output_type") == "CUSTOMER_FINANCIAL_DECISION_SPEC":
        options = [o for o in (payload.get("options") or []) if isinstance(o, dict)]
        tradeoffs = [str(o.get("key_tradeoff", "")).strip().lower() for o in options]
        if any(not t for t in tradeoffs):
            codes.add("CFUX_OPTION_WITHOUT_TRADEOFF")
        if len(options) > 1 and len(set(tradeoffs)) < len(tradeoffs):
            codes.add("CFUX_TRADEOFFS_NOT_DISTINCT")
        if any(PRESSURE.search(t) for t in tradeoffs):
            codes.add("CFUX_PRESSURE_FRAMING")
        bases = {str(o.get("monetary_basis", "")).strip().lower() for o in options}
        if len(bases) > 1 and not NORMALIZED.search(str(payload.get("comparison_basis", ""))):
            codes.add("CFUX_OPTIONS_INCOMPARABLE_BASIS")
        for key in ("must_understand", "claim_guardrails"):
            if _blank(payload.get(key)):
                codes.add(f"CFUX_{key.upper()}_EMPTY")
        if not str(payload.get("comparison_basis", "")).strip():
            codes.add("CFUX_COMPARISON_BASIS_EMPTY")
    return {
        "status": "FAIL" if codes else "PASS",
        "blocking_codes": sorted(codes),
        "evaluation_scope": "DETERMINISTIC_UTILITY_FLOOR_ONLY",
        "independent_semantic_judge": "NOT_EXECUTED",
        "downstream_authorized": False,
    }
