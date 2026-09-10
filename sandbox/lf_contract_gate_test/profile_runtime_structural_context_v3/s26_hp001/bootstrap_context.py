from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
BOOTSTRAP_PATH = HERE / "bootstrap_context.json"
SHA64 = re.compile(r"^[0-9a-f]{64}$")

EXPECTED_POLICIES = {
    "POL-LF-OPERATION-LIFECYCLE": ("GOVERNANCE_LIFECYCLE", "v1.0", "973b5a0ad26433095066ff06b53c3043f38fef51d04e9482c458e178f20920e8"),
    "POL-LF-POLICY-CONSUMPTION": ("POLICY_CONSUMPTION", "v1.1-transversal-candidate", "e5eb786e14a4b735e271a81b702a0a775e0bf39ba174d333531a82a0858b5553"),
    "POL-LF-SOURCE-RESOLUTION": ("SOURCE_RESOLUTION", "v1.4-transversal-supabase-authority-visual-support", "5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46"),
    "POL-LF-STATE-MODEL": ("STATE_MODEL", "v1.1-transversal-candidate", "f451bb4d2b17cdac48c4dddb250108b2874a9d036edcfb9d2f7fa540416332aa"),
}
EXPECTED_ASSURANCE = {
    "policy_code": "POL-LF-OPERATION-LIFECYCLE",
    "policy_version": "v1.1-candidate",
    "status": "CANDIDATE",
    "policy_sha": "1677a6dc7078be9e2e851d055466093b9459a6008a05e73e82c0911f27088e6e",
    "authority_mode": "SHADOW_ASSURANCE_ONLY_NOT_ACTIVE_POLICY",
}


class BootstrapBlocked(RuntimeError):
    pass


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _canonical_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return _sha256(raw)


def load_bootstrap() -> dict[str, Any]:
    value = json.loads(BOOTSTRAP_PATH.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise BootstrapBlocked("BOOTSTRAP_NOT_OBJECT")
    return value


def validate_bootstrap(payload: dict[str, Any]) -> None:
    if payload.get("schema") != "S26_HP001_BOOTSTRAP_CONTEXT_V1":
        raise BootstrapBlocked("BOOTSTRAP_SCHEMA_INVALID")
    if payload.get("project_id") != "S26" or payload.get("run_id") != "S26-HP-001":
        raise BootstrapBlocked("BOOTSTRAP_IDENTITY_INVALID")
    if payload.get("operation_code") != "EJECUCION_PERFIL_LF":
        raise BootstrapBlocked("BOOTSTRAP_OPERATION_INVALID")
    if payload.get("execution_mode") != "SANDBOX":
        raise BootstrapBlocked("BOOTSTRAP_EXECUTION_MODE_INVALID")
    if payload.get("execution_mode_source") != "TEST_HARNESS_EXPLICIT_NON_PRODUCTION":
        raise BootstrapBlocked("BOOTSTRAP_EXECUTION_MODE_SOURCE_INVALID")
    if payload.get("distribution_mode") != "DIRECT":
        raise BootstrapBlocked("BOOTSTRAP_DISTRIBUTION_MODE_INVALID")
    if payload.get("router_execution_mode_resolved") is not False:
        raise BootstrapBlocked("BOOTSTRAP_ROUTER_EXECUTION_MODE_FALSE_PROVENANCE")

    resolution = payload.get("policy_resolution") or {}
    if resolution.get("source") != "SUPABASE_CONTROL_PLANE":
        raise BootstrapBlocked("BOOTSTRAP_POLICY_SOURCE_INVALID")
    if resolution.get("snapshot_view") != "public.v_lf_operation_policy_snapshot":
        raise BootstrapBlocked("BOOTSTRAP_POLICY_VIEW_INVALID")
    if resolution.get("reusable_for_new_run") is not False:
        raise BootstrapBlocked("BOOTSTRAP_POLICY_SNAPSHOT_REUSE_FORBIDDEN")
    refs = resolution.get("active_policy_refs")
    if not isinstance(refs, list):
        raise BootstrapBlocked("BOOTSTRAP_POLICY_REFS_NOT_ARRAY")
    if resolution.get("required_policy_count") != len(EXPECTED_POLICIES):
        raise BootstrapBlocked("BOOTSTRAP_REQUIRED_POLICY_COUNT_INVALID")
    if resolution.get("resolved_policy_count") != len(refs):
        raise BootstrapBlocked("BOOTSTRAP_RESOLVED_POLICY_COUNT_INVALID")

    by_code: dict[str, dict[str, Any]] = {}
    for ref in refs:
        if not isinstance(ref, dict):
            raise BootstrapBlocked("BOOTSTRAP_POLICY_REF_INVALID")
        code = ref.get("policy_code")
        if not isinstance(code, str) or not code:
            raise BootstrapBlocked("BOOTSTRAP_POLICY_CODE_MISSING")
        if code in by_code:
            raise BootstrapBlocked(f"BOOTSTRAP_POLICY_DUPLICATE:{code}")
        by_code[code] = ref
    if set(by_code) != set(EXPECTED_POLICIES):
        raise BootstrapBlocked("BOOTSTRAP_REQUIRED_POLICY_SET_MISMATCH")

    for code, (role, version, sha) in EXPECTED_POLICIES.items():
        ref = by_code[code]
        if ref.get("policy_role") != role:
            raise BootstrapBlocked(f"BOOTSTRAP_POLICY_ROLE_MISMATCH:{code}")
        if ref.get("policy_version") != version:
            raise BootstrapBlocked(f"BOOTSTRAP_POLICY_VERSION_MISMATCH:{code}")
        if ref.get("policy_sha") != sha or not SHA64.fullmatch(str(ref.get("policy_sha") or "")):
            raise BootstrapBlocked(f"BOOTSTRAP_POLICY_SHA_MISMATCH:{code}")
        if ref.get("required") is not True:
            raise BootstrapBlocked(f"BOOTSTRAP_POLICY_NOT_REQUIRED:{code}")
        if "DIRECT" not in (ref.get("distribution_modes") or []):
            raise BootstrapBlocked(f"BOOTSTRAP_POLICY_DIRECT_NOT_ALLOWED:{code}")

    calculated_snapshot = _canonical_sha(refs)
    if resolution.get("active_policy_snapshot_sha256") != calculated_snapshot:
        raise BootstrapBlocked("BOOTSTRAP_POLICY_SNAPSHOT_SHA_MISMATCH")

    assurance = payload.get("development_assurance") or {}
    for key, value in EXPECTED_ASSURANCE.items():
        if assurance.get(key) != value:
            raise BootstrapBlocked(f"BOOTSTRAP_ASSURANCE_INVALID:{key}")
    exception = assurance.get("direct_development_exception") or {}
    if exception.get("allowed") is not True:
        raise BootstrapBlocked("BOOTSTRAP_DIRECT_DEV_EXCEPTION_NOT_ALLOWED")
    if payload["execution_mode"] not in (exception.get("allowed_modes") or []):
        raise BootstrapBlocked("BOOTSTRAP_EXECUTION_MODE_NOT_IN_ASSURANCE")
    mandatory = {
        "MODE_EXPLICITLY_DECLARED_NON_PRODUCTION",
        "NO_PRODUCTION_CLASS_PROMOTION_OR_AUTOMATIC_IMPACT",
        "DIRECT_RESULT_LABELLED_NON_PRODUCTION_EVIDENCE",
        "DIRECT_RESULT_CANNOT_SATISFY_ROUTER_PROTECTION_OR_LIVE_PROMOTION_GATE",
        "PRODUCTION_CANDIDATE_MUST_BE_RETESTED_THROUGH_ROUTER_BEFORE_PROMOTION",
    }
    if not mandatory.issubset(set(exception.get("requirements") or [])):
        raise BootstrapBlocked("BOOTSTRAP_ASSURANCE_REQUIREMENTS_INCOMPLETE")
    if by_code["POL-LF-OPERATION-LIFECYCLE"]["policy_version"] == assurance.get("policy_version"):
        raise BootstrapBlocked("BOOTSTRAP_CANDIDATE_MISREPRESENTED_AS_ACTIVE")

    decision = payload.get("decision") or {}
    expected_decision = {
        "explicit_non_production_mode": True,
        "all_required_active_policies_resolved": True,
        "active_policy_authority_not_overridden_by_candidate": True,
        "policy_capsule_loaded_before_gate_a": True,
        "next_gate_authorized": True,
    }
    if decision != expected_decision:
        raise BootstrapBlocked("BOOTSTRAP_DECISION_INVALID")
    if payload.get("status") != "PASS" or payload.get("next_gate") != "A_INPUT_ADMISSION":
        raise BootstrapBlocked("BOOTSTRAP_TRANSITION_INVALID")


def evaluate_bootstrap(payload: dict[str, Any] | None = None) -> dict[str, Any]:
    value = payload if payload is not None else load_bootstrap()
    validate_bootstrap(value)
    resolution = value["policy_resolution"]
    return {
        "output": value,
        "output_sha256": _sha256(BOOTSTRAP_PATH.read_bytes()) if payload is None else _canonical_sha(value),
        "operation_code": value["operation_code"],
        "execution_mode": value["execution_mode"],
        "distribution_mode": value["distribution_mode"],
        "active_policy_count": len(resolution["active_policy_refs"]),
        "policy_snapshot_sha256": resolution["active_policy_snapshot_sha256"],
    }
