from __future__ import annotations

from typing import Any, Mapping

from s30_strategy_executor_contract_binding_v1 import PASS, validate_contract_binding_v1

BLOCKED = "BLOCKED"
EXPECTED_OBJECTIVES = {f"F{i:02d}" for i in range(1, 15)}
REQUIRED_DIMENSIONS = {"FUNCTIONALITY", "QUALITY", "DEPTH", "PERFORMANCE"}
REQUIRED_PERFORMANCE_OBJECTIVES = {
    "F02": {"P01"}, "F03": {"P02"}, "F06": {"P03"},
    "F07": {"P04"}, "F11": {"P05"}, "F14": {"P06"},
}
REQUIRED_PERFORMANCE_METRICS = {f"P{i:02d}" for i in range(1, 10)}
REQUIRED_DIMENSION_CHECKS = {"Q01", "D01", "P01", "P02"}
REQUIRED_RUNTIME_NEGATIVE_CHECKS = {"L10", "L11", "L12", "L13", "L14"}
ZERO_EFFECT_FLAGS = (
    "business_effect_dispatch_allowed", "effect_guard_rows_allowed", "model_calls_allowed",
    "production_write_allowed", "strategy_snapshot_mutation_allowed", "scheduler_activation",
    "orchestrator_activation", "production_activation", "s26_mutation",
)


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def validate_family_objective_matrix_v4(
    manifest: Mapping[str, Any],
    matrix: Mapping[str, Any],
    activation: Mapping[str, Any],
    live_canary: Mapping[str, Any],
    performance_policy: Mapping[str, Any],
) -> dict:
    binding = validate_contract_binding_v1(
        manifest, activation, matrix, live_canary, performance_policy
    )
    if binding.get("status") != PASS:
        return _block("BLOCK_V4_CONTRACT_BINDING", binding_code=binding.get("code"))

    if matrix.get("matrix_version") != "S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V4":
        return _block("BLOCK_V4_MATRIX_VERSION")
    if matrix.get("supersedes") != "S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V3":
        return _block("BLOCK_V4_SUPERSEDES")
    if matrix.get("base_matrix_version") != "S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V3":
        return _block("BLOCK_V4_BASE_MATRIX")
    if matrix.get("matrix_status") != "PRECANARY_MULTIDIMENSIONAL_ASSURANCE_READY_RUNTIME_EVIDENCE_PENDING":
        return _block("BLOCK_V4_MATRIX_STATE")
    if any(matrix.get(k) is not False for k in (
        "runtime_execution_claimed", "production_activation_claimed", "authorization_claimed"
    )):
        return _block("BLOCK_V4_UNSUPPORTED_CLAIM")
    if matrix.get("claim_ceiling") != "SOURCE_AND_PRECANARY_ASSURANCE_ONLY":
        return _block("BLOCK_V4_CLAIM_CEILING")

    dimensions = set(matrix.get("required_dimensions") or [])
    if dimensions != REQUIRED_DIMENSIONS:
        return _block("BLOCK_V4_DIMENSION_POLICY")
    gates = matrix.get("dimension_gates") or {}
    if set(gates) != REQUIRED_DIMENSIONS:
        return _block("BLOCK_V4_DIMENSION_GATE_COVERAGE")
    for dimension in REQUIRED_DIMENSIONS:
        gate = gates.get(dimension) or {}
        if not gate.get("acceptance") or not gate.get("evidence_rule"):
            return _block("BLOCK_V4_DIMENSION_GATE_SHAPE", dimension=dimension)

    profiles = matrix.get("objective_dimension_profiles") or []
    profile_ids = [p.get("objective_id") for p in profiles if isinstance(p, Mapping)]
    if len(profile_ids) != len(set(profile_ids)) or set(profile_ids) != EXPECTED_OBJECTIVES:
        return _block("BLOCK_V4_DIMENSION_PROFILE_COVERAGE")
    for profile in profiles:
        oid = profile.get("objective_id")
        dims = profile.get("dimensions") or {}
        if set(dims) != REQUIRED_DIMENSIONS:
            return _block("BLOCK_V4_DIMENSION_SHAPE", objective_id=oid)
        for dimension in ("FUNCTIONALITY", "QUALITY", "DEPTH"):
            if (dims.get(dimension) or {}).get("status") != "REQUIRED":
                return _block("BLOCK_V4_REQUIRED_DIMENSION", objective_id=oid, dimension=dimension)
        perf = dims.get("PERFORMANCE") or {}
        metric_ids = set(perf.get("metric_ids") or [])
        expected = REQUIRED_PERFORMANCE_OBJECTIVES.get(oid)
        if expected is not None:
            if perf.get("status") != "REQUIRED" or metric_ids != expected:
                return _block("BLOCK_V4_PERFORMANCE_OBJECTIVE", objective_id=oid)
        else:
            if perf.get("status") != "OBSERVE_ONLY" or metric_ids:
                return _block("BLOCK_V4_OBSERVE_ONLY_METRIC_BINDING", objective_id=oid)
        if not perf.get("rationale"):
            return _block("BLOCK_V4_PERFORMANCE_RATIONALE", objective_id=oid)

    samples = performance_policy.get("sample_policy") or {}
    if samples.get("warmup_runs_min", 0) < 1 or samples.get("measured_samples_min", 0) < 5:
        return _block("BLOCK_V4_PERFORMANCE_SAMPLE_POLICY")
    if (performance_policy.get("retry_policy") or {}).get("unbounded_retries_allowed") is not False:
        return _block("BLOCK_V4_PERFORMANCE_RETRY_POLICY")
    metrics = performance_policy.get("metrics") or []
    metric_ids = [m.get("id") for m in metrics if isinstance(m, Mapping)]
    if len(metric_ids) != len(set(metric_ids)) or set(metric_ids) != REQUIRED_PERFORMANCE_METRICS:
        return _block("BLOCK_V4_PERFORMANCE_METRIC_COVERAGE")
    for metric in metrics:
        if metric.get("aggregation") not in {"P95", "TOTAL"} or metric.get("unit") not in {"ms", "count"}:
            return _block("BLOCK_V4_PERFORMANCE_METRIC_SHAPE", metric_id=metric.get("id"))
        maximum = metric.get("max")
        if not isinstance(maximum, (int, float)) or maximum < 0 or (metric.get("unit") == "ms" and maximum <= 0):
            return _block("BLOCK_V4_PERFORMANCE_BUDGET", metric_id=metric.get("id"))
    measurement = performance_policy.get("measurement_requirements") or {}
    for key in (
        "capture_raw_samples", "capture_p50_p95_max", "capture_total_wall_clock",
        "capture_retry_count", "capture_timeout_count", "missing_metric_is_failure",
    ):
        if measurement.get(key) is not True:
            return _block("BLOCK_V4_PERFORMANCE_MEASUREMENT", field=key)

    if live_canary.get("runtime_execution_status") != "NOT_EXECUTED_SOURCE_ONLY":
        return _block("BLOCK_V4_RUNTIME_CLAIM")
    if live_canary.get("activation_authority") != "NONE":
        return _block("BLOCK_V4_AUTHORITY_CLAIM")
    if live_canary.get("mode") != "CONTROL_STATE_NO_EFFECT":
        return _block("BLOCK_V4_LIVE_MODE")
    if any(live_canary.get(k) is not False for k in ZERO_EFFECT_FLAGS):
        return _block("BLOCK_V4_ZERO_EFFECT")

    checks = live_canary.get("checks") or []
    check_ids = [c.get("id") for c in checks if isinstance(c, Mapping)]
    if len(check_ids) != 14 or len(check_ids) != len(set(check_ids)):
        return _block("BLOCK_V4_FUNCTIONAL_CHECK_COVERAGE")
    if not REQUIRED_RUNTIME_NEGATIVE_CHECKS.issubset(set(check_ids)):
        return _block("BLOCK_V4_RUNTIME_NEGATIVE_COVERAGE")
    dimension_checks = live_canary.get("dimension_checks") or []
    dimension_check_ids = [c.get("id") for c in dimension_checks if isinstance(c, Mapping)]
    if set(dimension_check_ids) != REQUIRED_DIMENSION_CHECKS or len(dimension_check_ids) != len(set(dimension_check_ids)):
        return _block("BLOCK_V4_DIMENSION_CHECK_COVERAGE")
    if any(not c.get("expected") for c in dimension_checks):
        return _block("BLOCK_V4_DIMENSION_CHECK_SHAPE")

    target = live_canary.get("target_strategy") or {}
    if target.get("selector_kind") != "EXACT_SNAPSHOT_CODE":
        return _block("BLOCK_V4_CANARY_SELECTOR")
    if target.get("snapshot_code") != "LF_OPERATING_CONSTITUTION_POLICY_AUTONOMOUS_OPERATIONS_20260906":
        return _block("BLOCK_V4_CANARY_TARGET")
    if target.get("resolved_snapshot_id") is not None:
        return _block("BLOCK_V4_CANARY_HARDCODED_ID")

    plan = live_canary.get("performance_measurement_plan") or {}
    if plan.get("policy_ref") != "strategy_executor_performance_policy_v1.json":
        return _block("BLOCK_V4_MEASUREMENT_POLICY_REF")
    if plan.get("raw_sample_evidence_required") is not True:
        return _block("BLOCK_V4_MEASUREMENT_RAW_EVIDENCE")
    if set(plan.get("summary_statistics_required") or []) != {"P50", "P95", "MAX", "TOTAL"}:
        return _block("BLOCK_V4_MEASUREMENT_SUMMARY_POLICY")
    if plan.get("missing_or_partial_measurement") != "FAIL_CLOSED":
        return _block("BLOCK_V4_MEASUREMENT_FAIL_CLOSED")

    return {
        "status": PASS,
        "code": "PASS_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V4",
        "binding_manifest": manifest.get("contract_version"),
        "objective_count": len(profiles),
        "dimension_count": len(REQUIRED_DIMENSIONS),
        "functional_live_check_count": len(checks),
        "dimension_live_check_count": len(dimension_checks),
        "performance_metric_count": len(metrics),
        "runtime_execution_claimed": False,
    }
