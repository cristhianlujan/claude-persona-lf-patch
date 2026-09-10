from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
INPUT_PATH = HERE / "input.txt"
OUTPUT_PATH = HERE / "gate_a_output.json"
EXPECTED_SOURCE_REF = "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/input.txt"


class GateAAdmissionBlocked(RuntimeError):
    pass


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _load_output() -> dict[str, Any]:
    payload = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise GateAAdmissionBlocked("GATE_A_OUTPUT_NOT_OBJECT")
    return payload


def admit_input() -> dict[str, Any]:
    raw = INPUT_PATH.read_bytes()
    if not raw:
        raise GateAAdmissionBlocked("GATE_A_INPUT_EMPTY")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise GateAAdmissionBlocked("GATE_A_INPUT_NOT_UTF8") from exc
    if not text.strip():
        raise GateAAdmissionBlocked("GATE_A_INPUT_BLANK")

    payload = _load_output()
    if payload.get("schema") != "S26_HP001_GATE_A_OUTPUT_V1":
        raise GateAAdmissionBlocked("GATE_A_SCHEMA_INVALID")
    if payload.get("gate") != "A_INPUT_ADMISSION":
        raise GateAAdmissionBlocked("GATE_A_NAME_INVALID")
    if payload.get("project_id") != "S26" or payload.get("run_id") != "S26-HP-001":
        raise GateAAdmissionBlocked("GATE_A_IDENTITY_INVALID")
    if payload.get("status") != "PASS" or payload.get("next_gate") != "B_EKB_GOVERNANCE":
        raise GateAAdmissionBlocked("GATE_A_TRANSITION_INVALID")

    input_obj = payload.get("input") or {}
    if input_obj.get("source_type") != "USER_TEXT":
        raise GateAAdmissionBlocked("GATE_A_SOURCE_TYPE_INVALID")
    if input_obj.get("source_ref") != EXPECTED_SOURCE_REF:
        raise GateAAdmissionBlocked("GATE_A_SOURCE_REF_INVALID")
    if input_obj.get("encoding") != "utf-8":
        raise GateAAdmissionBlocked("GATE_A_ENCODING_INVALID")
    if input_obj.get("content") != text:
        raise GateAAdmissionBlocked("GATE_A_CONTENT_MUTATED")
    actual_input_sha = _sha256(raw)
    if input_obj.get("sha256") != actual_input_sha:
        raise GateAAdmissionBlocked("GATE_A_INPUT_SHA_MISMATCH")

    admission = payload.get("admission") or {}
    required_true = ("input_present", "input_non_empty", "identity_bound", "byte_exact_preservation")
    if any(admission.get(key) is not True for key in required_true):
        raise GateAAdmissionBlocked("GATE_A_REQUIRED_ASSERTION_MISSING")
    if admission.get("content_mutated") is not False:
        raise GateAAdmissionBlocked("GATE_A_MUTATION_FLAG_INVALID")

    return {
        "output": payload,
        "output_sha256": _sha256(OUTPUT_PATH.read_bytes()),
        "input_sha256": actual_input_sha,
    }
