"""Shared, read-only helpers for LF skill validators.

The module performs no network calls and writes no application data. Validators
emit one JSON object to stdout and use deterministic exit codes:
0 PASS_WITH_EVIDENCE, 1 RETURN_TO_WORKER/FAIL, 2 BLOCKED/input error.
"""
from __future__ import annotations

import argparse
import hashlib
import json
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
) -> dict[str, Any]:
    failed = sorted(set(str(item) for item in failed_assertions if item))
    blocked = sorted(set(str(item) for item in (blocking_assertions or []) if item))
    if not 0 <= retry_count <= 2:
        raise ValidationInputError("retry_count_out_of_range")
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
    return {
        "judge_code": judge_code,
        "result": outcome,
        "compliance_bit": 1 if outcome == "PASS_WITH_EVIDENCE" else 0,
        "failed_assertions": failed,
        "blocking_assertions": blocked,
        "evidence_refs": refs,
        "evidence": dict(evidence),
        "repair_instructions": repairs,
        "retry_count": retry_count,
        "judged_at": utc_now(),
    }


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
