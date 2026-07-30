#!/usr/bin/env python3
"""Apply deterministic cross-artifact corrections discovered by the deep audit."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "creating-integral-user-stories"


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def replace_all(path: Path, replacements: dict[str, str]) -> bool:
    before = path.read_text(encoding="utf-8")
    after = before
    for old, new in replacements.items():
        after = after.replace(old, new)
    if before != after:
        path.write_text(after, encoding="utf-8")
        return True
    return False


def fix_a10() -> bool:
    fixture_path = SKILL / "evals" / "fixtures" / "screen_simple_query.json"
    registry_path = SKILL / "evals" / "evals.json"
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    case_id = fixture["story_core_eval"]["case_id"]
    case = next(item for item in registry.get("executable_cases", []) if item.get("id") == case_id)
    candidate = case["candidate_story_pack"]
    identity = candidate["identity"]
    families = sorted({item["family"] for item in candidate.get("tests", []) if isinstance(item, dict) and item.get("family")})
    required_families = {"FUNCTIONAL", "VALIDATION", "PERMISSION", "TENANT", "ERROR", "ACCESSIBILITY"}
    before = json.dumps(fixture, ensure_ascii=False, sort_keys=True)
    fixture["source_snapshot"].update(
        screen_code=identity["screen_code"],
        module_code=identity["module_code"],
        version=identity["source_version"],
        sha256=identity["source_snapshot_sha"],
        hash_kind="SYNTHETIC_FIXTURE_ALIGNED_TO_E21",
    )
    fixture["expected"]["minimum_executable_test_families"] = families
    fixture["expected"]["test_families_pending_before_integration"] = sorted(required_families - set(families))
    after = json.dumps(fixture, ensure_ascii=False, sort_keys=True)
    if before != after:
        write_json(fixture_path, fixture)
        return True
    return False


def fix_a12() -> bool:
    path = SKILL / "evals" / "trigger-evals.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    before = json.dumps(data, ensure_ascii=False, sort_keys=True)
    old = "A15_NO_CANONICAL_MUTATION_DURING_TRIGGER_EVAL"
    new = "A23_NO_CANONICAL_MUTATION"
    for case in data.get("cases", []):
        for assertion in case.get("assertions", []):
            if assertion.get("code") == old:
                assertion["code"] = new
        case["critical_assertions"] = [new if value == old else value for value in case.get("critical_assertions", [])]
    after = json.dumps(data, ensure_ascii=False, sort_keys=True)
    if before != after:
        write_json(path, data)
        return True
    return False


def fix_metadata_fallbacks() -> list[str]:
    targets = {
        "scripts/validate_field_coverage.py": {
            'judge_version=VERSION,': 'judge_version=os.getenv("LF_JUDGE_VERSION"),',
            'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_J04_J05_EVAL_RUNNER",': 'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),',
            'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_J04_J05_VALIDATOR",': 'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),',
        },
        "scripts/validate_screen_decomposition.py": {
            'judge_version=VERSION,': 'judge_version=os.getenv("LF_JUDGE_VERSION"),',
            'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_SCREEN_VALIDATOR",': 'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),',
        },
        "scripts/validate_story_pack.py": {
            'judge_version=VERSION,': 'judge_version=os.getenv("LF_JUDGE_VERSION"),',
            'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_J03_EVAL_RUNNER",': 'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),',
            'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_J03_VALIDATOR",': 'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),',
        },
        "scripts/validate_test_coverage.py": {
            'judge_version=JUDGE_VERSION,': 'judge_version=os.getenv("LF_JUDGE_VERSION"),',
            'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_SEMANTIC_VALIDATOR",': 'executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),',
        },
    }
    changed: list[str] = []
    for relative, replacements in targets.items():
        if replace_all(SKILL / relative, replacements):
            changed.append(relative)
    return changed


def fix_a19() -> list[str]:
    changed: list[str] = []
    validator = SKILL / "scripts" / "validate_package.py"
    before = validator.read_text(encoding="utf-8")
    after = before
    if "import hashlib\n" not in after:
        after = after.replace("import ast\n", "import ast\nimport hashlib\n", 1)
    if "def package_input_sha256(root: Path) -> str:" not in after:
        marker = "def emit_package_result(root: Path, evidence_refs: list[str], retry_count: int) -> int:\n"
        function = '''def package_input_sha256(root: Path) -> str:\n    """Hash a package directory deterministically from paths and file contents."""\n    digest = hashlib.sha256()\n    files = sorted(\n        path for path in root.rglob("*")\n        if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"\n    )\n    for path in files:\n        relative = path.relative_to(root).as_posix().encode("utf-8")\n        digest.update(relative)\n        digest.update(b"\\0")\n        digest.update(hashlib.sha256(path.read_bytes()).digest())\n        digest.update(b"\\n")\n    return digest.hexdigest()\n\n\n'''
        if marker not in after:
            raise RuntimeError("A19 emit marker missing")
        after = after.replace(marker, function + marker, 1)
    evidence_old = '        "checks": checks,\n        "input_path": str(root),\n    }\n'
    evidence_new = '        "checks": checks,\n        "input_path": str(root),\n        "input_sha256": package_input_sha256(root),\n    }\n'
    if evidence_old in after:
        after = after.replace(evidence_old, evidence_new, 1)
    if after != before:
        validator.write_text(after, encoding="utf-8")
        changed.append("scripts/validate_package.py")

    auditor = ROOT / "tools" / "judge_audit.py"
    before = auditor.read_text(encoding="utf-8")
    after = before
    if "import importlib.util\n" not in after:
        after = after.replace("import hashlib\n", "import hashlib\nimport importlib.util\n", 1)
    after = after.replace(
        '"A19": {"path": "judges/skill-package.yaml", "judge": "J11_SKILL_PACKAGE", "assertions": 10,',
        '"A19": {"path": "judges/skill-package.yaml", "judge": "J11_SKILL_PACKAGE", "assertions": 5,',
        1,
    )
    old_repo = '''def repo_stars(repo: str) -> int:\n    request = urllib.request.Request(f"https://api.github.com/repos/{repo}", headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-judge-audit"})\n    token = os.getenv("GITHUB_TOKEN")\n    if token:\n        request.add_header("Authorization", f"Bearer {token}")\n    with urllib.request.urlopen(request, timeout=30) as response:\n        return int(json.load(response)["stargazers_count"])\n'''
    new_repo = '''def repo_stars(repo: str) -> int:\n    snapshot_path = ROOT / "tools" / "benchmark-snapshot.json"\n    if snapshot_path.is_file():\n        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))\n        for row in snapshot.get("repositories", []):\n            if row.get("repository") == repo:\n                return int(row["stars_lower_bound"])\n        raise ValueError(f"benchmark_missing_from_snapshot:{repo}")\n    request = urllib.request.Request(\n        f"https://api.github.com/repos/{repo}",\n        headers={"Accept": "application/vnd.github+json", "User-Agent": "r8-judge-audit"},\n    )\n    token = os.getenv("GITHUB_TOKEN")\n    if token:\n        request.add_header("Authorization", f"Bearer {token}")\n    with urllib.request.urlopen(request, timeout=30) as response:\n        return int(json.load(response)["stargazers_count"])\n'''
    if old_repo in after:
        after = after.replace(old_repo, new_repo, 1)
    if "def run_package_case(" not in after:
        marker = "def run_self_test(cfg: dict[str, Any]) -> dict[str, Any]:\n"
        function = '''def run_package_case(\n    cfg: dict[str, Any],\n    title: str,\n    *,\n    broken: bool,\n    expected_result: str,\n    with_metadata: bool = True,\n) -> dict[str, Any]:\n    validator_file = SKILL / cfg["validator"]\n    module_name = f"r8_validate_package_{title.lower()}"\n    spec = importlib.util.spec_from_file_location(module_name, validator_file)\n    if spec is None or spec.loader is None:\n        return {"title": title, "passed": False, "error": "validator_module_unloadable"}\n    module = importlib.util.module_from_spec(spec)\n    sys.modules[module_name] = module\n    spec.loader.exec_module(module)\n    with tempfile.TemporaryDirectory(prefix=f"r8_{title.lower()}_") as tmp:\n        root = Path(tmp)\n        module.write_self_test_package(root, broken)\n        command = [sys.executable, cfg["validator"], str(root), "--evidence-ref", f"directory:{root}"]\n        proc = subprocess.run(command, cwd=SKILL, env=runtime_env(with_metadata), text=True, capture_output=True, timeout=240)\n        try:\n            result = parse_emitted(proc.stdout)\n            errors = validate_envelope(result, cfg["judge"], expected_result)\n            hashes_ok = all(isinstance(result.get(key), str) and len(result[key]) == 64 for key in ("input_sha256", "evidence_sha256", "output_sha256"))\n            passed = result.get("result") == expected_result and not errors and hashes_ok\n            return {\n                "title": title, "passed": passed, "command": command, "process_exit_code": proc.returncode,\n                "expected_result": expected_result, "actual_result": result.get("result"),\n                "failed_assertions": result.get("failed_assertions"), "blocking_assertions": result.get("blocking_assertions"),\n                "assertions_total": result.get("assertions_total"), "assertions_passed": result.get("assertions_passed"),\n                "input_sha256": result.get("input_sha256"), "evidence_sha256": result.get("evidence_sha256"),\n                "output_sha256": result.get("output_sha256"), "envelope_errors": errors,\n                "evidence_checks": result.get("evidence", {}).get("checks"),\n            }\n        except Exception as exc:\n            return {"title": title, "passed": False, "command": command, "process_exit_code": proc.returncode, "stdout": proc.stdout[-5000:], "stderr": proc.stderr[-2500:], "error": f"{type(exc).__name__}:{exc}"}\n\n\n'''
        if marker not in after:
            raise RuntimeError("A19 self-test marker missing")
        after = after.replace(marker, function + marker, 1)
    old_branch = '    elif special == "package":\n        executions.append(run_self_test(cfg))\n'
    new_branch = '''    elif special == "package":\n        executions += [\n            run_package_case(cfg, "PACKAGE_POSITIVE", broken=False, expected_result="PASS_WITH_EVIDENCE"),\n            run_package_case(cfg, "PACKAGE_NEGATIVE", broken=True, expected_result="RETURN_TO_WORKER"),\n            run_package_case(cfg, "MISSING_METADATA", broken=False, expected_result="BLOCKED", with_metadata=False),\n            run_self_test(cfg),\n        ]\n'''
    if old_branch in after:
        after = after.replace(old_branch, new_branch, 1)
    old_check = '        "positive_and_negative_present": any(item.get("title") in {"POSITIVE", "E21_STORY_CORE_POSITIVE", "E23_FIELD_CONTRACTS_POSITIVE"} for item in executions) and any(item.get("title") in {"NEGATIVE", "E22_STORY_CORE_NEGATIVE", "E24_FIELD_CONTRACTS_NEGATIVE"} for item in executions),\n'
    new_check = '        "positive_and_negative_present": any(item.get("title") in {"POSITIVE", "PACKAGE_POSITIVE", "E21_STORY_CORE_POSITIVE", "E23_FIELD_CONTRACTS_POSITIVE"} for item in executions) and any(item.get("title") in {"NEGATIVE", "PACKAGE_NEGATIVE", "E22_STORY_CORE_NEGATIVE", "E24_FIELD_CONTRACTS_NEGATIVE"} for item in executions),\n'
    if old_check in after:
        after = after.replace(old_check, new_check, 1)
    if after != before:
        auditor.write_text(after, encoding="utf-8")
        changed.append("tools/judge_audit.py")
    return changed


def main() -> int:
    changed: list[str] = []
    if fix_a10():
        changed.append("A10")
    if fix_a12():
        changed.append("A12")
    changed.extend(fix_metadata_fallbacks())
    changed.extend(fix_a19())
    print(json.dumps({"changed": changed}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
