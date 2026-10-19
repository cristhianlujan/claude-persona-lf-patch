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
                  metrics: StageMetrics | None = None, derived_status_ref: str = "judge") -> dict:
    if step not in CANONICAL_STEPS:
        raise ValueError(f"PASE_F09_015_UNKNOWN_STEP:{step}")
    metrics = metrics or StageMetrics()
    try:
        start = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
        finish = datetime.fromisoformat(finished_at.replace("Z", "+00:00"))
        duration: int | float | str = round(max(0.0, (finish - start).total_seconds() * 1000), 3)
    except (TypeError, ValueError):
        duration = NOT_OBSERVED
    return {
        "schema": ENVELOPE_VERSION,
        "trace_id": execution_id,
        "step_id": step,
        "control_id": control_id,
        "started_at": started_at or NOT_OBSERVED,
        "finished_at": finished_at or NOT_OBSERVED,
        "duration_ms": duration,
        "queries": metrics.queries.fields(),
        "transport": metrics.transport.fields(),
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


_VERSION_PREFIX_RE = re.compile(r"^\d{14}_")


def _retry_migration_name(item: dict) -> str:
    """Owner decision D1 (2026-10-14): chain retries by PR + migration name.

    The Train may reassign the version between attempts when the ledger floor
    advances, so the version is recorded per attempt but is not part of the key.
    """
    name = str(item.get("migration_name") or "").strip()
    if not name:
        path = str(item.get("migration_path") or "").strip()
        base = path.rsplit("/", 1)[-1]
        name = base[:-4] if base.endswith(".sql") else base
    name = _VERSION_PREFIX_RE.sub("", name)
    if not name:
        raise ValueError("PASE_F09_015_RETRY_CHAIN_MIGRATION_NAME_MISSING:"
                         + str(item.get("execution_id") or NOT_OBSERVED))
    return name


def retry_chains(executions: list[dict]) -> list[dict]:
    groups: dict[tuple[str, str], list[dict]] = {}
    for item in executions:
        key = (str(item.get("pr", "")), _retry_migration_name(item))
        groups.setdefault(key, []).append(item)
    result = []
    for (pr, name), items in sorted(groups.items(), key=lambda item: (int(item[0][0]) if item[0][0].isdigit() else item[0][0], item[0][1])):
        ordered = sorted(items, key=lambda item: (str(item.get("created_at") or ""),
                                                  str(item.get("execution_id") or "")))
        result.append({"pr": pr, "migration_name": name,
                       "attempts": [{"attempt_number": i, "execution_id": item.get("execution_id"),
                                     "migration_version": str(item.get("migration_version") or NOT_OBSERVED),
                                     "created_at": item.get("created_at")} for i, item in enumerate(ordered, 1)]})
    return result
