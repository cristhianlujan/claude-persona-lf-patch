#!/usr/bin/env python3
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
r = json.loads((HERE / "generator_live_readback_v1.json").read_text(encoding="utf-8"))

assert r["result"] == "PASS_GENERATOR_EXECUTED_AGAINST_LIVE_SCHEMA"
assert r["snapshot_md5"] == "721a2893838b08f1765a6c24f8f97a5c"
assert r["universe"] == {
    "operation_count": 36,
    "active_route_count": 22,
    "routed_operation_count": 14,
    "unrouted_operation_count": 22,
    "static_execution_route_count": 17,
    "inspection_no_execution_route_count": 5,
}
assert r["generated_arrays"] == {
    "direct_operations": 14,
    "unrouted_operations": 22,
    "inspection_routes": 5,
}
probe = r["direct_reservation_structural_probe"]
assert probe["router_provenance_required"] is False
assert probe["policy_snapshot_on_insert"] is True
assert probe["required_policy_resolution_guard"] is True
assert probe["policy_snapshot_immutable_and_currentness_guard"] is True
assert probe["registered_operation_required"] is True
assert all(v is False for v in r["safety"].values())
assert "fail-closed" in r["important_limit"]

print("TRANSVERSAL_GENERATOR_LIVE_READBACK_V1_PASS universe=36 routes=22")
