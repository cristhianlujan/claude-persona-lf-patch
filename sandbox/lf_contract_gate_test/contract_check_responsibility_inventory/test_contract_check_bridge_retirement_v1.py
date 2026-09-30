#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BRIDGE = ROOT / "scripts/lf_contract_check.py"
CARRIER_REL = "sandbox/lf_contract_gate_test/contract_check_carrier/contract_check_carrier_v1.py"
CARRIER = ROOT / CARRIER_REL
INVENTORY = Path(__file__).with_name("contract_check_legacy_bridge_inventory_v1.json")
SELF_CHANGE = ROOT / "sandbox/lf_contract_gate_test/contract_check_self_change_admission/lf_contract_check_self_change_admission_v1.py"
INDEPENDENT = ROOT / "sandbox/lf_contract_gate_test/contract_check_self_change_admission/lf_independent_change_admission_carrier_v1.py"
CONTRACT = ROOT / "sandbox/lf_contract_gate_test/lf_contract.yml"
WORKFLOWS = ROOT / ".github/workflows"


def main() -> None:
    checks = 0
    assert not BRIDGE.exists(); checks += 1
    assert CARRIER.is_file(); checks += 1

    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    assert inventory["status"] == "RETIRED"; checks += 1
    assert inventory["cleanup_required"] is False; checks += 1
    assert inventory["known_runtime_or_validation_consumers_to_clean"] == []; checks += 1
    assert inventory["retirement"]["retired_bridge_path"] == "scripts/lf_contract_check.py"; checks += 1
    assert inventory["retirement"]["canonical_entrypoint"] == CARRIER_REL; checks += 1

    self_change = SELF_CHANGE.read_text(encoding="utf-8")
    assert CARRIER_REL in self_change; checks += 1
    assert '"scripts/lf_contract_check.py",  # retired-path tombstone' in self_change; checks += 1
    anchor_block = self_change.split("ANCHOR_SURFACES = (", 1)[1].split(")", 1)[0]
    assert CARRIER_REL in anchor_block and "scripts/lf_contract_check.py" not in anchor_block; checks += 1

    independent = INDEPENDENT.read_text(encoding="utf-8")
    anchor_query = independent.split("def _anchors()", 1)[1].split("def _execution_readback", 1)[0]
    assert CARRIER_REL in anchor_query and "scripts/lf_contract_check.py" not in anchor_query; checks += 1

    contract = CONTRACT.read_text(encoding="utf-8")
    assert CARRIER_REL in contract and "scripts/lf_contract_check.py" not in contract; checks += 1

    workflow_text = "\n".join(p.read_text(encoding="utf-8") for p in WORKFLOWS.glob("*.yml"))
    assert "scripts/lf_contract_check.py" not in workflow_text; checks += 1

    assert checks == 13, checks
    print("PASS_CONTRACT_CHECK_BRIDGE_RETIREMENT_V1=13/13")


if __name__ == "__main__":
    main()
