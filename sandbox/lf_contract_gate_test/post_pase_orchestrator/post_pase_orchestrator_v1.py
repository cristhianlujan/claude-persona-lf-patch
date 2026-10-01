from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Callable, Dict, List

HERE = Path(__file__).resolve().parent
CONTRACT_PATH = HERE / "post_pase_orchestrator_contract_v1.json"
HEX64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_PLAN_SCHEMA = "LF_POST_PASE_PLAN_V1"
EXPECTED_ROUTER = "POST_PASE_ROUTER_V1"
RESOLVED_BINDING_STATE = "RESOLVED_CURRENT_CARRIER"


class PostPaseOrchestratorBlocked(RuntimeError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise PostPaseOrchestratorBlocked(code)


def load_contract() -> Dict[str, Any]:
    data = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    validate_contract(data)
    return data


def validate_contract(contract: Dict[str, Any]) -> None:
    _require(contract.get("schema_version") == "lf-post-pase-orchestrator/v1", "BLOCK_CONTRACT_SCHEMA")
    _require(contract.get("solution_code") == "POST_PASE_ORCHESTRATOR_V1", "BLOCK_CONTRACT_IDENTITY")
    _require(contract.get("asset_code") == "POST_PASE_ORCHESTRATOR", "BLOCK_ASSET_IDENTITY")
    _require(contract.get("owner") == "LF_GOVERNANCE", "BLOCK_OWNER")
    _require(contract.get("mode") == "SEQUENTIAL_IMMUTABLE_PLAN_DISPATCH", "BLOCK_MODE")
    policy = contract.get("dispatch_policy") or {}
    _require(policy.get("parallel_dispatch") is False, "BLOCK_PARALLEL_DISPATCH")
    _require(policy.get("applicability_rediscovery") is False, "BLOCK_APPLICABILITY_REDISCOVERY")
    _require(policy.get("owner_runner_carrier_recalculation") is False, "BLOCK_OWNER_RECALCULATION")
    _require(policy.get("embedded_control_logic") is False, "BLOCK_EMBEDDED_CONTROL_LOGIC")
    persistence = contract.get("persistence_policy") or {}
    _require(persistence.get("new_store_created") is False, "BLOCK_PARALLEL_RECEIPT_STORE")
    _require(persistence.get("orchestrator_is_not_evidence_ledger") is True, "BLOCK_EVIDENCE_LEDGER_COLLAPSE")


def _default_plan_verifier(plan: Dict[str, Any]) -> bool:
    from sandbox.lf_contract_gate_test.post_pase_router.post_pase_router_v1 import verify_post_pase_plan
    return verify_post_pase_plan(plan)


def _default_request_builder(**kwargs: Any) -> Dict[str, Any]:
    from sandbox.lf_contract_gate_test.capability_execution_contract.capability_execution_contract_v1 import build_request
    return build_request(**kwargs)


def _default_receipt_validator(request: Dict[str, Any], receipt: Dict[str, Any]) -> None:
    from sandbox.lf_contract_gate_test.capability_execution_contract.capability_execution_contract_v1 import validate_receipt
    validate_receipt(request, receipt)


def _validate_plan_envelope(plan: Dict[str, Any]) -> None:
    _require(isinstance(plan, dict), "BLOCK_PLAN_SHAPE")
    _require(plan.get("schema_version") == EXPECTED_PLAN_SCHEMA, "BLOCK_PLAN_SCHEMA")
    _require(plan.get("router_code") == EXPECTED_ROUTER, "BLOCK_PLAN_ROUTER")
    _require(plan.get("immutable") is True, "BLOCK_PLAN_NOT_IMMUTABLE")
    _require(plan.get("control_execution_performed") is False, "BLOCK_ROUTER_EXECUTION_CONTAMINATION")
    _require(plan.get("control_logic_embedded") is False, "BLOCK_ROUTER_CONTROL_LOGIC_CONTAMINATION")
    _require(plan.get("owner_recalculation_performed") is False, "BLOCK_ROUTER_OWNER_CONTAMINATION")
    _require(plan.get("evidence_collection_performed") is False, "BLOCK_ROUTER_EVIDENCE_CONTAMINATION")
    _require(isinstance(plan.get("plan_digest"), str) and bool(HEX64.fullmatch(plan["plan_digest"])), "BLOCK_PLAN_DIGEST")
    _require(isinstance(plan.get("merge_sha"), str) and bool(plan["merge_sha"]), "BLOCK_PLAN_SOURCE_REVISION")
    controls = plan.get("controls")
    _require(isinstance(controls, list) and controls, "BLOCK_PLAN_CONTROLS")


def _required_controls(plan: Dict[str, Any]) -> List[Dict[str, Any]]:
    required: List[Dict[str, Any]] = []
    seen: set[str] = set()
    for row in plan["controls"]:
        _require(isinstance(row, dict), "BLOCK_CONTROL_SHAPE")
        code = row.get("capability_code")
        _require(isinstance(code, str) and bool(code) and code not in seen, "BLOCK_CONTROL_IDENTITY")
        seen.add(code)
        disposition = row.get("disposition")
        _require(disposition in {"REQUIRED", "NOT_APPLICABLE"}, "BLOCK_CONTROL_DISPOSITION")
        if disposition == "REQUIRED":
            _require(isinstance(row.get("scope"), dict) and row["scope"], "BLOCK_REQUIRED_SCOPE")
            _require(isinstance(row.get("scope_digest"), str) and bool(HEX64.fullmatch(row["scope_digest"])), "BLOCK_SCOPE_DIGEST")
            required.append(row)
        else:
            _require(row.get("scope") is None and row.get("scope_digest") is None, "BLOCK_NOT_APPLICABLE_SCOPE")
    return required


def _validate_binding(binding: Dict[str, Any], *, capability_code: str, orchestrator_execution_id: str,
                      plan_digest: str) -> None:
    _require(isinstance(binding, dict) and binding.get("ready") is True, "BLOCK_BINDING_NOT_READY")
    _require(binding.get("capability_code") == capability_code, "BLOCK_BINDING_CAPABILITY_CROSSBIND")
    _require(binding.get("orchestrator_execution_id") == orchestrator_execution_id, "BLOCK_BINDING_EXECUTION_CROSSBIND")
    _require(binding.get("plan_digest") == plan_digest, "BLOCK_BINDING_PLAN_CROSSBIND")
    _require(binding.get("super_admin") == "LF_GOVERNANCE", "BLOCK_BINDING_SUPER_ADMIN")
    _require(binding.get("state") == RESOLVED_BINDING_STATE, "BLOCK_BINDING_STATE")
    for field in ("runner_ref", "carrier", "source_revision", "dispatch_receipt_id"):
        _require(isinstance(binding.get(field), str) and bool(binding[field]), f"BLOCK_BINDING_{field.upper()}")
    _require(isinstance(binding.get("binding_digest"), str) and bool(HEX64.fullmatch(binding["binding_digest"])), "BLOCK_BINDING_DIGEST")
    guard = binding.get("entry_guard_readback")
    _require(isinstance(guard, dict) and guard.get("ready") is True, "BLOCK_ENTRY_GUARD_READBACK")
    _require(guard.get("decision") == "ORCHESTRATOR_ENTRY_ACCEPTED", "BLOCK_ENTRY_GUARD_DECISION")
    _require(guard.get("guard_code") == "ORCHESTRATOR_EXECUTION_GUARD_V1", "BLOCK_ENTRY_GUARD_CODE")
    _require(guard.get("orchestrator_execution_id") == orchestrator_execution_id, "BLOCK_ENTRY_GUARD_EXECUTION_CROSSBIND")
    _require(guard.get("receipt_id") == binding["dispatch_receipt_id"], "BLOCK_ENTRY_GUARD_RECEIPT_CROSSBIND")
    refs = binding.get("authority_refs")
    _require(isinstance(refs, dict), "BLOCK_AUTHORITY_REFS")
    for key in ("governance_admin", "owner_runner_carrier", "entry_guard", "evidence_ledger"):
        row = refs.get(key)
        _require(isinstance(row, dict), f"BLOCK_AUTHORITY_REF:{key}")
        _require(isinstance(row.get("ref"), str) and bool(row["ref"]), f"BLOCK_AUTHORITY_REF_NAME:{key}")
        _require(isinstance(row.get("revision"), str) and bool(row["revision"]), f"BLOCK_AUTHORITY_REF_REVISION:{key}")
        _require(isinstance(row.get("digest"), str) and bool(HEX64.fullmatch(row["digest"])), f"BLOCK_AUTHORITY_REF_DIGEST:{key}")


def execute_post_pase_plan(
    plan: Dict[str, Any],
    *,
    orchestrator_execution_id: str,
    consumer_execution_id: str,
    binding_provider: Callable[[Dict[str, Any]], Dict[str, Any]],
    capability_executor: Callable[[Dict[str, Any], Dict[str, Any]], Dict[str, Any]],
    receipt_sink: Callable[[Dict[str, Any]], Any],
    plan_verifier: Callable[[Dict[str, Any]], bool] | None = None,
    request_builder: Callable[..., Dict[str, Any]] | None = None,
    receipt_validator: Callable[[Dict[str, Any], Dict[str, Any]], None] | None = None,
) -> Dict[str, Any]:
    contract = load_contract()
    _require(isinstance(orchestrator_execution_id, str) and bool(orchestrator_execution_id), "BLOCK_ORCHESTRATOR_EXECUTION_ID")
    _require(isinstance(consumer_execution_id, str) and bool(consumer_execution_id), "BLOCK_CONSUMER_EXECUTION_ID")
    _validate_plan_envelope(plan)
    verifier = plan_verifier or _default_plan_verifier
    _require(verifier(plan) is True, "BLOCK_PLAN_VERIFICATION")
    required = _required_controls(plan)
    build_request = request_builder or _default_request_builder
    validate_receipt = receipt_validator or _default_receipt_validator
    plan_digest = plan["plan_digest"]
    persisted: List[Dict[str, Any]] = []
    skipped = [row["capability_code"] for row in plan["controls"] if row["disposition"] == "NOT_APPLICABLE"]

    for ordinal, control in enumerate(required, start=1):
        code = control["capability_code"]
        binding_query = {
            "schema_version": "LF_POST_PASE_BINDING_QUERY_V1",
            "orchestrator_execution_id": orchestrator_execution_id,
            "consumer_execution_id": consumer_execution_id,
            "plan_digest": plan_digest,
            "capability_code": code,
            "scope_digest": control["scope_digest"],
            "source_revision": plan["merge_sha"],
        }
        binding = binding_provider(binding_query)
        _validate_binding(binding, capability_code=code, orchestrator_execution_id=orchestrator_execution_id, plan_digest=plan_digest)
        prior_receipts = [row["receipt_digest"] for row in persisted]
        step_input = {
            "schema_version": "LF_POST_PASE_DISPATCH_INPUT_V1",
            "orchestrator_execution_id": orchestrator_execution_id,
            "consumer_execution_id": consumer_execution_id,
            "plan_digest": plan_digest,
            "merge_sha": plan["merge_sha"],
            "capability_code": code,
            "ordinal": ordinal,
            "scope_digest": control["scope_digest"],
            "prior_receipt_digests": prior_receipts,
        }
        request = build_request(
            orchestrator_execution_id=orchestrator_execution_id,
            consumer_execution_id=consumer_execution_id,
            capability_code=code,
            plan_digest=plan_digest,
            dispatch_receipt_id=binding["dispatch_receipt_id"],
            dispatch_scope=control["scope"],
            entry_guard_readback=binding["entry_guard_readback"],
            authority_refs=binding["authority_refs"],
            input_ref=f"post-pase://{plan_digest}/dispatch/{ordinal}/{code}",
            input_digest=digest(step_input),
            source_revision=binding["source_revision"],
        )
        receipt = capability_executor(binding, request)
        validate_receipt(request, receipt)
        _require(receipt.get("capability_code") == code, "BLOCK_RECEIPT_CAPABILITY")
        _require(receipt.get("plan_digest") == plan_digest, "BLOCK_RECEIPT_PLAN")
        _require(isinstance(receipt.get("receipt_digest"), str) and bool(HEX64.fullmatch(receipt["receipt_digest"])), "BLOCK_RECEIPT_DIGEST")
        sink_record = {
            "schema_version": "LF_POST_PASE_RECEIPT_PERSIST_V1",
            "orchestrator_execution_id": orchestrator_execution_id,
            "consumer_execution_id": consumer_execution_id,
            "plan_digest": plan_digest,
            "capability_code": code,
            "ordinal": ordinal,
            "binding_digest": binding["binding_digest"],
            "request_digest": request["request_digest"],
            "receipt_digest": receipt["receipt_digest"],
            "evidence_refs": receipt.get("evidence_refs"),
            "receipt": receipt,
        }
        sink_result = receipt_sink(sink_record)
        _require(sink_result is not False, "BLOCK_RECEIPT_PERSISTENCE")
        persisted.append({
            "capability_code": code,
            "ordinal": ordinal,
            "request_digest": request["request_digest"],
            "receipt_digest": receipt["receipt_digest"],
            "evidence_refs": receipt.get("evidence_refs"),
        })

    result: Dict[str, Any] = {
        "schema_version": contract["output_schema"],
        "solution_code": contract["solution_code"],
        "orchestrator_execution_id": orchestrator_execution_id,
        "consumer_execution_id": consumer_execution_id,
        "plan_digest": plan_digest,
        "source_revision": plan["merge_sha"],
        "dispatch_mode": "SEQUENTIAL_FAIL_CLOSED",
        "required_capability_count": len(required),
        "persisted_receipt_count": len(persisted),
        "skipped_not_applicable": skipped,
        "receipts": persisted,
        "applicability_rediscovered": False,
        "owner_runner_carrier_recalculated": False,
        "control_logic_embedded": False,
        "parallel_dispatch_performed": False,
        "self_authorized": False,
    }
    result["orchestration_receipt_digest"] = digest(result)
    return result
