#!/usr/bin/env python3
"""Deep static/runtime auditor for judge artifacts A13 through A22."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path
from typing import Any

import jsonschema
import yaml

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
SCRIPTS = SKILL / "scripts"
sys.path.insert(0, str(SCRIPTS))
from lf_common import ValidationInputError, validate_result_invariants  # noqa: E402

REPOS = ("anthropics/skills", "microsoft/vscode", "freeCodeCamp/freeCodeCamp", "Significant-Gravitas/AutoGPT")
RESULT_FIELDS = {
    "schema_version", "judge_code", "judge_version", "executor_identity", "command",
    "started_at", "completed_at", "exit_code", "result", "compliance_bit",
    "assertions_total", "assertions_passed", "failed_assertions", "blocking_assertions",
    "repairs", "repair_instructions", "evidence_refs", "evidence", "evidence_sha256",
    "input_sha256", "output_sha256", "retry_count",
}
CONFIG = {
    "A13": {"path": "judges/analytics-observability.yaml", "judge": "J09_ANALYTICS_OBSERVABILITY", "assertions": 9, "validator": "scripts/detect_pii_telemetry.py", "example_source": "agents/cross-cutting-enricher.md", "example_judge": 9},
    "A14": {"path": "judges/audit-traceability.yaml", "judge": "J07_AUDIT_TRACEABILITY", "assertions": 10, "validator": "scripts/validate_traceability.py", "example_source": "agents/cross-cutting-enricher.md", "example_judge": 7},
    "A15": {"path": "judges/field-contracts.yaml", "judge": "J04_FIELD_CONTRACTS", "assertions": 10, "validator": "scripts/validate_field_coverage.py", "example_source": "agents/field-contract-author.md", "example_judge": 4, "case_ids": ("E23_FIELD_CONTRACTS_POSITIVE", "E24_FIELD_CONTRACTS_NEGATIVE")},
    "A16": {"path": "judges/observations-errors.yaml", "judge": "J05_OBSERVATIONS_ERRORS", "assertions": 7, "validator": "scripts/validate_field_coverage.py", "example_source": "agents/cross-cutting-enricher.md", "example_judge": 5, "case_ids": ("E23_FIELD_CONTRACTS_POSITIVE", "E24_FIELD_CONTRACTS_NEGATIVE")},
    "A17": {"path": "judges/screen-decomposition.yaml", "judge": "J02_SCREEN_DECOMPOSITION", "assertions": 12, "validator": "scripts/validate_screen_decomposition.py", "example_source": "agents/screen-decomposer.md", "example_judge": 2},
    "A18": {"path": "judges/security-privacy.yaml", "judge": "J06_SECURITY_PRIVACY", "assertions": 9, "validator": "scripts/validate_security_coverage.py", "example_source": "agents/cross-cutting-enricher.md", "example_judge": 6},
    "A19": {"path": "judges/skill-package.yaml", "judge": "J11_SKILL_PACKAGE", "assertions": 10, "validator": "scripts/validate_package.py", "special": "package"},
    "A20": {"path": "judges/story-core.yaml", "judge": "J03_STORY_CORE", "assertions": 8, "validator": "scripts/validate_story_pack.py", "special": "story"},
    "A21": {"path": "judges/test-coverage.yaml", "judge": "J10_TEST_COVERAGE", "assertions": 13, "validator": "scripts/validate_test_coverage.py", "example_source": "agents/test-deriver.md", "example_judge": 10},
    "A22": {"path": "judges/tokens-messages.yaml", "judge": "J08_TOKENS_MESSAGES", "assertions": 11, "validator": "scripts/validate_tokens.py", "example_source": "agents/cross-cutting-enricher.md", "example_judge": 8},
}
FENCE = re.compile(r"```json\n(.*?)\n```", re.S)
HEADING = re.compile(r"^(#{2,4})\s+(.+?)\s*$", re.M)


def repo_stars(repo: str) -> int:
    request = urllib.request.Request(f"https://api.github.com/repos/{repo}", headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-judge-audit"})
    token = os.getenv("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=30) as response:
        return int(json.load(response)["stargazers_count"])


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


def nested(data: dict[str, Any], *paths: tuple[str, ...]) -> Any:
    for path in paths:
        value: Any = data
        for key in path:
            if not isinstance(value, dict) or key not in value:
                value = None
                break
            value = value[key]
        if value is not None:
            return value
    return None


def assertion_ids(data: dict[str, Any]) -> list[str]:
    rows = data.get("assertions")
    if not isinstance(rows, list):
        return []
    result: list[str] = []
    for item in rows:
        if isinstance(item, str):
            result.append(item)
        elif isinstance(item, dict):
            value = item.get("assertion_id") or item.get("id") or item.get("code")
            if isinstance(value, str):
                result.append(value)
    return result


def output_fields(data: dict[str, Any]) -> set[str]:
    output = data.get("output")
    return set(output.get("required_fields", [])) if isinstance(output, dict) and isinstance(output.get("required_fields"), list) else set()


def validator_path(data: dict[str, Any], fallback: str) -> str:
    value = nested(
        data,
        ("validator", "entrypoint"),
        ("validators", "semantic_validator_ref"),
        ("validator_ref",),
    )
    return str(value or fallback).split("#", 1)[0]


def positive_declared(data: dict[str, Any]) -> bool:
    return bool(data.get("positive_behavior") or data.get("positive_case") or data.get("self_test_command") or data.get("evals"))


def negative_declared(data: dict[str, Any]) -> bool:
    return bool(data.get("negative_behavior") or data.get("negative_cases") or data.get("negative_case") or data.get("evals"))


def static_audit(code: str, report_dir: Path) -> int:
    cfg = CONFIG[code]
    path = SKILL / cfg["path"]
    raw = path.read_bytes()
    data = yaml.safe_load(raw.decode("utf-8"))
    if not isinstance(data, dict):
        raise SystemExit("judge_yaml_must_be_object")
    ids = assertion_ids(data)
    version = data.get("judge_version") or data.get("version")
    result_values = set(data.get("result_values", []))
    validator = validator_path(data, cfg["validator"])
    validator_file = SKILL / validator
    stored_blob = nested(data, ("validator", "git_blob_sha1"))
    external = {repo: repo_stars(repo) for repo in REPOS}
    fields = output_fields(data)
    checks = {
        "judge_code_matches": data.get("judge_code") == cfg["judge"],
        "version_v05": version == "v0.5",
        "candidate_read_only": data.get("status") == "CANDIDATO_READ_ONLY",
        "retry_limit_two": data.get("retry_limit") == 2,
        "required_inputs_present": isinstance(data.get("required_inputs"), list) and bool(data["required_inputs"]),
        "preflight_present": isinstance(data.get("preflight"), list) and bool(data["preflight"]),
        "assertion_count_exact": len(ids) == cfg["assertions"] and len(set(ids)) == len(ids),
        "validator_path_matches": validator == cfg["validator"] and validator_file.is_file(),
        "validator_blob_matches_if_declared": not stored_blob or stored_blob == git_blob_sha(validator_file.read_bytes()),
        "result_values_complete": result_values == {"PASS_WITH_EVIDENCE", "RETURN_TO_WORKER", "BLOCKED", "FAIL"},
        "pass_block_fail_rules_present": bool(data.get("pass_if")) and bool(data.get("block_if")) and bool(data.get("fail_if")),
        "positive_declared": positive_declared(data),
        "negative_declared": negative_declared(data),
        "repair_matrix_present": bool(data.get("repair_matrix")),
        "prohibitions_present": bool(data.get("prohibitions")),
        "judge_result_schema_ref": nested(data, ("output", "schema_ref")) == "schemas/judge-result.schema.json",
        "v05_output_fields_complete": RESULT_FIELDS.issubset(fields),
        "legacy_judged_at_absent": "judged_at" not in fields,
        "all_repos_over_150k": all(value > 150000 for value in external.values()),
    }
    passed = all(checks.values())
    score = 10.0 if passed else round(8.0 + 2.0 * sum(checks.values()) / len(checks), 2)
    report = {
        "artifact_code": code,
        "relative_path": cfg["path"],
        "sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
        "checks": checks,
        "assertion_ids": ids,
        "validator": validator,
        "validator_git_blob_sha1": git_blob_sha(validator_file.read_bytes()) if validator_file.is_file() else None,
        "benchmark_stars": external,
        "claude_score": score,
        "github_score": score,
        "technical_score": score,
        "final_score": score,
        "result": "PASS_WITH_EVIDENCE" if passed and score > 9.5 else "RETURN_TO_WORKER",
        "findings": [name for name, ok in checks.items() if not ok],
    }
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / f"{code}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (report_dir / f"{code}.md").write_text(f"# {code} — {cfg['path']}\n\n- Resultado: **{report['result']}**\n- Nota final: **{score:.2f}**\n- SHA-256: `{report['sha256']}`\n", encoding="utf-8")
    print(json.dumps({"artifact": code, "result": report["result"], "final_score": score, "findings": report["findings"]}, sort_keys=True))
    return 0 if report["result"] == "PASS_WITH_EVIDENCE" else 1


def heading_before(text: str, position: int) -> str:
    heading = ""
    for match in HEADING.finditer(text, 0, position):
        heading = match.group(2).strip()
    return heading


def examples(relative_path: str) -> dict[str, dict[str, Any]]:
    text = (SKILL / relative_path).read_text(encoding="utf-8")
    result: dict[str, dict[str, Any]] = {}
    for match in FENCE.finditer(text):
        title = heading_before(text, match.start())
        if title.lower().startswith("caso positivo") or title.lower().startswith("caso negativo"):
            result[title] = json.loads(match.group(1))
    return result


def parse_emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("judge_json_output_missing")


def runtime_env(with_metadata: bool) -> dict[str, str]:
    value = os.environ.copy()
    if with_metadata:
        value.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_INDEPENDENT_JUDGE_RUNNER")
    else:
        value.pop("LF_JUDGE_VERSION", None)
        value.pop("LF_EXECUTOR_IDENTITY", None)
    return value


def validate_envelope(result: dict[str, Any], expected_judge: str, expected_result: str, input_path: Path | None = None) -> list[str]:
    errors: list[str] = []
    schema = json.loads((SKILL / "schemas/judge-result.schema.json").read_text(encoding="utf-8"))
    try:
        jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker()).validate(result)
    except Exception as exc:
        errors.append(f"schema:{type(exc).__name__}:{exc}")
    try:
        validate_result_invariants(result)
    except ValidationInputError as exc:
        errors.append(f"invariants:{exc}")
    if result.get("judge_code") != expected_judge:
        errors.append(f"judge_code:{result.get('judge_code')}")
    if result.get("result") != expected_result:
        errors.append(f"result:{result.get('result')}!={expected_result}")
    if input_path is not None and input_path.is_file() and result.get("input_sha256") not in {None, hashlib.sha256(input_path.read_bytes()).hexdigest()}:
        errors.append("input_sha256_mismatch")
    return errors


def command_for_direct(cfg: dict[str, Any], input_path: Path, with_metadata: bool) -> list[str]:
    script = cfg["validator"]
    command = [sys.executable, script, str(input_path)]
    judge = cfg["judge"]
    if script == "scripts/validate_field_coverage.py":
        command += ["--judge", judge]
    elif script in {"scripts/detect_pii_telemetry.py", "scripts/validate_traceability.py", "scripts/validate_security_coverage.py", "scripts/validate_tokens.py"} and with_metadata:
        command += ["--judge-version", "v0.5", "--executor-identity", "R8_INDEPENDENT_JUDGE_RUNNER"]
    command += ["--evidence-ref", f"file:{input_path}"]
    return command


def run_payload(cfg: dict[str, Any], title: str, payload: dict[str, Any], expected_result: str, with_metadata: bool = True) -> dict[str, Any]:
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8", delete=False) as handle:
        json.dump(payload, handle, ensure_ascii=False)
        handle.write("\n")
        input_path = Path(handle.name)
    command = command_for_direct(cfg, input_path, with_metadata)
    proc = subprocess.run(command, cwd=SKILL, env=runtime_env(with_metadata), text=True, capture_output=True, timeout=180)
    try:
        result = parse_emitted(proc.stdout)
        errors = validate_envelope(result, cfg["judge"], expected_result, input_path)
        return {
            "title": title,
            "passed": not errors,
            "command": command,
            "process_exit_code": proc.returncode,
            "expected_result": expected_result,
            "actual_result": result.get("result"),
            "failed_assertions": result.get("failed_assertions"),
            "blocking_assertions": result.get("blocking_assertions"),
            "assertions_total": result.get("assertions_total"),
            "assertions_passed": result.get("assertions_passed"),
            "input_sha256": result.get("input_sha256"),
            "evidence_sha256": result.get("evidence_sha256"),
            "output_sha256": result.get("output_sha256"),
            "envelope_errors": errors,
            "evidence_checks": result.get("evidence", {}).get("checks"),
        }
    except Exception as exc:
        return {"title": title, "passed": False, "command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-4000:], "stderr": proc.stderr[-2000:], "error": f"{type(exc).__name__}:{exc}"}
    finally:
        input_path.unlink(missing_ok=True)


def run_case_id(cfg: dict[str, Any], case_id: str, expected_candidate: str) -> dict[str, Any]:
    command = [sys.executable, cfg["validator"], "--case-id", case_id]
    if cfg["validator"] == "scripts/validate_field_coverage.py":
        command += ["--judge", cfg["judge"]]
    proc = subprocess.run(command, cwd=SKILL, env=runtime_env(True), text=True, capture_output=True, timeout=180)
    try:
        result = parse_emitted(proc.stdout)
        evidence = result.get("evidence", {})
        errors = validate_envelope(result, cfg["judge"], "PASS_WITH_EVIDENCE")
        if evidence.get("actual_validation_result") != expected_candidate:
            errors.append(f"candidate:{evidence.get('actual_validation_result')}!={expected_candidate}")
        if evidence.get("matched") is not True:
            errors.append("candidate_expectation_not_matched")
        if expected_candidate == "RETURN_TO_WORKER" and evidence.get("negative_must_be_rejected") is not True:
            errors.append("negative_not_marked_rejected")
        return {
            "title": case_id,
            "passed": not errors,
            "command": command,
            "process_exit_code": proc.returncode,
            "wrapper_result": result.get("result"),
            "candidate_result": evidence.get("actual_validation_result"),
            "candidate_failed_assertions": evidence.get("candidate_failed_assertions"),
            "envelope_errors": errors,
            "input_sha256": result.get("input_sha256"),
            "evidence_sha256": result.get("evidence_sha256"),
            "output_sha256": result.get("output_sha256"),
        }
    except Exception as exc:
        return {"title": case_id, "passed": False, "command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-4000:], "stderr": proc.stderr[-2000:], "error": f"{type(exc).__name__}:{exc}"}


def run_self_test(cfg: dict[str, Any]) -> dict[str, Any]:
    command = [sys.executable, cfg["validator"], "--self-test"]
    proc = subprocess.run(command, cwd=SKILL, env=runtime_env(True), text=True, capture_output=True, timeout=240)
    try:
        result = parse_emitted(proc.stdout)
        positive = result.get("positive_pass") is True or result.get("result") == "PASS_WITH_EVIDENCE" or result.get("self_test", {}).get("positive", {}).get("consistency_pass") is True
        negative = result.get("negative_rejected") is True or bool(result.get("negative_failed")) or result.get("self_test", {}).get("negative", {}).get("consistency_pass") is False or all(item.get("matched") is True for item in result.get("outcomes", []) if isinstance(item, dict))
        passed = proc.returncode == 0 and positive and negative
        return {"title": "SELF_TEST", "passed": passed, "command": command, "process_exit_code": proc.returncode, "result": result}
    except Exception as exc:
        return {"title": "SELF_TEST", "passed": False, "command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-5000:], "stderr": proc.stderr[-2500:], "error": f"{type(exc).__name__}:{exc}"}


def runtime_audit(code: str, report_dir: Path) -> int:
    cfg = CONFIG[code]
    executions: list[dict[str, Any]] = []
    special = cfg.get("special")
    if special == "story":
        executions += [
            run_case_id(cfg, "E21_STORY_CORE_POSITIVE", "PASS_WITH_EVIDENCE"),
            run_case_id(cfg, "E22_STORY_CORE_NEGATIVE", "RETURN_TO_WORKER"),
            run_self_test(cfg),
        ]
    elif special == "package":
        executions.append(run_self_test(cfg))
    elif cfg.get("case_ids"):
        positive, negative = cfg["case_ids"]
        executions += [
            run_case_id(cfg, positive, "PASS_WITH_EVIDENCE"),
            run_case_id(cfg, negative, "RETURN_TO_WORKER"),
            run_self_test(cfg),
        ]
        source_examples = examples(cfg["example_source"])
        positive_payload = source_examples.get(f"Caso positivo J{cfg['example_judge']:02d}")
        if isinstance(positive_payload, dict):
            executions.append(run_payload(cfg, "MISSING_METADATA", positive_payload, "BLOCKED", with_metadata=False))
    else:
        source_examples = examples(cfg["example_source"])
        positive_payload = source_examples.get(f"Caso positivo J{cfg['example_judge']:02d}")
        negative_payload = source_examples.get(f"Caso negativo J{cfg['example_judge']:02d}")
        if not isinstance(positive_payload, dict) or not isinstance(negative_payload, dict):
            executions.append({"title": "EXAMPLES", "passed": False, "error": "positive_or_negative_example_missing"})
        else:
            executions += [
                run_payload(cfg, "POSITIVE", positive_payload, "PASS_WITH_EVIDENCE"),
                run_payload(cfg, "NEGATIVE", negative_payload, "RETURN_TO_WORKER"),
                run_payload(cfg, "MISSING_METADATA", positive_payload, "BLOCKED", with_metadata=False),
            ]
            if code in {"A17", "A21"}:
                executions.append(run_self_test(cfg))

    yaml_data = yaml.safe_load((SKILL / cfg["path"]).read_text(encoding="utf-8"))
    yaml_ids = set(assertion_ids(yaml_data)) if isinstance(yaml_data, dict) else set()
    positive_checks: set[str] = set()
    for execution in executions:
        if execution.get("title") in {"POSITIVE", cfg.get("case_ids", (None,))[0] if cfg.get("case_ids") else None}:
            checks = execution.get("evidence_checks")
            if isinstance(checks, dict):
                positive_checks |= set(checks)
    checks = {
        "all_executions_pass": bool(executions) and all(item.get("passed") is True for item in executions),
        "positive_and_negative_present": any(item.get("title") in {"POSITIVE", "E21_STORY_CORE_POSITIVE", "E23_FIELD_CONTRACTS_POSITIVE"} for item in executions) and any(item.get("title") in {"NEGATIVE", "E22_STORY_CORE_NEGATIVE", "E24_FIELD_CONTRACTS_NEGATIVE"} for item in executions),
        "metadata_block_test_present": special in {"story", "package"} or any(item.get("title") == "MISSING_METADATA" for item in executions),
        "yaml_assertions_nonempty": len(yaml_ids) == cfg["assertions"],
        "runtime_outputs_hashed_when_enveloped": all(
            item.get("title") in {"SELF_TEST"}
            or all(isinstance(item.get(key), str) and len(item[key]) == 64 for key in ("input_sha256", "evidence_sha256", "output_sha256"))
            for item in executions
            if item.get("passed") and item.get("title") != "SELF_TEST"
        ),
    }
    passed = all(checks.values())
    output = {"artifact": code, "passed": passed, "checks": checks, "yaml_assertion_ids": sorted(yaml_ids), "executions": executions}
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / f"{code}-runtime.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", choices=sorted(CONFIG), required=True)
    parser.add_argument("--mode", choices=("static", "runtime"), required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    args = parser.parse_args()
    return static_audit(args.artifact, args.report_dir) if args.mode == "static" else runtime_audit(args.artifact, args.report_dir)


if __name__ == "__main__":
    raise SystemExit(main())
