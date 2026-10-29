#!/usr/bin/env python3
"""Deterministic pre-quality utility floor (NOT an independent semantic judge)."""
from __future__ import annotations


def evaluate(payload, contract_gate):
    if not isinstance(contract_gate, dict) or contract_gate.get("status") != "PASS":
        return {"status": "FAIL", "blocking_codes": ["CFUX_CONTRACT_REQUIRED_FIRST"], "downstream_authorized": False}
    codes: set[str] = set()
    if not isinstance(payload, dict):
        codes.add("CFUX_OUTPUT_NOT_OBJECT")
    elif payload.get("output_type") == "CUSTOMER_FINANCIAL_DECISION_SPEC":
        options = payload.get("options") or []
        if len(options) < 2:
            codes.add("CFUX_DECISION_WITHOUT_COMPARABLE_OPTIONS")
        tradeoffs = [str(o.get("key_tradeoff", "")).strip().lower() for o in options if isinstance(o, dict)]
        if any(not t for t in tradeoffs):
            codes.add("CFUX_OPTION_WITHOUT_TRADEOFF")
        if len(set(tradeoffs)) < len(tradeoffs):
            codes.add("CFUX_TRADEOFFS_NOT_DISTINCT")
        for key in ("must_understand", "claim_guardrails"):
            if not payload.get(key):
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
