#!/usr/bin/env python3
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
data = json.loads((HERE / "live_graph_readback_20260913_v1.json").read_text(encoding="utf-8"))
ops = {o["operation_code"]: o for o in data["operations"]}

assert len(ops) == 14
assert data["summary"]["routed_operations"] == 14
assert data["summary"]["clean_graph_operations"] == 8
assert data["summary"]["operations_with_graph_findings"] == 6
assert len(data["summary"]["finding_operations"]) == 6
assert data["closure"] == "BLOCK"

assert ops["ACTUALIZACION_DB_LF"]["missing_block_target_ids"] == ["preflight->close", "patch->close"]
assert ops["ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF"]["graph_status"] == "NO_ACTIVE_STEPS"
assert ops["CREACION_CARD_LF"]["unreachable_required_step_ids"] == ["contract_judge", "close"]
assert ops["CREACION_ESTRATEGIA_LF"]["missing_required_step_contracts"] == 43
assert ops["CREACION_ESTRATEGIA_LF"]["unreachable_required_steps"] == 42
assert ops["CREACION_SKILL_LF"]["unreachable_required_steps"] == 9
assert "pre_write_execution_binding_gate" in ops["CREACION_SKILL_LF"]["unreachable_required_step_ids"]
assert ops["LEARNING_BRIDGE_KB_CARD_LF"]["self_loop_ids"] == ["close->close (blocked edge)"]

clean = [
    o for o in ops.values()
    if o.get("graph_status") != "NO_ACTIVE_STEPS"
    and o["missing_required_step_contracts"] == 0
    and o["unreachable_required_steps"] == 0
    and o["missing_pass_targets"] == 0
    and o["missing_block_targets"] == 0
    and o["self_loops"] == 0
]
assert len(clean) == 8

print("TRANSVERSAL_LIVE_GRAPH_READBACK_V1_PASS routed=14 clean=8 findings=6")
