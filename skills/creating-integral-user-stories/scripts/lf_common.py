"""Shared, read-only helpers for LF skill validators.

The module performs no network calls and writes no application data. Validators
emit one JSON object to stdout and use deterministic exit codes:
0 PASS_WITH_EVIDENCE, 1 RETURN_TO_WORKER/FAIL, 2 BLOCKED/input error.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

SCHEMA_VERSION = "v0.5"
RESULT_VALUES = ("PASS_WITH_EVIDENCE", "RETURN_TO_WORKER", "BLOCKED", "FAIL")
EXIT_BY_RESULT = {
    "PASS_WITH_EVIDENCE": 0,
    "RETURN_TO_WORKER": 1,
    "FAIL": 1,
    "BLOCKED": 2,
}


class ValidationInputError(ValueError):
    """Raised when evidence or a result envelope is structurally unusable."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_json(path: str | Path) -> Any:
    target = Path(path)
    if not target.is_file():
        raise ValidationInputError(f"input_not_found:{target}")
    try:
        return json.loads(target.read_text(encoding="utf-8"))
    except UnicodeDecodeError as exc:
        raise ValidationInputError(f"input_not_utf8:{target}") from exc
    except json.JSONDecodeError as exc:
        raise ValidationInputError(
            f"invalid_json:{target}:line={exc.lineno}:column={exc.colno}"
        ) from exc


def load_yaml(path: str | Path) -> Any:
    try:
        import yaml
    except ImportError as exc:
        raise ValidationInputError("pyyaml_not_available") from exc
    target = Path(path)
    if not target.is_file():
        raise ValidationInputError(f"input_not_found:{target}")
    try:
        return yaml.safe_load(target.read_text(encoding="utf-8"))
    except UnicodeDecodeError as exc:
        raise ValidationInputError(f"input_not_utf8:{target}") from exc
    except yaml.YAMLError as exc:
        raise ValidationInputError(f"invalid_yaml:{target}:{exc}") from exc


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def add_common_input(parser: argparse.ArgumentParser, help_text: str) -> None:
    parser.add_argument("input", type=Path, help=help_text)
    parser.add_argument(
        "--evidence-ref",
        action="append",
        default=[],
        help="Resolvable evidence reference. May be repeated.",
    )


def parser(description: str) -> argparse.ArgumentParser:
    return argparse.ArgumentParser(description=description)


def failure(
    assertion_id: str,
    target_path: str,
    instruction: str,
    prohibited_shortcuts: Sequence[str] | None = None,
) -> dict[str, Any]:
    return {
        "assertion_id": assertion_id,
        "target_path": target_path,
        "instruction": instruction,
        "prohibited_shortcuts": list(
            prohibited_shortcuts
            or ("delete_assertion", "lower_threshold", "invent_source", "self_approve")
        ),
    }


def _valid_sha256(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(char in "0123456789abcdef" for char in value)
    )


def _parse_utc(value: Any, field: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise ValidationInputError(f"{field}_missing")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValidationInputError(f"{field}_invalid") from exc


def _check_failed(value: Any) -> bool:
    """Interpret deterministic check payloads without domain-specific guessing."""
    if isinstance(value, bool):
        return not value
    if value is None:
        return True
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, (list, tuple, set, dict)):
        return len(value) != 0
    if isinstance(value, str):
        normalized = value.strip().upper()
        return normalized not in {"", "0", "PASS", "OK", "TRUE"}
    return True


def _canonical_sha256_without_output_hash(out: Mapping[str, Any]) -> str:
    payload = dict(out)
    payload.pop("output_sha256", None)
    return hashlib.sha256(
        json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def validate_result_invariants(out: Mapping[str, Any]) -> None:
    """Enforce cross-property invariants that JSON Schema Draft-07 cannot express."""
    if out.get("schema_version") != SCHEMA_VERSION:
        raise ValidationInputError("schema_version_mismatch")

    result = out.get("result")
    if result not in RESULT_VALUES:
        raise ValidationInputError("result_invalid")

    total = out.get("assertions_total")
    passed = out.get("assertions_passed")
    if not isinstance(total, int) or isinstance(total, bool) or total < 1:
        raise ValidationInputError("assertions_total_invalid")
    if not isinstance(passed, int) or isinstance(passed, bool) or passed < 0:
        raise ValidationInputError("assertions_passed_invalid")
    if passed > total:
        raise ValidationInputError("assertions_passed_exceeds_total")

    failed = list(out.get("failed_assertions") or [])
    blocked = list(out.get("blocking_assertions") or [])
    unresolved = set(failed) | set(blocked)
    if passed + len(unresolved) != total:
        raise ValidationInputError("assertion_counts_inconsistent")

    repairs = list(out.get("repairs") or [])
    repair_instructions = list(out.get("repair_instructions") or [])
    if repairs != repair_instructions:
        raise ValidationInputError("repairs_not_equivalent")

    started = _parse_utc(out.get("started_at"), "started_at")
    completed = _parse_utc(out.get("completed_at"), "completed_at")
    if completed < started:
        raise ValidationInputError("timestamp_order_invalid")

    checks = out.get("evidence", {}).get("checks")
    if isinstance(checks, Mapping):
        failing_checks = {str(key) for key, value in checks.items() if _check_failed(value)}
        if not failing_checks.issubset(unresolved):
            raise ValidationInputError("failed_checks_not_reported")

    if result == "PASS_WITH_EVIDENCE":
        if passed != total:
            raise ValidationInputError("pass_without_all_assertions")
        if failed or blocked:
            raise ValidationInputError("pass_with_findings")
        if out.get("exit_code") != 0 or out.get("compliance_bit") != 1:
            raise ValidationInputError("pass_result_flags_invalid")
        if not _valid_sha256(out.get("input_sha256")):
            raise ValidationInputError("pass_input_sha256_invalid")
        if repairs:
            raise ValidationInputError("pass_with_repairs")
    elif result == "RETURN_TO_WORKER":
        if not failed or not repairs:
            raise ValidationInputError("return_without_failures_or_repairs")
        if out.get("exit_code") != 1 or out.get("compliance_bit") != 0:
            raise ValidationInputError("return_result_flags_invalid")
    elif result == "BLOCKED":
        if not blocked:
            raise ValidationInputError("blocked_without_assertion")
        if out.get("exit_code") != 2 or out.get("compliance_bit") != 0:
            raise ValidationInputError("blocked_result_flags_invalid")
    elif result == "FAIL":
        if not failed:
            raise ValidationInputError("fail_without_assertion")
        if out.get("exit_code") != 1 or out.get("compliance_bit") != 0:
            raise ValidationInputError("fail_result_flags_invalid")

    expected_hash = _canonical_sha256_without_output_hash(out)
    if out.get("output_sha256") != expected_hash:
        raise ValidationInputError("output_sha256_mismatch")


def result_object(
    judge_code: str,
    failed_assertions: Iterable[str],
    evidence: Mapping[str, Any],
    evidence_refs: Sequence[str] | None = None,
    repair_instructions: Sequence[Mapping[str, Any]] | None = None,
    blocking_assertions: Iterable[str] | None = None,
    retry_count: int = 0,
    forced_result: str | None = None,
    *,
    judge_version: str | None = None,
    executor_identity: str | None = None,
    started_at: str | None = None,
    command: str | None = None,
) -> dict[str, Any]:
    started = started_at or utc_now()
    failed = sorted(set(str(item) for item in failed_assertions if item))
    blocked = sorted(set(str(item) for item in (blocking_assertions or []) if item))
    if not 0 <= retry_count <= 2:
        raise ValidationInputError("retry_count_out_of_range")

    version = (judge_version or os.getenv("LF_JUDGE_VERSION") or "").strip()
    executor = (executor_identity or os.getenv("LF_EXECUTOR_IDENTITY") or "").strip()
    if not version:
        blocked.append("judge_version_missing")
    if not executor:
        blocked.append("executor_identity_missing")

    checks = evidence.get("checks") if isinstance(evidence, Mapping) else None
    if isinstance(checks, Mapping):
        failed.extend(str(key) for key, value in checks.items() if _check_failed(value))
    failed = sorted(set(failed))
    blocked = sorted(set(blocked))

    if forced_result is not None:
        if forced_result not in RESULT_VALUES:
            raise ValidationInputError(f"invalid_result:{forced_result}")
        outcome = forced_result
    elif blocked:
        outcome = "BLOCKED"
    elif failed:
        outcome = "RETURN_TO_WORKER"
    else:
        outcome = "PASS_WITH_EVIDENCE"

    if outcome == "PASS_WITH_EVIDENCE" and (failed or blocked):
        blocked.append("forced_pass_with_findings")
        blocked = sorted(set(blocked))
        outcome = "BLOCKED"

    refs = list(dict.fromkeys(evidence_refs or []))
    if not refs:
        refs = ["evidence:inline"]
    repairs = [dict(item) for item in (repair_instructions or [])]
    if outcome == "RETURN_TO_WORKER" and not repairs:
        repairs = [
            failure(item.split("=", 1)[0], "$", f"Repair assertion: {item}")
            for item in failed
        ]

    assertions_total = len(checks) if isinstance(checks, Mapping) else len(set(failed) | set(blocked))
    assertions_total = max(assertions_total, len(set(failed) | set(blocked)), 1)
    assertions_passed = max(assertions_total - len(set(failed) | set(blocked)), 0)

    input_sha256 = evidence.get("input_sha256") if isinstance(evidence, Mapping) else None
    if input_sha256 is not None and not _valid_sha256(input_sha256):
        blocked.append("input_sha256_invalid")
        input_sha256 = None
    if input_sha256 is None:
        input_path = evidence.get("input_path") if isinstance(evidence, Mapping) else None
        if input_path:
            target = Path(str(input_path))
            if target.is_file():
                input_sha256 = sha256_file(target)
    if outcome == "PASS_WITH_EVIDENCE" and not input_sha256:
        blocked.append("input_sha256_unavailable")

    blocked = sorted(set(blocked))
    if blocked:
        outcome = "BLOCKED"
        assertions_total = max(assertions_total, len(set(failed) | set(blocked)), 1)
        assertions_passed = max(assertions_total - len(set(failed) | set(blocked)), 0)

    evidence_payload = {
        "evidence_refs": refs,
        "evidence": dict(evidence),
        "repairs": repairs,
    }
    evidence_sha256 = hashlib.sha256(
        json.dumps(evidence_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()

    completed = utc_now()
    output = {
        "schema_version": SCHEMA_VERSION,
        "judge_code": judge_code,
        "judge_version": version or "MISSING",
        "executor_identity": executor or "MISSING",
        "command": command or " ".join(shlex.quote(arg) for arg in sys.argv),
        "started_at": started,
        "completed_at": completed,
        "exit_code": EXIT_BY_RESULT.get(outcome, 2),
        "result": outcome,
        "compliance_bit": 1 if outcome == "PASS_WITH_EVIDENCE" else 0,
        "assertions_total": assertions_total,
        "assertions_passed": assertions_passed,
        "failed_assertions": failed,
        "blocking_assertions": blocked,
        "repairs": repairs,
        "repair_instructions": repairs,
        "evidence_refs": refs,
        "evidence": dict(evidence),
        "evidence_sha256": evidence_sha256,
        "input_sha256": input_sha256,
        "retry_count": retry_count,
    }
    output["output_sha256"] = _canonical_sha256_without_output_hash(output)
    validate_result_invariants(output)
    return output


def emit(out: Mapping[str, Any]) -> int:
    validate_result_invariants(out)
    result = str(out.get("result", "BLOCKED"))
    print(json.dumps(out, ensure_ascii=False, sort_keys=True))
    return EXIT_BY_RESULT.get(result, 2)


def emit_blocked(judge_code: str, reason: str, evidence_ref: str = "evidence:inline") -> int:
    return emit(
        result_object(
            judge_code,
            [],
            {"input_error": reason},
            [evidence_ref],
            blocking_assertions=[reason],
            forced_result="BLOCKED",
            judge_version=os.getenv("LF_JUDGE_VERSION") or SCHEMA_VERSION,
            executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "LF_COMMON_BLOCK_HANDLER",
            command="lf_common.emit_blocked",
        )
    )


def require_object(value: Any, name: str = "input") -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationInputError(f"{name}_must_be_object")
    return value


def duplicate_values(values: Iterable[Any]) -> list[Any]:
    seen: set[Any] = set()
    duplicates: set[Any] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        else:
            seen.add(value)
    return sorted(duplicates, key=str)


def main_guard(judge_code: str, fn) -> int:
    try:
        return int(fn())
    except ValidationInputError as exc:
        return emit_blocked(judge_code, str(exc))
    except KeyboardInterrupt:
        return emit_blocked(judge_code, "execution_interrupted")
