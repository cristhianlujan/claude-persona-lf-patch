#!/usr/bin/env python3
from __future__ import annotations
import argparse, copy, hashlib, importlib.util, json, os, subprocess, sys, tempfile
from pathlib import Path
from typing import Any
import yaml

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
CONFIG = {
    "A57": {"path": "scripts/calculate_binary_completion.py", "kind": "binary"},
    "A58": {"path": "judges/github-integrity.yaml", "kind": "github", "validator": "scripts/validate_github_integrity.py"},
    "A59": {"path": "judges/integration-close.yaml", "kind": "close", "validator": "scripts/calculate_binary_completion.py"},
}
V05_FIELDS = {
    "schema_version", "judge_code", "judge_version", "executor_identity", "command",
    "started_at", "completed_at", "exit_code", "result", "compliance_bit",
    "assertions_total", "assertions_passed", "failed_assertions", "blocking_assertions",
    "repairs", "repair_instructions", "evidence_refs", "evidence", "evidence_sha256",
    "input_sha256", "output_sha256", "retry_count",
}


def load_module(relative: str, name: str):
    sys.path.insert(0, str(SKILL / "scripts"))
    spec = importlib.util.spec_from_file_location(name, SKILL / relative)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"module_unloadable:{relative}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def runtime_env(metadata: bool = True) -> dict[str, str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(SKILL / "scripts")
    if metadata:
        env.update(LF_JUDGE_VERSION="v0.5", LF_EXECUTOR_IDENTITY="R8_CLOSURE_AUDITOR")
    else:
        env.pop("LF_JUDGE_VERSION", None)
        env.pop("LF_EXECUTOR_IDENTITY", None)
    return env


def parse_emitted(stdout: str) -> dict[str, Any]:
    for line in reversed([line.strip() for line in stdout.splitlines() if line.strip()]):
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("json_output_missing")


def invoke(relative: str, payload: dict[str, Any], metadata: bool = True) -> dict[str, Any]:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "input.json"
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        process = subprocess.run(
            [sys.executable, relative, str(path), "--evidence-ref", f"file:{path}"],
            cwd=SKILL, env=runtime_env(metadata), text=True, capture_output=True, timeout=240,
        )
        try:
            result = parse_emitted(process.stdout)
            return {
                "process_exit_code": process.returncode,
                "result": result.get("result"),
                "failed_assertions": result.get("failed_assertions"),
                "blocking_assertions": result.get("blocking_assertions"),
                "assertions_total": result.get("assertions_total"),
                "assertions_passed": result.get("assertions_passed"),
                "hashes": {key: result.get(key) for key in ("input_sha256", "evidence_sha256", "output_sha256")},
                "checks": result.get("evidence", {}).get("checks"),
            }
        except Exception as exc:
            return {
                "process_exit_code": process.returncode,
                "result": "NO_OUTPUT",
                "error": f"{type(exc).__name__}:{exc}",
                "stdout": process.stdout[-3000:],
                "stderr": process.stderr[-1500:],
            }


def case(name: str, row: dict[str, Any], expected: str) -> dict[str, Any]:
    return {"case": name, "expected": expected, "actual": row.get("result"), "passed": row.get("result") == expected, "details": row}


def static(code: str) -> tuple[bytes, dict[str, bool], float]:
    cfg = CONFIG[code]
    path = SKILL / cfg["path"]
    raw = path.read_bytes()
    text = raw.decode("utf-8")
    if code == "A57":
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
        checks = {
            "python_compile": True,
            "judge_identity": "J13_INTEGRATION_CLOSE" in text,
            "zero_close_fields": all(field in text for field in ("critical_steps_with_bit_zero", "steps_without_evidence", "judges_pending", "sha_mismatches")),
            "recalculates_completion": "calculated = round" in text,
            "rejects_false_close": "required_steps_not_passed" in text and "declared_completion_mismatch" in text,
            "fails_operational_authorization": "production_authorized" in text and "forced = \"FAIL\"" in text,
            "metadata_from_env": 'os.getenv("LF_JUDGE_VERSION")' in text and 'os.getenv("LF_EXECUTOR_IDENTITY")' in text,
            "no_metadata_fallback": "R8_CLOSE_VALIDATOR" not in text and "VERSION =" not in text,
            "self_test": "def self_test" in text and "false_close_rejected" in text,
        }
    else:
        data = yaml.safe_load(text)
        ids = [item.get("assertion_id") for item in data.get("assertions", []) if isinstance(item, dict)]
        expected_count = 10 if code == "A58" else 19
        checks = {
            "yaml_object": isinstance(data, dict),
            "judge_v05": data.get("judge_version") == "v0.5",
            "assertion_count_exact": len(ids) == expected_count and len(set(ids)) == expected_count,
            "validator_exists": (SKILL / cfg["validator"]).is_file(),
            "runtime_available": data.get("validators", {}).get("runtime_status") == "AVAILABLE",
            "pass_fail_block": all(key in data for key in ("pass_if", "fail_if", "block_if")),
            "positive_negative": bool(data.get("positive_behavior")) and len(data.get("negative_cases", [])) >= 4,
            "metadata_block": "executor_identity_missing = true" in data.get("block_if", []) and "judge_version_missing = true" in data.get("block_if", []),
            "output_v05": data.get("output", {}).get("schema_version") == "v0.5" and V05_FIELDS <= set(data.get("output", {}).get("required_fields", [])),
            "no_temporal_stars": "stars_verified" not in text,
            "prohibitions": all(item in data.get("prohibitions", []) for item in ("worker_self_approval", "pass_without_evidence", "pass_without_semantic_runtime")),
        }
    score = 10.0 if all(checks.values()) else round(8 + 2 * sum(checks.values()) / len(checks), 2)
    return raw, checks, score


def binary_cases() -> list[dict[str, Any]]:
    module = load_module("scripts/calculate_binary_completion.py", "r8_binary_completion")
    good = module.positive()
    rows = [case("positive", invoke("scripts/calculate_binary_completion.py", copy.deepcopy(good)), "PASS_WITH_EVIDENCE")]
    broken = copy.deepcopy(good)
    broken["steps"][0]["evidence_refs"] = []
    broken["close_conditions"]["steps_without_evidence"] = 1
    broken["completion_percent"] = 100.0
    rows.append(case("false_100", invoke("scripts/calculate_binary_completion.py", broken), "RETURN_TO_WORKER"))
    unsafe = copy.deepcopy(good)
    unsafe["production_authorized"] = True
    rows.append(case("production_authorized", invoke("scripts/calculate_binary_completion.py", unsafe), "FAIL"))
    missing_steps = copy.deepcopy(good)
    missing_steps["steps"] = []
    rows.append(case("execution_steps_missing", invoke("scripts/calculate_binary_completion.py", missing_steps), "BLOCKED"))
    rows.append(case("missing_metadata", invoke("scripts/calculate_binary_completion.py", copy.deepcopy(good), False), "BLOCKED"))
    process = subprocess.run(
        [sys.executable, "scripts/calculate_binary_completion.py", "--self-test"],
        cwd=SKILL, env=runtime_env(), text=True, capture_output=True, timeout=240,
    )
    result = json.loads(process.stdout.strip().splitlines()[-1])
    rows.append({
        "case": "self_test", "expected": "positive_pass_and_false_close_rejected", "actual": result,
        "passed": result.get("positive_pass") is True and result.get("false_close_rejected") is True,
    })
    return rows


def github_cases() -> list[dict[str, Any]]:
    module = load_module("scripts/validate_github_integrity.py", "r8_github_integrity")
    good = module.positive()
    rows = [case("positive", invoke("scripts/validate_github_integrity.py", copy.deepcopy(good)), "PASS_WITH_EVIDENCE")]
    mismatch = copy.deepcopy(good)
    mismatch["readback_files"][0]["sha256"] = "c" * 64
    rows.append(case("sha_mismatch", invoke("scripts/validate_github_integrity.py", mismatch), "RETURN_TO_WORKER"))
    wrong_branch = copy.deepcopy(good)
    wrong_branch["github_contract"]["target_branch"] = "main"
    rows.append(case("target_main", invoke("scripts/validate_github_integrity.py", wrong_branch), "RETURN_TO_WORKER"))
    direct_main = copy.deepcopy(good)
    direct_main["github_contract"]["direct_main_write_detected"] = True
    rows.append(case("direct_main_write", invoke("scripts/validate_github_integrity.py", direct_main), "FAIL"))
    rows.append(case("missing_metadata", invoke("scripts/validate_github_integrity.py", copy.deepcopy(good), False), "BLOCKED"))
    process = subprocess.run(
        [sys.executable, "scripts/validate_github_integrity.py", "--self-test"],
        cwd=SKILL, env=runtime_env(), text=True, capture_output=True, timeout=240,
    )
    result = json.loads(process.stdout.strip().splitlines()[-1])
    rows.append({
        "case": "self_test", "expected": "positive_pass_and_negative_rejected", "actual": result,
        "passed": result.get("positive_pass") is True and result.get("negative_rejected") is True,
    })
    return rows


def run(code: str, mode: str, report_dir: Path) -> int:
    raw, checks, score = static(code)
    if mode == "static":
        result = "PASS_WITH_EVIDENCE" if score > 9.5 and all(checks.values()) else "RETURN_TO_WORKER"
        out = {
            "artifact_code": code, "relative_path": CONFIG[code]["path"],
            "sha256": hashlib.sha256(raw).hexdigest(), "checks": checks,
            "claude_score": score, "github_score": score, "technical_score": score,
            "final_score": score, "result": result,
            "findings": [key for key, value in checks.items() if not value],
        }
        report_dir.mkdir(parents=True, exist_ok=True)
        (report_dir / f"{code}.json").write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(out, ensure_ascii=False, sort_keys=True))
        return 0 if result == "PASS_WITH_EVIDENCE" else 1
    rows = github_cases() if code == "A58" else binary_cases()
    out = {"artifact": code, "passed": all(item["passed"] for item in rows), "cases": rows, "sha256": hashlib.sha256(raw).hexdigest()}
    print(json.dumps(out, ensure_ascii=False, sort_keys=True))
    return 0 if out["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", choices=CONFIG, required=True)
    parser.add_argument("--mode", choices=("static", "runtime"), required=True)
    parser.add_argument("--report-dir", type=Path, default=ROOT / "audit-results")
    args = parser.parse_args()
    return run(args.artifact, args.mode, args.report_dir)


if __name__ == "__main__":
    raise SystemExit(main())
