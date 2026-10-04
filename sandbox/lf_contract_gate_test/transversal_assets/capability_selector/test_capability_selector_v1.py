from __future__ import annotations

import json
from pathlib import Path

from capability_selector_v1 import select_capabilities

ROOT = Path(__file__).resolve().parent
EXPECTED_KEYS = {"selected_capabilities", "reasons", "fallback_state"}
EXPECTED_STATES = {"CLEAR", "MULTI", "NO_SIGNAL", "CONTRADICTORY", "CAPABILITY_FAILURE"}


def _assert_contract(result: dict, state: str) -> None:
    assert set(result) == EXPECTED_KEYS
    assert result["fallback_state"] == state
    assert state in EXPECTED_STATES
    assert isinstance(result["selected_capabilities"], list)
    assert isinstance(result["reasons"], list)


def _load(name: str) -> dict:
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


def run() -> None:
    fallback = {"fallback_capabilities": ["SAFE_FALLBACK"]}
    catalog = [
        {"capability_code": "CAP_A", "signal_type": "kind", "accepted_values": ["A"], "rank": 10, "state": "AVAILABLE"},
        {"capability_code": "CAP_B", "signal_type": "severity", "accepted_values": ["HIGH"], "rank": 20, "state": "AVAILABLE"},
    ]

    clear = select_capabilities([{"type": "kind", "value": "A"}], catalog, fallback)
    _assert_contract(clear, "CLEAR")
    assert clear["selected_capabilities"] == ["CAP_A"]

    multi = select_capabilities(
        [{"type": "kind", "value": "A"}, {"type": "severity", "value": "HIGH"}],
        catalog,
        fallback,
    )
    _assert_contract(multi, "MULTI")
    assert multi["selected_capabilities"] == ["CAP_B", "CAP_A"]

    no_signal = select_capabilities([], catalog, fallback)
    _assert_contract(no_signal, "NO_SIGNAL")
    assert no_signal["selected_capabilities"] == ["SAFE_FALLBACK"]

    contradictory = select_capabilities(
        [{"type": "kind", "value": "A"}, {"type": "kind", "value": "B"}],
        catalog,
        fallback,
    )
    _assert_contract(contradictory, "CONTRADICTORY")
    assert contradictory["selected_capabilities"] == ["SAFE_FALLBACK"]

    failed = select_capabilities(
        [{"type": "kind", "value": "A"}],
        [{"capability_code": "CAP_A", "signal_type": "kind", "accepted_values": ["A"], "rank": 99, "state": "FAILED"}],
        fallback,
    )
    _assert_contract(failed, "CAPABILITY_FAILURE")
    assert failed["selected_capabilities"] == ["SAFE_FALLBACK"]

    low_conf = select_capabilities([{"type": "kind", "value": "A", "confidence": 0.01}], catalog, fallback)
    high_conf = select_capabilities([{"type": "kind", "value": "A", "confidence": 0.99}], catalog, fallback)
    assert low_conf == high_conf
    assert all(r.get("ranking_effect") == "ORDER_ONLY" for r in high_conf["reasons"])

    non_ig = _load("non_ig_consumer_fixture_v1.json")
    non_ig_result = select_capabilities(non_ig["signals"], non_ig["catalog"], non_ig["policy"])
    _assert_contract(non_ig_result, "MULTI")
    assert non_ig_result["selected_capabilities"] == ["DOCUMENT_REPAIR", "DOCUMENT_DELIVERY_CHECK"]

    ig = _load("ig_consumer_binding_v1.json")
    ig_result = select_capabilities(ig["signals"], ig["catalog"], ig["policy"])
    _assert_contract(ig_result, "MULTI")
    assert ig_result["selected_capabilities"] == ["TARGETED_EVIDENCE_ACQUISITION", "REPLAY_REGEN_ROLLBACK_PROOF"]
    ig_fallback = select_capabilities([], ig["catalog"], ig["policy"])
    _assert_contract(ig_fallback, "NO_SIGNAL")
    assert ig_fallback["selected_capabilities"] == ["FULL_SAFE_MIX_V1_CANDIDATE"]

    source = (ROOT / "capability_selector_v1.py").read_text(encoding="utf-8").lower()
    for forbidden in (
        "input_governance",
        "ig_curator",
        "pantalla",
        "familia",
        "m5.4",
        "gpt",
        "claude",
        "gemini",
        "method_router",
        "model_router",
        "safe_change_admission",
        "materiality",
        "reversibility",
        "consumer_ref",
    ):
        assert forbidden not in source, forbidden

    print("PASS_CAPABILITY_SELECTOR_V1 checks=17 states=5 consumers=2 domain_branches=0")


if __name__ == "__main__":
    run()
