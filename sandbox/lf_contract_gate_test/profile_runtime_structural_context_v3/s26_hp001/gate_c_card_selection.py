from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

from .gate_b_governance import evaluate_governance

REPO = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUTPUT_PATH = HERE / "gate_c_output.json"
CONTRACT_PATH = HERE / "preexecution_contract.json"
RESOLVER_PATH = REPO / "sandbox/lf_contract_gate_test/profile_execution_runtime/runtime_authority_resolver_v1.py"


class GateCCardSelectionBlocked(RuntimeError):
    pass


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise GateCCardSelectionBlocked(f"GATE_C_NOT_OBJECT:{path.name}")
    return payload


def _load_resolver():
    spec = importlib.util.spec_from_file_location("s26_hp001_gate_c_runtime_authority", RESOLVER_PATH)
    if spec is None or spec.loader is None:
        raise GateCCardSelectionBlocked("GATE_C_RESOLVER_LOAD_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def resolve_card_policy(runtime_context: dict[str, Any], input_fields: dict[str, Any]) -> dict[str, Any]:
    card_required = runtime_context.get("card_required", False)
    if not isinstance(card_required, bool):
        raise GateCCardSelectionBlocked("GATE_C_CARD_REQUIRED_NOT_BOOLEAN")
    resolver = _load_resolver()
    resolved = resolver._resolve_card(runtime_context, REPO, input_fields)
    if card_required and resolved.get("status") == "FALLBACK":
        raise GateCCardSelectionBlocked("GATE_C_REQUIRED_CARD_MISSING")
    return resolved


def evaluate_card_selection(gate_b: dict[str, Any] | None = None) -> dict[str, Any]:
    gate_b = gate_b or evaluate_governance()
    b = gate_b["output"]
    payload = _load_json(OUTPUT_PATH)
    contract = _load_json(CONTRACT_PATH)
    expected = contract.get("stage_c_card") or {}

    if payload.get("schema") != "S26_HP001_GATE_C_OUTPUT_V1":
        raise GateCCardSelectionBlocked("GATE_C_SCHEMA_INVALID")
    if payload.get("gate") != "C_CARD_SELECTION":
        raise GateCCardSelectionBlocked("GATE_C_NAME_INVALID")
    if payload.get("project_id") != "S26" or payload.get("run_id") != b.get("run_id"):
        raise GateCCardSelectionBlocked("GATE_C_IDENTITY_INVALID")
    if b.get("next_gate") != "C_CARD_SELECTION":
        raise GateCCardSelectionBlocked("GATE_B_DID_NOT_AUTHORIZE_C")

    upstream = payload.get("upstream") or {}
    if upstream.get("source_gate") != "B_EKB_GOVERNANCE":
        raise GateCCardSelectionBlocked("GATE_C_UPSTREAM_GATE_INVALID")
    if upstream.get("source_output_sha256") != gate_b.get("output_sha256"):
        raise GateCCardSelectionBlocked("GATE_C_UPSTREAM_OUTPUT_SHA_MISMATCH")

    b_input = b.get("input") or {}
    if upstream.get("input_sha256") != b_input.get("sha256"):
        raise GateCCardSelectionBlocked("GATE_C_UPSTREAM_INPUT_SHA_MISMATCH")

    inherited = payload.get("input") or {}
    if inherited.get("input_literal") != b_input.get("content"):
        raise GateCCardSelectionBlocked("GATE_C_INPUT_LITERAL_MUTATED")
    if inherited.get("input_literal_sha256") != b_input.get("sha256"):
        raise GateCCardSelectionBlocked("GATE_C_INPUT_SHA_MUTATED")
    if inherited.get("surface_code") != "UI_SCREEN_DESIGN" or inherited.get("task_code") != "CREATE_NEW":
        raise GateCCardSelectionBlocked("GATE_C_TASK_SIGNATURE_INVALID")
    if inherited.get("card_required") is not expected.get("card_required"):
        raise GateCCardSelectionBlocked("GATE_C_CARD_REQUIRED_POLICY_MISMATCH")

    candidates = inherited.get("card_candidates")
    if not isinstance(candidates, list):
        raise GateCCardSelectionBlocked("GATE_C_CANDIDATES_NOT_ARRAY")

    selection = payload.get("selection") or {}
    if selection.get("candidate_count") != len(candidates):
        raise GateCCardSelectionBlocked("GATE_C_CANDIDATE_COUNT_MISMATCH")
    if selection.get("candidate_count") != expected.get("expected_candidate_count"):
        raise GateCCardSelectionBlocked("GATE_C_EXPECTED_CANDIDATE_COUNT_MISMATCH")

    input_fields = {
        "profile_slug": "ui_architect",
        "task_mode": "CREATE_NEW",
        "output_contract_version": "UI_PRODUCTION_SPEC_V6",
        "domain_scope": "GENERIC_SERVICE_MARKETPLACE",
    }
    runtime_context = {
        "surface_code": inherited["surface_code"],
        "task_code": inherited["task_code"],
        "card_required": inherited["card_required"],
        "card_candidates": candidates,
    }
    resolved = resolve_card_policy(runtime_context, input_fields)

    for key in ("status", "mode", "card_id", "card_ref", "card_sha256", "schema_invention_allowed"):
        if selection.get(key) != resolved.get(key):
            raise GateCCardSelectionBlocked(f"GATE_C_SELECTION_DIVERGENCE:{key}")
    if selection.get("reason") != resolved.get("reason"):
        raise GateCCardSelectionBlocked("GATE_C_SELECTION_DIVERGENCE:reason")

    if selection.get("candidate_count") == 0 and selection.get("evaluated_candidates") != []:
        raise GateCCardSelectionBlocked("GATE_C_FALSE_REVIEW_EVIDENCE")
    if expected.get("no_card_is_valid") is not True:
        raise GateCCardSelectionBlocked("GATE_C_NO_CARD_POLICY_INVALID")
    if selection.get("mode") != expected.get("decision"):
        raise GateCCardSelectionBlocked("GATE_C_CONTRACT_DECISION_MISMATCH")
    if selection.get("reason") != expected.get("reason"):
        raise GateCCardSelectionBlocked("GATE_C_CONTRACT_REASON_MISMATCH")
    if selection.get("schema_invention_allowed") is not False:
        raise GateCCardSelectionBlocked("GATE_C_SCHEMA_INVENTION_ALLOWED")

    if payload.get("status") != "PASS" or payload.get("next_gate") != expected.get("next_gate"):
        raise GateCCardSelectionBlocked("GATE_C_TRANSITION_INVALID")

    return {
        "output": payload,
        "output_sha256": _sha256(OUTPUT_PATH.read_bytes()),
        "input_sha256": inherited["input_literal_sha256"],
        "candidate_count": len(candidates),
        "decision": selection["mode"],
    }
