#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import json
import re
from pathlib import Path
from typing import Any, Mapping

REGISTRY_CONTRACT = "INPUT_GOVERNANCE_CAPABILITY_REGISTRY_V1"
EXPECTED_REGISTRY_BLOB_SHA = "2cd314c8cc0323c4bba85c13564f7a28b8680122"
PASS = "PASS"
BLOCKED = "BLOCKED"
DISCOVERY = "DISCOVERY_REQUIRED"
_HEX = re.compile(r"^[0-9a-f]+$")


def git_blob_sha(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def _result(status: str, code: str, **extra: Any) -> dict[str, Any]:
    out = {"resolver_contract": "S33_CAPABILITY_RESOLVER_V1", "status": status, "code": code}
    out.update(extra)
    return out


def _looks_like_raw_resource_name(value: str) -> bool:
    lowered = value.casefold()
    return (
        "." in value
        or lowered.startswith("fn_")
        or lowered.startswith("public.")
        or lowered.startswith("programacion.")
        or lowered.startswith("edge:")
        or lowered.startswith("rpc:")
        or "/" in value
    )


def validate_registry(registry: Mapping[str, Any], *, expected_blob_sha: str | None = None, raw_bytes: bytes | None = None) -> dict[str, Any]:
    errors: list[dict[str, str]] = []

    def require(condition: bool, code: str, path: str, detail: str) -> None:
        if not condition:
            errors.append({"code": code, "path": path, "detail": detail})

    if expected_blob_sha is not None:
        require(raw_bytes is not None, "REGISTRY_BYTES_REQUIRED", "$", "raw registry bytes required for blob binding")
        if raw_bytes is not None:
            require(git_blob_sha(raw_bytes) == expected_blob_sha, "REGISTRY_BLOB_MISMATCH", "$", "registry bytes do not match frozen Git blob")
    require(registry.get("registry_contract") == REGISTRY_CONTRACT, "REGISTRY_CONTRACT_MISMATCH", "registry_contract", "unexpected contract")
    require(registry.get("strategy_id") == "S33", "REGISTRY_STRATEGY_MISMATCH", "strategy_id", "registry must bind S33")
    selection = registry.get("selection_policy") if isinstance(registry.get("selection_policy"), Mapping) else {}
    require(selection.get("consumer_requests") == "CAPABILITY_ID_ONLY", "CAPABILITY_ID_ONLY_REQUIRED", "selection_policy.consumer_requests", "raw implementation selection forbidden")
    require(selection.get("raw_function_name_selection") == "DENY", "RAW_FUNCTION_SELECTION_NOT_DENIED", "selection_policy.raw_function_name_selection", "raw function selection must be denied")
    require(selection.get("multiple_valid") == "BLOCK_CAPABILITY_AMBIGUOUS", "AMBIGUITY_POLICY_MISMATCH", "selection_policy.multiple_valid", "multiple valid implementations must block")
    require(selection.get("stale") == "RERESOLVE", "STALE_POLICY_MISMATCH", "selection_policy.stale", "stale capability must re-resolve")
    require(selection.get("model_selection_of_resource") == "DENY", "MODEL_RESOURCE_SELECTION_NOT_DENIED", "selection_policy.model_selection_of_resource", "model cannot select resources")

    required_fields = registry.get("required_entry_fields")
    require(isinstance(required_fields, list) and bool(required_fields), "REQUIRED_ENTRY_FIELDS_INVALID", "required_entry_fields", "required fields must be declared")
    required = set(required_fields or [])
    entries = registry.get("entries")
    require(isinstance(entries, list) and bool(entries), "REGISTRY_ENTRIES_INVALID", "entries", "non-empty entries required")
    entries = entries if isinstance(entries, list) else []
    for index, entry in enumerate(entries):
        path = f"entries[{index}]"
        if not isinstance(entry, Mapping):
            errors.append({"code":"ENTRY_NOT_OBJECT","path":path,"detail":"entry must be mapping"})
            continue
        missing = sorted(required - set(entry))
        require(not missing, "ENTRY_REQUIRED_FIELD_MISSING", path, f"missing={missing}")
        capability_id = entry.get("capability_id")
        require(isinstance(capability_id, str) and bool(capability_id) and not _looks_like_raw_resource_name(capability_id), "CAPABILITY_ID_INVALID", f"{path}.capability_id", "capability id must be logical, not raw resource")
        require(isinstance(entry.get("allowed_consumers"), list) and bool(entry.get("allowed_consumers")), "ENTRY_CONSUMERS_INVALID", f"{path}.allowed_consumers", "allowed consumers required")
        require(isinstance(entry.get("deprecated"), bool), "ENTRY_DEPRECATED_INVALID", f"{path}.deprecated", "deprecated must be boolean")
        require(isinstance(entry.get("selectable"), bool), "ENTRY_SELECTABLE_INVALID", f"{path}.selectable", "selectable must be boolean")
        sha = entry.get("implementation_sha")
        require(
            sha == "LIVE_FUNCTION_IDENTITY" or (isinstance(sha, str) and len(sha) in {40, 64} and _HEX.fullmatch(sha) is not None),
            "IMPLEMENTATION_SHA_INVALID", f"{path}.implementation_sha", "implementation SHA must be 40/64 hex or LIVE_FUNCTION_IDENTITY"
        )
        budget = entry.get("resource_budget")
        require(isinstance(budget, Mapping) and bool(budget), "RESOURCE_BUDGET_INVALID", f"{path}.resource_budget", "resource budget/measurement policy required")

    safety = registry.get("safety") if isinstance(registry.get("safety"), Mapping) else {}
    for field in ("production_authorized", "runtime_change_authorized", "supabase_mutation_authorized", "foreign_lane_write_authorized"):
        require(safety.get(field) is False, "REGISTRY_SAFETY_BOUNDARY", f"safety.{field}", "isolated registry cannot authorize mutation/promotion")

    return {
        "valid": not errors,
        "blocking_codes": sorted({e["code"] for e in errors}),
        "errors": errors,
        "entry_count": len(entries),
    }


def load_registry(path: str | Path) -> dict[str, Any]:
    raw = Path(path).read_bytes()
    data = json.loads(raw.decode("utf-8"))
    if not isinstance(data, dict):
        raise ValueError("registry root must be object")
    checked = validate_registry(data, expected_blob_sha=EXPECTED_REGISTRY_BLOB_SHA, raw_bytes=raw)
    if not checked["valid"]:
        raise ValueError(f"registry invalid: {checked['blocking_codes']}")
    return data


def _currentness_for(capability_id: str, currentness: Mapping[str, Any] | None) -> Mapping[str, Any]:
    if not isinstance(currentness, Mapping):
        return {}
    value = currentness.get(capability_id)
    return value if isinstance(value, Mapping) else currentness


def _check_current(entry: Mapping[str, Any], currentness: Mapping[str, Any] | None) -> tuple[bool, str]:
    rule = str(entry.get("currentness_rule", ""))
    if "BLOCKED_UNTIL" in rule or "CONTRACT_DRIFT_PRESENT" in rule:
        return False, "CONTRACT_DRIFT"
    observed = _currentness_for(str(entry.get("capability_id")), currentness)
    if observed.get("state") != "CURRENT":
        return False, "STALE"
    expected_sha = entry.get("implementation_sha")
    if expected_sha == "LIVE_FUNCTION_IDENTITY":
        if observed.get("implementation_ref") != entry.get("implementation_ref"):
            return False, "LIVE_IDENTITY_MISMATCH"
    elif observed.get("implementation_sha") != expected_sha:
        return False, "IMPLEMENTATION_SHA_MISMATCH"
    return True, "CURRENT"


def resolve_capability(
    registry: Mapping[str, Any],
    *,
    capability_id: str,
    consumer: str,
    currentness: Mapping[str, Any] | None,
    selector_authority: str = "DETERMINISTIC",
    allow_internal: bool = False,
) -> dict[str, Any]:
    if selector_authority != "DETERMINISTIC":
        return _result(BLOCKED, "BLOCK_MODEL_RESOURCE_SELECTION", capability_id=capability_id)
    if not isinstance(capability_id, str) or not capability_id or _looks_like_raw_resource_name(capability_id):
        return _result(BLOCKED, "BLOCK_RAW_RESOURCE_NAME_SELECTION", capability_id=str(capability_id))
    if not isinstance(consumer, str) or not consumer:
        return _result(BLOCKED, "BLOCK_CONSUMER_REQUIRED", capability_id=capability_id)

    entries = [copy.deepcopy(x) for x in registry.get("entries", []) if isinstance(x, Mapping) and x.get("capability_id") == capability_id]
    if not entries:
        return _result(DISCOVERY, "DISCOVERY_OR_SCHEMA_RESOLVER", capability_id=capability_id, candidate_count=0)

    nondeprecated = [x for x in entries if x.get("deprecated") is False]
    if not nondeprecated:
        return _result(BLOCKED, "BLOCK_CAPABILITY_DEPRECATED", capability_id=capability_id, candidate_count=len(entries))

    selectable = [x for x in nondeprecated if x.get("selectable") is True or allow_internal]
    if not selectable:
        return _result(BLOCKED, "BLOCK_CAPABILITY_NOT_SELECTABLE", capability_id=capability_id, candidate_count=len(nondeprecated))

    consumer_allowed = [x for x in selectable if consumer in x.get("allowed_consumers", [])]
    if not consumer_allowed:
        return _result(BLOCKED, "BLOCK_CONSUMER_NOT_ALLOWED", capability_id=capability_id, candidate_count=len(selectable), consumer=consumer)

    current: list[dict[str, Any]] = []
    stale_reasons: list[str] = []
    for entry in consumer_allowed:
        is_current, reason = _check_current(entry, currentness)
        if is_current:
            current.append(entry)
        else:
            stale_reasons.append(reason)

    if not current:
        if "CONTRACT_DRIFT" in stale_reasons:
            return _result(BLOCKED, "BLOCK_CAPABILITY_CONTRACT_DRIFT", capability_id=capability_id, currentness_reasons=stale_reasons)
        return _result(BLOCKED, "RERESOLVE_CAPABILITY_STALE", capability_id=capability_id, currentness_reasons=stale_reasons)
    if len(current) > 1:
        return _result(BLOCKED, "BLOCK_CAPABILITY_AMBIGUOUS", capability_id=capability_id, candidate_count=len(current), implementations=[x.get("implementation_ref") for x in current])

    selected = current[0]
    return _result(
        PASS,
        "CAPABILITY_RESOLVED",
        capability_id=capability_id,
        consumer=consumer,
        candidate_count=1,
        execution_plan={
            "canonical_facade": selected["canonical_facade"],
            "implementation_ref": selected["implementation_ref"],
            "implementation_version": selected["implementation_version"],
            "implementation_sha": selected["implementation_sha"],
            "execution_type": selected["execution_type"],
            "authority": selected["authority"],
            "read_write_mode": selected["read_write_mode"],
            "side_effect_class": selected["side_effect_class"],
            "resource_budget": selected["resource_budget"],
            "fallback_policy": selected["fallback_policy"],
            "owner_lane": selected["owner_lane"],
        },
    )
