from __future__ import annotations

from typing import Any

MATURITY_STATES = ["UNDETERMINED", "GENERIC", "SPECIALIZED", "ADAPTIVE", "EXPERT", "EVIDENCE_OPTIMIZED"]
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
    # PASS and FAIL are both substantive claims and therefore require evidence.
    if status in {"PASS", "FAIL"} and not refs:
        return "UNKNOWN"
    return status


def _maturity(evidence: dict[str, Any]) -> str:
    domain = _proof(evidence, "domain_task_uplift")
    if domain == "UNKNOWN":
        return "UNDETERMINED"
    if domain == "FAIL":
        return "GENERIC"

    strategy = _proof(evidence, "strategy_routing")
    if strategy in {"FAIL", "UNKNOWN"}:
        return "SPECIALIZED"

    expert = _proof(evidence, "expert_holdout")
    if expert in {"FAIL", "UNKNOWN"}:
        return "ADAPTIVE"

    repeated = _proof(evidence, "repeated_optimization")
    if repeated in {"FAIL", "UNKNOWN"}:
        return "EXPERT"
    return "EVIDENCE_OPTIMIZED"


def assess_profile(payload: dict[str, Any]) -> dict[str, Any]:
    """Evidence-bound profile capability assessment. It never authorizes a write."""
    if not isinstance(payload, dict):
        raise ValueError("PROFILE_ASSESSMENT_INPUT_INVALID")
    evidence = payload.get("evidence")
    signals = payload.get("signals")
    if not isinstance(evidence, dict) or not isinstance(signals, dict):
        raise ValueError("PROFILE_ASSESSMENT_INPUT_INVALID")

    structural = _proof(evidence, "structural_compatibility")
    architecture = _proof(evidence, "architecture_fit")
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
            gaps.append({
                "gap": key,
                "status": status,
                "refs": evidence.get(key, {}).get("refs", []) if isinstance(evidence.get(key), dict) else [],
            })

    evidence_needed: list[str] = []
    mode: str | None = None

    if architecture == "FAIL":
        mode = "REARCHITECT"
    elif structural == "FAIL":
        mode = "PATCH"
    elif structural == "UNKNOWN":
        evidence_needed.append("structural_compatibility")
    elif architecture == "UNKNOWN":
        evidence_needed.append("architecture_fit")
    else:
        domain = _proof(evidence, "domain_task_uplift")
        strategy = _proof(evidence, "strategy_routing")
        expert = _proof(evidence, "expert_holdout")
        repeated = _proof(evidence, "repeated_optimization")
        optimize = _proof(evidence, "optimization_opportunity")

        if domain == "UNKNOWN":
            evidence_needed.append("domain_task_uplift")
        elif domain == "FAIL":
            mode = "SPECIALIZE"
        elif strategy == "UNKNOWN":
            evidence_needed.append("strategy_routing")
        elif strategy == "FAIL":
            mode = "ADAPT"
        elif expert == "UNKNOWN":
            evidence_needed.append("expert_holdout")
        elif expert == "PASS" and repeated == "UNKNOWN":
            evidence_needed.append("repeated_optimization")
        elif optimize == "UNKNOWN":
            evidence_needed.append("optimization_opportunity")
        elif optimize == "PASS":
            mode = "OPTIMIZE"
        else:
            mode = "NO_CHANGE"

    assessment_status = "EVIDENCE_SUFFICIENT" if mode is not None else "NEEDS_MORE_EVIDENCE"
    if mode is not None and mode not in EVOLUTION_MODES:
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
        "assessment_status": assessment_status,
        "maturity": maturity,
        "structural_compatibility": structural,
        "profile_gaps": gaps,
        "evolution_mode": mode,
        "evidence_needed": sorted(set(evidence_needed)),
        "typed_signals": typed_signals,
        "uncertainty": signals.get("uncertainty", "UNKNOWN"),
        "risk": signals.get("risk", "UNKNOWN"),
        "next_action": "TARGETED_EVIDENCE_ACQUISITION" if evidence_needed else "CONTINUE_EVOLUTION_FLOW",
        "write_authorized": False,
        "admission_required": True,
    }
