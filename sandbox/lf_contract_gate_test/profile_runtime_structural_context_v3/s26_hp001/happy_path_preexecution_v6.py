from __future__ import annotations

from .bootstrap_context import evaluate_bootstrap
from .gate_a_admission import admit_input
from .gate_b_governance import evaluate_governance
from .gate_c_card_selection import evaluate_card_selection
from .gate_d_authority import evaluate_authority_resolution
from .gate_e_context import evaluate_typed_context


def _stage_bootstrap(bootstrap_sha: str) -> dict:
    return {"bootstrap_context_sha256": bootstrap_sha}


def run_preexecution() -> dict:
    bootstrap = evaluate_bootstrap()
    boot = bootstrap["output"]
    if boot.get("next_gate") != "A_INPUT_ADMISSION":
        raise RuntimeError("BOOTSTRAP_DID_NOT_AUTHORIZE_GATE_A")
    bootstrap_sha = bootstrap["output_sha256"]

    gate_a = admit_input()
    a = gate_a["output"]
    if a.get("next_gate") != "B_EKB_GOVERNANCE":
        raise RuntimeError("GATE_A_DID_NOT_AUTHORIZE_STAGE_B")

    gate_b = evaluate_governance(gate_a)
    b = gate_b["output"]
    if b.get("next_gate") != "C_CARD_SELECTION" or b.get("run_id") != a.get("run_id"):
        raise RuntimeError("GATE_B_TRANSITION_INVALID")

    gate_c = evaluate_card_selection(gate_b)
    c = gate_c["output"]
    if c.get("next_gate") != "D_AUTHORITY_RESOLUTION" or c.get("run_id") != b.get("run_id"):
        raise RuntimeError("GATE_C_TRANSITION_INVALID")

    gate_d = evaluate_authority_resolution(gate_c)
    d = gate_d["output"]
    if d.get("next_gate") != "E_ADAPTER_TYPED_CONTEXT" or d.get("run_id") != c.get("run_id"):
        raise RuntimeError("GATE_D_TRANSITION_INVALID")

    gate_e = evaluate_typed_context(gate_d, bootstrap)
    e = gate_e["output"]
    if e.get("next_gate") != "F_PROFILE_EXECUTION" or e.get("run_id") != d.get("run_id"):
        raise RuntimeError("GATE_E_TRANSITION_INVALID")
    if gate_e.get("input_sha256") != gate_d.get("input_sha256"):
        raise RuntimeError("GATE_D_TO_E_INPUT_SHA_DRIFT")
    if gate_e.get("bootstrap_context_sha256") != bootstrap_sha:
        raise RuntimeError("GATE_E_BOOTSTRAP_SHA_DRIFT")

    compact_policies = [
        {
            "policy_role": ref["policy_role"],
            "policy_code": ref["policy_code"],
            "policy_version": ref["policy_version"],
            "policy_sha": ref["policy_sha"],
        }
        for ref in boot["policy_resolution"]["active_policy_refs"]
    ]

    return {
        "gate": "S26_HP001_PREEXECUTION_BOOTSTRAP_A_E_V6",
        "result": "PASS",
        "bootstrap": {
            "status": boot["status"],
            "operation_code": bootstrap["operation_code"],
            "execution_mode": bootstrap["execution_mode"],
            "distribution_mode": bootstrap["distribution_mode"],
            "execution_mode_source": boot["execution_mode_source"],
            "router_execution_mode_resolved": boot["router_execution_mode_resolved"],
            "active_policy_count": bootstrap["active_policy_count"],
            "active_policy_refs": compact_policies,
            "policy_snapshot_sha256": bootstrap["policy_snapshot_sha256"],
            "bootstrap_context_sha256": bootstrap_sha,
            "development_assurance": {
                "policy_code": boot["development_assurance"]["policy_code"],
                "policy_version": boot["development_assurance"]["policy_version"],
                "status": boot["development_assurance"]["status"],
                "authority_mode": boot["development_assurance"]["authority_mode"],
            },
            "loaded_before_gate_a": True,
        },
        "upstream_gate_a": {
            "gate": a["gate"], "status": a["status"], "run_id": a["run_id"],
            "input_sha256": (a.get("input") or {}).get("sha256"),
            "output_sha256": gate_a["output_sha256"],
            **_stage_bootstrap(bootstrap_sha),
        },
        "stage_b": {
            "gate": b["gate"], "status": b["status"], "run_id": b["run_id"],
            "input_sha256": gate_b["input_sha256"], "output_sha256": gate_b["output_sha256"],
            "broad_snapshot_count": gate_b["broad_snapshot_count"],
            "applicable_control_count": gate_b["applicable_control_count"],
            **_stage_bootstrap(bootstrap_sha),
        },
        "stage_c": {
            "gate": c["gate"], "status": c["status"], "run_id": c["run_id"],
            "input_sha256": gate_c["input_sha256"], "output_sha256": gate_c["output_sha256"],
            "candidate_count": gate_c["candidate_count"], "decision": gate_c["decision"],
            **_stage_bootstrap(bootstrap_sha),
        },
        "stage_d": {
            "gate": d["gate"], "status": d["status"], "run_id": d["run_id"],
            "input_sha256": gate_d["input_sha256"], "output_sha256": gate_d["output_sha256"],
            "authority_count": gate_d["authority_count"],
            **_stage_bootstrap(bootstrap_sha),
        },
        "stage_e": {
            "gate": e["gate"], "status": e["status"], "run_id": e["run_id"],
            "input_sha256": gate_e["input_sha256"], "output_sha256": gate_e["output_sha256"],
            "typed_context_sha256": gate_e["typed_context_sha256"],
            "adapter_binding_count": gate_e["adapter_binding_count"],
            "authority_count": gate_e["authority_count"],
            "next_gate": e["next_gate"],
            **_stage_bootstrap(bootstrap_sha),
        },
        "stages": {
            "BOOTSTRAP": "PASS_MODE_AND_ACTIVE_POLICY_CAPSULE",
            "A_INPUT": "PASS",
            "B_EKB": "PASS_LIVE_SNAPSHOT_MATERIALIZED_AND_REPLAYED",
            "C_CARD": "PASS_NO_CARD_GOVERNED",
            "D_AUTHORITY": "PASS_PROVENANCE_BOUND",
            "E_TYPED_CONTEXT": "PASS_MATERIALIZED",
        },
        "input_literal_sha256": gate_e["input_sha256"],
        "output_contract_version": (e.get("typed_context") or {}).get("input_fields", {}).get("output_contract_version"),
        "runtime_execution_performed": False,
        "model_weight_acquisition_performed": False,
        "paid_fallback_performed": False,
        "claim_ceiling": "PREEXECUTION_TYPED_CONTEXT_ONLY_NOT_RUNTIME_NOT_GOLDEN",
    }
