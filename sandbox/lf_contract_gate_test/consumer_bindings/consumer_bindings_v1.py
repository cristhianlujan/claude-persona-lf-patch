from __future__ import annotations

import hashlib
import json
import re
import uuid
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "lf-consumer-bindings/v1"
EXPECTED_TARGET = "CONSUMERS_RESOLVE_SAME_CANONICAL_CAPABILITY_AUTHORITY_AND_CANNOT_BYPASS_BINDING"
CANONICAL_REGISTRY = "public.lf_capability_registry"
CANONICAL_CURRENT = "public.lf_capability_current"
CANONICAL_RELATIONS = "public.lf_activo_relaciones"
CANONICAL_BIND_ENTRYPOINT = "public.fn_lf_capability_bind_from_orchestrator_v1"
OWNER_RUNNER_CARRIER_AUTHORITY = "OWNER_RUNNER_CARRIER_AUTHORITY_V1"
ENTRY_GUARD = "ORCHESTRATOR_EXECUTION_GUARD_V1"
ARTIFACT_POLICY = "PASE_POST_PASE_ARTIFACT_TRANSPORT_NO_ZIP_V1"
RESOLUTION_MODE = "CANONICAL_CAPABILITY_AUTHORITY_ONLY"
READY_BIND_DECISIONS = {"BOUND_CURRENT", "READY_CURRENT", "REBOUND_CURRENT", "PIN_BOUND_VERSION"}
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class ConsumerBindingError(ValueError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise ConsumerBindingError(code)


def validate_contract(contract: dict[str, Any]) -> dict[str, Any]:
    _require(contract.get("schema_version") == SCHEMA_VERSION, "BLOCK_CONSUMER_BINDINGS_SCHEMA")
    _require(contract.get("expected_target") == EXPECTED_TARGET, "BLOCK_CONSUMER_BINDINGS_TARGET")

    authority = contract.get("canonical_authority") or {}
    _require(authority.get("registry") == CANONICAL_REGISTRY, "BLOCK_NONCANONICAL_CAPABILITY_REGISTRY")
    _require(authority.get("current") == CANONICAL_CURRENT, "BLOCK_NONCANONICAL_CAPABILITY_CURRENT")
    _require(authority.get("relations") == CANONICAL_RELATIONS, "BLOCK_NONCANONICAL_RELATIONS")
    _require(authority.get("owner_runner_carrier") == OWNER_RUNNER_CARRIER_AUTHORITY, "BLOCK_OWNER_AUTHORITY_DRIFT")
    _require(authority.get("entry_guard") == ENTRY_GUARD, "BLOCK_ENTRY_GUARD_DRIFT")
    _require(authority.get("binding_entrypoint") == CANONICAL_BIND_ENTRYPOINT, "BLOCK_BIND_ENTRYPOINT_DRIFT")

    invariants = contract.get("invariants") or {}
    _require(invariants.get("resolution_mode") == RESOLUTION_MODE, "BLOCK_BINDING_RESOLUTION_MODE")
    _require(invariants.get("parallel_binding_registry") is False, "BLOCK_PARALLEL_BINDING_REGISTRY")
    _require(invariants.get("owner_recalculation") is False, "BLOCK_OWNER_RECALCULATION")
    _require(invariants.get("binding_bypass_allowed") is False, "BLOCK_BINDING_BYPASS")
    _require(invariants.get("applicability_rediscovery") is False, "BLOCK_APPLICABILITY_REDISCOVERY")
    _require(invariants.get("cutover_executed") is False, "BLOCK_PREMATURE_CUTOVER")
    _require(invariants.get("runtime_activated") is False, "BLOCK_RUNTIME_ACTIVATION")
    _require(invariants.get("production_activated") is False, "BLOCK_PRODUCTION_ACTIVATION")
    _require(invariants.get("artifact_transport_policy") == ARTIFACT_POLICY, "BLOCK_ARTIFACT_POLICY_DRIFT")

    consumers = contract.get("consumers")
    _require(isinstance(consumers, list) and consumers, "BLOCK_MISSING_CONSUMERS")
    codes = [row.get("consumer_code") for row in consumers]
    _require(len(codes) == len(set(codes)), "BLOCK_DUPLICATE_CONSUMER")
    _require(set(codes) == {"POST_PASE_ORCHESTRATOR_V1", "PASE_ORCHESTRATOR_V1", "ASSURANCE_EVALUATOR"}, "BLOCK_CONSUMER_SET_DRIFT")

    post = next(row for row in consumers if row["consumer_code"] == "POST_PASE_ORCHESTRATOR_V1")
    _require(post.get("binding_mode") == "SOURCE_READY_NO_CUTOVER", "BLOCK_POST_PASE_BINDING_MODE")
    _require(post.get("required_entrypoint") == CANONICAL_BIND_ENTRYPOINT, "BLOCK_POST_PASE_BIND_ENTRYPOINT")
    _require(post.get("guard_code") == ENTRY_GUARD, "BLOCK_POST_PASE_GUARD")
    _require(post.get("owner_resolution") == "DELEGATE_TO_OWNER_RUNNER_CARRIER_AUTHORITY", "BLOCK_POST_PASE_OWNER_RESOLUTION")
    _require(post.get("legacy_execution_path_retained") is True, "BLOCK_PREMATURE_LEGACY_RETIREMENT")
    _require(post.get("binding_bypass_allowed") is False, "BLOCK_POST_PASE_BINDING_BYPASS")
    required = post.get("capabilities")
    _require(required == [
        "CURRENTNESS_AUTHORITY",
        "GITHUB_RECONCILIATION",
        "AUTHORITY_READBACK",
        "RUNTIME_DEPLOY_VERIFICATION",
        "EVIDENCE_LEDGER",
        "FINAL_EVIDENCE",
        "CLOSURE_GATE",
    ], "BLOCK_POST_PASE_CAPABILITY_SET_DRIFT")

    pase = next(row for row in consumers if row["consumer_code"] == "PASE_ORCHESTRATOR_V1")
    _require(pase.get("reuse_validation") == "FAIL_CLOSED_IF_BINDING_MATERIALIZED_BEFORE_QUALIFIED_CUTOVER", "BLOCK_PASE_REUSE_VALIDATION")
    _require(pase.get("parallel_registry") is False, "BLOCK_PASE_PARALLEL_REGISTRY")

    assurance = next(row for row in consumers if row["consumer_code"] == "ASSURANCE_EVALUATOR")
    _require(assurance.get("reuse_validation") == "CANONICAL_BIND_ENTRYPOINT_ALREADY_DECLARED", "BLOCK_ASSURANCE_REUSE_VALIDATION")
    _require(assurance.get("required_entrypoint") == CANONICAL_BIND_ENTRYPOINT, "BLOCK_ASSURANCE_BIND_ENTRYPOINT")

    return contract


def validate_reuse_sources(contract: dict[str, Any], repo_root: Path) -> dict[str, str]:
    validate_contract(contract)
    consumers = {row["consumer_code"]: row for row in contract["consumers"]}
    pase_path = repo_root / consumers["PASE_ORCHESTRATOR_V1"]["source_path"]
    assurance_path = repo_root / consumers["ASSURANCE_EVALUATOR"]["source_path"]
    _require(pase_path.is_file(), "BLOCK_PASE_REUSE_SOURCE_MISSING")
    _require(assurance_path.is_file(), "BLOCK_ASSURANCE_REUSE_SOURCE_MISSING")
    pase = pase_path.read_text(encoding="utf-8")
    assurance = assurance_path.read_text(encoding="utf-8")
    _require("binding_materialized=true" in pase, "BLOCK_PASE_BINDING_FAIL_CLOSED_MARKER_MISSING")
    _require("binding-aware cutover" in pase, "BLOCK_PASE_QUALIFIED_CUTOVER_MARKER_MISSING")
    _require(CANONICAL_BIND_ENTRYPOINT in assurance, "BLOCK_ASSURANCE_CANONICAL_BIND_ENTRYPOINT_MISSING")
    _require(ENTRY_GUARD in assurance, "BLOCK_ASSURANCE_ENTRY_GUARD_MISSING")
    return {
        "PASE_ORCHESTRATOR_V1": "REUSE_PATH_VALIDATED_FAIL_CLOSED_NO_CUTOVER",
        "ASSURANCE_EVALUATOR": "REUSE_PATH_VALIDATED_CANONICAL_BIND_ENTRYPOINT",
    }


def build_bind_call(
    *,
    consumer_execution_id: str,
    capability_code: str,
    expected_manifest_sha256: str,
    plan_digest: str,
    dispatch_receipt_id: str,
    actor_execution_id: str,
) -> dict[str, Any]:
    _require(bool(consumer_execution_id.strip()), "BLOCK_MISSING_CONSUMER_EXECUTION_ID")
    _require(bool(capability_code.strip()), "BLOCK_MISSING_CAPABILITY_CODE")
    _require(bool(actor_execution_id.strip()), "BLOCK_MISSING_ACTOR_EXECUTION_ID")
    _require(bool(HEX64.fullmatch(expected_manifest_sha256)), "BLOCK_INVALID_EXPECTED_MANIFEST_SHA256")
    _require(bool(HEX64.fullmatch(plan_digest)), "BLOCK_INVALID_PLAN_DIGEST")
    try:
        receipt = str(uuid.UUID(dispatch_receipt_id))
    except (ValueError, AttributeError) as exc:
        raise ConsumerBindingError("BLOCK_INVALID_DISPATCH_RECEIPT_ID") from exc
    return {
        "entrypoint": CANONICAL_BIND_ENTRYPOINT,
        "args": {
            "p_execution_id": consumer_execution_id,
            "p_capability_code": capability_code,
            "p_expected_manifest_sha256": expected_manifest_sha256,
            "p_plan_digest": plan_digest,
            "p_dispatch_receipt_id": receipt,
            "p_actor_execution_id": actor_execution_id,
        },
        "owner_resolution": "DELEGATE_TO_OWNER_RUNNER_CARRIER_AUTHORITY",
        "owner_authority": OWNER_RUNNER_CARRIER_AUTHORITY,
        "entry_guard": ENTRY_GUARD,
    }


def validate_bind_readback(readback: dict[str, Any]) -> dict[str, Any]:
    _require(isinstance(readback, dict), "BLOCK_INVALID_BIND_READBACK")
    if readback.get("ready") is not True:
        decision = readback.get("decision")
        if decision is None and isinstance(readback.get("binding"), dict):
            decision = readback["binding"].get("decision")
        _require(isinstance(decision, str) and decision.startswith(("BLOCK_", "MIGRATION_", "LEGACY_")), "BLOCK_UNTYPED_BIND_FAILURE")
        return {"ready": False, "decision": decision}
    entry = readback.get("entry_guard") or {}
    binding = readback.get("binding") or {}
    _require(entry.get("decision") == "ORCHESTRATOR_ENTRY_ACCEPTED", "BLOCK_BIND_READBACK_ENTRY_GUARD")
    _require(entry.get("guard_code") == ENTRY_GUARD, "BLOCK_BIND_READBACK_GUARD_CODE")
    _require(binding.get("decision") in READY_BIND_DECISIONS, "BLOCK_BIND_READBACK_DECISION")
    manifest = binding.get("manifest_sha256")
    if manifest is not None:
        _require(bool(HEX64.fullmatch(manifest)), "BLOCK_BIND_READBACK_MANIFEST_DIGEST")
    return {"ready": True, "decision": binding.get("decision"), "guard": entry.get("decision")}
