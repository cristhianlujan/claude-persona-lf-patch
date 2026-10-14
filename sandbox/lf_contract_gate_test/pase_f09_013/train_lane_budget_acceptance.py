#!/usr/bin/env python3
"""Read-only evaluator for the frozen F09-013 Train lane budget.

Live mode reads event 21014 and execution evidence from Supabase using a
read-only PostgreSQL transaction. It never writes. Unit tests exercise only
fixture data; this file must not be run in live mode as part of this PR.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import datetime, timezone
import json
import os
import re
import sys
from typing import Any

EVENT_ID = 21014
CUTOFF = datetime.fromisoformat("2026-10-14T23:09:31+00:00")
NOT_OBSERVED = "NOT_OBSERVED"
TRAIN_PREFIX = "EXEC-DB-TRAIN-"
C3_TARGET = re.compile(r"^(?:\d{14}_)?lf_pase_f09_015_c3_", re.IGNORECASE)
STEP_NAMES = ("preflight", "patch", "verify")
METRIC_PATHS = {
    "duration_ms": ("duration_ms",),
    "queries_count": ("queries", "count"),
    "queries_duration_ms": ("queries", "duration_ms"),
    "transport_count": ("transport", "count"),
    "transport_duration_ms": ("transport", "duration_ms"),
}


def parse_jsonb(value: Any) -> dict:
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        parsed = json.loads(value)
        return parsed if isinstance(parsed, dict) else {}
    return {}


def as_utc(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, str):
        value = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def json_time(value: Any) -> str | None:
    parsed = as_utc(value)
    return parsed.isoformat().replace("+00:00", "Z") if parsed else None


def number(value: Any) -> int | float | None:
    if value is None or value == NOT_OBSERVED or isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    if result != result or result in (float("inf"), float("-inf")):
        return None
    return int(result) if result.is_integer() else result


def read_path(value: dict, path: tuple[str, ...]) -> Any:
    current: Any = value
    for part in path:
        if not isinstance(current, dict) or part not in current:
            return NOT_OBSERVED
        current = current[part]
    return current


def migration_target_excluded(target_code: Any) -> bool:
    value = str(target_code or "")
    value = value.rsplit("/", 1)[-1]
    if value.endswith(".sql"):
        value = value[:-4]
    return bool(C3_TARGET.match(value))


def classify_run(run: dict, all_runs: list[dict]) -> tuple[str, str, float | None]:
    started = as_utc(run.get("started_at"))
    if started is None:
        return "excluded", "missing_started_at", None
    earlier = []
    for candidate in all_runs:
        if candidate.get("execution_id") == run.get("execution_id"):
            continue
        prior_started = as_utc(candidate.get("started_at"))
        if prior_started is not None and (prior_started, str(candidate.get("execution_id", ""))) < (
            started, str(run.get("execution_id", ""))
        ):
            earlier.append((prior_started, str(candidate.get("execution_id", "")), candidate))
    if not earlier:
        return "excluded", "no_prior_run_reference", None
    prior = max(earlier, key=lambda item: (item[0], item[1]))[2]
    prior_status = str(prior.get("status") or "")
    prior_end = as_utc(prior.get("completed_at")) or as_utc(prior.get("updated_at"))
    if prior_status not in ("COMPLETED", "BLOCKED") or prior_end is None:
        return "excluded", "previous_run_not_closed", None
    gap_min = (started - prior_end).total_seconds() / 60
    if gap_min < 0:
        return "excluded", "overlapping_or_invalid_timestamps", gap_min
    if gap_min >= 30:
        return "cold", "idle_gap_at_least_30_minutes", gap_min
    if gap_min <= 10:
        return "hot", "idle_gap_at_most_10_minutes", gap_min
    return "excluded", "idle_gap_between_10_and_30_minutes", gap_min


def percentile_nearest_rank(values: list[int | float]) -> dict[str, int | float | str]:
    ordered = sorted(values)
    if not ordered:
        return {"p50": NOT_OBSERVED, "p95": NOT_OBSERVED, "p99": NOT_OBSERVED}

    def at(p: float) -> int | float:
        rank = max(1, int((p * len(ordered)) + 0.999999999))
        return ordered[min(rank, len(ordered)) - 1]

    return {"p50": at(0.50), "p95": at(0.95), "p99": at(0.99)}


def caps_from_event(event_payload: dict) -> dict[str, int | float | None]:
    frozen = event_payload.get("frozen_caps")
    if not isinstance(frozen, dict):
        raise ValueError("F09_013_EVENT_FROZEN_CAPS_MISSING")
    caps: dict[str, int | float | None] = {}
    for step in STEP_NAMES:
        block = frozen.get(step)
        if not isinstance(block, dict):
            raise ValueError(f"F09_013_EVENT_STEP_CAPS_MISSING:{step}")
        for metric in METRIC_PATHS:
            key = metric + "_cap"
            if key not in block:
                raise ValueError(f"F09_013_EVENT_METRIC_CAP_MISSING:{step}.{key}")
            raw = block[key]
            caps[f"{step}.{metric}"] = None if raw == NOT_OBSERVED else number(raw)
    total_block = frozen.get("total")
    if not isinstance(total_block, dict) or "duration_ms_cap" not in total_block:
        raise ValueError("F09_013_EVENT_TOTAL_CAP_MISSING")
    raw_total = total_block["duration_ms_cap"]
    caps["total.duration_ms"] = None if raw_total == NOT_OBSERVED else number(raw_total)
    if any(value is None and not key.endswith(("transport_count", "transport_duration_ms"))
           for key, value in caps.items()):
        raise ValueError("F09_013_REQUIRED_NUMERIC_CAP_MISSING")
    return caps


def telemetry_for_step(step_row: dict) -> dict:
    payload = parse_jsonb(step_row.get("evidence_payload"))
    envelope = payload.get("pase_f09_015_telemetry_v1")
    return envelope if isinstance(envelope, dict) else {}


def execution_metrics(run: dict, step_rows: list[dict]) -> tuple[dict[str, Any], list[str]]:
    metrics: dict[str, Any] = {}
    missing_steps: list[str] = []
    grouped: dict[str, list[dict]] = defaultdict(list)
    for row in step_rows:
        grouped[str(row.get("step_id") or "")].append(row)

    for step in STEP_NAMES:
        rows = grouped.get(step, [])
        if len(rows) != 1:
            missing_steps.append(step if not rows else f"{step}:duplicate_rows")
            continue
        envelope = telemetry_for_step(rows[0])
        if not envelope:
            missing_steps.append(step)
            continue
        for metric, path in METRIC_PATHS.items():
            metrics[f"{step}.{metric}"] = read_path(envelope, path)

    started = as_utc(run.get("started_at"))
    completed = as_utc(run.get("completed_at"))
    if started is not None and completed is not None and completed >= started:
        metrics["total.duration_ms"] = round((completed - started).total_seconds() * 1000, 3)
    else:
        metrics["total.duration_ms"] = NOT_OBSERVED
    return metrics, missing_steps


def analyze(event_row: dict, execution_rows: list[dict], step_rows: list[dict]) -> dict:
    if int(event_row.get("id", -1)) != EVENT_ID:
        raise ValueError("F09_013_FREEZE_EVENT_ID_MISMATCH")
    payload = parse_jsonb(event_row.get("payload"))
    if payload.get("acceptance_declared") is not False:
        raise ValueError("F09_013_FREEZE_EVENT_ENVELOPE_INVALID")
    caps = caps_from_event(payload)
    rule = payload.get("acceptance_rule") or {}
    target_count = int(rule.get("sample_count", 10))
    min_cold = int(rule.get("min_cold_samples", 2))

    all_runs = [
        row for row in execution_rows
        if str(row.get("execution_id") or "").startswith(TRAIN_PREFIX)
    ]
    all_runs.sort(key=lambda row: (
        as_utc(row.get("started_at")) or datetime.min.replace(tzinfo=timezone.utc),
        str(row.get("execution_id") or ""),
    ))
    steps_by_execution: dict[str, list[dict]] = defaultdict(list)
    for row in step_rows:
        steps_by_execution[str(row.get("execution_id") or "")].append(row)

    candidates = []
    for run in all_runs:
        created = as_utc(run.get("created_at"))
        if str(run.get("status") or "") != "COMPLETED" or created is None or created <= CUTOFF:
            continue
        if migration_target_excluded(run.get("target_code")):
            continue
        candidates.append(run)

    evaluated = []
    findings = []
    valid_by_group: dict[str, list[dict]] = {"cold": [], "hot": []}
    for run in candidates:
        classification, reason, gap = classify_run(run, all_runs)
        metrics, missing_steps = execution_metrics(run, steps_by_execution.get(str(run["execution_id"]), []))
        missing_metrics = []
        exceeded = []
        for metric_name, cap in caps.items():
            observed = number(metrics.get(metric_name))
            if cap is None:
                continue
            if observed is None:
                missing_metrics.append(metric_name)
            elif observed > cap:
                exceeded.append({"metric": metric_name, "observed": observed, "cap": cap})
                findings.append({
                    "execution_id": run["execution_id"],
                    "classification": classification,
                    "kind": "BUDGET_EXCEEDED",
                    "metric": metric_name,
                    "observed": observed,
                    "cap": cap,
                })
        for step in missing_steps:
            findings.append({
                "execution_id": run["execution_id"],
                "classification": classification,
                "kind": "STEP_EVIDENCE_MISSING",
                "step": step,
            })
        for metric_name in missing_metrics:
            findings.append({
                "execution_id": run["execution_id"],
                "classification": classification,
                "kind": "CAPPED_METRIC_NOT_OBSERVED",
                "metric": metric_name,
            })
        valid = classification in ("cold", "hot") and not missing_steps and not missing_metrics
        item = {
            "execution_id": run["execution_id"],
            "target_code": run.get("target_code"),
            "created_at": json_time(run.get("created_at")),
            "started_at": json_time(run.get("started_at")),
            "completed_at": json_time(run.get("completed_at")),
            "classification": classification,
            "classification_reason": reason,
            "idle_gap_minutes": round(gap, 3) if gap is not None else NOT_OBSERVED,
            "valid_sample": valid,
            "metrics": metrics,
            "exceeded_caps": exceeded,
            "missing_steps": missing_steps,
            "missing_capped_metrics": missing_metrics,
        }
        evaluated.append(item)
        if valid:
            valid_by_group[classification].append(item)

    percentiles = {}
    for group, samples in valid_by_group.items():
        values = {}
        for metric_name in caps:
            collected = [
                number(sample["metrics"].get(metric_name))
                for sample in samples
            ]
            numeric = [value for value in collected if value is not None]
            values[metric_name] = percentile_nearest_rank(numeric)
        percentiles[group] = values

    cold_count = len(valid_by_group["cold"])
    hot_count = len(valid_by_group["hot"])
    valid_count = cold_count + hot_count
    return {
        "event_id": EVENT_ID,
        "cutoff_created_at_exclusive": CUTOFF.isoformat().replace("+00:00", "Z"),
        "sample_target": target_count,
        "minimum_cold_samples": min_cold,
        "valid_sample_count": valid_count,
        "valid_cold_sample_count": cold_count,
        "valid_hot_sample_count": hot_count,
        "samples_remaining": max(0, target_count - valid_count),
        "cold_samples_remaining": max(0, min_cold - cold_count),
        "evaluated_executions": evaluated,
        "percentiles_nearest_rank": percentiles,
        "findings": findings,
    }


def fetch_live(dsn: str) -> dict:
    try:
        import psycopg
    except ImportError as exc:
        raise RuntimeError("Install psycopg v3 to use live read-only mode") from exc

    event_sql = """
        SELECT id, payload
          FROM public.lf_eventos
         WHERE id = %s AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
    """
    execution_sql = """
        SELECT execution_id, status, target_code, created_at, started_at,
               completed_at, updated_at
          FROM public.lf_operation_execution
         WHERE execution_id LIKE 'EXEC-DB-TRAIN-%'
         ORDER BY started_at NULLS FIRST, execution_id
    """
    step_sql = """
        SELECT s.execution_id, s.step_id, s.status, s.evidence_payload
          FROM public.lf_operation_execution_steps s
          JOIN public.lf_operation_execution e USING (execution_id)
         WHERE e.execution_id LIKE 'EXEC-DB-TRAIN-%%'
         ORDER BY s.execution_id, s.step_order
    """
    with psycopg.connect(dsn, autocommit=False) as connection:
        try:
            connection.execute("SET TRANSACTION READ ONLY")
            with connection.cursor() as cursor:
                cursor.execute("SHOW transaction_read_only")
                read_only = cursor.fetchone()[0]
                if str(read_only).lower() not in ("on", "true", "1"):
                    raise RuntimeError("F09_013_READ_ONLY_TRANSACTION_NOT_CONFIRMED")
                cursor.execute(event_sql, (EVENT_ID,))
                event_records = cursor.fetchall()
                if len(event_records) != 1:
                    raise RuntimeError(f"F09_013_FREEZE_EVENT_CARDINALITY:{len(event_records)}")
                event = {"id": event_records[0][0], "payload": event_records[0][1]}
                cursor.execute(execution_sql)
                executions = [dict(zip([d.name for d in cursor.description], row))
                              for row in cursor.fetchall()]
                cursor.execute(step_sql)
                steps = [dict(zip([d.name for d in cursor.description], row))
                         for row in cursor.fetchall()]
            return analyze(event, executions, steps)
        finally:
            connection.rollback()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--live-read-only",
        action="store_true",
        help="read Supabase with a transaction explicitly set READ ONLY",
    )
    parser.add_argument(
        "--dsn-env",
        default="LF_SUPABASE_READONLY_DSN",
        help="environment variable containing a read-only Supabase DSN",
    )
    args = parser.parse_args()
    if not args.live_read_only:
        parser.error("live execution requires --live-read-only; tests use fixtures only")
    dsn = os.environ.get(args.dsn_env, "").strip()
    if not dsn:
        parser.error(f"missing read-only DSN environment variable: {args.dsn_env}")
    report = fetch_live(dsn)
    print(json.dumps(report, indent=2, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
