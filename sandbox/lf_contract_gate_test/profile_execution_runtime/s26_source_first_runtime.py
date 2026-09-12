#!/usr/bin/env python3
"""S26 source-first / correct-by-construction execution boundary.

This module is intentionally local to S26. It wraps the existing contract-bound
profile runtime without changing historical contracts or the generic runner.
"""

from __future__ import annotations

from copy import deepcopy
from typing import Any

from contract_bound_profile_runtime import execute_contract_bound_profile_runtime
from profile_execution_contract import canonical_json_sha256, validate_source_fidelity_contract
from profile_runtime_runner import RuntimeExecutionBlocked

SOURCE_MODEL_SCHEMA = "S26_SOURCE_MODEL_V1"
BUILD_PLAN_SCHEMA = "S26_GOVERNED_BUILD_PLAN_V1"
SOURCE_FIRST_MODE = "S26_SOURCE_FIRST_V1"

IMMUTABLE_SEMANTIC = "IMMUTABLE_SEMANTIC"
OBSERVED_SAMPLE_ONLY = "OBSERVED_SAMPLE_ONLY"
RUNTIME_BINDING = "RUNTIME_BINDING"
PRESENTATION_ONLY = "PRESENTATION_ONLY"


def _nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_sha256(value: Any) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True


def _seal(payload: dict[str, Any], field: str) -> dict[str, Any]:
    sealed = deepcopy(payload)
    sealed[field] = canonical_json_sha256(sealed)
    return sealed


def _expected_protected_semantics(source_fidelity_contract: dict[str, Any]) -> list[dict[str, str]]:
    items = [
        {
            "entity_id": item["entity_id"],
            "source_entity_sha256": canonical_json_sha256(item),
            "classification": IMMUTABLE_SEMANTIC,
        }
        for item in source_fidelity_contract["immutable_entities"]
    ]
    return sorted(items, key=lambda item: item["entity_id"])


def build_source_model(
    *,
    run_id: str,
    source_fidelity_contract: dict[str, Any],
    observed_samples: list[dict[str, str]] | None = None,
    runtime_bindings: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    errors = validate_source_fidelity_contract(source_fidelity_contract)
    if errors:
        raise ValueError("SOURCE_FIDELITY_CONTRACT_INVALID:" + ",".join(errors))
    if not _nonempty_string(run_id):
        raise ValueError("SOURCE_MODEL_RUN_ID_INVALID")

    normalized_samples: list[dict[str, str]] = []
    for item in observed_samples or []:
        if not isinstance(item, dict):
            raise ValueError("OBSERVED_SAMPLE_INVALID")
        sample_id = item.get("sample_id")
        source_ref = item.get("source_ref")
        value_sha256 = item.get("value_sha256")
        if not _nonempty_string(sample_id) or not _nonempty_string(source_ref) or not _is_sha256(value_sha256):
            raise ValueError("OBSERVED_SAMPLE_INVALID")
        normalized_samples.append(
            {
                "sample_id": sample_id,
                "source_ref": source_ref,
                "value_sha256": value_sha256,
                "classification": OBSERVED_SAMPLE_ONLY,
            }
        )
    if len({item["sample_id"] for item in normalized_samples}) != len(normalized_samples):
        raise ValueError("OBSERVED_SAMPLE_ID_DUPLICATE")
    normalized_samples.sort(key=lambda item: item["sample_id"])

    normalized_bindings: list[dict[str, str]] = []
    for item in runtime_bindings or []:
        if not isinstance(item, dict):
            raise ValueError("RUNTIME_BINDING_INVALID")
        binding_id = item.get("binding_id")
        target = item.get("target")
        authority_ref = item.get("authority_ref")
        if not all(_nonempty_string(value) for value in (binding_id, target, authority_ref)):
            raise ValueError("RUNTIME_BINDING_INVALID")
        normalized_bindings.append(
            {
                "binding_id": binding_id,
                "target": target,
                "authority_ref": authority_ref,
                "classification": RUNTIME_BINDING,
            }
        )
    if len({item["binding_id"] for item in normalized_bindings}) != len(normalized_bindings):
        raise ValueError("RUNTIME_BINDING_ID_DUPLICATE")
    if len({item["target"] for item in normalized_bindings}) != len(normalized_bindings):
        raise ValueError("RUNTIME_BINDING_TARGET_DUPLICATE")
    normalized_bindings.sort(key=lambda item: item["binding_id"])

    model = {
        "schema": SOURCE_MODEL_SCHEMA,
        "mode": SOURCE_FIRST_MODE,
        "run_id": run_id,
        "source_fidelity_contract_sha256": source_fidelity_contract["contract_sha256"],
        "source_ref": source_fidelity_contract["source_ref"],
        "source_sha256": source_fidelity_contract["source_sha256"],
        "authority_kind": source_fidelity_contract["authority_kind"],
        "protected_semantics": _expected_protected_semantics(source_fidelity_contract),
        "observed_samples": normalized_samples,
        "runtime_bindings": normalized_bindings,
        "presentation_dimensions": [
            {"dimension": item, "classification": PRESENTATION_ONLY}
            for item in sorted(source_fidelity_contract["mutable_dimensions"])
        ],
    }
    return _seal(model, "source_model_sha256")


def validate_source_model(
    source_model: Any,
    *,
    run_id: str,
    source_fidelity_contract: dict[str, Any],
) -> list[str]:
    errors = validate_source_fidelity_contract(source_fidelity_contract)
    if errors:
        return ["SOURCE_FIDELITY_CONTRACT_INVALID"] + errors
    if not isinstance(source_model, dict):
        return ["SOURCE_MODEL_NOT_OBJECT"]

    if source_model.get("schema") != SOURCE_MODEL_SCHEMA:
        errors.append("SOURCE_MODEL_SCHEMA_INVALID")
    if source_model.get("mode") != SOURCE_FIRST_MODE:
        errors.append("SOURCE_MODEL_MODE_INVALID")
    if source_model.get("run_id") != run_id:
        errors.append("SOURCE_MODEL_RUN_ID_MISMATCH")

    expected_header = {
        "source_fidelity_contract_sha256": source_fidelity_contract["contract_sha256"],
        "source_ref": source_fidelity_contract["source_ref"],
        "source_sha256": source_fidelity_contract["source_sha256"],
        "authority_kind": source_fidelity_contract["authority_kind"],
    }
    for key, expected in expected_header.items():
        if source_model.get(key) != expected:
            errors.append(f"SOURCE_MODEL_{key.upper()}_MISMATCH")

    if source_model.get("protected_semantics") != _expected_protected_semantics(source_fidelity_contract):
        errors.append("SOURCE_MODEL_PROTECTED_SEMANTICS_INCOMPLETE_OR_MUTATED")

    samples = source_model.get("observed_samples")
    if not isinstance(samples, list):
        errors.append("SOURCE_MODEL_OBSERVED_SAMPLES_NOT_ARRAY")
    else:
        allowed = {"sample_id", "source_ref", "value_sha256", "classification"}
        seen: set[str] = set()
        for index, item in enumerate(samples):
            if not isinstance(item, dict):
                errors.append(f"SOURCE_MODEL_OBSERVED_SAMPLE_{index}_INVALID")
                continue
            if set(item) != allowed:
                errors.append(f"SOURCE_MODEL_OBSERVED_SAMPLE_{index}_EXTRA_OR_MISSING_FIELDS")
            if item.get("classification") != OBSERVED_SAMPLE_ONLY:
                errors.append(f"SOURCE_MODEL_OBSERVED_SAMPLE_{index}_CLASSIFICATION_INVALID")
            if not _nonempty_string(item.get("sample_id")) or item.get("sample_id") in seen:
                errors.append(f"SOURCE_MODEL_OBSERVED_SAMPLE_{index}_ID_INVALID")
            else:
                seen.add(item["sample_id"])
            if not _nonempty_string(item.get("source_ref")) or not _is_sha256(item.get("value_sha256")):
                errors.append(f"SOURCE_MODEL_OBSERVED_SAMPLE_{index}_BINDING_INVALID")

    bindings = source_model.get("runtime_bindings")
    if not isinstance(bindings, list):
        errors.append("SOURCE_MODEL_RUNTIME_BINDINGS_NOT_ARRAY")
    else:
        allowed = {"binding_id", "target", "authority_ref", "classification"}
        seen_ids: set[str] = set()
        seen_targets: set[str] = set()
        for index, item in enumerate(bindings):
            if not isinstance(item, dict):
                errors.append(f"SOURCE_MODEL_RUNTIME_BINDING_{index}_INVALID")
                continue
            if set(item) != allowed:
                errors.append(f"SOURCE_MODEL_RUNTIME_BINDING_{index}_EXTRA_OR_MISSING_FIELDS")
            if item.get("classification") != RUNTIME_BINDING:
                errors.append(f"SOURCE_MODEL_RUNTIME_BINDING_{index}_CLASSIFICATION_INVALID")
            binding_id = item.get("binding_id")
            target = item.get("target")
            authority_ref = item.get("authority_ref")
            if not all(_nonempty_string(value) for value in (binding_id, target, authority_ref)):
                errors.append(f"SOURCE_MODEL_RUNTIME_BINDING_{index}_INVALID")
            if binding_id in seen_ids:
                errors.append("SOURCE_MODEL_RUNTIME_BINDING_ID_DUPLICATE")
            if target in seen_targets:
                errors.append("SOURCE_MODEL_RUNTIME_BINDING_TARGET_DUPLICATE")
            if _nonempty_string(binding_id):
                seen_ids.add(binding_id)
            if _nonempty_string(target):
                seen_targets.add(target)

    expected_dimensions = [
        {"dimension": item, "classification": PRESENTATION_ONLY}
        for item in sorted(source_fidelity_contract["mutable_dimensions"])
    ]
    if source_model.get("presentation_dimensions") != expected_dimensions:
        errors.append("SOURCE_MODEL_PRESENTATION_DIMENSIONS_MISMATCH")

    claimed_sha = source_model.get("source_model_sha256")
    if not _is_sha256(claimed_sha):
        errors.append("SOURCE_MODEL_SHA256_INVALID")
    else:
        expected_sha = canonical_json_sha256(
            {key: value for key, value in source_model.items() if key != "source_model_sha256"}
        )
        if claimed_sha != expected_sha:
            errors.append("SOURCE_MODEL_SHA256_MISMATCH")
    return sorted(set(errors))


def build_governed_build_plan(
    *,
    run_id: str,
    source_model: dict[str, Any],
    source_fidelity_contract: dict[str, Any],
) -> dict[str, Any]:
    errors = validate_source_model(
        source_model,
        run_id=run_id,
        source_fidelity_contract=source_fidelity_contract,
    )
    if errors:
        raise ValueError("SOURCE_MODEL_INVALID:" + ",".join(errors))

    plan = {
        "schema": BUILD_PLAN_SCHEMA,
        "mode": SOURCE_FIRST_MODE,
        "run_id": run_id,
        "source_model_sha256": source_model["source_model_sha256"],
        "semantic_bindings": [
            {
                "entity_id": item["entity_id"],
                "source_entity_sha256": item["source_entity_sha256"],
                "binding_mode": "REFERENCE",
            }
            for item in source_model["protected_semantics"]
        ],
        "runtime_bindings": [
            {
                "binding_id": item["binding_id"],
                "target": item["target"],
                "authority_ref": item["authority_ref"],
                "binding_mode": "REFERENCE",
            }
            for item in source_model["runtime_bindings"]
        ],
        "observed_sample_policy": "NON_BINDING_EVIDENCE_ONLY",
        "presentation_dimensions": [item["dimension"] for item in source_model["presentation_dimensions"]],
    }
    return _seal(plan, "governed_build_plan_sha256")


def validate_governed_build_plan(
    governed_build_plan: Any,
    *,
    run_id: str,
    source_model: dict[str, Any],
    source_fidelity_contract: dict[str, Any],
) -> list[str]:
    source_errors = validate_source_model(
        source_model,
        run_id=run_id,
        source_fidelity_contract=source_fidelity_contract,
    )
    if source_errors:
        return ["SOURCE_MODEL_INVALID"] + source_errors
    if not isinstance(governed_build_plan, dict):
        return ["GOVERNED_BUILD_PLAN_NOT_OBJECT"]

    errors: list[str] = []
    if governed_build_plan.get("schema") != BUILD_PLAN_SCHEMA:
        errors.append("GOVERNED_BUILD_PLAN_SCHEMA_INVALID")
    if governed_build_plan.get("mode") != SOURCE_FIRST_MODE:
        errors.append("GOVERNED_BUILD_PLAN_MODE_INVALID")
    if governed_build_plan.get("run_id") != run_id:
        errors.append("GOVERNED_BUILD_PLAN_RUN_ID_MISMATCH")
    if governed_build_plan.get("source_model_sha256") != source_model.get("source_model_sha256"):
        errors.append("GOVERNED_BUILD_PLAN_SOURCE_MODEL_SHA_MISMATCH")

    expected_semantics = [
        {
            "entity_id": item["entity_id"],
            "source_entity_sha256": item["source_entity_sha256"],
            "binding_mode": "REFERENCE",
        }
        for item in source_model["protected_semantics"]
    ]
    if governed_build_plan.get("semantic_bindings") != expected_semantics:
        errors.append("GOVERNED_BUILD_PLAN_SEMANTIC_BINDINGS_INCOMPLETE_OR_MUTATED")

    expected_runtime = [
        {
            "binding_id": item["binding_id"],
            "target": item["target"],
            "authority_ref": item["authority_ref"],
            "binding_mode": "REFERENCE",
        }
        for item in source_model["runtime_bindings"]
    ]
    if governed_build_plan.get("runtime_bindings") != expected_runtime:
        errors.append("GOVERNED_BUILD_PLAN_RUNTIME_BINDINGS_MISMATCH")
    if governed_build_plan.get("observed_sample_policy") != "NON_BINDING_EVIDENCE_ONLY":
        errors.append("GOVERNED_BUILD_PLAN_OBSERVED_SAMPLE_POLICY_INVALID")
    if governed_build_plan.get("presentation_dimensions") != [
        item["dimension"] for item in source_model["presentation_dimensions"]
    ]:
        errors.append("GOVERNED_BUILD_PLAN_PRESENTATION_DIMENSIONS_MISMATCH")

    claimed_sha = governed_build_plan.get("governed_build_plan_sha256")
    if not _is_sha256(claimed_sha):
        errors.append("GOVERNED_BUILD_PLAN_SHA256_INVALID")
    else:
        expected_sha = canonical_json_sha256(
            {
                key: value
                for key, value in governed_build_plan.items()
                if key != "governed_build_plan_sha256"
            }
        )
        if claimed_sha != expected_sha:
            errors.append("GOVERNED_BUILD_PLAN_SHA256_MISMATCH")
    return sorted(set(errors))


class _SourceFirstAdapter:
    def __init__(
        self,
        adapter: Any,
        *,
        source_fidelity_contract: dict[str, Any],
        source_model: dict[str, Any],
        governed_build_plan: dict[str, Any],
    ) -> None:
        self._adapter = adapter
        self.adapter_id = adapter.adapter_id
        self.is_test_double = getattr(adapter, "is_test_double", False)
        self._source_fidelity_contract = deepcopy(source_fidelity_contract)
        self._source_model = deepcopy(source_model)
        self._governed_build_plan = deepcopy(governed_build_plan)

    def execute(self, request: dict[str, Any]) -> dict[str, Any]:
        request["source_first_mode"] = SOURCE_FIRST_MODE
        request["source_fidelity_contract"] = deepcopy(self._source_fidelity_contract)
        request["source_model"] = deepcopy(self._source_model)
        request["governed_build_plan"] = deepcopy(self._governed_build_plan)
        request["source_model_sha256"] = self._source_model["source_model_sha256"]
        request["governed_build_plan_sha256"] = self._governed_build_plan["governed_build_plan_sha256"]
        request["request_sha256"] = canonical_json_sha256(
            {key: value for key, value in request.items() if key != "request_sha256"}
        )
        return self._adapter.execute(request)


def execute_s26_source_first_profile_runtime(
    *,
    execution_contract: dict[str, Any],
    source_fidelity_contract: dict[str, Any],
    source_model: dict[str, Any],
    governed_build_plan: dict[str, Any],
    execution_id: str,
    profile_code: str,
    profile_slug: str,
    profile_sources: list[dict[str, str]],
    input_literal: str,
    adapter: Any,
    attestation_verifier: Any,
    allow_test_doubles: bool = False,
    obligation_manifest: dict[str, Any] | None = None,
    lf_adapter_sources: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    if not isinstance(execution_contract, dict):
        raise RuntimeExecutionBlocked("EXECUTION_CONTRACT_INVALID")
    if execution_contract.get("run_id") != execution_id:
        raise RuntimeExecutionBlocked("EXECUTION_CONTRACT_RUN_ID_MISMATCH")
    if execution_contract.get("source_fidelity_contract_sha256") != source_fidelity_contract.get("contract_sha256"):
        raise RuntimeExecutionBlocked("SOURCE_FIRST_SOURCE_FIDELITY_SHA_MISMATCH")
    if execution_contract.get("source_fidelity_contract_ref") != source_fidelity_contract.get("source_ref"):
        raise RuntimeExecutionBlocked("SOURCE_FIRST_SOURCE_FIDELITY_REF_MISMATCH")

    source_errors = validate_source_model(
        source_model,
        run_id=execution_id,
        source_fidelity_contract=source_fidelity_contract,
    )
    if source_errors:
        raise RuntimeExecutionBlocked("SOURCE_MODEL_INVALID", ",".join(source_errors))

    plan_errors = validate_governed_build_plan(
        governed_build_plan,
        run_id=execution_id,
        source_model=source_model,
        source_fidelity_contract=source_fidelity_contract,
    )
    if plan_errors:
        raise RuntimeExecutionBlocked("GOVERNED_BUILD_PLAN_INVALID", ",".join(plan_errors))

    wrapped_adapter = _SourceFirstAdapter(
        adapter,
        source_fidelity_contract=source_fidelity_contract,
        source_model=source_model,
        governed_build_plan=governed_build_plan,
    )
    result = execute_contract_bound_profile_runtime(
        execution_contract=execution_contract,
        execution_id=execution_id,
        profile_code=profile_code,
        profile_slug=profile_slug,
        profile_sources=profile_sources,
        input_literal=input_literal,
        adapter=wrapped_adapter,
        attestation_verifier=attestation_verifier,
        allow_test_doubles=allow_test_doubles,
        obligation_manifest=obligation_manifest,
        lf_adapter_sources=lf_adapter_sources,
    )
    request = result["request"]
    if request.get("source_first_mode") != SOURCE_FIRST_MODE:
        raise RuntimeExecutionBlocked("SOURCE_FIRST_REQUEST_BINDING_MISSING")
    if request.get("source_model_sha256") != source_model["source_model_sha256"]:
        raise RuntimeExecutionBlocked("SOURCE_FIRST_SOURCE_MODEL_NOT_BOUND")
    if request.get("governed_build_plan_sha256") != governed_build_plan["governed_build_plan_sha256"]:
        raise RuntimeExecutionBlocked("SOURCE_FIRST_BUILD_PLAN_NOT_BOUND")

    result["source_first_mode"] = SOURCE_FIRST_MODE
    result["source_model_sha256"] = source_model["source_model_sha256"]
    result["governed_build_plan_sha256"] = governed_build_plan["governed_build_plan_sha256"]
    return result
