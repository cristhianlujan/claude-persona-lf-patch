#!/usr/bin/env python3
"""Deterministic pre-quality utility floor (NOT an independent semantic judge)."""
from __future__ import annotations

import re
import unicodedata

# Pressure phrases (EN + ES), matched on text folded to lowercase ASCII words.
PRESSURE = re.compile(
    r"\b(act now|act fast|best option|best choice|best deal|dont miss|last chance|limited time|limited offer|hurry|"
    r"guaranteed|risk free|garantizad[oa]s?|sin riesgo|only today|today only|pay immediately|pay now|must pay|before it is too late|urgent|"
    r"aproveche|aprovecha|ultima oportunidad|no se lo pierda|no lo deje pasar|solo hoy|mejor opcion|"
    r"mejor alternativa|oferta limitada|tiempo limitado|pagar ya|pague ya|pague ahora|pagar ahora|ahora mismo|urgente|actue ya)\b"
)
NEGATORS = {"no", "not", "never", "without", "nor", "sin", "ni", "nunca", "nada", "avoid", "reject", "rejects", "don", "doesn", "cannot"}
QUOTED = re.compile(r"(\"[^\"]*\"|'[^']*'|\u201c[^\u201d]*\u201d)")
NON_COMPARABLE = re.compile(r"non-?comparable|not comparable|no comparable|no comparables|no son comparables", re.I)
NORMALIZED = re.compile(r"\bnormali[sz]\w*|\bnormaliz\w*|\bconverted to\b|\bcommon basis\b|\bsame basis\b|\bmisma base\b", re.I)
INVISIBLE = re.compile("[\u200b-\u200f\u2060\ufeff\u00a0]")


def _fold(text) -> str:
    text = unicodedata.normalize("NFKD", str(text))
    text = "".join(c for c in text if not unicodedata.combining(c)).lower().replace("\u2019", "").replace("'", "")
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


def _squash(text) -> str:
    return INVISIBLE.sub("", str(text)).strip()


def _negated(words, index) -> bool:
    return any(w in NEGATORS for w in words[max(0, index - 6):index])


def _pressure(text) -> bool:
    """True when text contains a pressure phrase that is not negated and not merely quoted."""
    folded = _fold(QUOTED.sub(" ", str(text)))
    words = folded.split()
    for m in PRESSURE.finditer(folded):
        if not _negated(words, len(folded[: m.start()].split())):
            return True
    return False


def _affirmed_normalization(text) -> bool:
    if NON_COMPARABLE.search(str(text)):
        return True
    folded = _fold(text)
    words = folded.split()
    return any(not _negated(words, len(folded[: m.start()].split())) for m in NORMALIZED.finditer(folded))


def _blank(items) -> bool:
    return not isinstance(items, list) or not items or any(not isinstance(x, str) or not _squash(x) for x in items)


def evaluate(payload, contract_gate):
    if not isinstance(contract_gate, dict) or contract_gate.get("status") != "PASS":
        return {"status": "FAIL", "blocking_codes": ["CFUX_CONTRACT_REQUIRED_FIRST"], "downstream_authorized": False}
    codes: set[str] = set()
    if not isinstance(payload, dict):
        codes.add("CFUX_OUTPUT_NOT_OBJECT")
    elif payload.get("output_type") == "CUSTOMER_FINANCIAL_DECISION_SPEC":
        options = [o for o in (payload.get("options") or []) if isinstance(o, dict)]
        tradeoffs = [_fold(_squash(o.get("key_tradeoff", ""))) for o in options]
        if any(not t for t in tradeoffs):
            codes.add("CFUX_OPTION_WITHOUT_TRADEOFF")
        if len(options) > 1 and len(set(tradeoffs)) < len(tradeoffs):
            codes.add("CFUX_TRADEOFFS_NOT_DISTINCT")
        texts = [o.get(k, "") for o in options for k in ("key_tradeoff", "customer_consequence", "timing")]
        texts += [x for x in (payload.get("recommended_presentation_priority") or []) if isinstance(x, str)]
        if any(_pressure(t) for t in texts):
            codes.add("CFUX_PRESSURE_FRAMING")
        bases = {_fold(_squash(o.get("monetary_basis", ""))) for o in options}
        if len(bases) > 1 and not _affirmed_normalization(payload.get("comparison_basis", "")):
            codes.add("CFUX_OPTIONS_INCOMPARABLE_BASIS")
        for key in ("must_understand", "claim_guardrails"):
            if _blank(payload.get(key)):
                codes.add(f"CFUX_{key.upper()}_EMPTY")
        if not _squash(payload.get("comparison_basis", "")):
            codes.add("CFUX_COMPARISON_BASIS_EMPTY")
    return {
        "status": "FAIL" if codes else "PASS",
        "blocking_codes": sorted(codes),
        "evaluation_scope": "DETERMINISTIC_UTILITY_FLOOR_ONLY",
        "independent_semantic_judge": "NOT_EXECUTED",
        "downstream_authorized": False,
    }
