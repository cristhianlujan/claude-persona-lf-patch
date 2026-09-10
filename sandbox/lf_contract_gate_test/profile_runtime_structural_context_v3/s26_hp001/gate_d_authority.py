from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from .gate_c_card_selection import evaluate_card_selection

REPO = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUTPUT_PATH = HERE / "gate_d_output.json"
CONTRACT_PATH = HERE / "preexecution_contract.json"


class GateDAuthorityBlocked(RuntimeError):
    pass


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise GateDAuthorityBlocked(f"GATE_D_NOT_OBJECT:{path.name}")
    return payload


def validate_authority_output(payload: dict[str, Any], gate_c: dict[str, Any], contract: dict[str, Any], *, repo_root: Path = REPO) -> None:
    c = gate_c["output"]
    if payload.get("schema") != "S26_HP001_GATE_D_OUTPUT_V1":
        raise GateDAuthorityBlocked("GATE_D_SCHEMA_INVALID")
    if payload.get("gate") != "D_AUTHORITY_RESOLUTION":
        raise GateDAuthorityBlocked("GATE_D_NAME_INVALID")
    if payload.get("project_id") != "S26" or payload.get("run_id") != c.get("run_id"):
        raise GateDAuthorityBlocked("GATE_D_IDENTITY_INVALID")
    if c.get("next_gate") != "D_AUTHORITY_RESOLUTION":
        raise GateDAuthorityBlocked("GATE_C_DID_NOT_AUTHORIZE_D")
    upstream = payload.get("upstream") or {}
    if upstream.get("source_gate") != "C_CARD_SELECTION":
        raise GateDAuthorityBlocked("GATE_D_UPSTREAM_GATE_INVALID")
    if upstream.get("source_output_sha256") != gate_c.get("output_sha256"):
        raise GateDAuthorityBlocked("GATE_D_UPSTREAM_OUTPUT_SHA_MISMATCH")
    c_input = c.get("input") or {}
    if upstream.get("input_sha256") != c_input.get("input_literal_sha256"):
        raise GateDAuthorityBlocked("GATE_D_UPSTREAM_INPUT_SHA_MISMATCH")
    preflight = payload.get("governance_preflight") or {}
    if preflight.get("source") != "SUPABASE_CONTROL_PLANE" or preflight.get("table") != "public.lf_error_knowledge":
        raise GateDAuthorityBlocked("GATE_D_EKB_SOURCE_INVALID")
    if preflight.get("schema_first_verified") is not True:
        raise GateDAuthorityBlocked("GATE_D_EKB_SCHEMA_FIRST_MISSING")
    if not isinstance(preflight.get("broad_high_critical_active_count"), int) or preflight["broad_high_critical_active_count"] <= 0:
        raise GateDAuthorityBlocked("GATE_D_EKB_BROAD_SNAPSHOT_EMPTY")
    digest = preflight.get("broad_snapshot_sha256")
    if not isinstance(digest, str) or len(digest) != 64:
        raise GateDAuthorityBlocked("GATE_D_EKB_SNAPSHOT_DIGEST_INVALID")
    codes = preflight.get("applicable_codes") or []
    for code in ("AUD-019", "GOV-023", "GOV-032", "PROFILE-CARD-RUNTIME-MATERIALIZATION-GAP-001"):
        if code not in codes:
            raise GateDAuthorityBlocked(f"GATE_D_EKB_REQUIRED_CONTROL_MISSING:{code}")
    if preflight.get("snapshot_reused_from_gate_b") is not False or preflight.get("prior_gate_outputs_mutated") is not False:
        raise GateDAuthorityBlocked("GATE_D_EKB_PRIOR_GATE_IMMUTABILITY_INVALID")
    expected = contract.get("stage_d_authority") or {}
    incoming = payload.get("input") or {}
    for key in ("surface_code", "task_code", "current_run_id"):
        if incoming.get(key) != expected.get(key):
            raise GateDAuthorityBlocked(f"GATE_D_INPUT_{key.upper()}_INVALID")
    if incoming.get("current_run_id") != c.get("run_id"):
        raise GateDAuthorityBlocked("GATE_D_CURRENT_RUN_ID_MISMATCH")
    required = expected.get("required_authority_types") or []
    if incoming.get("required_authority_types") != required:
        raise GateDAuthorityBlocked("GATE_D_REQUIRED_TYPES_DRIFT")
    expected_paths = expected.get("authority_paths") or {}
    if incoming.get("authority_paths") != expected_paths:
        raise GateDAuthorityBlocked("GATE_D_AUTHORITY_PATHS_DRIFT")
    resolved = payload.get("authority_resolution")
    if not isinstance(resolved, list):
        raise GateDAuthorityBlocked("GATE_D_RESOLUTION_NOT_ARRAY")
    if len(resolved) != len(required):
        raise GateDAuthorityBlocked("GATE_D_AUTHORITY_COUNT_INVALID")
    by_type = {}
    for item in resolved:
        if not isinstance(item, dict):
            raise GateDAuthorityBlocked("GATE_D_AUTHORITY_ITEM_INVALID")
        authority_type = item.get("authority_type")
        if authority_type not in required:
            raise GateDAuthorityBlocked(f"GATE_D_UNKNOWN_AUTHORITY:{authority_type}")
        if authority_type in by_type:
            raise GateDAuthorityBlocked(f"GATE_D_DUPLICATE_AUTHORITY:{authority_type}")
        by_type[authority_type] = item
    if set(by_type) != set(required):
        missing = sorted(set(required).difference(by_type))
        raise GateDAuthorityBlocked("GATE_D_REQUIRED_AUTHORITY_MISSING:" + ",".join(missing))
    for authority_type in required:
        item = by_type[authority_type]
        expected_ref = expected_paths.get(authority_type)
        if item.get("authority_id") != f"S26_HP001_{authority_type}":
            raise GateDAuthorityBlocked(f"GATE_D_AUTHORITY_ID_INVALID:{authority_type}")
        if item.get("run_id") != c.get("run_id"):
            raise GateDAuthorityBlocked(f"GATE_D_AUTHORITY_RUN_ID_INVALID:{authority_type}")
        if item.get("cross_run_declared") is not False or item.get("cross_run_authorization") is not None:
            raise GateDAuthorityBlocked(f"GATE_D_CROSS_RUN_AUTHORITY_FORBIDDEN:{authority_type}")
        if item.get("ref") != expected_ref:
            raise GateDAuthorityBlocked(f"GATE_D_AUTHORITY_REF_INVALID:{authority_type}")
        path = (repo_root / expected_ref).resolve()
        try:
            path.relative_to(repo_root.resolve())
        except ValueError as exc:
            raise GateDAuthorityBlocked(f"GATE_D_AUTHORITY_PATH_ESCAPE:{authority_type}") from exc
        if not path.is_file():
            raise GateDAuthorityBlocked(f"GATE_D_AUTHORITY_FILE_MISSING:{authority_type}")
        actual_sha = _sha256(path.read_bytes())
        if item.get("sha256") != actual_sha:
            raise GateDAuthorityBlocked(f"GATE_D_AUTHORITY_SHA_MISMATCH:{authority_type}")
    decision = payload.get("decision") or {}
    expected_decision = {"authority_resolution_complete": True,"required_authority_count": len(required),"resolved_authority_count": len(required),"incompatible_authorities_detected": False,"cross_run_authority_used": False,"candidate_derived_authority_used": False,"semantic_authority_invention_allowed": False,"next_gate_authorized": True}
    for key, value in expected_decision.items():
        if decision.get(key) != value:
            raise GateDAuthorityBlocked(f"GATE_D_DECISION_INVALID:{key}")
    if payload.get("status") != "PASS" or payload.get("next_gate") != expected.get("next_gate"):
        raise GateDAuthorityBlocked("GATE_D_TRANSITION_INVALID")


def evaluate_authority_resolution(gate_c: dict[str, Any] | None = None) -> dict[str, Any]:
    gate_c = gate_c or evaluate_card_selection()
    payload = _load_json(OUTPUT_PATH)
    contract = _load_json(CONTRACT_PATH)
    validate_authority_output(payload, gate_c, contract)
    return {"output": payload,"output_sha256": _sha256(OUTPUT_PATH.read_bytes()),"input_sha256": (payload.get("upstream") or {}).get("input_sha256"),"authority_count": len(payload.get("authority_resolution") or [])}
