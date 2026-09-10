from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "preexecution_contract.json"
INPUT_PATH = HERE / "input.txt"
MARKETPLACE_CARD_PATH = REPO / "cards/marketplace_lf/decision_product_experience/CARD.md"
RESOLVER_PATH = REPO / "sandbox/lf_contract_gate_test/profile_execution_runtime/runtime_authority_resolver_v1.py"


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"NOT_OBJECT:{path}")
    return value


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _load_resolver():
    spec = importlib.util.spec_from_file_location("s26_hp001_runtime_authority", RESOLVER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("RUNTIME_AUTHORITY_RESOLVER_LOAD_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_preexecution() -> dict[str, Any]:
    contract = _load_json(CONTRACT_PATH)
    if contract.get("schema") != "S26_HP001_PREEXECUTION_CONTRACT_V1":
        raise RuntimeError("PREEXECUTION_CONTRACT_SCHEMA_INVALID")
    if contract.get("test_id") != "S26-HP-001":
        raise RuntimeError("PREEXECUTION_TEST_ID_INVALID")

    ekb = contract.get("stage_b_ekb") or {}
    required_ekb_codes = {"AUD-025", "CI-005", "CI-007", "CI-E16-001", "CI-MIG-001", "DB-001", "GOV-010"}
    if ekb.get("schema_first_verified") is not True or ekb.get("read_before_material_write") is not True:
        raise RuntimeError("EKB_PREEXECUTION_ORDER_NOT_PROVEN")
    if set(ekb.get("active_codes_used") or []) != required_ekb_codes:
        raise RuntimeError("EKB_ACTIVE_CODE_SET_MISMATCH")

    card_contract = contract.get("stage_c_card") or {}
    card_text = MARKETPLACE_CARD_PATH.read_text(encoding="utf-8")
    if "Runtime: DISABLED" not in card_text:
        raise RuntimeError("MARKETPLACE_LF_CARD_RUNTIME_STATUS_CHANGED")
    if "MarketPlace LF context pack" not in card_text:
        raise RuntimeError("MARKETPLACE_LF_CARD_CONTEXT_REQUIREMENT_MISSING")
    if card_contract.get("decision") != "NO_CARD_GOVERNED":
        raise RuntimeError("CARD_DECISION_NOT_FAIL_CLOSED")
    if card_contract.get("required_but_missing_context") != "MarketPlace LF context pack":
        raise RuntimeError("CARD_CONTEXT_GAP_NOT_BOUND")
    if card_contract.get("schema_invention_allowed") is not False:
        raise RuntimeError("CARD_FALLBACK_SCHEMA_INVENTION_ALLOWED")

    input_literal = INPUT_PATH.read_text(encoding="utf-8")
    if "Libertad Financiera" in input_literal or "MarketPlace LF" in input_literal:
        raise RuntimeError("HP001_INPUT_UNEXPECTED_LF_CONTEXT")

    authority = contract.get("stage_d_authority") or {}
    expected_paths = authority.get("authority_paths") or {}
    required_types = authority.get("required_authority_types") or []
    sources = []
    for authority_type in required_types:
        ref = expected_paths.get(authority_type)
        if not isinstance(ref, str) or not ref:
            raise RuntimeError(f"AUTHORITY_PATH_MISSING:{authority_type}")
        path = REPO / ref
        if not path.is_file():
            raise RuntimeError(f"AUTHORITY_FILE_MISSING:{authority_type}")
        sources.append({
            "authority_type": authority_type,
            "authority_id": f"S26_HP001_{authority_type}",
            "run_id": "S26-HP-001",
            "ref": ref,
            "sha256": _sha(path),
        })

    stage_e = contract.get("stage_e_context") or {}
    if stage_e.get("required_adapter_codes") != []:
        raise RuntimeError("HP001_UNEXPECTED_ADAPTER_REQUIREMENT")
    if stage_e.get("output_contract_version") != "UI_PRODUCTION_SPEC_V6":
        raise RuntimeError("HP001_OUTPUT_CONTRACT_VERSION_INVALID")
    if stage_e.get("model_weight_acquisition_allowed") is not False or stage_e.get("paid_fallback_allowed") is not False:
        raise RuntimeError("HP001_COST_OR_WEIGHT_BOUNDARY_INVALID")

    runtime_context = {
        "surface_code": authority.get("surface_code"),
        "task_code": authority.get("task_code"),
        "current_run_id": authority.get("current_run_id"),
        "input_fields": {
            "profile_slug": stage_e.get("profile_slug"),
            "task_mode": authority.get("task_code"),
            "output_contract_version": stage_e.get("output_contract_version"),
            "domain_scope": "GENERIC_SERVICE_MARKETPLACE",
        },
        "card_candidates": [],
        "required_authority_types": required_types,
        "authority_sources": sources,
        "required_adapter_codes": [],
    }
    request = {
        "input_literal": input_literal,
        "lf_adapter_bindings": [],
    }
    resolver = _load_resolver()
    resolved = resolver.resolve_runtime_context(runtime_context, request=request, repo_root=REPO)

    card_resolution = resolved.get("card_resolution") or {}
    if card_resolution.get("status") != "FALLBACK" or card_resolution.get("mode") != "NO_CARD_GOVERNED":
        raise RuntimeError("NO_CARD_GOVERNED_NOT_MATERIALIZED")
    if card_resolution.get("reason") != "NO_APPLICABLE_CARD":
        raise RuntimeError("NO_CARD_REASON_INVALID")
    if card_resolution.get("schema_invention_allowed") is not False:
        raise RuntimeError("RESOLVER_ALLOWED_SCHEMA_INVENTION")
    if resolved.get("adapter_binding") != []:
        raise RuntimeError("UNEXPECTED_ADAPTER_BINDING")
    if {a.get("authority_type") for a in resolved.get("authority_resolution", [])} != set(required_types):
        raise RuntimeError("AUTHORITY_RESOLUTION_INCOMPLETE")
    typed_sha = resolved.get("typed_context_sha256")
    if not isinstance(typed_sha, str) or len(typed_sha) != 64:
        raise RuntimeError("TYPED_CONTEXT_SHA_INVALID")

    return {
        "gate": "S26_HP001_PREEXECUTION_B_E_V1",
        "result": "PASS",
        "stages": {
            "B_EKB": "PASS_CONTROL_PLANE_READBACK",
            "C_CARD": "PASS_NO_CARD_GOVERNED",
            "D_AUTHORITY": "PASS_PROVENANCE_BOUND",
            "E_TYPED_CONTEXT": "PASS",
        },
        "card_resolution": card_resolution,
        "authority_types": sorted(required_types),
        "adapter_binding_count": 0,
        "typed_context_sha256": typed_sha,
        "input_literal_sha256": resolved.get("input_literal_sha256"),
        "output_contract_version": stage_e.get("output_contract_version"),
        "runtime_execution_performed": False,
        "model_weight_acquisition_performed": False,
        "paid_fallback_performed": False,
        "claim_ceiling": contract.get("claim_ceiling"),
    }
