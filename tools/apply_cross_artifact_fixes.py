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


def main() -> int:
    changed: list[str] = []
    if fix_a10():
        changed.append("A10")
    if fix_a12():
        changed.append("A12")
    changed.extend(fix_metadata_fallbacks())
    print(json.dumps({"changed": changed}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
