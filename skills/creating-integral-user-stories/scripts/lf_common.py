"""Shared deterministic helpers for LF read-only validators."""
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
EXIT_BY_RESULT = {"PASS_WITH_EVIDENCE": 0, "RETURN_TO_WORKER": 1, "FAIL": 1, "BLOCKED": 2}


class ValidationInputError(ValueError):
    """Evidence or result envelope is unusable."""


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
    parser.add_argument("--evidence-ref", action="append", default=[])


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


def _assertion_id(value: Any) -> str:
    return str(value).split("=", 1)[0].strip()


def _parse_utc(value: Any, field: str) -> datetime:
    if not isinstance(value, str) or not value:
        raise ValidationInputError(f"{field}_missing")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValidationInputError(f"{field}_invalid") from exc


def _check_failed(value: Any) -> bool:
    if isinstance(value, bool):
        return not value
    if value is None:
        return True
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, (list, tuple, set, dict)):
        return bool(value)
    if isinstance(value, str):
        return value.strip().upper() not in {"", "0", "PASS", "OK", "TRUE"}
    return True


def _canonical_sha256_without_output_hash(out: Mapping[str, Any]) -> str:
    payload = dict(out)
    payload.pop("output_sha256", None)
    canonical = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def validate_result_invariants(out: Mapping[str, Any]) -> None:
    """Enforce cross-property rules unavailable in JSON Schema Draft-07."""
    if out.get("schema_version") != SCHEMA_VERSION:
        raise ValidationInputError("schema_version_mismatch")
    result = out.get("result")
    if result not in RESULT_VALUES:
        raise ValidationInputError("result_invalid")

    total, passed = out.get("assertions_total"), out.get("assertions_passed")
    if not isinstance(total, int) or isinstance(total, bool) or total < 1:
        raise ValidationInputError("assertions_total_invalid")
    if not isinstance(passed, int) or isinstance(passed, bool) or passed < 0:
        raise ValidationInputError("assertions_passed_invalid")
    if passed > total:
        raise ValidationInputError("assertions_passed_exceeds_total")

    failed = {_assertion_id(x) for x in out.get("failed_assertions") or []}
    blocked = {_assertion_id(x) for x in out.get("blocking_assertions") or []}
    unresolved = failed | blocked
    if passed + len(unresolved) != total:
        raise ValidationInputError("assertion_counts_inconsistent")

    repairs = list(out.get("repairs") or [])
    if repairs != list(out.get("repair_instructions") or []):
        raise ValidationInputError("repairs_not_equivalent")

    if _parse_utc(out.get("completed_at"), "completed_at") < _parse_utc(
        out.get("started_at"), "started_at"
    ):
        raise ValidationInputError("timestamp_order_invalid")

    checks = out.get("evidence", {}).get("checks")
    if isinstance(checks, Mapping):
        failing = {_assertion_id(k) for k, value in checks.items() if _check_failed(value)}
        if not failing.issubset(unresolved):
            raise ValidationInputError("failed_checks_not_reported")

    expected_flags = {
        "PASS_WITH_EVIDENCE": (0, 1),
        "RETURN_TO_WORKER": (1, 0),
        "BLOCKED": (2, 0),
        "FAIL": (1, 0),
    }
    if (out.get("exit_code"), out.get("compliance_bit")) != expected_flags[result]:
        raise ValidationInputError("result_flags_invalid")

    if result == "PASS_WITH_EVIDENCE":
        if passed != total or unresolved or repairs:
            raise ValidationInputError("pass_without_all_assertions")
        if not _valid_sha256(out.get("input_sha256")):
            raise ValidationInputError("pass_input_sha256_invalid")
    elif result == "RETURN_TO_WORKER" and (not failed or not repairs):
        raise ValidationInputError("return_without_failures_or_repairs")
    elif result == "BLOCKED" and not blocked:
        raise ValidationInputError("blocked_without_assertion")
    elif result == "FAIL" and not failed:
        raise ValidationInputError("fail_without_assertion")

    if out.get("output_sha256") != _canonical_sha256_without_output_hash(out):
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
    if not 0 <= retry_count <= 2:
        raise ValidationInputError("retry_count_out_of_range")

    failed = {_assertion_id(x) for x in failed_assertions if x}
    blocked = {_assertion_id(x) for x in (blocking_assertions or []) if x}
    version = (judge_version or os.getenv("LF_JUDGE_VERSION") or "").strip()
    executor = (executor_identity or os.getenv("LF_EXECUTOR_IDENTITY") or "").strip()
    if not version:
        blocked.add("judge_version_missing")
    if not executor:
        blocked.add("executor_identity_missing")

    checks = evidence.get("checks") if isinstance(evidence, Mapping) else None
    if isinstance(checks, Mapping):
        failed.update(_assertion_id(k) for k, value in checks.items() if _check_failed(value))

    if forced_result is not None and forced_result not in RESULT_VALUES:
        raise ValidationInputError(f"invalid_result:{forced_result}")
    outcome = forced_result or (
        "BLOCKED" if blocked else "RETURN_TO_WORKER" if failed else "PASS_WITH_EVIDENCE"
    )
    if outcome == "PASS_WITH_EVIDENCE" and (failed or blocked):
        blocked.add("forced_pass_with_findings")
        outcome = "BLOCKED"

    refs = list(dict.fromkeys(evidence_refs or [])) or ["evidence:inline"]
    repairs = [dict(item) for item in (repair_instructions or [])]
    if outcome == "RETURN_TO_WORKER" and not repairs:
        repairs = [failure(item, "$", f"Repair assertion: {item}") for item in sorted(failed)]

    assertion_ids = failed | blocked
    total = len(checks) if isinstance(checks, Mapping) else len(assertion_ids)
    total = max(total, len(assertion_ids), 1)

    input_sha256 = evidence.get("input_sha256") if isinstance(evidence, Mapping) else None
    if input_sha256 is not None and not _valid_sha256(input_sha256):
        blocked.add("input_sha256_invalid")
        input_sha256 = None
    if input_sha256 is None and isinstance(evidence, Mapping) and evidence.get("input_path"):
        target = Path(str(evidence["input_path"]))
        if target.is_file():
            input_sha256 = sha256_file(target)
    if outcome == "PASS_WITH_EVIDENCE" and not input_sha256:
        blocked.add("input_sha256_unavailable")
    if blocked:
        outcome = "BLOCKED"

    assertion_ids = failed | blocked
    total = max(total, len(assertion_ids), 1)
    passed = max(total - len(assertion_ids), 0)
    if outcome == "PASS_WITH_EVIDENCE":
        passed = total

    evidence_payload = {
        "evidence_refs": refs,
        "evidence": dict(evidence),
        "repairs": repairs,
    }
    evidence_sha256 = hashlib.sha256(
        json.dumps(
            evidence_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()

    output = {
        "schema_version": SCHEMA_VERSION,
        "judge_code": judge_code,
        "judge_version": version or "MISSING",
        "executor_identity": executor or "MISSING",
        "command": command or " ".join(shlex.quote(arg) for arg in sys.argv),
        "started_at": started_at or utc_now(),
        "completed_at": utc_now(),
        "exit_code": EXIT_BY_RESULT[outcome],
        "result": outcome,
        "compliance_bit": 1 if outcome == "PASS_WITH_EVIDENCE" else 0,
        "assertions_total": total,
        "assertions_passed": passed,
        "failed_assertions": sorted(failed),
        "blocking_assertions": sorted(blocked),
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
    print(json.dumps(out, ensure_ascii=False, sort_keys=True))
    return EXIT_BY_RESULT[str(out["result"])]


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
    seen, duplicates = set(), set()
    for value in values:
        duplicates.add(value) if value in seen else seen.add(value)
    return sorted(duplicates, key=str)


def main_guard(judge_code: str, fn) -> int:
    try:
        return int(fn())
    except ValidationInputError as exc:
        return emit_blocked(judge_code, str(exc))
    except KeyboardInterrupt:
        return emit_blocked(judge_code, "execution_interrupted")
