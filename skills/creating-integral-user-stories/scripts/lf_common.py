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

RESULT_VALUES = ("PASS_WITH_EVIDENCE", "RETURN_TO_WORKER", "BLOCKED", "FAIL")
EXIT_BY_RESULT = {
    "PASS_WITH_EVIDENCE": 0,
    "RETURN_TO_WORKER": 1,
    "FAIL": 1,
    "BLOCKED": 2,
}


class ValidationInputError(ValueError):
    """Raised when evidence cannot be read or is structurally unusable."""


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

    refs = list(dict.fromkeys(evidence_refs or []))
    if not refs:
        refs = ["evidence:inline"]
    repairs = [dict(item) for item in (repair_instructions or [])]
    if outcome == "RETURN_TO_WORKER" and not repairs:
        repairs = [
            failure(item.split("=", 1)[0], "$", f"Repair assertion: {item}")
            for item in failed
        ]

    checks = evidence.get("checks") if isinstance(evidence, Mapping) else None
    assertions_total = len(checks) if isinstance(checks, Mapping) else len(failed) + len(blocked)
    assertions_total = max(assertions_total, len(failed) + len(blocked))
    assertions_passed = max(assertions_total - len(failed) - len(blocked), 0)

    input_sha256 = None
    input_path = evidence.get("input_path") if isinstance(evidence, Mapping) else None
    if input_path:
        target = Path(str(input_path))
        if target.is_file():
            input_sha256 = sha256_file(target)
    if outcome == "PASS_WITH_EVIDENCE" and not input_sha256:
        blocked = sorted(set(blocked + ["input_sha256_unavailable"]))
        outcome = "BLOCKED"
        assertions_total = max(assertions_total, len(failed) + len(blocked))
        assertions_passed = max(assertions_total - len(failed) - len(blocked), 0)

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
    output["output_sha256"] = hashlib.sha256(
        json.dumps(output, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return output


def emit(out: Mapping[str, Any]) -> int:
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
