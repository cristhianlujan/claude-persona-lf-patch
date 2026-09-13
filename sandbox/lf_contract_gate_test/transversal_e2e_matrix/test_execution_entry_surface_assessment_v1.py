#!/usr/bin/env python3
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
data = json.loads((HERE / "execution_entry_surface_assessment_v1.json").read_text(encoding="utf-8"))
entry = data["fresh_execution_entry"]
mit = data["insert_trigger_mitigations"]
verdict = data["verdict"]

assert entry["inserts_into"] == "public.lf_operation_execution"
assert entry["calls_router"] is False
assert entry["router_receipt_argument"] is False
assert entry["parent_execution_argument"] is False
assert entry["active_route_precondition"] is False
assert entry["active_contract_precondition"] is False
assert entry["public_anon_authenticated_revoked"] is True

# Do not overclaim: the direct reservation surface is guarded by policy and registry
# triggers. The unresolved issue is Router/equivalent authority provenance.
assert mit["policy_snapshot_on_insert"] is True
assert mit["required_policy_resolution_guard"] is True
assert mit["policy_snapshot_currentness_and_immutability_guard"] is True
assert mit["registered_operation_required"] is True
assert mit["final_status_requires_proof_and_step"] is True
assert verdict["policy_enforcement_on_direct_reservation"] == "PRESENT"
assert verdict["registry_enforcement_on_direct_reservation"] == "PRESENT"
assert verdict["router_authority_provenance"] == "GAP"
assert verdict["trusted_backend_direct_entry_requires_hardening"] is True

# Text scans that hit *_execution_steps are not fresh execution-entry paths.
for fn in data["non_entry_functions_detected_by_text_scan"]:
    assert fn["fresh_execution_entry"] is False
    assert fn["requires_existing_execution"] is True

assert data["router_surface"]["creates_execution"] is False
assert data["router_surface"]["mandatory_binding_to_reserve_function"] is False
assert verdict["closure"].startswith("BLOCK_UNTIL_")

print("TRANSVERSAL_EXECUTION_ENTRY_SURFACE_V1_PASS router_authority=GAP policy_guard=PRESENT")
