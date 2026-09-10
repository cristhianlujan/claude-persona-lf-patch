from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any

from .gate_a_admission import admit_input
from .gate_b_governance import evaluate_governance
from .gate_c_card_selection import evaluate_card_selection
from .gate_d_authority import evaluate_authority_resolution

REPO = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "preexecution_contract.json"
RESOLVER_PATH = REPO / "sandbox/lf_contract_gate_test/profile_execution_runtime/runtime_authority_resolver_v1.py"


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"NOT_OBJECT:{path}")
    return value


def _load_resolver():
    spec = importlib.util.spec_from_file_location("s26_hp001_runtime_authority_v4", RESOLVER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("RUNTIME_AUTHORITY_RESOLVER_LOAD_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_preexecution() -> dict[str, Any]:
    gate_a = admit_input()
    gate_a_output = gate_a["output"]
    if gate_a_output.get("next_gate") != "B_EKB_GOVERNANCE": raise RuntimeError("GATE_A_DID_NOT_AUTHORIZE_STAGE_B")
    gate_b = evaluate_governance(gate_a)
    gate_b_output = gate_b["output"]
    if gate_b_output.get("next_gate") != "C_CARD_SELECTION": raise RuntimeError("GATE_B_DID_NOT_AUTHORIZE_STAGE_C")
    if gate_b_output.get("run_id") != gate_a_output.get("run_id"): raise RuntimeError("GATE_B_RUN_ID_MISMATCH")
    gate_c = evaluate_card_selection(gate_b)
    gate_c_output = gate_c["output"]
    if gate_c_output.get("next_gate") != "D_AUTHORITY_RESOLUTION": raise RuntimeError("GATE_C_DID_NOT_AUTHORIZE_STAGE_D")
    if gate_c_output.get("run_id") != gate_b_output.get("run_id"): raise RuntimeError("GATE_C_RUN_ID_MISMATCH")
    gate_d = evaluate_authority_resolution(gate_c)
    gate_d_output = gate_d["output"]
    if gate_d_output.get("next_gate") != "E_ADAPTER_TYPED_CONTEXT": raise RuntimeError("GATE_D_DID_NOT_AUTHORIZE_STAGE_E")
    if gate_d_output.get("run_id") != gate_c_output.get("run_id"): raise RuntimeError("GATE_D_RUN_ID_MISMATCH")
    c_input = gate_c_output.get("input") or {}
    input_literal = c_input.get("input_literal")
    input_literal_sha256 = c_input.get("input_literal_sha256")
    if not isinstance(input_literal, str) or not input_literal: raise RuntimeError("GATE_C_INPUT_LITERAL_MISSING")
    if not isinstance(input_literal_sha256, str) or len(input_literal_sha256) != 64: raise RuntimeError("GATE_C_INPUT_SHA_INVALID")
    if gate_d.get("input_sha256") != input_literal_sha256: raise RuntimeError("GATE_D_TO_E_INPUT_SHA_DRIFT")
    contract = _load_json(CONTRACT_PATH)
    if contract.get("schema") != "S26_HP001_PREEXECUTION_CONTRACT_V1": raise RuntimeError("PREEXECUTION_CONTRACT_SCHEMA_INVALID")
    if contract.get("test_id") != gate_d_output.get("run_id"): raise RuntimeError("PREEXECUTION_TEST_ID_INVALID")
    d_input = gate_d_output.get("input") or {}
    required_types = d_input.get("required_authority_types") or []
    sources = gate_d_output.get("authority_resolution") or []
    stage_e = contract.get("stage_e_context") or {}
    if stage_e.get("upstream_gate_required") != "D_AUTHORITY_RESOLUTION": raise RuntimeError("HP001_STAGE_E_UPSTREAM_INVALID")
    if stage_e.get("required_adapter_codes") != []: raise RuntimeError("HP001_UNEXPECTED_ADAPTER_REQUIREMENT")
    if stage_e.get("output_contract_version") != "UI_PRODUCTION_SPEC_V6": raise RuntimeError("HP001_OUTPUT_CONTRACT_VERSION_INVALID")
    if stage_e.get("model_weight_acquisition_allowed") is not False or stage_e.get("paid_fallback_allowed") is not False: raise RuntimeError("HP001_COST_OR_WEIGHT_BOUNDARY_INVALID")
    runtime_context = {"surface_code": d_input.get("surface_code"),"task_code": d_input.get("task_code"),"current_run_id": d_input.get("current_run_id"),"input_fields": {"profile_slug": stage_e.get("profile_slug"),"task_mode": d_input.get("task_code"),"output_contract_version": stage_e.get("output_contract_version"),"domain_scope": "GENERIC_SERVICE_MARKETPLACE"},"card_candidates": c_input.get("card_candidates"),"required_authority_types": required_types,"authority_sources": sources,"required_adapter_codes": []}
    request = {"input_literal": input_literal,"lf_adapter_bindings": []}
    resolver = _load_resolver()
    resolved = resolver.resolve_runtime_context(runtime_context, request=request, repo_root=REPO)
    if resolved.get("input_literal_sha256") != input_literal_sha256: raise RuntimeError("GATE_C_TO_DOWNSTREAM_INPUT_SHA_DRIFT")
    expected_selection = gate_c_output.get("selection") or {}
    card_resolution = resolved.get("card_resolution") or {}
    for key in ("status","mode","card_id","card_ref","card_sha256","schema_invention_allowed","reason"):
        if card_resolution.get(key) != expected_selection.get(key): raise RuntimeError(f"GATE_C_TO_RUNTIME_CARD_DIVERGENCE:{key}")
    if resolved.get("authority_resolution") != sources: raise RuntimeError("GATE_D_TO_RUNTIME_AUTHORITY_DIVERGENCE")
    if resolved.get("adapter_binding") != []: raise RuntimeError("UNEXPECTED_ADAPTER_BINDING")
    typed_sha = resolved.get("typed_context_sha256")
    if not isinstance(typed_sha, str) or len(typed_sha) != 64: raise RuntimeError("TYPED_CONTEXT_SHA_INVALID")
    return {"gate":"S26_HP001_PREEXECUTION_A_E_V4","result":"PASS","upstream_gate_a":{"gate":gate_a_output["gate"],"status":gate_a_output["status"],"run_id":gate_a_output["run_id"],"input_sha256":(gate_a_output.get("input") or {}).get("sha256"),"output_sha256":gate_a["output_sha256"]},"stage_b":{"gate":gate_b_output["gate"],"status":gate_b_output["status"],"run_id":gate_b_output["run_id"],"input_sha256":gate_b["input_sha256"],"output_sha256":gate_b["output_sha256"],"broad_snapshot_count":gate_b["broad_snapshot_count"],"applicable_control_count":gate_b["applicable_control_count"]},"stage_c":{"gate":gate_c_output["gate"],"status":gate_c_output["status"],"run_id":gate_c_output["run_id"],"input_sha256":gate_c["input_sha256"],"output_sha256":gate_c["output_sha256"],"candidate_count":gate_c["candidate_count"],"decision":gate_c["decision"]},"stage_d":{"gate":gate_d_output["gate"],"status":gate_d_output["status"],"run_id":gate_d_output["run_id"],"input_sha256":gate_d["input_sha256"],"output_sha256":gate_d["output_sha256"],"authority_count":gate_d["authority_count"],"authority_types":sorted(required_types)},"stage_e_input":{"source_gate":"D_AUTHORITY_RESOLUTION","source_output_sha256":gate_d["output_sha256"],"run_id":gate_d_output["run_id"],"input_literal_sha256":input_literal_sha256},"stages":{"A_INPUT":"PASS","B_EKB":"PASS_LIVE_SNAPSHOT_MATERIALIZED_AND_REPLAYED","C_CARD":"PASS_NO_CARD_GOVERNED","D_AUTHORITY":"PASS_PROVENANCE_BOUND","E_TYPED_CONTEXT":"PASS"},"card_resolution":card_resolution,"authority_types":sorted(required_types),"adapter_binding_count":0,"typed_context_sha256":typed_sha,"input_literal_sha256":resolved.get("input_literal_sha256"),"output_contract_version":stage_e.get("output_contract_version"),"runtime_execution_performed":False,"model_weight_acquisition_performed":False,"paid_fallback_performed":False,"claim_ceiling":contract.get("claim_ceiling")}
