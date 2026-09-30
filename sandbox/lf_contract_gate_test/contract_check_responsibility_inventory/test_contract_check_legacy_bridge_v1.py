#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BRIDGE_PATH = ROOT / "scripts/lf_contract_check.py"


def load_bridge():
    spec = importlib.util.spec_from_file_location("lf_contract_check_bridge_test", BRIDGE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError("bridge_unloadable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def expect_retired(callable_, name: str) -> None:
    try:
        callable_()
    except Exception as exc:
        expected = f"LEGACY_CONTRACT_CHECK_API_RETIRED:{name}"
        if expected not in str(exc):
            raise AssertionError((expected, str(exc))) from exc
    else:
        raise AssertionError(f"legacy API did not fail closed: {name}")


def main() -> int:
    text = BRIDGE_PATH.read_text(encoding="utf-8")
    assert "LF Contract Check v0.21" not in text
    assert "BRIDGE_STATUS = \"TEMPORARY_COMPATIBILITY_BRIDGE\"" in text
    assert "CLEANUP_REQUIRED = True" in text
    assert "NEW_CONSUMERS_ALLOWED = False" in text
    assert "contract_check_carrier_v1.py" in text

    bridge = load_bridge()
    assert bridge.BRIDGE_STATUS == "TEMPORARY_COMPATIBILITY_BRIDGE"
    assert bridge.CLEANUP_REQUIRED is True
    assert bridge.NEW_CONSUMERS_ALLOWED is False

    sentinel = {"verdict": "PASS", "source": "new-carrier"}
    original_run = bridge.CARRIER.run
    try:
        bridge.CARRIER.run = lambda packet: sentinel if packet == {"probe": True} else None
        assert bridge.run({"probe": True}) is sentinel
    finally:
        bridge.CARRIER.run = original_run

    expect_retired(lambda: bridge.validate_changed_files(["x"]), "validate_changed_files")
    expect_retired(bridge.get_changed_files, "get_changed_files")
    expect_retired(
        lambda: bridge.validate_candidate_receipt_shape("r", {}, []),
        "validate_candidate_receipt_shape",
    )

    print("PASS_CONTRACT_CHECK_LEGACY_BRIDGE_V1=12/12")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
