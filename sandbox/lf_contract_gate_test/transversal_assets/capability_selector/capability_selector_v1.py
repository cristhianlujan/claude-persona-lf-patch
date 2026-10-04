"""Domain-agnostic capability selector.

Selection only: this module never grants execution permission, resolves admission,
or recomputes evidence/currentness authorities. Consumers provide typed signals,
a catalog annotated with currentness, and a safe fallback policy.
"""

from __future__ import annotations
from typing import Any, Dict, List, Mapping, Sequence, Tuple

VALID_SIGNAL_STATES = {"ACTIVE", "INACTIVE"}
VALID_RESULT_STATES = {
    "CLEAR", "MULTI", "NO_SIGNAL", "CONTRADICTORY", "CAPABILITY_FAILURE",
}


def _fallback(policy: Mapping[str, Any], state: str, reasons: List[Dict[str, Any]]) -> Dict[str, Any]:
    configured = policy.get("safe_fallback", [])
    selected = sorted({str(code) for code in configured if isinstance(code, str) and code.strip()})
    if not selected:
        reasons = list(reasons) + [{"code": "SAFE_FALLBACK_NOT_CONFIGURED"}]
    return {"selected_capabilities": selected, "reasons": reasons, "fallback_state": state}


def _normalized_signals(signals: Any) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    reasons: List[Dict[str, Any]] = []
    if not isinstance(signals, list):
        return [], [{"code": "INVALID_SIGNALS_CONTAINER"}]
    normalized: List[Dict[str, Any]] = []
    for idx, signal in enumerate(signals):
        if not isinstance(signal, dict):
            reasons.append({"code": "INVALID_SIGNAL", "index": idx})
            continue
        signal_type = signal.get("signal_type")
        state = signal.get("state")
        if not isinstance(signal_type, str) or not signal_type.strip() or state not in VALID_SIGNAL_STATES:
            reasons.append({"code": "INVALID_SIGNAL", "index": idx})
            continue
        normalized.append({"signal_type": signal_type.strip(), "state": state, "confidence": signal.get("confidence")})
    return normalized, reasons


def _contradictory(active_types: set[str], normalized: Sequence[Mapping[str, Any]], policy: Mapping[str, Any]) -> bool:
    by_type: Dict[str, set[str]] = {}
    for signal in normalized:
        by_type.setdefault(str(signal["signal_type"]), set()).add(str(signal["state"]))
    if any(states == VALID_SIGNAL_STATES for states in by_type.values()):
        return True
    contradiction_sets = policy.get("contradiction_sets", [])
    if not isinstance(contradiction_sets, list):
        return True
    for group in contradiction_sets:
        if isinstance(group, list):
            typed = {item for item in group if isinstance(item, str) and item}
            if len(typed) >= 2 and typed.issubset(active_types):
                return True
    return False


def select_capabilities(signals: Any, catalog: Any, policy: Any) -> Dict[str, Any]:
    """Return exactly selected_capabilities, reasons, fallback_state."""
    if not isinstance(policy, dict):
        policy = {}
    normalized, validation_reasons = _normalized_signals(signals)
    if validation_reasons:
        return _fallback(policy, "CAPABILITY_FAILURE", validation_reasons)

    active_types = {s["signal_type"] for s in normalized if s["state"] == "ACTIVE"}
    if not active_types:
        return _fallback(policy, "NO_SIGNAL", [{"code": "NO_ACTIVE_TYPED_SIGNAL"}])

    if _contradictory(active_types, normalized, policy):
        return _fallback(policy, "CONTRADICTORY", [{"code": "CONTRADICTORY_TYPED_SIGNALS", "signal_types": sorted(active_types)}])

    if not isinstance(catalog, list):
        return _fallback(policy, "CAPABILITY_FAILURE", [{"code": "INVALID_CATALOG_CONTAINER"}])

    matched: Dict[str, Tuple[int, set[str]]] = {}
    known_signal_types: set[str] = set()
    require_current = policy.get("require_current_catalog", True) is not False

    for idx, entry in enumerate(catalog):
        if not isinstance(entry, dict):
            return _fallback(policy, "CAPABILITY_FAILURE", [{"code": "INVALID_CATALOG_ENTRY", "index": idx}])
        code = entry.get("capability_code")
        signal_types = entry.get("signal_types")
        if not isinstance(code, str) or not code.strip() or not isinstance(signal_types, list):
            return _fallback(policy, "CAPABILITY_FAILURE", [{"code": "INVALID_CATALOG_ENTRY", "index": idx}])
        typed = {item for item in signal_types if isinstance(item, str) and item}
        known_signal_types.update(typed)
        matched_signals = typed.intersection(active_types)
        if not matched_signals:
            continue
        if require_current and entry.get("availability_state") != "CURRENT":
            return _fallback(policy, "CAPABILITY_FAILURE", [{"code": "MATCHED_CAPABILITY_NOT_CURRENT", "capability_code": code.strip()}])
        rank = entry.get("rank", 0)
        if isinstance(rank, bool) or not isinstance(rank, (int, float)):
            rank = 0
        prior = matched.get(code.strip())
        if prior is None:
            matched[code.strip()] = (int(rank), set(matched_signals))
        else:
            matched[code.strip()] = (max(prior[0], int(rank)), prior[1].union(matched_signals))

    unknown = sorted(active_types.difference(known_signal_types))
    if unknown:
        return _fallback(policy, "CAPABILITY_FAILURE", [{"code": "UNROUTABLE_TYPED_SIGNAL", "signal_types": unknown}])
    if not matched:
        return _fallback(policy, "CAPABILITY_FAILURE", [{"code": "NO_MATCHED_CAPABILITY"}])

    ordered = sorted(matched.items(), key=lambda item: (-item[1][0], item[0]))
    selected = [code for code, _ in ordered]
    reasons: List[Dict[str, Any]] = []
    for code, (rank, signal_types) in ordered:
        reasons.append({"code": "MATCHED_TYPED_SIGNAL", "capability_code": code, "signal_types": sorted(signal_types), "rank": rank})
    reasons.append({"code": "RANKING_NON_AUTHORIZING", "detail": "rank and confidence affect neither permission nor admission"})
    return {"selected_capabilities": selected, "reasons": reasons, "fallback_state": "MULTI" if len(active_types) > 1 else "CLEAR"}
