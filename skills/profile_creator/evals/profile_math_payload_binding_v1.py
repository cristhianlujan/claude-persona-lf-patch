"""Read-only typed argument adapter for the five shadow mathematical methods.

Builds data-only call arguments from the existing registry. Does not import
functions, invoke methods, or grant any kind of execution permission.
"""
from __future__ import annotations
from typing import Any


def prepare_math_arguments(method_id: str, payload: dict[str, Any],
                           registry: dict[str, Any]) -> dict[str, Any]:
    def reject(reason: str) -> dict[str, Any]:
        return {"status": "BLOCK", "reason": reason,
                "execution_authorized": False, "cutover_eligible": False}

    if not isinstance(method_id, str) or not isinstance(payload, dict) or not isinstance(registry, dict):
        return reject("INVALID_INPUT")
    methods = registry.get("methods")
    if not isinstance(methods, list):
        return reject("METHOD_REGISTRY_INVALID")
    matches = [m for m in methods if isinstance(m, dict) and m.get("method_id") == method_id]
    if len(matches) != 1:
        return reject("METHOD_ID_NOT_UNIQUE")
    method = matches[0]
    source = method.get("candidate_implementation")
    if (method.get("method_family") != "MATHEMATICAL"
            or method.get("selection_lane") != "SHADOW_ONLY"
            or method.get("availability_state") != "EXPERIMENTAL_NOT_ADMITTED"
            or method.get("auto_select") is not False
            or method.get("execution_permission") is not False
            or not isinstance(source, dict)
            or source.get("invocation_authorized") is not False
            or source.get("production_binding") is not False):
        return reject("METHOD_NOT_SHADOW_SOURCE_ONLY")
    contract = source.get("argument_contract")
    if not isinstance(contract, dict):
        return reject("ARGUMENT_CONTRACT_MISSING")
    positional = contract.get("positional", [])
    optional = contract.get("optional", {})
    external = contract.get("externally_bound", [])
    if (not isinstance(positional, list) or not positional
            or any(not isinstance(k, str) or not k for k in positional)
            or len(set(positional)) != len(positional)
            or not isinstance(optional, dict)
            or any(not isinstance(k, str) or not k for k in optional)
            or not isinstance(external, list)
            or any(not isinstance(k, str) or not k for k in external)
            or len(set(external)) != len(external)):
        return reject("ARGUMENT_CONTRACT_INVALID")
    if set(positional) & (set(optional) | set(external)) or set(optional) & set(external):
        return reject("ARGUMENT_CONTRACT_OVERLAP")
    if any(k not in payload for k in positional):
        return reject("REQUIRED_ARGUMENT_MISSING")
    if any(k not in (set(positional) | set(optional)) for k in payload):
        return reject("UNEXPECTED_ARGUMENT")
    return {
        "status": "READY_ARGUMENTS_ONLY",
        "method_id": method_id,
        "source_path": source.get("source_path"),
        "exported_function": source.get("exported_function"),
        "args": [payload[k] for k in positional],
        "kwargs": {k: payload[k] if k in payload else val for k, val in optional.items()},
        "externally_bound": external,
        "handler_invoked": False,
        "execution_authorized": False,
        "cutover_eligible": False,
    }
