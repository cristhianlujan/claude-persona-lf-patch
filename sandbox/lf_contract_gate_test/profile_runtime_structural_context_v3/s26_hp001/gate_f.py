from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
F_INPUT = HERE / "gate_f_input.json"
TARGET_MODEL_GENERATION_MS = 60000.0
MAX_ACCEPTABLE_MODEL_GENERATION_MS = 120000.0
MAX_ACCEPTABLE_PROFILE_ELAPSED_MS = 120000.0
HARD_TRANSPORT_TIMEOUT_MS = 300000.0
WORKER_WATCHDOG_MS = 900000.0
F_OUTPUT = HERE / "gate_f_output.json"
OBSERVATION = HERE / "gate_f_runtime_observation.json"

class GateFBlocked(RuntimeError):
    pass

def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def _load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise GateFBlocked(f"GATE_F_NOT_OBJECT:{path.name}")
    return value

def validate_gate_f_payload(payload: dict[str, Any], *, f_input_sha: str, observation_sha: str) -> dict[str, Any]:
    if payload.get("schema") != "S26_HP001_GATE_F_OUTPUT_V1":
        raise GateFBlocked("GATE_F_SCHEMA_INVALID")
    if payload.get("gate") != "F_PROFILE_EXECUTION" or payload.get("project_id") != "S26" or payload.get("run_id") != "S26-HP-001":
        raise GateFBlocked("GATE_F_IDENTITY_INVALID")

    upstream = payload.get("upstream") or {}
    if upstream.get("source_boundary_sha256") != f_input_sha:
        raise GateFBlocked("GATE_F_INPUT_SHA_MISMATCH")
    if upstream.get("source_boundary_ref") != "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_input.json":
        raise GateFBlocked("GATE_F_INPUT_REF_INVALID")

    hist = payload.get("historical_manual_candidate") or {}
    if hist.get("consumed_current_gate_f_boundary") is not False or hist.get("satisfies_exact_head_runtime_execution") is not False:
        raise GateFBlocked("GATE_F_HISTORICAL_MANUAL_FALSE_CREDIT")

    obs = payload.get("runtime_observation") or {}
    if obs.get("sha256") != observation_sha:
        raise GateFBlocked("GATE_F_OBSERVATION_SHA_MISMATCH")
    if obs.get("gate_authority") is not False:
        raise GateFBlocked("GATE_F_OBSERVATION_WRONGLY_AUTHORIZED")

    req = payload.get("execution_requirement") or {}
    decision = payload.get("decision") or {}
    qdp = payload.get("quality_depth_performance") or {}

    performance_budget = (
        isinstance(qdp.get("model_generation_elapsed_ms"), (int, float))
        and not isinstance(qdp.get("model_generation_elapsed_ms"), bool)
        and qdp.get("model_generation_elapsed_ms") <= MAX_ACCEPTABLE_MODEL_GENERATION_MS
        and isinstance(obs.get("profile_elapsed_ms"), (int, float))
        and not isinstance(obs.get("profile_elapsed_ms"), bool)
        and obs.get("profile_elapsed_ms") <= MAX_ACCEPTABLE_PROFILE_ELAPSED_MS
    )

    exact = (
        obs.get("source_match") is True
        and decision.get("exact_head_runtime_observed") is True
        and decision.get("gate_f_input_consumed_by_exact_head_runtime") is True
        and decision.get("runtime_source_current") is True
        and decision.get("runtime_completion_pass") is True
        and decision.get("exact_runtime_output_available") is True
        and decision.get("quality_pass") is True
        and decision.get("depth_pass") is True
        and decision.get("model_generation_performance_pass") is True
        and qdp.get("exact_runtime_output_available") is True
        and qdp.get("quality_on_exact_runtime_output") == "PASS"
        and qdp.get("depth_on_exact_runtime_output") == "PASS"
        and qdp.get("model_generation_performance") == "PASS"
        and performance_budget
    )

    if payload.get("status") == "PASS":
        if not exact:
            raise GateFBlocked("GATE_F_FALSE_PASS_WITHOUT_EXACT_RUNTIME_EVIDENCE")
        if payload.get("next_gate") != "G_STRUCTURED_OUTPUT":
            raise GateFBlocked("GATE_F_PASS_NEXT_GATE_INVALID")
    elif payload.get("status") == "BLOCKED":
        if exact:
            raise GateFBlocked("GATE_F_FALSE_BLOCK_WITH_COMPLETE_EVIDENCE")
        if payload.get("next_gate") is not None or decision.get("next_gate_authorized") is not False:
            raise GateFBlocked("GATE_F_BLOCKED_BUT_DOWNSTREAM_AUTHORIZED")
        if not decision.get("blocking_codes"):
            raise GateFBlocked("GATE_F_BLOCKING_CODES_MISSING")
    else:
        raise GateFBlocked("GATE_F_STATUS_INVALID")

    if req.get("machine_readable_runtime_timings_required") is not True or req.get("model_generation_performance_required") is not True:
        raise GateFBlocked("GATE_F_PERFORMANCE_REQUIREMENT_MISSING")
    expected_budget = {
        "target_model_generation_ms": TARGET_MODEL_GENERATION_MS,
        "max_acceptable_model_generation_ms": MAX_ACCEPTABLE_MODEL_GENERATION_MS,
        "max_acceptable_profile_elapsed_ms": MAX_ACCEPTABLE_PROFILE_ELAPSED_MS,
        "hard_transport_timeout_ms": HARD_TRANSPORT_TIMEOUT_MS,
        "worker_watchdog_ms": WORKER_WATCHDOG_MS,
    }
    for key, expected in expected_budget.items():
        if req.get(key) != expected:
            raise GateFBlocked(f"GATE_F_PERFORMANCE_BUDGET_INVALID:{key}")
    if payload.get("status") == "PASS" and not performance_budget:
        raise GateFBlocked("GATE_F_PERFORMANCE_BUDGET_EXCEEDED")
    return payload

def evaluate_gate_f() -> dict[str, Any]:
    payload = _load(F_OUTPUT)
    validate_gate_f_payload(payload, f_input_sha=_sha(F_INPUT), observation_sha=_sha(OBSERVATION))
    return {
        "output": payload,
        "output_sha256": _sha(F_OUTPUT),
        "gate_f_input_sha256": _sha(F_INPUT),
        "runtime_observation_sha256": _sha(OBSERVATION),
        "status": payload["status"],
        "next_gate_authorized": payload["decision"]["next_gate_authorized"],
        "blocking_codes": payload["decision"]["blocking_codes"],
    }
