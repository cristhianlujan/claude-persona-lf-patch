import hashlib
import json
from typing import Any, Dict, Iterable, List


KNOWN_WORKER_KINDS = {"PROFILE", "AGENT", "SCRIPT", "SERVICE", "CAPABILITY"}
CONCRETE_IDENTITY_KEYS = {"worker_ref", "worker_profile", "capability_code"}


def _digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _block(decision: str, *, details: Dict[str, Any] | None = None) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "schema_version": "LF_SKILL_WORKER_RESOLUTION_V1",
        "status": "BLOCKED",
        "decision": decision,
    }
    if details:
        result["details"] = details
    result["resolution_digest"] = _digest(result)
    return result


def _validate_step_contract(step_contract: Dict[str, Any]) -> Dict[str, Any] | None:
    if not isinstance(step_contract, dict):
        return _block("BLOCK_STEP_CONTRACT_INVALID")

    forbidden = sorted(CONCRETE_IDENTITY_KEYS.intersection(step_contract))
    if forbidden:
        return _block(
            "BLOCK_CONCRETE_WORKER_IDENTITY_IN_MANIFEST",
            details={"forbidden_keys": forbidden},
        )

    step_id = step_contract.get("step_id")
    worker_role = step_contract.get("worker_role")
    kinds = step_contract.get("allowed_worker_kinds")
    if not isinstance(step_id, str) or not step_id.strip():
        return _block("BLOCK_STEP_ID_MISSING")
    if not isinstance(worker_role, str) or not worker_role.strip():
        return _block("BLOCK_WORKER_ROLE_MISSING")
    if not isinstance(kinds, list) or not kinds:
        return _block("BLOCK_ALLOWED_WORKER_KINDS_MISSING")
    if any(not isinstance(kind, str) or kind not in KNOWN_WORKER_KINDS for kind in kinds):
        return _block("BLOCK_ALLOWED_WORKER_KIND_INVALID")
    if len(set(kinds)) != len(kinds):
        return _block("BLOCK_ALLOWED_WORKER_KIND_DUPLICATE")
    return None


def _candidate_rejection_reasons(
    candidate: Dict[str, Any],
    *,
    worker_role: str,
    allowed_kinds: set[str],
    source_revision: str,
) -> List[str]:
    reasons: List[str] = []
    worker_ref = candidate.get("worker_ref")
    worker_kind = candidate.get("worker_kind")
    worker_roles = candidate.get("worker_roles")

    if not isinstance(worker_ref, str) or not worker_ref.strip():
        reasons.append("WORKER_REF_MISSING")
    if worker_kind not in allowed_kinds:
        reasons.append("WORKER_KIND_NOT_ALLOWED")
    if not isinstance(worker_roles, list) or worker_role not in worker_roles:
        reasons.append("WORKER_ROLE_NOT_CLAIMED")
    if candidate.get("route_status") != "READY_TO_EXECUTE":
        reasons.append("ROUTER_NOT_READY")
    if candidate.get("downstream_execution_allowed") is not True:
        reasons.append("DOWNSTREAM_NOT_ALLOWED")
    if candidate.get("currentness_state") != "CURRENT":
        reasons.append("CURRENTNESS_NOT_CURRENT")
    if candidate.get("source_revision") != source_revision:
        reasons.append("SOURCE_REVISION_MISMATCH")
    if not isinstance(candidate.get("source_ref"), str) or not candidate.get("source_ref", "").strip():
        reasons.append("SOURCE_REF_MISSING")

    if worker_kind == "CAPABILITY":
        if not isinstance(candidate.get("capability_code"), str) or not candidate.get("capability_code", "").strip():
            reasons.append("CAPABILITY_CODE_MISSING")
        if candidate.get("capability_execution_contract") != "CAPABILITY_EXECUTION_CONTRACT_V1":
            reasons.append("CAPABILITY_CONTRACT_MISSING")

    return reasons


def resolve_worker(step_contract: Dict[str, Any], authority_snapshot: Dict[str, Any]) -> Dict[str, Any]:
    step_error = _validate_step_contract(step_contract)
    if step_error:
        return step_error

    if not isinstance(authority_snapshot, dict):
        return _block("BLOCK_AUTHORITY_SNAPSHOT_INVALID")

    binding_authority_ref = authority_snapshot.get("binding_authority_ref")
    binding_revision = authority_snapshot.get("binding_revision")
    source_revision = authority_snapshot.get("source_revision")
    candidates = authority_snapshot.get("candidates")

    if not isinstance(binding_authority_ref, str) or not binding_authority_ref.strip():
        return _block("BLOCK_BINDING_AUTHORITY_REF_MISSING")
    if not isinstance(binding_revision, str) or not binding_revision.strip():
        return _block("BLOCK_BINDING_REVISION_MISSING")
    if not isinstance(source_revision, str) or not source_revision.strip():
        return _block("BLOCK_SOURCE_REVISION_MISSING")
    if not isinstance(candidates, list):
        return _block("BLOCK_CANDIDATE_SET_INVALID")

    worker_role = step_contract["worker_role"]
    allowed_kinds = set(step_contract["allowed_worker_kinds"])
    eligible: List[Dict[str, Any]] = []
    rejected: List[Dict[str, Any]] = []

    seen_refs: set[str] = set()
    for candidate in candidates:
        if not isinstance(candidate, dict):
            rejected.append({"worker_ref": None, "reasons": ["CANDIDATE_INVALID"]})
            continue
        worker_ref = candidate.get("worker_ref")
        if isinstance(worker_ref, str) and worker_ref in seen_refs:
            return _block("BLOCK_WORKER_AUTHORITY_DUPLICATE", details={"worker_ref": worker_ref})
        if isinstance(worker_ref, str):
            seen_refs.add(worker_ref)

        reasons = _candidate_rejection_reasons(
            candidate,
            worker_role=worker_role,
            allowed_kinds=allowed_kinds,
            source_revision=source_revision,
        )
        if reasons:
            rejected.append({"worker_ref": worker_ref, "reasons": reasons})
        else:
            eligible.append(candidate)

    if not eligible:
        capability_contract_gap = any(
            "CAPABILITY_CONTRACT_MISSING" in item["reasons"] for item in rejected
        )
        decision = "BLOCK_CAPABILITY_CONTRACT_MISSING" if capability_contract_gap else "BLOCK_WORKER_UNRESOLVED"
        return _block(
            decision,
            details={"worker_role": worker_role, "rejected": rejected},
        )

    if len(eligible) > 1:
        return _block(
            "BLOCK_WORKER_AMBIGUOUS",
            details={"worker_role": worker_role, "eligible_worker_refs": sorted(c["worker_ref"] for c in eligible)},
        )

    selected = eligible[0]
    binding_material: Dict[str, Any] = {
        "step_id": step_contract["step_id"],
        "worker_role": worker_role,
        "worker_ref": selected["worker_ref"],
        "worker_kind": selected["worker_kind"],
        "binding_authority_ref": binding_authority_ref,
        "binding_revision": binding_revision,
        "source_revision": source_revision,
        "source_ref": selected["source_ref"],
    }
    if selected["worker_kind"] == "CAPABILITY":
        binding_material["capability_code"] = selected["capability_code"]
        binding_material["capability_execution_contract"] = selected["capability_execution_contract"]

    binding_digest = _digest(binding_material)
    binding_seed = {
        "worker_ref": selected["worker_ref"],
        "worker_kind": selected["worker_kind"],
        "binding_authority_ref": binding_authority_ref,
        "binding_revision": binding_revision,
        "binding_digest": binding_digest,
        "source_revision": source_revision,
    }
    if selected["worker_kind"] == "CAPABILITY":
        binding_seed["capability_code"] = selected["capability_code"]
        binding_seed["capability_execution_contract"] = selected["capability_execution_contract"]

    result = {
        "schema_version": "LF_SKILL_WORKER_RESOLUTION_V1",
        "status": "RESOLVED",
        "decision": "WORKER_RESOLVED",
        "step_id": step_contract["step_id"],
        "worker_role": worker_role,
        "binding_seed": binding_seed,
        "rejected_candidate_count": len(rejected),
    }
    result["resolution_digest"] = _digest(result)
    return result
