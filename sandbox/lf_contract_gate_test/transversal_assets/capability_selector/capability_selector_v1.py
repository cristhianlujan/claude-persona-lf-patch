from __future__ import annotations

from typing import Any

_STATES = {"CLEAR", "MULTI", "NO_SIGNAL", "CONTRADICTORY", "CAPABILITY_FAILURE"}


def _fallback(policy: dict[str, Any]) -> list[str]:
    raw = policy.get("fallback_capabilities")
    if not isinstance(raw, list) or any(not isinstance(x, str) or not x for x in raw):
        raise ValueError("FALLBACK_POLICY_INVALID")
    return sorted(set(raw))


def _out(selected: list[str], reasons: list[dict[str, Any]], state: str) -> dict[str, Any]:
    if state not in _STATES:
        raise ValueError("STATE_INVALID")
    return {
        "selected_capabilities": selected,
        "reasons": reasons,
        "fallback_state": state,
    }


def select_capabilities(
    signals: list[dict[str, Any]],
    catalog: list[dict[str, Any]],
    policy: dict[str, Any],
) -> dict[str, Any]:
    """Select capability codes from typed signals. Selection never authorizes execution."""
    try:
        fallback = _fallback(policy)
    except Exception:
        return _out([], [{"code": "FALLBACK_POLICY_INVALID"}], "CAPABILITY_FAILURE")

    if not isinstance(signals, list):
        return _out(fallback, [{"code": "SIGNALS_INVALID"}], "CAPABILITY_FAILURE")
    if not isinstance(catalog, list):
        return _out(fallback, [{"code": "CATALOG_INVALID"}], "CAPABILITY_FAILURE")

    normalized: list[tuple[str, Any]] = []
    by_type: dict[str, set[str]] = {}
    for signal in signals:
        if not isinstance(signal, dict):
            return _out(fallback, [{"code": "SIGNAL_RECORD_INVALID"}], "CAPABILITY_FAILURE")
        signal_type = signal.get("type")
        status = signal.get("status", "OK")
        if not isinstance(signal_type, str) or not signal_type or "value" not in signal:
            return _out(fallback, [{"code": "SIGNAL_RECORD_INVALID"}], "CAPABILITY_FAILURE")
        if status not in {"OK", "FAILED"}:
            return _out(fallback, [{"code": "SIGNAL_RECORD_INVALID"}], "CAPABILITY_FAILURE")
        if status == "FAILED":
            return _out(fallback, [{"code": "SIGNAL_SOURCE_FAILURE"}], "CAPABILITY_FAILURE")
        value = signal["value"]
        normalized.append((signal_type, value))
        by_type.setdefault(signal_type, set()).add(repr(value))

    contradictory = sorted(k for k, values in by_type.items() if len(values) > 1)
    if contradictory:
        return _out(
            fallback,
            [{"code": "CONFLICTING_TYPED_SIGNAL", "signal_type": contradictory[0]}],
            "CONTRADICTORY",
        )

    if not normalized:
        return _out(fallback, [{"code": "NO_TYPED_SIGNAL"}], "NO_SIGNAL")

    matched: dict[str, dict[str, Any]] = {}
    for entry in catalog:
        if not isinstance(entry, dict):
            return _out(fallback, [{"code": "CATALOG_RECORD_INVALID"}], "CAPABILITY_FAILURE")
        code = entry.get("capability_code")
        signal_type = entry.get("signal_type")
        accepted = entry.get("accepted_values")
        rank = entry.get("rank", 0)
        state = entry.get("state", "AVAILABLE")
        if (
            not isinstance(code, str)
            or not code
            or not isinstance(signal_type, str)
            or not signal_type
            or not isinstance(accepted, list)
            or not isinstance(rank, (int, float))
            or isinstance(rank, bool)
            or state not in {"AVAILABLE", "FAILED"}
        ):
            return _out(fallback, [{"code": "CATALOG_RECORD_INVALID"}], "CAPABILITY_FAILURE")

        if not any(t == signal_type and v in accepted for t, v in normalized):
            continue
        if state == "FAILED":
            return _out(fallback, [{"code": "MATCHED_CAPABILITY_FAILURE"}], "CAPABILITY_FAILURE")

        prior = matched.get(code)
        reason = {
            "code": "TYPED_SIGNAL_MATCH",
            "signal_type": signal_type,
            "capability_code": code,
            "rank": rank,
            "ranking_effect": "ORDER_ONLY",
        }
        if prior is None or rank > prior["rank"]:
            matched[code] = {"rank": rank, "reason": reason}

    if not matched:
        return _out(fallback, [{"code": "NO_CATALOG_MATCH"}], "NO_SIGNAL")

    ordered = sorted(matched, key=lambda code: (-matched[code]["rank"], code))
    reasons = [matched[code]["reason"] for code in ordered]
    state = "CLEAR" if len(ordered) == 1 else "MULTI"
    return _out(ordered, reasons, state)
