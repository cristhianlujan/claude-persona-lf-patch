"""Consume an externally resolved execution contract; never author authority."""
from __future__ import annotations

from dataclasses import dataclass
import json
import re
from typing import Any

from .hashing import canonical_json_sha256

HEX64 = re.compile(r"[0-9a-f]{64}")


class ExecutionBindingError(RuntimeError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


@dataclass(frozen=True)
class ResolvedExecutionBinding:
    # Trusted provider supplies the expected contract digest independently of
    # the payload. Provider admission/currentness remain external obligations.
    execution_contract: dict[str, Any]
    expected_contract_sha256: str
    request_binding_sha256: str
    source_ref: str


def consume_execution_binding(provider, descriptor, *, allow_test_bindings=False):
    if provider is None:
        raise ExecutionBindingError("RUNTIME_EXECUTION_BINDING_REQUIRED")
    if (type(allow_test_bindings) is not bool
            or type(getattr(provider, "is_test_double", None)) is not bool
            or (getattr(provider, "is_test_double", None) is not False and not allow_test_bindings)):
        raise ExecutionBindingError("RUNTIME_TEST_EXECUTION_BINDING_FORBIDDEN")
    try:
        # No original task, result, mutable receipt or store is handed to it.
        request = json.loads(json.dumps(descriptor, allow_nan=False))
        resolved = provider.resolve(request)
    except Exception as exc:
        raise ExecutionBindingError("RUNTIME_EXECUTION_BINDING_RESOLUTION_FAILED") from exc
    if not isinstance(resolved, ResolvedExecutionBinding):
        raise ExecutionBindingError("RUNTIME_EXECUTION_BINDING_INVALID")
    try:
        contract = json.loads(json.dumps(resolved.execution_contract, allow_nan=False))
    except (TypeError, ValueError) as exc:
        raise ExecutionBindingError("RUNTIME_EXECUTION_CONTRACT_INVALID") from exc
    if (not isinstance(contract, dict)
            or not isinstance(resolved.source_ref, str) or not 0 < len(resolved.source_ref.strip()) <= 1000
            or not isinstance(resolved.expected_contract_sha256, str)
            or HEX64.fullmatch(resolved.expected_contract_sha256) is None):
        raise ExecutionBindingError("RUNTIME_EXECUTION_BINDING_INVALID")
    digest = canonical_json_sha256({k: v for k, v in contract.items() if k != "contract_sha256"})
    if digest != resolved.expected_contract_sha256 or contract.get("contract_sha256") != digest:
        raise ExecutionBindingError("RUNTIME_EXECUTION_CONTRACT_DIGEST_MISMATCH")
    if resolved.request_binding_sha256 != canonical_json_sha256(descriptor):
        raise ExecutionBindingError("RUNTIME_EXECUTION_REQUEST_BINDING_MISMATCH")
    if (contract.get("run_id") != descriptor["execution_id"]
            or contract.get("profile_code") != descriptor["profile_code"]
            or contract.get("context_fingerprint") != descriptor["context_fingerprint"]):
        raise ExecutionBindingError("RUNTIME_EXECUTION_CONTRACT_CONTEXT_MISMATCH")
    if contract.get("executor_mode") != "REMOTE_API":
        raise ExecutionBindingError("RUNTIME_EXECUTION_CONTRACT_MODE_MISMATCH")
    evidence = {"schema": "lf-runtime-execution-binding-consumption/v1",
                "source_ref": resolved.source_ref,
                "execution_contract_sha256": digest,
                "request_binding_sha256": resolved.request_binding_sha256,
                "test_binding": provider.is_test_double,
                "downstream_authorized": False}
    return contract, evidence
