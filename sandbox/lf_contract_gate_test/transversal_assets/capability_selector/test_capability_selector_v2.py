import json
from pathlib import Path

from capability_selector_v1 import select_capabilities
from capability_selector_v2 import compose_capabilities

ROOT = Path(__file__).resolve().parent
METHODS = ROOT.parent / "method_pack_registry" / "method_pack_registry_v1.json"


def run():
    # Existing v1 contract remains unchanged.
    old = select_capabilities(
        [{"type": "risk", "value": "HIGH"}],
        [{"capability_code": "ASSURE", "signal_type": "risk", "accepted_values": ["HIGH"], "rank": 10, "state": "AVAILABLE"}],
        {"fallback_capabilities": ["SAFE"]},
    )
    assert set(old) == {"selected_capabilities", "reasons", "fallback_state"}

    registry = json.loads(METHODS.read_text(encoding="utf-8"))
    context = {
        "profile_gaps": ["strategy_routing"],
        "task_family": "PROFILE_EVOLUTION",
        "complexity": "HIGH",
        "novelty": "HIGH",
        "uncertainty": "HIGH",
        "causal_requirement": "REQUIRED",
        "risk": "CRITICAL",
        "evidence_sufficiency": "INSUFFICIENT",
        "optimization_need": "REQUIRED",
        "budget": {"max_method_cost_points": 8},
    }
    catalog = [
        {"capability_code": "TARGETED_EVIDENCE_ACQUISITION", "signal_type": "evidence_sufficiency", "accepted_values": ["INSUFFICIENT"], "rank": 30, "state": "AVAILABLE"},
        {"capability_code": "INDEPENDENT_ASSURANCE", "signal_type": "risk", "accepted_values": ["HIGH", "CRITICAL"], "rank": 20, "state": "AVAILABLE"},
        {"capability_code": "CAUSAL_EFFECT_LINEAGE", "signal_type": "causal_requirement", "accepted_values": ["HIGH", "REQUIRED"], "rank": 25, "state": "AVAILABLE"},
    ]
    r = compose_capabilities(context, catalog, {"fallback_capabilities": ["PACK_VALIDATION_HARNESS"]}, registry)
    assert r["schema"] == "CAPABILITY_SELECTOR_COMPOSITION_V2"
    assert r["execution_authorized"] is False and r["admission_required"] is True
    assert "TARGETED_EVIDENCE_ACQUISITION" in r["selected_capabilities"]
    assert "CAUSAL_EFFECT_LINEAGE" in r["composition_order"]
    assert any(m["method_id"] == "HOSTILE_CHALLENGE" for m in r["method_requirements"])
    assert any(not m["within_budget"] for m in r["method_requirements"])
    assert r["estimated_cost"]["method_cost_points"] <= 8
    print("PASS_CAPABILITY_SELECTOR_V2 backward_compatible=1 admission_separated=1")


if __name__ == "__main__":
    run()
