#!/usr/bin/env python3
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "LF_GATE_ERROR_V1"
PRODUCER = "LF_GATE_ERROR_RUNNER_V1"
DEFAULT_SCHEMA_REF = "gobernanza/contracts/lf_gate_error_v1.schema.json"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def manifest_digest(manifest: dict[str, Any]) -> str:
    payload = dict(manifest)
    payload.pop("manifest_sha256", None)
    return sha256_bytes(canonical_json(payload).encode("utf-8"))


def write_text(path: Path, text: str) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return sha256_bytes(path.read_bytes())


def last_nonempty_line(text: str) -> str:
    for line in reversed(text.splitlines()):
        if line.strip():
            return line.strip()
    return ""


def classify_error(stderr: str, stdout: str, returncode: int) -> tuple[str, str, str | None]:
    combined = stderr if stderr.strip() else stdout
    lines = [line.strip() for line in combined.splitlines() if line.strip()]
    preferred = ""
    error_pattern = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*(?:Error|Exception)|AssertionError|SystemExit)(?::|$)")
    for line in reversed(lines):
        if error_pattern.match(line):
            preferred = line
            break
    summary = preferred or (lines[-1] if lines else f"PROCESS_EXIT_{returncode}")
    match = error_pattern.match(summary)
    error_class = match.group(1) if match else "PROCESS_EXIT"
    assertion_text = summary if summary.startswith("AssertionError") else None
    return error_class, summary, assertion_text


def safe_stem(test_file: str, index: int) -> str:
    name = Path(test_file).name.replace(".py", "")
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", name)
    path_hash = sha256_bytes(test_file.encode("utf-8"))[:10]
    return f"{index:03d}-{cleaned}-{path_hash}"


def resolve_source_sha(explicit: str | None) -> str:
    candidate = (explicit or os.environ.get("GITHUB_SHA") or "").strip().lower()
    if re.fullmatch(r"[0-9a-f]{40}", candidate):
        return candidate
    try:
        candidate = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip().lower()
    except Exception:
        candidate = ""
    if not re.fullmatch(r"[0-9a-f]{40}", candidate):
        raise SystemExit("LF_GATE_ERROR_V1_SOURCE_SHA_INVALID")
    return candidate


def validate_manifest(manifest: dict[str, Any], output_dir: Path) -> list[str]:
    errors: list[str] = []
    required = {
        "schema_version",
        "producer",
        "suite_code",
        "source_sha",
        "run_id",
        "job_name",
        "schema_ref",
        "schema_sha256",
        "test_pattern",
        "test_count",
        "failure_count",
        "control_errors",
        "failures",
        "diagnostic_complete",
        "manifest_sha256",
    }
    missing = sorted(required - set(manifest))
    if missing:
        errors.append("MISSING_KEYS:" + ",".join(missing))
        return errors
    if manifest.get("schema_version") != SCHEMA_VERSION:
        errors.append("SCHEMA_VERSION_INVALID")
    if manifest.get("producer") != PRODUCER:
        errors.append("PRODUCER_INVALID")
    if not re.fullmatch(r"[0-9a-f]{40}", str(manifest.get("source_sha", ""))):
        errors.append("SOURCE_SHA_INVALID")
    if manifest.get("failure_count") != len(manifest.get("failures") or []):
        errors.append("FAILURE_COUNT_MISMATCH")
    if manifest.get("test_count", 0) < manifest.get("failure_count", 0):
        errors.append("TEST_FAILURE_COUNT_INVALID")
    if manifest.get("manifest_sha256") != manifest_digest(manifest):
        errors.append("MANIFEST_SHA256_MISMATCH")
    for failure in manifest.get("failures") or []:
        for path_key, sha_key in (
            ("stdout_path", "stdout_sha256"),
            ("stderr_path", "stderr_sha256"),
            ("traceback_path", "traceback_sha256"),
        ):
            rel = failure.get(path_key)
            if not rel:
                errors.append(f"{path_key.upper()}_MISSING")
                continue
            path = output_dir / rel
            if not path.is_file():
                errors.append(f"ARTIFACT_MISSING:{rel}")
                continue
            observed = sha256_bytes(path.read_bytes())
            if observed != failure.get(sha_key):
                errors.append(f"ARTIFACT_SHA256_MISMATCH:{rel}")
        if not failure.get("test_file"):
            errors.append("TEST_FILE_MISSING")
        if not failure.get("error_summary"):
            errors.append("ERROR_SUMMARY_MISSING")
        if failure.get("diagnostic_complete") is not True:
            errors.append("FAILURE_DIAGNOSTIC_INCOMPLETE")
    return errors


def write_manifest(output_dir: Path, manifest: dict[str, Any]) -> Path:
    manifest["manifest_sha256"] = manifest_digest(manifest)
    manifest_path = output_dir / "lf_gate_error_v1.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest_path


def run_suite(
    *,
    suite_code: str,
    pattern: str,
    output_dir: Path,
    source_sha: str,
    run_id: str,
    job_name: str,
    schema_ref: str,
    python_executable: str,
    echo: bool = True,
) -> tuple[int, dict[str, Any], Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    schema_path = Path(schema_ref)
    control_errors: list[dict[str, str]] = []
    if not schema_path.is_file():
        control_errors.append({"code": "LF_GATE_ERROR_V1_SCHEMA_MISSING", "detail": schema_ref})
        schema_sha256 = "0" * 64
    else:
        schema_sha256 = sha256_bytes(schema_path.read_bytes())

    tests = sorted(path for path in glob.glob(pattern, recursive=True) if Path(path).is_file())
    if not tests:
        control_errors.append({"code": "LF_GATE_ERROR_V1_TESTS_MISSING", "detail": pattern})

    failures: list[dict[str, Any]] = []
    for index, test_file in enumerate(tests, start=1):
        command = [python_executable, test_file]
        if echo:
            print(f"LF_GATE_ERROR_V1_RUNNING={test_file}")
        completed = subprocess.run(command, capture_output=True, text=True)
        if echo and completed.stdout:
            sys.stdout.write(completed.stdout)
            if not completed.stdout.endswith("\n"):
                sys.stdout.write("\n")
        if echo and completed.stderr:
            sys.stderr.write(completed.stderr)
            if not completed.stderr.endswith("\n"):
                sys.stderr.write("\n")
        if completed.returncode == 0:
            if echo:
                print(f"LF_GATE_ERROR_V1_RESULT=PASS TEST={test_file}")
            continue

        stem = safe_stem(test_file, index)
        stdout_rel = f"failures/{stem}.stdout.log"
        stderr_rel = f"failures/{stem}.stderr.log"
        stdout_sha = write_text(output_dir / stdout_rel, completed.stdout)
        stderr_sha = write_text(output_dir / stderr_rel, completed.stderr)
        error_class, error_summary, assertion_text = classify_error(
            completed.stderr, completed.stdout, completed.returncode
        )
        if completed.stderr.strip():
            traceback_rel = stderr_rel
            traceback_sha = stderr_sha
        else:
            traceback_rel = stdout_rel
            traceback_sha = stdout_sha
        failure_id = sha256_bytes(
            canonical_json(
                {
                    "suite_code": suite_code,
                    "test_file": test_file,
                    "exit_code": completed.returncode,
                    "stdout_sha256": stdout_sha,
                    "stderr_sha256": stderr_sha,
                }
            ).encode("utf-8")
        )
        failure = {
            "failure_id": failure_id,
            "test_file": test_file,
            "command": command,
            "exit_code": completed.returncode,
            "error_class": error_class,
            "error_summary": error_summary,
            "assertion_text": assertion_text,
            "stdout_path": stdout_rel,
            "stdout_sha256": stdout_sha,
            "stderr_path": stderr_rel,
            "stderr_sha256": stderr_sha,
            "traceback_path": traceback_rel,
            "traceback_sha256": traceback_sha,
            "diagnostic_complete": bool(test_file and error_summary and traceback_rel and traceback_sha),
        }
        failures.append(failure)
        if echo:
            print(
                "LF_GATE_ERROR_V1_RESULT=FAIL "
                f"RC={completed.returncode} TEST={test_file} ERROR={error_summary}"
            )

    diagnostic_complete = not control_errors and all(
        item.get("diagnostic_complete") is True for item in failures
    )
    manifest: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "producer": PRODUCER,
        "suite_code": suite_code,
        "source_sha": source_sha,
        "run_id": run_id,
        "job_name": job_name,
        "schema_ref": schema_ref,
        "schema_sha256": schema_sha256,
        "test_pattern": pattern,
        "test_count": len(tests),
        "failure_count": len(failures),
        "control_errors": control_errors,
        "failures": failures,
        "diagnostic_complete": diagnostic_complete,
        "manifest_sha256": "",
    }
    manifest_path = write_manifest(output_dir, manifest)
    validation_errors = validate_manifest(manifest, output_dir)
    if validation_errors:
        raise SystemExit("LF_GATE_ERROR_V1_MANIFEST_INVALID:" + "|".join(validation_errors))

    if echo:
        print(f"LF_GATE_ERROR_V1_MANIFEST={manifest_path}")
        print(f"LF_GATE_ERROR_V1_TEST_COUNT={manifest['test_count']}")
        print(f"LF_GATE_ERROR_V1_FAILURE_COUNT={manifest['failure_count']}")
        print(f"LF_GATE_ERROR_V1_DIAGNOSTIC_COMPLETE={str(manifest['diagnostic_complete']).lower()}")
        print(f"LF_GATE_ERROR_V1_MANIFEST_SHA256={manifest['manifest_sha256']}")

    if control_errors:
        return 2, manifest, manifest_path
    if failures:
        return 1, manifest, manifest_path
    return 0, manifest, manifest_path


def self_test() -> int:
    schema_ref = str(Path(__file__).resolve().parents[1] / "contracts" / "lf_gate_error_v1.schema.json")
    with tempfile.TemporaryDirectory(prefix="lf-gate-error-v1-") as td:
        root = Path(td)
        tests_dir = root / "tests"
        tests_dir.mkdir()
        (tests_dir / "test_01_pass.py").write_text("print('PASS_SENTINEL')\n", encoding="utf-8")
        (tests_dir / "test_02_assert.py").write_text(
            "assert False, 'expected_deterministic_failure'\n", encoding="utf-8"
        )
        (tests_dir / "test_03_value.py").write_text(
            "raise ValueError('second_failure_not_collapsed')\n", encoding="utf-8"
        )
        rc, manifest, _ = run_suite(
            suite_code="SELFTEST",
            pattern=str(tests_dir / "test_*.py"),
            output_dir=root / "out",
            source_sha="a" * 40,
            run_id="SELFTEST-RUN",
            job_name="SELFTEST-JOB",
            schema_ref=schema_ref,
            python_executable=sys.executable,
            echo=False,
        )
        assert rc == 1, rc
        assert manifest["test_count"] == 3, manifest
        assert manifest["failure_count"] == 2, manifest
        assert len({x["failure_id"] for x in manifest["failures"]}) == 2, manifest
        assert any(
            x["assertion_text"] == "AssertionError: expected_deterministic_failure"
            for x in manifest["failures"]
        ), manifest
        assert any(
            x["error_summary"] == "ValueError: second_failure_not_collapsed"
            for x in manifest["failures"]
        ), manifest
        assert not validate_manifest(manifest, root / "out"), manifest

        rc_missing, manifest_missing, _ = run_suite(
            suite_code="SELFTEST-MISSING",
            pattern=str(tests_dir / "does_not_exist_*.py"),
            output_dir=root / "out-missing",
            source_sha="b" * 40,
            run_id="SELFTEST-MISSING-RUN",
            job_name="SELFTEST-MISSING-JOB",
            schema_ref=schema_ref,
            python_executable=sys.executable,
            echo=False,
        )
        assert rc_missing == 2, rc_missing
        assert manifest_missing["diagnostic_complete"] is False
        assert manifest_missing["control_errors"] == [
            {
                "code": "LF_GATE_ERROR_V1_TESTS_MISSING",
                "detail": str(tests_dir / "does_not_exist_*.py"),
            }
        ]

        first = manifest["failures"][0]
        tamper_path = root / "out" / first["traceback_path"]
        tamper_path.write_text(tamper_path.read_text(encoding="utf-8") + "TAMPER\n", encoding="utf-8")
        tamper_errors = validate_manifest(manifest, root / "out")
        assert any(item.startswith("ARTIFACT_SHA256_MISMATCH:") for item in tamper_errors), tamper_errors

    print("PASS_LF_GATE_ERROR_V1_SELF_TEST cases=single_assertion,multi_failure,missing_test,tamper_hash")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run LF gate tests and persist deterministic failure evidence")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--suite-code")
    parser.add_argument("--pattern")
    parser.add_argument("--output-dir")
    parser.add_argument("--source-sha")
    parser.add_argument("--run-id", default=os.environ.get("GITHUB_RUN_ID", "LOCAL"))
    parser.add_argument("--job-name", default=os.environ.get("GITHUB_JOB", "LOCAL"))
    parser.add_argument("--schema-ref", default=DEFAULT_SCHEMA_REF)
    parser.add_argument("--python", dest="python_executable", default=sys.executable)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    for field in ("suite_code", "pattern", "output_dir"):
        if not getattr(args, field):
            raise SystemExit(f"LF_GATE_ERROR_V1_ARG_MISSING:{field}")
    source_sha = resolve_source_sha(args.source_sha)
    rc, _, _ = run_suite(
        suite_code=args.suite_code,
        pattern=args.pattern,
        output_dir=Path(args.output_dir),
        source_sha=source_sha,
        run_id=str(args.run_id),
        job_name=str(args.job_name),
        schema_ref=args.schema_ref,
        python_executable=args.python_executable,
        echo=True,
    )
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
