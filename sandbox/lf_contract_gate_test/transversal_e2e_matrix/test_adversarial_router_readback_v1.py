#!/usr/bin/env python3
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
data = json.loads((HERE / "adversarial_router_readback_20260913_v1.json").read_text(encoding="utf-8"))
summary = data["route_summary"]
routes = data["routes"]

assert summary == {
    "static_routes": 17,
    "bypass_and_ready": 14,
    "policy_filter_bypass_but_other_gate_blocks": 1,
    "blocked_before_policy_surface": 2,
    "invalid_modes_per_route": 5,
}
assert len(routes) == 17
assert sum(r["verdict"] == "BYPASS_AND_READY" for r in routes) == 14
assert sum(r["verdict"] == "POLICY_FILTER_BYPASS_BUT_OTHER_GATE_BLOCKS" for r in routes) == 1
assert sum(r["verdict"] == "BLOCKED_BEFORE_POLICY_SURFACE" for r in routes) == 2

for r in routes:
    if r["verdict"] in {"BYPASS_AND_READY", "POLICY_FILTER_BYPASS_BUT_OTHER_GATE_BLOCKS"}:
        assert r["invalid_modes_zero_required"] == 5

by_key = {(r["asset_type"], r["action_code"]): r for r in routes}
assert by_key[("PERFIL", "PROFILE_EXECUTION")]["canonical_required"] == 5
assert by_key[("PERFIL", "PROFILE_EXECUTION")]["invalid_modes_ready"] == 5
assert by_key[("PERFIL", "PROFILE_UPDATE")]["invalid_modes_other_gate_block"] == 5
assert by_key[("OPERATION_CODE", "RUNTIME_UPDATE")]["canonical_block"] == "BLOCK_ASSET_NOT_FOUND"
assert by_key[("STRATEGY", "STRATEGY_CREATE")]["canonical_block"] == "BLOCK_ACTIVE_CONTRACT_MISSING"

target = data["target_authority_probe"]
assert target["request_text_target"] == "ACT-0043"
assert target["target_hint"] == "ACT-0036"
assert target["observed_asset_code"] == "ACT-0036"
assert target["observed_status"] == "READY_TO_EXECUTE"
assert target["verdict"] == "TARGET_HINT_OVERRIDE_CONFIRMED"

assert data["closure"] == "BLOCK"
assert data["safety"]["router_function_volatility"] == "STABLE"
assert all(data["safety"][k] is False for k in ["ddl_executed","dml_executed","runtime_activation","production_activation","business_effects"])

print("TRANSVERSAL_ROUTER_ADVERSARIAL_READBACK_V1_PASS static=17 bypass_ready=14")
