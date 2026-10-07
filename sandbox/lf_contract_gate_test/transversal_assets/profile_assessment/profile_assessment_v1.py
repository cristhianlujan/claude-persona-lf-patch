from __future__ import annotations

from typing import Any

MATURITY_ORDER = ["GENERIC", "SPECIALIZED", "ADAPTIVE", "EXPERT", "EVIDENCE_OPTIMIZED"]
EVOLUTION_MODES = {"NO_CHANGE", "PATCH", "SPECIALIZE", "ADAPT", "REARCHITECT", "OPTIMIZE"}
_ALLOWED_STATUS = {"PASS", "FAIL", "UNKNOWN"}


def _proof(evidence: dict[str, Any], key: str) -> str:
    item = evidence.get(key)
    if not isinstance(item, dict):
        return "UNKNOWN"
    status = item.get("status", "UNKNOWN")
    refs = item.get("refs", [])
    if status not in _ALLOWED_STATUS or not isinstance(refs, list):
        return "UNKNOWN"
    if status == "PASS" and not refs:
        return "UNKNOWN"
    return status


def _maturity(evidence: dict[str, Any]) -> str:
    maturity = "GENERIC"
    if _proof(evidence, "domain_task_uplift") == "PASS":
        maturity = "SPECIALIZED"
    if maturity == "SPECIALIZED" and _proof(evidence, "strategy_routing") == "PASS":
        maturity = "ADAPTIVE"
    if maturity == "ADAPTIVE" and _proof(evidence, "expert_holdout") == "PASS":
        maturity = "EXPERT"
    if maturity == "EXPERT" and _proof(evidence, "repeated_optimization") == "PASS":
        maturity = "EVIDENCE_OPTIMIZED"
    return maturity


def assess_profile(payload: dict[str, Any]) -> dict[str, Any]:
    """Evidence-bound profile capability assessment. It never authorizes a write."""
    if not isinstance(payload, dict):
        raise ValueError("PROFILE_ASSESSMENT_INPUT_INVALID")
    evidence = payload.get("evidence")
    signals = payload.get("signals")
    if not isinstance(evidence, dict) or not isinstance(signals, dict):
        raise ValueError("PROFILE_ASSESSMENT_INPUT_INVALID")

    structural = _proof(evidence, "structural_compatibility")
    maturity = _maturity(evidence)

    gaps: list[dict[str, Any]] = []
    for key in (
        "domain_task_uplift",
        "strategy_routing",
        "expert_holdout",
        "repeated_optimization",
        "architecture_fit",
        "optimization_opportunity",
    ):
        status = _proof(evidence, key)
        if status != "PASS":
            gaps.append({"gap": key, "status": status, "refs": evidence.get(key, {}).get("refs", []) if isinstance(evidence.get(key), dict) else []})

    if _proof(evidence, "architecture_fit") == "FAIL":
        mode = "REARCHITECT"
    elif structural == "FAIL":
        mode = "PATCH"
    elif maturity == "GENERIC":
        mode = "SPECIALIZE"
    elif maturity == "SPECIALIZED" and _proof(evidence, "strategy_routing") != "PASS":
        mode = "ADAPT"
    elif maturity in {"ADAPTIVE", "EXPERT", "EVIDENCE_OPTIMIZED"} and _proof(evidence, "optimization_opportunity") == "PASS":
        mode = "OPTIMIZE"
    else:
        mode = "NO_CHANGE"

    if mode not in EVOLUTION_MODES:
        raise AssertionError("EVOLUTION_MODE_INVALID")

    typed_signals = []
    for key in (
        "task_family",
        "complexity",
        "novelty",
        "uncertainty",
        "causal_requirement",
        "risk",
        "repeated_pattern",
        "evidence_sufficiency",
    ):
        value = signals.get(key)
        if value is not None:
            typed_signals.append({"type": key, "value": value, "status": "OK"})

    return {
        "schema": "PROFILE_ASSESSMENT_V1",
        "maturity": maturity,
        "structural_compatibility": structural,
        "profile_gaps": gaps,
        "evolution_mode": mode,
        "typed_signals": typed_signals,
        "uncertainty": signals.get("uncertainty", "UNKNOWN"),
        "risk": signals.get("risk", "UNKNOWN"),
        "write_authorized": False,
        "admission_required": True,
    }
