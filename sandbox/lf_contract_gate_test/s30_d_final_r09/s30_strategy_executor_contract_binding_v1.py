from __future__ import annotations

from typing import Any, Mapping

PASS = "PASS"
BLOCKED = "BLOCKED"
EXPECTED_OPERATION = "EJECUCION_ESTRATEGIA_LF"
EXPECTED_MANIFEST = "S30_STRATEGY_EXECUTOR_CONTRACT_BINDING_V1"
REQUIRED_COMPONENTS = {"activation", "family_matrix", "live_canary", "performance_policy"}
ZERO_EFFECT_FLAGS = (
    "business_effect_dispatch_allowed",
    "model_calls_allowed",
    "production_write_allowed",
    "scheduler_activation",
    "orchestrator_activation",
    "production_activation",
    "s26_mutation",
)


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def validate_contract_binding_v1(
    manifest: Mapping[str, Any],
    activation: Mapping[str, Any],
    family_matrix: Mapping[str, Any],
    live_canary: Mapping[str, Any],
    performance_policy: Mapping[str, Any],
) -> dict:
    if manifest.get("contract_version") != EXPECTED_MANIFEST:
        return _block("BLOCK_BINDING_MANIFEST_VERSION")
    if manifest.get("operation_code") != EXPECTED_OPERATION:
        return _block("BLOCK_BINDING_OPERATION")
    if manifest.get("authority_mode") != "SINGLE_BINDING_MANIFEST_NO_COMPONENT_VERSION_DUPLICATION":
        return _block("BLOCK_BINDING_AUTHORITY_MODE")

    components = manifest.get("components") or {}
    if set(components) != REQUIRED_COMPONENTS:
        return _block(
            "BLOCK_BINDING_COMPONENT_COVERAGE",
            missing=sorted(REQUIRED_COMPONENTS - set(components)),
            extra=sorted(set(components) - REQUIRED_COMPONENTS),
        )

    actuals = {
        "activation": activation,
        "family_matrix": family_matrix,
        "live_canary": live_canary,
        "performance_policy": performance_policy,
    }
    observed_versions: dict[str, str] = {}
    for component_name, actual in actuals.items():
        spec = components.get(component_name) or {}
        version_field = spec.get("version_field")
        expected_version = spec.get("expected_version")
        source_ref = spec.get("source_ref")
        if not version_field or not expected_version or not source_ref:
            return _block("BLOCK_BINDING_COMPONENT_SHAPE", component=component_name)
        observed = actual.get(version_field)
        observed_versions[component_name] = observed
        if observed != expected_version:
            return _block(
                "BLOCK_STALE_BINDING",
                component=component_name,
                expected=expected_version,
                observed=observed,
            )
        if actual.get("operation_code") != EXPECTED_OPERATION:
            return _block("BLOCK_BINDING_COMPONENT_OPERATION", component=component_name)

    binding_field = manifest.get("component_binding_field")
    if binding_field != "contract_binding_manifest":
        return _block("BLOCK_BINDING_FIELD_POLICY")
    for component_name, actual in (("family_matrix", family_matrix), ("live_canary", live_canary)):
        if actual.get(binding_field) != EXPECTED_MANIFEST:
            return _block("BLOCK_BINDING_COMPONENT_MANIFEST_REF", component=component_name)

    forbidden = manifest.get("forbidden_component_version_fields") or {}
    for component_name, actual in (("family_matrix", family_matrix), ("live_canary", live_canary)):
        for field in forbidden.get(component_name) or []:
            if field in actual:
                return _block(
                    "BLOCK_DUPLICATED_VERSION_AUTHORITY",
                    component=component_name,
                    field=field,
                )

    currentness = manifest.get("currentness_policy") or {}
    if currentness.get("resolve_component_versions_from_manifest") is not True:
        return _block("BLOCK_BINDING_CURRENTNESS_POLICY")
    if currentness.get("component_version_mismatch") != "BLOCK_STALE_BINDING":
        return _block("BLOCK_BINDING_MISMATCH_POLICY")
    if currentness.get("direct_version_literal_reintroduced") != "BLOCK_DUPLICATED_VERSION_AUTHORITY":
        return _block("BLOCK_BINDING_DUPLICATION_POLICY")

    safety = manifest.get("safety_ceiling") or {}
    if safety.get("mode") != "CONTROL_STATE_NO_EFFECT":
        return _block("BLOCK_BINDING_SAFETY_MODE")
    if any(safety.get(key) is not False for key in ZERO_EFFECT_FLAGS):
        return _block("BLOCK_BINDING_SAFETY_CEILING")

    if live_canary.get("mode") != "CONTROL_STATE_NO_EFFECT":
        return _block("BLOCK_BINDING_CANARY_MODE")
    if live_canary.get("effect_guard_rows_allowed") is not False:
        return _block("BLOCK_BINDING_EFFECT_GUARD_BOUNDARY")
    if live_canary.get("strategy_snapshot_mutation_allowed") is not False:
        return _block("BLOCK_BINDING_STRATEGY_MUTATION_BOUNDARY")
    if any(live_canary.get(key) is not False for key in ZERO_EFFECT_FLAGS):
        return _block("BLOCK_BINDING_CANARY_ZERO_EFFECT")

    if performance_policy.get("mode") != "CONTROL_STATE_NO_EFFECT":
        return _block("BLOCK_BINDING_PERFORMANCE_MODE")
    if performance_policy.get("runtime_execution_status") != "NOT_EXECUTED_SOURCE_ONLY":
        return _block("BLOCK_BINDING_PERFORMANCE_RUNTIME_CLAIM")
    if any(performance_policy.get(key) is not False for key in (
        "business_effect_dispatch_allowed", "model_calls_allowed", "production_write_allowed"
    )):
        return _block("BLOCK_BINDING_PERFORMANCE_ZERO_EFFECT")

    return {
        "status": PASS,
        "code": "PASS_STRATEGY_EXECUTOR_CONTRACT_BINDING_V1",
        "manifest": EXPECTED_MANIFEST,
        "operation_code": EXPECTED_OPERATION,
        "observed_versions": observed_versions,
        "duplicated_version_authority": False,
        "runtime_execution_claimed": False,
    }
