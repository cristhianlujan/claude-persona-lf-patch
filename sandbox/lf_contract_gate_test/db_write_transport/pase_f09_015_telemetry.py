"""Pure helpers for PASE-ATOM-F09-015 Train telemetry and verification."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
import json
import re
from typing import Any, Callable

ENVELOPE_VERSION = "pase_f09_015_telemetry_v1"
MAX_ENVELOPE_BYTES = 2560
CANONICAL_STEPS = ("preflight", "patch", "verify")
TELEMETRY_STAGES = ("transport", "queries", "control_execution", "judges", "evidence_persistence", "total")
NOT_OBSERVED = "NOT_OBSERVED"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def digest_json(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def sanitize_message(value: Any, limit: int = 512) -> str:
    text = " ".join(str(value or "").split())
    text = re.sub(r"(?i)(postgres(?:ql)?://[^\s]+)", "[REDACTED_CONNECTION]", text)
    text = re.sub(r"(?i)(password|token|secret|authorization)\s*[=:]\s*[^\s,;]+", r"\1=[REDACTED]", text)
    return text[:limit]


@dataclass
class Counters:
    count: int = 0
    duration_ms: float = 0.0
    bytes: int = 0

    def add(self, duration_ms: float, byte_count: int) -> None:
        self.count += 1
        self.duration_ms += max(0.0, duration_ms)
        self.bytes += max(0, byte_count)

    def fields(self) -> dict[str, int | float | str]:
        if not self.count:
            return {"count": NOT_OBSERVED, "duration_ms": NOT_OBSERVED, "bytes": NOT_OBSERVED}
        return {"count": self.count, "duration_ms": round(self.duration_ms, 3), "bytes": self.bytes}


@dataclass
class StageMetrics:
    queries: Counters = field(default_factory=Counters)
    transport: Counters = field(default_factory=Counters)


def make_envelope(*, step: str, started_at: str, finished_at: str, execution_id: str,
                  control_id: str, input_value: Any, result_value: Any,
                  metrics: StageMetrics | None = None, derived_status_ref: str = "judge",
                  run_identity: dict | None = None, observed_stages: dict | None = None,
                  total_started_at: str | None = None) -> dict:
    if step not in CANONICAL_STEPS:
        raise ValueError(f"PASE_F09_015_UNKNOWN_STEP:{step}")
    metrics = metrics or StageMetrics()
    try:
        start = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
        finish = datetime.fromisoformat(finished_at.replace("Z", "+00:00"))
        duration: int | float | str = round(max(0.0, (finish - start).total_seconds() * 1000), 3)
    except (TypeError, ValueError):
        duration = NOT_OBSERVED
    try:
        total_start = datetime.fromisoformat((total_started_at or started_at).replace("Z", "+00:00"))
        finish = datetime.fromisoformat(finished_at.replace("Z", "+00:00"))
        total_duration: int | float | str = round(max(0.0, (finish - total_start).total_seconds() * 1000), 3)
    except (TypeError, ValueError):
        total_duration = NOT_OBSERVED
    observed_stages = observed_stages or {}
    stages = {
        "transport": metrics.transport.fields(),
        "queries": metrics.queries.fields(),
        "control_execution": {"count": NOT_OBSERVED, "duration_ms": NOT_OBSERVED, "bytes": NOT_OBSERVED},
        "judges": {"count": NOT_OBSERVED, "duration_ms": NOT_OBSERVED, "bytes": NOT_OBSERVED},
        "evidence_persistence": {"count": NOT_OBSERVED, "duration_ms": NOT_OBSERVED, "bytes": NOT_OBSERVED},
        "total": {"count": 1 if isinstance(total_duration, (int, float)) else NOT_OBSERVED,
                  "duration_ms": total_duration, "bytes": NOT_OBSERVED},
    }
    for name, values in observed_stages.items():
        if name not in TELEMETRY_STAGES:
            raise ValueError(f"PASE_F09_015_UNKNOWN_STAGE:{name}")
        if not isinstance(values, dict):
            raise ValueError(f"PASE_F09_015_INVALID_STAGE:{name}")
        stages[name] = {key: values.get(key, NOT_OBSERVED) for key in ("count", "duration_ms", "bytes")}
    identity_fields = ("run_kind", "suite_id", "repository", "pr", "git_head_sha", "github_run_id",
                       "github_run_attempt", "train_run_id", "execution_id", "migration_version",
                       "source_blob", "source_sha256", "control_id")
    identity = {key: (run_identity or {}).get(key, NOT_OBSERVED) for key in identity_fields}
    return {
        "schema": ENVELOPE_VERSION,
        "trace_id": execution_id,
        "run_identity": identity,
        "step_id": step,
        "control_id": control_id,
        "started_at": started_at or NOT_OBSERVED,
        "finished_at": finished_at or NOT_OBSERVED,
        "duration_ms": duration,
        "queries": metrics.queries.fields(),
        "transport": metrics.transport.fields(),
        "stages": stages,
        "recorder_write": {"count": 1, "duration_ms": NOT_OBSERVED, "bytes": NOT_OBSERVED},
        "input_digest": digest_json(input_value) if input_value is not None else NOT_OBSERVED,
        "result_digest": digest_json(result_value) if result_value is not None else NOT_OBSERVED,
        "derived_status_ref": derived_status_ref,
        "failure": NOT_OBSERVED,
        "evidence_locator": NOT_OBSERVED,
    }


def serialize_envelope(envelope: dict, limit: int = MAX_ENVELOPE_BYTES) -> str:
    payload = json.dumps(envelope, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    size = len(payload.encode("utf-8"))
    if size > limit:
        raise ValueError(f"PASE_F09_015_ENVELOPE_TOO_LARGE:bytes={size}:limit={limit}")
    return payload


def record_failure_once(write_row: Callable[[dict], Any], append_receipt: Callable[[dict], Any],
                        original_error: dict) -> dict:
    """One attempt only. A rejected row is preserved with the original error in the receipt."""
    error = {"code": sanitize_message(original_error.get("code"), 96) or NOT_OBSERVED,
             "sqlstate": sanitize_message(original_error.get("sqlstate"), 32) or NOT_OBSERVED,
             "message": sanitize_message(original_error.get("message")) or NOT_OBSERVED,
             "evidence_locator": sanitize_message(original_error.get("evidence_locator"), 256) or NOT_OBSERVED}
    try:
        result = write_row(error)
        return {"outcome": "FAILURE_ROW_RECORDED", "row_result": result, "error": error}
    except Exception as guard_error:  # do not retry the rejected write
        rejection = sanitize_message(guard_error, 512)
        receipt = {"original_error": error, "failure_row_rejected": rejection}
        append_receipt(receipt)
        return {"outcome": "FAILURE_ROW_REJECTED", **receipt}


def verify_execution(execution: dict, canonical_steps: tuple[str, ...] = CANONICAL_STEPS) -> dict:
    rows = execution.get("steps") or []
    emitted = {str(row.get("step_id")): row for row in rows}
    if len(emitted) != len(rows):
        raise ValueError("PASE_F09_015_DUPLICATE_STEP")
    unexpected = sorted(set(emitted) - set(canonical_steps))
    if unexpected:
        raise ValueError("PASE_F09_015_NONCANONICAL_STEP:" + ",".join(unexpected))
    absent = [step for step in canonical_steps if step not in emitted]
    for step, row in emitted.items():
        payload = row.get("evidence_payload") or row.get("payload") or {}
        if isinstance(payload, str):
            try:
                payload = json.loads(payload)
            except ValueError as exc:
                raise ValueError(f"PASE_F09_015_INVALID_STEP_PAYLOAD:{step}") from exc
        envelope = payload.get(ENVELOPE_VERSION) if isinstance(payload, dict) else None
        if not isinstance(envelope, dict):
            raise ValueError(f"PASE_F09_015_ENVELOPE_MISSING:{step}")
        if envelope.get("schema") != ENVELOPE_VERSION or envelope.get("step_id") != step:
            raise ValueError(f"PASE_F09_015_ENVELOPE_IDENTITY_MISMATCH:{step}")
        if envelope.get("trace_id") != execution.get("execution_id"):
            raise ValueError(f"PASE_F09_015_TRACE_ID_MISMATCH:{step}")
        identity = envelope.get("run_identity")
        required_identity = ("run_kind", "suite_id", "repository", "pr", "git_head_sha", "github_run_id",
                             "github_run_attempt", "train_run_id", "execution_id", "migration_version",
                             "source_blob", "source_sha256", "control_id")
        if not isinstance(identity, dict) or any(not str(identity.get(key, "")).strip() for key in required_identity):
            raise ValueError(f"PASE_F09_015_RUN_IDENTITY_INCOMPLETE:{step}")
        if identity.get("execution_id") != execution.get("execution_id"):
            raise ValueError(f"PASE_F09_015_RUN_IDENTITY_MISMATCH:{step}")
        stages = envelope.get("stages")
        if not isinstance(stages, dict) or set(stages) != set(TELEMETRY_STAGES):
            raise ValueError(f"PASE_F09_015_STAGE_SET_INVALID:{step}")
        for stage in TELEMETRY_STAGES:
            value = stages[stage]
            if not isinstance(value, dict) or value.get("duration_ms") == NOT_OBSERVED:
                raise ValueError(f"PASE_F09_015_STAGE_NOT_OBSERVED:{step}:{stage}")
            duration_value = value.get("duration_ms")
            if isinstance(duration_value, bool) or not isinstance(duration_value, (int, float)) or duration_value < 0:
                raise ValueError(f"PASE_F09_015_STAGE_DURATION_INVALID:{step}:{stage}")
        if "verdict" in envelope:
            raise ValueError(f"PASE_F09_015_ENVELOPE_OWNS_VERDICT:{step}")
        if len(json.dumps(envelope, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")) > MAX_ENVELOPE_BYTES:
            raise ValueError(f"PASE_F09_015_ENVELOPE_TOO_LARGE:{step}")
    failed_index = next((i for i, step in enumerate(canonical_steps)
                         if step in emitted and emitted[step].get("status") not in ("PASS_CLEAN", "PASS")), None)
    receipt_failure = execution.get("failure_receipt") or {}
    receipt_failed_step = receipt_failure.get("failed_step")
    failure_row_rejected = bool(receipt_failure.get("failure_row_rejection"))
    if failed_index is None and failure_row_rejected and receipt_failed_step in canonical_steps:
        failed_index = canonical_steps.index(receipt_failed_step)
    if failed_index is None:
        if absent:
            raise ValueError("PASE_F09_015_REQUIRED_STEP_MISSING:" + ",".join(absent))
        return {"status": "PASS", "steps": list(canonical_steps), "not_reached": []}
    failed_step = canonical_steps[failed_index]
    not_reached = list(canonical_steps[failed_index + 1:])
    if any(step in emitted for step in not_reached):
        raise ValueError("PASE_F09_015_STEP_EMITTED_AFTER_FAILURE:" +
                         ",".join(step for step in not_reached if step in emitted))
    permitted_missing_failed_row = failure_row_rejected and receipt_failed_step == failed_step
    unexpected_absent = [step for step in absent if step not in not_reached
                         and not (step == failed_step and permitted_missing_failed_row)]
    if unexpected_absent:
        raise ValueError("PASE_F09_015_REQUIRED_STEP_MISSING:" + ",".join(unexpected_absent))
    return {"status": "FAILURE_PATH_RECONSTRUCTED", "failed_step": failed_step,
            "failure_row_rejected": permitted_missing_failed_row,
            "not_reached": not_reached, "emitted": [step for step in canonical_steps if step in emitted]}


def retry_chains(executions: list[dict]) -> list[dict]:
    groups: dict[tuple[str, str], list[dict]] = {}
    for item in executions:
        key = (str(item.get("pr", "")), str(item.get("migration_version", "")))
        groups.setdefault(key, []).append(item)
    result = []
    for (pr, version), items in sorted(groups.items(), key=lambda item: (int(item[0][0]) if item[0][0].isdigit() else item[0][0], item[0][1])):
        ordered = sorted(items, key=lambda item: (str(item.get("created_at") or ""),
                                                  str(item.get("execution_id") or "")))
        result.append({"pr": pr, "migration_version": version,
                       "attempts": [{"attempt_number": i, "execution_id": item.get("execution_id"),
                                     "created_at": item.get("created_at")} for i, item in enumerate(ordered, 1)]})
    return result
