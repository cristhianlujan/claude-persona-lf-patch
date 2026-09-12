from __future__ import annotations

from typing import Any, Mapping

from s30_strategy_executor_family_assurance import PASS, validate_family_objective_matrix

BLOCKED = "BLOCKED"

EXPECTED_OBJECTIVES = {f"F{i:02d}" for i in range(1, 15)}
REQUIRED_DIMENSIONS = {"FUNCTIONALITY", "QUALITY", "DEPTH", "PERFORMANCE"}
REQUIRED_PERFORMANCE_OBJECTIVES = {
    "F02": {"P01"},
    "F03": {"P02"},
    "F06": {"P03"},
    "F07": {"P04"},
    "F11": {"P05"},
    "F14": {"P06"},
}
REQUIRED_PERFORMANCE_METRICS = {f"P{i:02d}" for i in range(1, 10)}
REQUIRED_DIMENSION_CHECKS = {"Q01", "D01", "P01", "P02"}
REQUIRED_RUNTIME_NEGATIVE_CHECKS = {"L10", "L11", "L12", "L13", "L14"}
REQUIRED_ZERO_EFFECT_FLAGS = (
    "business_effect_dispatch_allowed",
    "effect_guard_rows_allowed",
    "model_calls_allowed",
    "production_write_allowed",
    "strategy_snapshot_mutation_allowed",
    "scheduler_activation",
    "orchestrator_activation",
    "production_activation",
    "s26_mutation",
)


def _block(code: str, **extra: Any) -> dict:
    return {"status": BLOCKED, "code": code, **extra}


def validate_family_objective_matrix_v3(
    matrix_v3: Mapping[str, Any],
    matrix_v2: Mapping[str, Any],
    activation: Mapping[str, Any],
    live_canary_v3: Mapping[str, Any],
    live_canary_v2: Mapping[str, Any],
    dry_canary: Mapping[str, Any],
    bootstrap: Mapping[str, Any],
    performance_policy: Mapping[str, Any],
) -> dict:
    base = validate_family_objective_matrix(
        matrix_v2, activation, live_canary_v2, dry_canary, bootstrap
    )
    if base.get("status") != PASS:
        return _block("BLOCK_V3_BASE_MATRIX", base_code=base.get("code"))

    if matrix_v3.get("matrix_version") != "S30_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V3":
        return _block("BLOCK_V3_MATRIX_VERSION")
    if matrix_v3.get("supersedes") != matrix_v2.get("matrix_version"):
        return _block("BLOCK_V3_SUPERSEDES_BINDING")
    if matrix_v3.get("base_matrix_version") != matrix_v2.get("matrix_version"):
        return _block("BLOCK_V3_BASE_MATRIX_BINDING")
    if matrix_v3.get("operation_code") != "EJECUCION_ESTRATEGIA_LF":
        return _block("BLOCK_V3_OPERATION_CODE")
    if matrix_v3.get("activation_contract") != activation.get("contract_version"):
        return _block("BLOCK_V3_ACTIVATION_BINDING")
    if matrix_v3.get("runtime_canary_contract") != live_canary_v3.get("contract_version"):
        return _block("BLOCK_V3_CANARY_BINDING")
    if matrix_v3.get("performance_policy") != performance_policy.get("policy_version"):
        return _block("BLOCK_V3_PERFORMANCE_POLICY_BINDING")
    if matrix_v3.get("matrix_status") != "PRECANARY_MULTIDIMENSIONAL_ASSURANCE_READY_RUNTIME_EVIDENCE_PENDING":
        return _block("BLOCK_V3_MATRIX_STATE")
    if any(matrix_v3.get(k) is not False for k in (
        "runtime_execution_claimed",
        "production_activation_claimed",
        "authorization_claimed",
    )):
        return _block("BLOCK_V3_UNSUPPORTED_CLAIM")
    if matrix_v3.get("claim_ceiling") != "SOURCE_AND_PRECANARY_ASSURANCE_ONLY":
        return _block("BLOCK_V3_CLAIM_CEILING")

    dimensions = set(matrix_v3.get("required_dimensions") or [])
    if dimensions != REQUIRED_DIMENSIONS:
        return _block(
            "BLOCK_V3_DIMENSION_POLICY",
            missing=sorted(REQUIRED_DIMENSIONS - dimensions),
            extra=sorted(dimensions - REQUIRED_DIMENSIONS),
        )

    gates = matrix_v3.get("dimension_gates") or {}
    if set(gates) != REQUIRED_DIMENSIONS:
        return _block("BLOCK_V3_DIMENSION_GATE_COVERAGE")
    for dimension in REQUIRED_DIMENSIONS:
        gate = gates.get(dimension) or {}
        if not gate.get("acceptance") or not gate.get("evidence_rule"):
            return _block("BLOCK_V3_DIMENSION_GATE_SHAPE", dimension=dimension)

    profiles = matrix_v3.get("objective_dimension_profiles") or []
    profile_ids = [p.get("objective_id") for p in profiles if isinstance(p, Mapping)]
    if len(profile_ids) != len(set(profile_ids)) or set(profile_ids) != EXPECTED_OBJECTIVES:
        return _block(
            "BLOCK_V3_DIMENSION_PROFILE_COVERAGE",
            missing=sorted(EXPECTED_OBJECTIVES - set(profile_ids)),
            extra=sorted(set(profile_ids) - EXPECTED_OBJECTIVES),
        )

    for profile in profiles:
        objective_id = profile.get("objective_id")
        dims = profile.get("dimensions") or {}
        if set(dims) != REQUIRED_DIMENSIONS:
            return _block("BLOCK_V3_DIMENSION_SHAPE", objective_id=objective_id)
        for dimension in ("FUNCTIONALITY", "QUALITY", "DEPTH"):
            if (dims.get(dimension) or {}).get("status") != "REQUIRED":
                return _block(
                    "BLOCK_V3_REQUIRED_DIMENSION",
                    objective_id=objective_id,
                    dimension=dimension,
                )
        perf = dims.get("PERFORMANCE") or {}
        if perf.get("status") not in {"REQUIRED", "OBSERVE_ONLY"}:
            return _block("BLOCK_V3_PERFORMANCE_DIMENSION", objective_id=objective_id)
        metric_ids = set(perf.get("metric_ids") or [])
        required_for_objective = REQUIRED_PERFORMANCE_OBJECTIVES.get(objective_id)
        if required_for_objective is not None:
            if perf.get("status") != "REQUIRED" or metric_ids != required_for_objective:
                return _block(
                    "BLOCK_V3_PERFORMANCE_OBJECTIVE",
                    objective_id=objective_id,
                    expected=sorted(required_for_objective),
                    actual=sorted(metric_ids),
                )
        elif perf.get("status") == "OBSERVE_ONLY" and metric_ids:
            return _block("BLOCK_V3_OBSERVE_ONLY_METRIC_BINDING", objective_id=objective_id)
        if not perf.get("rationale"):
            return _block("BLOCK_V3_PERFORMANCE_RATIONALE", objective_id=objective_id)

    if performance_policy.get("policy_version") != "S30_STRATEGY_EXECUTOR_PERFORMANCE_POLICY_V1":
        return _block("BLOCK_V3_PERFORMANCE_POLICY_VERSION")
    if performance_policy.get("operation_code") != "EJECUCION_ESTRATEGIA_LF":
        return _block("BLOCK_V3_PERFORMANCE_OPERATION_CODE")
    if performance_policy.get("mode") != "CONTROL_STATE_NO_EFFECT":
        return _block("BLOCK_V3_PERFORMANCE_MODE")
    if performance_policy.get("runtime_execution_status") != "NOT_EXECUTED_SOURCE_ONLY":
        return _block("BLOCK_V3_RUNTIME_CLAIM")
    if performance_policy.get("budget_scope") != "SANDBOX_CANARY_ONLY_NOT_PRODUCTION_SLO":
        return _block("BLOCK_V3_PERFORMANCE_SCOPE")
    if performance_policy.get("requires_post_canary_baseline_review") is not True:
        return _block("BLOCK_V3_PERFORMANCE_BASELINE_REVIEW")
    if performance_policy.get("timing_source") != "MONOTONIC_CLOCK":
        return _block("BLOCK_V3_PERFORMANCE_CLOCK")

    samples = performance_policy.get("sample_policy") or {}
    if samples.get("warmup_runs_min", 0) < 1 or samples.get("measured_samples_min", 0) < 5:
        return _block("BLOCK_V3_PERFORMANCE_SAMPLE_POLICY")
    retries = performance_policy.get("retry_policy") or {}
    if retries.get("unbounded_retries_allowed") is not False:
        return _block("BLOCK_V3_PERFORMANCE_RETRY_POLICY")

    metrics = performance_policy.get("metrics") or []
    metric_ids = [m.get("id") for m in metrics if isinstance(m, Mapping)]
    if len(metric_ids) != len(set(metric_ids)) or set(metric_ids) != REQUIRED_PERFORMANCE_METRICS:
        return _block(
            "BLOCK_V3_PERFORMANCE_METRIC_COVERAGE",
            missing=sorted(REQUIRED_PERFORMANCE_METRICS - set(metric_ids)),
            extra=sorted(set(metric_ids) - REQUIRED_PERFORMANCE_METRICS),
        )
    for metric in metrics:
        if not metric.get("name") or metric.get("aggregation") not in {"P95", "TOTAL"}:
            return _block("BLOCK_V3_PERFORMANCE_METRIC_SHAPE", metric_id=metric.get("id"))
        if metric.get("unit") not in {"ms", "count"}:
            return _block("BLOCK_V3_PERFORMANCE_METRIC_UNIT", metric_id=metric.get("id"))
        maximum = metric.get("max")
        if not isinstance(maximum, (int, float)) or maximum < 0:
            return _block("BLOCK_V3_PERFORMANCE_BUDGET", metric_id=metric.get("id"))
        if metric.get("unit") == "ms" and maximum <= 0:
            return _block("BLOCK_V3_PERFORMANCE_BUDGET", metric_id=metric.get("id"))

    measurement = performance_policy.get("measurement_requirements") or {}
    for key in (
        "capture_raw_samples",
        "capture_p50_p95_max",
        "capture_total_wall_clock",
        "capture_retry_count",
        "capture_timeout_count",
        "missing_metric_is_failure",
    ):
        if measurement.get(key) is not True:
            return _block("BLOCK_V3_PERFORMANCE_MEASUREMENT", field=key)

    if any(performance_policy.get(k) is not False for k in (
        "business_effect_dispatch_allowed",
        "model_calls_allowed",
        "production_write_allowed",
    )):
        return _block("BLOCK_V3_PERFORMANCE_ZERO_EFFECT")

    if live_canary_v3.get("contract_version") != "S30_STRATEGY_EXECUTOR_LIVE_CANARY_V3":
        return _block("BLOCK_V3_LIVE_CANARY_VERSION")
    if live_canary_v3.get("supersedes") != live_canary_v2.get("contract_version"):
        return _block("BLOCK_V3_LIVE_SUPERSEDES_BINDING")
    if live_canary_v3.get("family_matrix_binding") != matrix_v3.get("matrix_version"):
        return _block("BLOCK_V3_LIVE_MATRIX_BINDING")
    if live_canary_v3.get("performance_policy_binding") != performance_policy.get("policy_version"):
        return _block("BLOCK_V3_LIVE_PERFORMANCE_BINDING")
    if live_canary_v3.get("runtime_execution_status") != "NOT_EXECUTED_SOURCE_ONLY":
        return _block("BLOCK_V3_RUNTIME_CLAIM")
    if live_canary_v3.get("activation_authority") != "NONE":
        return _block("BLOCK_V3_AUTHORITY_CLAIM")
    if live_canary_v3.get("mode") != "CONTROL_STATE_NO_EFFECT":
        return _block("BLOCK_V3_LIVE_MODE")
    if any(live_canary_v3.get(k) is not False for k in REQUIRED_ZERO_EFFECT_FLAGS):
        return _block("BLOCK_V3_ZERO_EFFECT")

    strategy = activation.get("strategy_resolution") or {}
    target = live_canary_v3.get("target_strategy") or {}
    if target.get("snapshot_id") != strategy.get("canonical_canary_snapshot_id") or target.get("snapshot_code") != strategy.get("canonical_canary_snapshot_code"):
        return _block("BLOCK_V3_CANARY_TARGET_BINDING")

    checks = live_canary_v3.get("checks") or []
    check_ids = [c.get("id") for c in checks if isinstance(c, Mapping)]
    if len(check_ids) != 14 or len(check_ids) != len(set(check_ids)):
        return _block("BLOCK_V3_FUNCTIONAL_CHECK_COVERAGE")
    if not REQUIRED_RUNTIME_NEGATIVE_CHECKS.issubset(set(check_ids)):
        return _block("BLOCK_V3_RUNTIME_NEGATIVE_COVERAGE")

    dimension_checks = live_canary_v3.get("dimension_checks") or []
    dimension_check_ids = [c.get("id") for c in dimension_checks if isinstance(c, Mapping)]
    if len(dimension_check_ids) != len(set(dimension_check_ids)) or set(dimension_check_ids) != REQUIRED_DIMENSION_CHECKS:
        return _block(
            "BLOCK_V3_DIMENSION_CHECK_COVERAGE",
            missing=sorted(REQUIRED_DIMENSION_CHECKS - set(dimension_check_ids)),
            extra=sorted(set(dimension_check_ids) - REQUIRED_DIMENSION_CHECKS),
        )
    dimensions_seen = {c.get("dimension") for c in dimension_checks}
    if not {"QUALITY", "DEPTH", "PERFORMANCE"}.issubset(dimensions_seen):
        return _block("BLOCK_V3_DIMENSION_CHECK_BINDING")
    if any(not c.get("expected") for c in dimension_checks):
        return _block("BLOCK_V3_DIMENSION_CHECK_SHAPE")

    measurement_plan = live_canary_v3.get("performance_measurement_plan") or {}
    if measurement_plan.get("policy_ref") != "strategy_executor_performance_policy_v1.json":
        return _block("BLOCK_V3_MEASUREMENT_POLICY_REF")
    if measurement_plan.get("raw_sample_evidence_required") is not True:
        return _block("BLOCK_V3_MEASUREMENT_RAW_EVIDENCE")
    if set(measurement_plan.get("summary_statistics_required") or []) != {"P50", "P95", "MAX", "TOTAL"}:
        return _block("BLOCK_V3_MEASUREMENT_SUMMARY_POLICY")
    if measurement_plan.get("missing_or_partial_measurement") != "FAIL_CLOSED":
        return _block("BLOCK_V3_MEASUREMENT_FAIL_CLOSED")

    return {
        "status": PASS,
        "code": "PASS_STRATEGY_EXECUTOR_FAMILY_OBJECTIVE_MATRIX_V3",
        "objective_count": len(profiles),
        "dimension_count": len(REQUIRED_DIMENSIONS),
        "functional_live_check_count": len(checks),
        "dimension_live_check_count": len(dimension_checks),
        "performance_metric_count": len(metrics),
        "runtime_execution_claimed": False,
    }
