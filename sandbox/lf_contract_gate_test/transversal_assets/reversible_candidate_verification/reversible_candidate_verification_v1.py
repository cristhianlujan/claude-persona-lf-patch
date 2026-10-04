from __future__ import annotations
import hashlib
import json
from dataclasses import dataclass, asdict
from typing import Any, Protocol

CAPABILITY_CODE = "REVERSIBLE_CANDIDATE_VERIFICATION"
SCHEMA_VERSION = "LF_REVERSIBLE_CANDIDATE_VERIFICATION_RECEIPT_V1"
MUTATION_POLICY = "ROLLBACK_ONLY"

@dataclass(frozen=True)
class CandidateIdentity:
    candidate_ref: str
    candidate_sha256: str
    metadata: dict[str, Any] | None = None

@dataclass(frozen=True)
class RollbackContract:
    mutation_policy: str = MUTATION_POLICY
    exact_state_digest_required: bool = True
    zero_material_residue_required: bool = True

class FlowAdapter(Protocol):
    adapter_code: str
    def run_rollback_only(self, candidate: CandidateIdentity, rollback: RollbackContract) -> dict[str, Any]: ...

class IndependentOracle(Protocol):
    oracle_code: str
    def evaluate(self, baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]: ...

def canonical_digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()

def _valid_sha256(value: str) -> bool:
    if len(value) != 64:
        return False
    try:
        int(value, 16)
        return True
    except ValueError:
        return False

def _blocked(candidate, adapter_code, oracle_code, findings, receipt=None):
    return {
        "schema_version": SCHEMA_VERSION,
        "capability_code": CAPABILITY_CODE,
        "candidate_identity": asdict(candidate),
        "flow_adapter": adapter_code,
        "oracle": oracle_code,
        "mutation_policy": MUTATION_POLICY,
        "verdict": "BLOCK",
        "findings": findings,
        "adapter_receipt": receipt,
        "promotion_authorized": False,
        "activation_authorized": False,
    }

def verify_candidate(candidate_identity: CandidateIdentity, flow_adapter: FlowAdapter, baseline_oracle: IndependentOracle, rollback_contract: RollbackContract) -> dict[str, Any]:
    adapter_code = str(getattr(flow_adapter, "adapter_code", "UNKNOWN_ADAPTER"))
    oracle_code = str(getattr(baseline_oracle, "oracle_code", "UNKNOWN_ORACLE"))
    if not candidate_identity.candidate_ref.strip() or not _valid_sha256(candidate_identity.candidate_sha256):
        return _blocked(candidate_identity, adapter_code, oracle_code, [{"code":"CANDIDATE_IDENTITY_INVALID","blocking":True}])
    if rollback_contract.mutation_policy != MUTATION_POLICY:
        return _blocked(candidate_identity, adapter_code, oracle_code, [{"code":"ROLLBACK_ONLY_REQUIRED","blocking":True}])
    try:
        receipt = flow_adapter.run_rollback_only(candidate_identity, rollback_contract)
    except Exception as exc:
        return _blocked(candidate_identity, adapter_code, oracle_code, [{"code":"ADAPTER_EXECUTION_FAILED","blocking":True,"detail":f"{type(exc).__name__}:{exc}"}])
    baseline = receipt.get("baseline")
    candidate = receipt.get("candidate")
    rollback = receipt.get("rollback")
    findings: list[dict[str, Any]] = []
    if not isinstance(baseline, dict) or not isinstance(candidate, dict) or not isinstance(rollback, dict):
        return _blocked(candidate_identity, adapter_code, oracle_code, [{"code":"ADAPTER_RECEIPT_INVALID","blocking":True}], receipt)
    baseline_digest = str(baseline.get("state_digest") or "")
    post_digest = str(rollback.get("post_state_digest") or "")
    rollback_status = str(rollback.get("status") or "")
    residue_count = rollback.get("material_residue_count")
    if rollback_status != "ROLLED_BACK":
        findings.append({"code":"ROLLBACK_FAILED","blocking":True,"status":rollback_status})
    if rollback_contract.exact_state_digest_required and (not baseline_digest or post_digest != baseline_digest):
        findings.append({"code":"POST_ROLLBACK_STATE_DRIFT","blocking":True,"baseline_digest":baseline_digest,"post_state_digest":post_digest})
    if rollback_contract.zero_material_residue_required and residue_count != 0:
        findings.append({"code":"MATERIAL_RESIDUE_PRESENT","blocking":True,"material_residue_count":residue_count})
    try:
        oracle = baseline_oracle.evaluate(baseline, candidate)
    except Exception as exc:
        findings.append({"code":"ORACLE_EXECUTION_FAILED","blocking":True,"detail":f"{type(exc).__name__}:{exc}"})
        oracle = {"pass":False}
    if oracle.get("pass") is not True:
        findings.append({"code":"ORACLE_REJECTED_CANDIDATE","blocking":True,"oracle_result":oracle})
    return {
        "schema_version": SCHEMA_VERSION,
        "capability_code": CAPABILITY_CODE,
        "candidate_identity": asdict(candidate_identity),
        "flow_adapter": adapter_code,
        "oracle": oracle_code,
        "mutation_policy": MUTATION_POLICY,
        "verdict": "BLOCK" if findings else "PASS",
        "findings": findings,
        "oracle_result": oracle,
        "adapter_receipt": receipt,
        "rollback_exact": bool(baseline_digest and post_digest == baseline_digest and rollback_status == "ROLLED_BACK"),
        "material_residue_count": residue_count,
        "promotion_authorized": False,
        "activation_authorized": False,
    }
