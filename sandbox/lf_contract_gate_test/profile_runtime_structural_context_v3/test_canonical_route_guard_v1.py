from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
GUARD_PATH = REPO / "sandbox/lf_contract_gate_test/canonical_route_guard/canonical_route_guard.py"


def _load_guard():
    spec = importlib.util.spec_from_file_location("canonical_route_guard", GUARD_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_canonical_route_guard_v1() -> None:
    guard = _load_guard()

    canonical = guard.evaluate_route("ACTUALIZACION_ROUTER_LF", "ACTUALIZACION_ROUTER_LF")
    assert canonical.decision == "PROCEED_CANONICAL"
    assert canonical.ask_user is False
    assert canonical.canonical_effect_allowed is True
    assert canonical.effect_authorization == "DEFER_TO_GOVERNING_CONTRACT"
    assert canonical.merge_allowed is None
    assert canonical.production_effect_allowed is None
    assert canonical.pass_claim_allowed is None

    deviation = guard.evaluate_route("ACTUALIZACION_ROUTER_LF", "GIT_DIRECT")
    assert deviation.decision == "ASK_CANONICAL_OR_EXPLORATORY"
    assert deviation.ask_user is True
    assert "¿Retomo la ruta canónica" in deviation.question
    assert deviation.canonical_effect_allowed is False
    assert deviation.merge_allowed is False
    assert deviation.pass_claim_allowed is False

    exploration = guard.evaluate_route(
        "ACTUALIZACION_ROUTER_LF", "GIT_DIRECT", explicit_exploration=True
    )
    assert exploration.decision == "PROCEED_EXPLORATORY_NO_CANONICAL_EFFECT"
    assert exploration.ask_user is False
    assert exploration.exploratory is True
    assert exploration.canonical_effect_allowed is False
    assert exploration.merge_allowed is False
    assert exploration.production_effect_allowed is False
    assert exploration.canonical_close_allowed is False
    assert exploration.pass_claim_allowed is False

    unresolved = guard.evaluate_route(None, "GIT_DIRECT")
    assert unresolved.decision == "RESOLVE_CANONICAL_ROUTE_FIRST"
    assert unresolved.canonical_effect_allowed is False

    claude = (REPO / "CLAUDE.md").read_text(encoding="utf-8")
    operational = (REPO / ".claude/operational-execution.md").read_text(encoding="utf-8")
    router_protocol = (
        REPO / "docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md"
    ).read_text(encoding="utf-8")
    for text in (claude, operational, router_protocol):
        assert "ASK_CANONICAL_OR_EXPLORATORY" in text
        assert "EXPLORATORY_NO_CANONICAL_EFFECT" in text


if __name__ == "__main__":
    test_canonical_route_guard_v1()
    print("PASS_CANONICAL_ROUTE_GUARD_V1")
