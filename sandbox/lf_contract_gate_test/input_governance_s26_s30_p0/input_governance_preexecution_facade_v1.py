#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Mapping

import input_governance_capability_resolver_v1 as capability

FACADE_CONTRACT = "INPUT_GOVERNANCE_PREEXECUTION_FACADE_V1"
EXPECTED_REGISTRY_BLOB_SHA = "2cd314c8cc0323c4bba85c13564f7a28b8680122"
EXPECTED_RESOLVER_BLOB_SHA = "7f5ed0ee618aed2ac7c4b136db919032f09fa27a"
UPSTREAM_STAGE_CONCLUSION_BLOB_SHA = "fa217d67ddca3aed8ad710aa914abc190d272ff7"

OPERATION_TO_CAPABILITY = {
    "REGISTERED_DATA_READ": "LF_BUDGETED_DATA_ACCESS",
    "UNKNOWN_DATA_SOURCE_SCHEMA": "LF_SCHEMA_CONTRACT_RESOLUTION",
    "EXECUTION_AUTHORITY_DECISION": "LF_EXECUTION_AUTHORITY",
    "INPUT_GOVERNANCE_DISPATCH": "INPUT_GOVERNANCE_DISPATCH",
}


@dataclass(frozen=True)
class BoundExecutor:
    implementation_ref: str
    implementation_sha: str
    execute: Callable[[Mapping[str, Any], Mapping[str, Any]], Mapping[str, Any]]


def _result(status: str, code: str, **extra: Any) -> dict[str, Any]:
    out = {"facade_contract": FACADE_CONTRACT, "status": status, "code": code}
    out.update(extra)
    return out


def _executor_matches(plan: Mapping[str, Any], executor: BoundExecutor) -> bool:
    return (
        executor.implementation_ref == plan.get("implementation_ref")
        and executor.implementation_sha == plan.get("implementation_sha")
    )


def execute_preexecution(
    registry: Mapping[str, Any],
    request: Mapping[str, Any],
    *,
    currentness: Mapping[str, Any] | None,
    executors: Mapping[str, BoundExecutor],
) -> dict[str, Any]:
    operation_kind = request.get("operation_kind")
    if operation_kind not in OPERATION_TO_CAPABILITY:
        return _result("BLOCKED", "BLOCK_OPERATION_KIND_UNKNOWN", backend_executed=False, operation_kind=operation_kind)
    consumer = request.get("consumer")
    if not isinstance(consumer, str) or not consumer:
        return _result("BLOCKED", "BLOCK_CONSUMER_REQUIRED", backend_executed=False)
    if request.get("resource_selector_authority", "DETERMINISTIC") != "DETERMINISTIC":
        return _result("BLOCKED", "BLOCK_MODEL_RESOURCE_SELECTION", backend_executed=False)

    capability_id = OPERATION_TO_CAPABILITY[operation_kind]
    resolution = capability.resolve_capability(
        registry,
        capability_id=capability_id,
        consumer=consumer,
        currentness=currentness,
        selector_authority="DETERMINISTIC",
    )
    if resolution.get("status") != capability.PASS:
        return _result(
            "BLOCKED",
            resolution.get("code", "BLOCK_CAPABILITY_RESOLUTION"),
            capability_id=capability_id,
            resolution=resolution,
            backend_executed=False,
        )

    plan = resolution["execution_plan"]
    implementation_ref = plan["implementation_ref"]
    executor = executors.get(implementation_ref)
    if executor is None:
        return _result(
            "BLOCKED",
            "BLOCK_BOUND_EXECUTOR_MISSING",
            capability_id=capability_id,
            resolution=resolution,
            backend_executed=False,
        )
    if not _executor_matches(plan, executor):
        return _result(
            "BLOCKED",
            "BLOCK_PRE_EXECUTOR_PROVENANCE_MISMATCH",
            capability_id=capability_id,
            resolution=resolution,
            expected={"implementation_ref":plan["implementation_ref"],"implementation_sha":plan["implementation_sha"]},
            observed={"implementation_ref":executor.implementation_ref,"implementation_sha":executor.implementation_sha},
            backend_executed=False,
        )

    payload = request.get("payload")
    if not isinstance(payload, Mapping):
        return _result("BLOCKED", "BLOCK_PAYLOAD_INVALID", capability_id=capability_id, resolution=resolution, backend_executed=False)

    raw = executor.execute(payload, plan)
    if not isinstance(raw, Mapping):
        return _result("BLOCKED", "BLOCK_EXECUTOR_RESULT_INVALID", capability_id=capability_id, resolution=resolution, backend_executed=True)
    attestation = raw.get("attestation")
    if not isinstance(attestation, Mapping):
        return _result("BLOCKED", "BLOCK_EXECUTOR_ATTESTATION_MISSING", capability_id=capability_id, resolution=resolution, backend_executed=True)
    if (
        attestation.get("implementation_ref") != plan["implementation_ref"]
        or attestation.get("implementation_sha") != plan["implementation_sha"]
    ):
        return _result(
            "BLOCKED",
            "BLOCK_POST_EXECUTOR_PROVENANCE_MISMATCH",
            capability_id=capability_id,
            resolution=resolution,
            backend_executed=True,
            attestation=dict(attestation),
        )

    if operation_kind == "REGISTERED_DATA_READ":
        if plan.get("authority") != "DETERMINISTIC":
            return _result("BLOCKED", "BLOCK_REGISTERED_READ_NONDETERMINISTIC", capability_id=capability_id, resolution=resolution, backend_executed=True)
        if attestation.get("model_calls", 0) != 0:
            return _result("BLOCKED", "BLOCK_REGISTERED_READ_MODEL_CALL", capability_id=capability_id, resolution=resolution, backend_executed=True)
    if operation_kind == "UNKNOWN_DATA_SOURCE_SCHEMA" and raw.get("schema_receipt") is None:
        return _result("BLOCKED", "BLOCK_SCHEMA_RECEIPT_MISSING", capability_id=capability_id, resolution=resolution, backend_executed=True)
    if operation_kind == "EXECUTION_AUTHORITY_DECISION" and raw.get("authority_decision") is None:
        return _result("BLOCKED", "BLOCK_EXECUTION_AUTHORITY_DECISION_MISSING", capability_id=capability_id, resolution=resolution, backend_executed=True)

    return _result(
        "PASS",
        "PREEXECUTION_FACADE_EXECUTED",
        capability_id=capability_id,
        resolution=resolution,
        backend_executed=True,
        executor_attestation=dict(attestation),
        output={k:v for k,v in raw.items() if k != "attestation"},
    )
