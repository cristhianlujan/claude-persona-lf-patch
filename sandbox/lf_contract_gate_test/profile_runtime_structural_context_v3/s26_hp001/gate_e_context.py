from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

from .bootstrap_context import evaluate_bootstrap
from .gate_d_authority import evaluate_authority_resolution

REPO = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUTPUT_PATH = HERE / "gate_e_output.json"
CONTRACT_PATH = HERE / "preexecution_contract.json"
RESOLVER_PATH = REPO / "sandbox/lf_contract_gate_test/profile_execution_runtime/runtime_authority_resolver_v1.py"


class GateETypedContextBlocked(RuntimeError):
    pass


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise GateETypedContextBlocked(f"GATE_E_NOT_OBJECT:{path.name}")
    return value


def _load_resolver():
    spec = importlib.util.spec_from_file_location("s26_hp001_runtime_authority_gate_e", RESOLVER_PATH)
    if spec is None or spec.loader is None:
        raise GateETypedContextBlocked("GATE_E_RESOLVER_LOAD_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _user_requirement(gate_d_output: dict[str, Any]) -> dict[str, Any]:
    matches = [
        item for item in (gate_d_output.get("authority_resolution") or [])
        if isinstance(item, dict) and item.get("authority_type") == "USER_REQUIREMENT"
    ]
    if len(matches) != 1:
        raise GateETypedContextBlocked("GATE_E_USER_REQUIREMENT_AUTHORITY_INVALID")
    return matches[0]


def _card_source_from_d(gate_d_output: dict[str, Any]) -> dict[str, Any]:
    upstream = gate_d_output.get("upstream") or {}
    binding = upstream.get("committed_readback_binding") or {}
    ref = binding.get("source_ref")
    expected_sha = upstream.get("source_output_sha256")
    if not isinstance(ref, str) or not ref:
        raise GateETypedContextBlocked("GATE_E_CARD_SOURCE_REF_MISSING")
    path = (REPO / ref).resolve()
    try:
        path.relative_to(REPO.resolve())
    except ValueError as exc:
        raise GateETypedContextBlocked("GATE_E_CARD_SOURCE_REF_ESCAPE") from exc
    if not path.is_file():
        raise GateETypedContextBlocked("GATE_E_CARD_SOURCE_MISSING")
    if _sha256(path.read_bytes()) != expected_sha:
        raise GateETypedContextBlocked("GATE_E_CARD_SOURCE_SHA_MISMATCH")
    payload = _load_json(path)
    if payload.get("gate") != "C_CARD_SELECTION" or payload.get("run_id") != gate_d_output.get("run_id"):
        raise GateETypedContextBlocked("GATE_E_CARD_SOURCE_IDENTITY_INVALID")
    return payload


def _validate_bootstrap_binding(payload: dict[str, Any], bootstrap: dict[str, Any]) -> None:
    source = bootstrap["output"]
    binding = payload.get("bootstrap_context") or {}
    expected = {
        "source_ref": "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/bootstrap_context.json",
        "source_commit_sha": "e96b9a9512291ccc1fbed4584890c18e36d324ea",
        "source_git_blob_sha": "fbbf4d127410989616b2e31cbf7937859afebf8b",
        "source_sha256": bootstrap["output_sha256"],
        "operation_code": bootstrap["operation_code"],
        "execution_mode": bootstrap["execution_mode"],
        "distribution_mode": bootstrap["distribution_mode"],
        "active_policy_count": bootstrap["active_policy_count"],
        "policy_snapshot_sha256": bootstrap["policy_snapshot_sha256"],
    }
    if binding != expected:
        raise GateETypedContextBlocked("GATE_E_BOOTSTRAP_BINDING_MISMATCH")
    if (source.get("decision") or {}).get("policy_capsule_loaded_before_gate_a") is not True:
        raise GateETypedContextBlocked("GATE_E_BOOTSTRAP_NOT_LOADED_BEFORE_A")


def _validate_payload(payload: dict[str, Any], gate_d: dict[str, Any], bootstrap: dict[str, Any] | None = None) -> dict[str, Any]:
    bootstrap = bootstrap or evaluate_bootstrap()
    _validate_bootstrap_binding(payload, bootstrap)

    d = gate_d["output"]
    if payload.get("schema") != "S26_HP001_GATE_E_OUTPUT_V1":
        raise GateETypedContextBlocked("GATE_E_SCHEMA_INVALID")
    if payload.get("gate") != "E_ADAPTER_TYPED_CONTEXT":
        raise GateETypedContextBlocked("GATE_E_NAME_INVALID")
    if payload.get("project_id") != "S26" or payload.get("run_id") != d.get("run_id"):
        raise GateETypedContextBlocked("GATE_E_IDENTITY_INVALID")
    if d.get("next_gate") != "E_ADAPTER_TYPED_CONTEXT":
        raise GateETypedContextBlocked("GATE_D_DID_NOT_AUTHORIZE_E")

    upstream = payload.get("upstream") or {}
    if upstream.get("source_gate") != "D_AUTHORITY_RESOLUTION":
        raise GateETypedContextBlocked("GATE_E_UPSTREAM_GATE_INVALID")
    if upstream.get("source_output_sha256") != gate_d.get("output_sha256"):
        raise GateETypedContextBlocked("GATE_E_UPSTREAM_OUTPUT_SHA_MISMATCH")
    if upstream.get("input_sha256") != gate_d.get("input_sha256"):
        raise GateETypedContextBlocked("GATE_E_UPSTREAM_INPUT_SHA_MISMATCH")

    binding = upstream.get("committed_readback_binding") or {}
    if binding.get("source_sha256") != gate_d.get("output_sha256"):
        raise GateETypedContextBlocked("GATE_E_D_READBACK_SHA_MISMATCH")
    if binding.get("source_git_blob_sha") != "40f287206429dd51c56b5e3d8f56f15c39eb21ac":
        raise GateETypedContextBlocked("GATE_E_D_READBACK_BLOB_MISMATCH")
    if binding.get("source_commit_sha") != "7c81237cf55a9dfd3fd7193f0811c84ebdd54085":
        raise GateETypedContextBlocked("GATE_E_D_READBACK_COMMIT_MISMATCH")

    contract = _load_json(CONTRACT_PATH)
    stage = contract.get("stage_e_context") or {}
    if stage.get("upstream_gate_required") != "D_AUTHORITY_RESOLUTION":
        raise GateETypedContextBlocked("GATE_E_CONTRACT_UPSTREAM_INVALID")
    if stage.get("typed_context_schema") != "LF_RUNTIME_TYPED_CONTEXT_V1":
        raise GateETypedContextBlocked("GATE_E_CONTRACT_TYPED_SCHEMA_INVALID")
    if stage.get("required_adapter_codes") != []:
        raise GateETypedContextBlocked("GATE_E_CONTRACT_ADAPTER_REQUIREMENT_INVALID")
    if stage.get("profile_slug") != "ui_architect":
        raise GateETypedContextBlocked("GATE_E_CONTRACT_PROFILE_INVALID")
    if stage.get("output_contract_version") != "UI_PRODUCTION_SPEC_V6":
        raise GateETypedContextBlocked("GATE_E_CONTRACT_OUTPUT_VERSION_INVALID")
    if stage.get("next_gate") != "F_PROFILE_EXECUTION":
        raise GateETypedContextBlocked("GATE_E_CONTRACT_NEXT_GATE_INVALID")

    resolver_input = payload.get("resolver_input") or {}
    runtime_context = resolver_input.get("runtime_context")
    request = resolver_input.get("request")
    if not isinstance(runtime_context, dict) or not isinstance(request, dict):
        raise GateETypedContextBlocked("GATE_E_RESOLVER_INPUT_INVALID")

    d_input = d.get("input") or {}
    expected_context = {
        "surface_code": d_input.get("surface_code"),
        "task_code": d_input.get("task_code"),
        "current_run_id": d_input.get("current_run_id"),
        "input_fields": {
            "profile_slug": stage.get("profile_slug"),
            "task_mode": d_input.get("task_code"),
            "output_contract_version": stage.get("output_contract_version"),
            "domain_scope": "GENERIC_SERVICE_MARKETPLACE",
        },
        "card_candidates": [],
        "required_authority_types": d_input.get("required_authority_types") or [],
        "authority_sources": d.get("authority_resolution") or [],
        "required_adapter_codes": [],
    }
    if runtime_context != expected_context:
        raise GateETypedContextBlocked("GATE_E_RUNTIME_CONTEXT_DIVERGENCE")

    user_auth = _user_requirement(d)
    user_path = REPO / str(user_auth.get("ref"))
    if not user_path.is_file():
        raise GateETypedContextBlocked("GATE_E_USER_REQUIREMENT_SOURCE_MISSING")
    literal = user_path.read_text(encoding="utf-8")
    if _sha256(user_path.read_bytes()) != user_auth.get("sha256"):
        raise GateETypedContextBlocked("GATE_E_USER_REQUIREMENT_SHA_MISMATCH")
    if request.get("input_literal") != literal:
        raise GateETypedContextBlocked("GATE_E_INPUT_LITERAL_DIVERGENCE")
    if request.get("lf_adapter_bindings") != []:
        raise GateETypedContextBlocked("GATE_E_UNEXPECTED_ADAPTER_BINDING_INPUT")

    card_source = _card_source_from_d(d)
    if (card_source.get("input") or {}).get("card_candidates") != []:
        raise GateETypedContextBlocked("GATE_E_CARD_CANDIDATES_DIVERGENCE")
    if (card_source.get("selection") or {}).get("mode") != "NO_CARD_GOVERNED":
        raise GateETypedContextBlocked("GATE_E_CARD_SELECTION_MODE_INVALID")

    resolver = _load_resolver()
    try:
        resolved = resolver.resolve_runtime_context(runtime_context, request=request, repo_root=REPO)
    except Exception as exc:
        code = getattr(exc, "code", None)
        raise GateETypedContextBlocked(str(code or exc)) from exc

    if resolved != payload.get("typed_context"):
        raise GateETypedContextBlocked("GATE_E_TYPED_CONTEXT_NOT_RESOLVER_EXACT")
    if resolved.get("typed_context_sha256") != payload.get("typed_context_sha256"):
        raise GateETypedContextBlocked("GATE_E_TYPED_CONTEXT_SHA_MISMATCH")
    if resolved.get("authority_resolution") != d.get("authority_resolution"):
        raise GateETypedContextBlocked("GATE_E_AUTHORITY_DIVERGENCE")
    if resolved.get("adapter_binding") != []:
        raise GateETypedContextBlocked("GATE_E_ADAPTER_BINDING_NOT_EMPTY")
    expected_card = card_source.get("selection") or {}
    actual_card = resolved.get("card_resolution") or {}
    for key in ("status", "mode", "card_id", "card_ref", "card_sha256", "schema_invention_allowed", "reason"):
        if actual_card.get(key) != expected_card.get(key):
            raise GateETypedContextBlocked(f"GATE_E_CARD_RESOLUTION_DIVERGENCE:{key}")

    policy = payload.get("policy") or {}
    for key in (
        "runtime_execution_allowed_in_this_stage",
        "model_weight_acquisition_allowed",
        "paid_fallback_allowed",
    ):
        if policy.get(key) is not False or stage.get(key) is not False:
            raise GateETypedContextBlocked(f"GATE_E_POLICY_BOUNDARY_INVALID:{key}")

    decision = payload.get("decision") or {}
    if decision != {
        "typed_context_ready": True,
        "required_adapter_count": 0,
        "resolved_adapter_count": 0,
        "next_gate_authorized": True,
    }:
        raise GateETypedContextBlocked("GATE_E_DECISION_INVALID")
    if payload.get("status") != "PASS" or payload.get("next_gate") != "F_PROFILE_EXECUTION":
        raise GateETypedContextBlocked("GATE_E_TRANSITION_INVALID")
    return resolved


def evaluate_typed_context(
    gate_d: dict[str, Any] | None = None,
    bootstrap: dict[str, Any] | None = None,
) -> dict[str, Any]:
    gate_d = gate_d or evaluate_authority_resolution()
    bootstrap = bootstrap or evaluate_bootstrap()
    payload = _load_json(OUTPUT_PATH)
    resolved = _validate_payload(payload, gate_d, bootstrap)
    return {
        "output": payload,
        "output_sha256": _sha256(OUTPUT_PATH.read_bytes()),
        "input_sha256": gate_d["input_sha256"],
        "typed_context_sha256": resolved["typed_context_sha256"],
        "bootstrap_context_sha256": bootstrap["output_sha256"],
        "policy_snapshot_sha256": bootstrap["policy_snapshot_sha256"],
        "adapter_binding_count": len(resolved.get("adapter_binding") or []),
        "authority_count": len(resolved.get("authority_resolution") or []),
    }
