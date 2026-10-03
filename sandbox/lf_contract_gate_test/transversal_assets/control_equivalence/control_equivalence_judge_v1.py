#!/usr/bin/env python3
"""Fail-closed field equivalence classifier for transverse shadow comparisons.

The judge does not execute either side and never mutates authoritative state.
It compares two already-produced JSON objects on one frozen subject and applies
an explicit consumer policy. D0 means exact equality. D4 is globally reserved
for known false-PASS risk and is blocking. D1/D2/D3/D5 have no global semantics:
the consumer must declare an exact field mapping and meaning in its policy.
"""
from __future__ import annotations

from typing import Any, Mapping

SCHEMA_VERSION = "lf-control-equivalence-judge/v1"
POLICY_SCHEMA = "lf-control-equivalence-policy/v1"
ALLOWED_LEVELS = frozenset({"D0", "D1", "D2", "D3", "D4", "D5"})


class EquivalenceError(ValueError):
    pass


def _flatten(value: Any, prefix: str = "") -> dict[str, Any]:
    if isinstance(value, Mapping):
        out: dict[str, Any] = {}
        for key in sorted(value):
            if not isinstance(key, str) or not key:
                raise EquivalenceError("INVALID_OBJECT_KEY")
            child = f"{prefix}.{key}" if prefix else key
            out.update(_flatten(value[key], child))
        return out
    if isinstance(value, list):
        out: dict[str, Any] = {}
        for i, item in enumerate(value):
            child = f"{prefix}[{i}]"
            out.update(_flatten(item, child))
        if not value:
            out[prefix] = []
        return out
    if not prefix:
        raise EquivalenceError("ROOT_MUST_BE_OBJECT")
    return {prefix: value}


def _validate_policy(policy: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    if not isinstance(policy, Mapping) or policy.get("schema_version") != POLICY_SCHEMA:
        raise EquivalenceError("INVALID_POLICY_SCHEMA")
    consumer = policy.get("consumer_ref")
    if not isinstance(consumer, str) or not consumer.strip():
        raise EquivalenceError("MISSING_CONSUMER_REF")
    mappings = policy.get("field_levels")
    if not isinstance(mappings, Mapping):
        raise EquivalenceError("MISSING_FIELD_LEVELS")
    normalized: dict[str, dict[str, Any]] = {}
    for field, spec in mappings.items():
        if not isinstance(field, str) or not field or not isinstance(spec, Mapping):
            raise EquivalenceError("INVALID_FIELD_LEVEL_MAPPING")
        level = spec.get("level")
        meaning = spec.get("meaning")
        if level not in ALLOWED_LEVELS - {"D0"}:
            raise EquivalenceError(f"INVALID_DIVERGENCE_LEVEL:{field}")
        if not isinstance(meaning, str) or not meaning.strip():
            raise EquivalenceError(f"MISSING_LEVEL_MEANING:{field}")
        if level == "D4" and spec.get("blocking") is not True:
            raise EquivalenceError(f"D4_MUST_BLOCK:{field}")
        normalized[field] = {
            "level": level,
            "meaning": meaning.strip(),
            "blocking": bool(spec.get("blocking", False)),
        }
    return normalized


def evaluate(current: Mapping[str, Any], candidate: Mapping[str, Any], policy: Mapping[str, Any]) -> dict[str, Any]:
    try:
        current_flat = _flatten(current)
        candidate_flat = _flatten(candidate)
        field_policy = _validate_policy(policy)
    except EquivalenceError as exc:
        return {
            "schema_version": SCHEMA_VERSION,
            "result": "BLOCKED",
            "reason_code": str(exc),
            "decisional": False,
            "authoritative_mutation": False,
        }

    fields = sorted(set(current_flat) | set(candidate_flat))
    divergences = []
    unclassified = []
    blocking = False
    for field in fields:
        left = current_flat.get(field, {"__missing__": True})
        right = candidate_flat.get(field, {"__missing__": True})
        if left == right:
            continue
        spec = field_policy.get(field)
        if spec is None:
            unclassified.append(field)
            continue
        blocking = blocking or spec["blocking"]
        divergences.append({
            "field": field,
            "current": left,
            "candidate": right,
            "level": spec["level"],
            "meaning": spec["meaning"],
            "blocking": spec["blocking"],
        })

    if unclassified:
        return {
            "schema_version": SCHEMA_VERSION,
            "result": "BLOCKED_UNCLASSIFIED_DIVERGENCE",
            "comparison_level": None,
            "unclassified_fields": unclassified,
            "divergences": divergences,
            "divergence_count": len(divergences) + len(unclassified),
            "decisional": False,
            "authoritative_mutation": False,
        }

    if not divergences:
        result = "PASS_EQUIVALENT"
        comparison_level = "D0"
    elif blocking:
        result = "BLOCKED_DIVERGENCE"
        comparison_level = max((d["level"] for d in divergences), key=lambda x: int(x[1:]))
    else:
        result = "DIVERGENCE_CLASSIFIED"
        comparison_level = max((d["level"] for d in divergences), key=lambda x: int(x[1:]))

    return {
        "schema_version": SCHEMA_VERSION,
        "result": result,
        "comparison_level": comparison_level,
        "consumer_ref": policy["consumer_ref"],
        "divergences": divergences,
        "divergence_count": len(divergences),
        "blocking": blocking,
        "decisional": False,
        "authoritative_mutation": False,
    }
