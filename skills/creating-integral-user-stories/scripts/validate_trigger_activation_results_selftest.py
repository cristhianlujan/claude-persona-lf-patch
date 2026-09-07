#!/usr/bin/env python3
"""Positive/negative meta-tests for validate_trigger_activation_results.py."""
from __future__ import annotations

import ast
import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
SKILL_ROOT = HERE.parent
ROOT = SKILL_ROOT.parent.parent
RUNNER = HERE / "validate_trigger_activation_results.py"
REGISTRY = SKILL_ROOT / "evals" / "trigger-evals.json"
ASSERTIONS = SKILL_ROOT / "evals" / "assertions.json"
SKILL = SKILL_ROOT / "SKILL.md"
TOPLEVEL = Path(subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "--show-toplevel"], text=True).strip()).resolve()
if TOPLEVEL != ROOT.resolve():
    raise SystemExit(f"SELFTEST_FIXTURE_INVALID: repo root mismatch expected={ROOT.resolve()} actual={TOPLEVEL}")
HEAD = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()


def base_observation() -> dict:
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    results = []
    for case in registry["cases"]:
        expected = case["expected"]["output"]
        row = {
            "id": case["id"],
            "activation": expected["activation"],
            "state_changes": [],
        }
        if "mode" in expected:
            row["mode"] = expected["mode"]
        results.append(row)
    return {
        "schema_version": "trigger-activation-observation/v1",
        "skill_code": registry["skill_code"],
        "executor_identity": "SELFTEST_SYNTHETIC_ORACLE",
        "runtime_identity": "HARNESS_META_TEST_ONLY",
        "results": results,
    }


def invoke(observation: dict, *, source_head: str = HEAD) -> tuple[int, dict]:
    with tempfile.TemporaryDirectory(prefix="trigger-activation-selftest-") as tmp:
        path = Path(tmp) / "observation.json"
        path.write_text(json.dumps(observation, ensure_ascii=False), encoding="utf-8")
        proc = subprocess.run(
            [
                sys.executable, str(RUNNER),
                "--repo-root", str(ROOT),
                "--registry", str(REGISTRY),
                "--observation", str(path),
                "--assertions", str(ASSERTIONS),
                "--skill", str(SKILL),
                "--source-head", source_head,
            ],
            text=True,
            capture_output=True,
        )
        line = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else "{}"
        return proc.returncode, json.loads(line)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("SELFTEST_FAIL: " + message)


def positive() -> dict:
    observation = base_observation()
    code, evidence = invoke(observation)
    require(code == 0, f"positive fixture rejected: {evidence}")
    require(evidence.get("assertions_total", 0) > 0, "vacuous positive accepted")
    require(evidence.get("assertions_passed") == evidence.get("assertions_total"), "positive assertions mismatch")
    require(evidence.get("failed_assertions") == [], "positive has failed assertions")
    require(evidence.get("blocking_assertions") == [], "positive has blocking assertions")
    require(evidence.get("structural_errors") == [], "positive has structural errors")
    require(len(evidence.get("evidence_sha256", "")) == 64, "evidence hash absent")
    return observation


def negative(positive_observation: dict) -> int:
    negatives = []

    wrong = copy.deepcopy(positive_observation)
    wrong["results"][0]["activation"] = "DO_NOT_ACTIVATE"
    negatives.append(("wrong_activation", wrong, HEAD))

    missing = copy.deepcopy(positive_observation)
    missing["results"] = missing["results"][:-1]
    negatives.append(("missing_case", missing, HEAD))

    duplicate = copy.deepcopy(positive_observation)
    duplicate["results"].append(copy.deepcopy(duplicate["results"][0]))
    negatives.append(("duplicate_case", duplicate, HEAD))

    mutated = copy.deepcopy(positive_observation)
    mutated["results"][0]["state_changes"] = ["canonical_artifacts"]
    negatives.append(("canonical_mutation", mutated, HEAD))

    unknown = copy.deepcopy(positive_observation)
    unknown["results"][0]["id"] = "UNKNOWN-CASE"
    negatives.append(("unknown_case", unknown, HEAD))

    wrong_mode = copy.deepcopy(positive_observation)
    next(row for row in wrong_mode["results"] if row["id"] == "T07")["mode"] = "FULL_GENERATION"
    negatives.append(("wrong_mode", wrong_mode, HEAD))

    empty = copy.deepcopy(positive_observation)
    empty["results"] = []
    negatives.append(("empty_results", empty, HEAD))

    negatives.append(("wrong_source_head", positive_observation, "0" * 40))

    for name, observation, source_head in negatives:
        code, result = invoke(observation, source_head=source_head)
        require(code != 0, f"negative {name} was accepted: {result}")
    return len(negatives)


def main() -> int:
    tree = ast.parse(RUNNER.read_text(encoding="utf-8"))
    funcs = {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}
    require({"evaluate_observation", "build_evidence", "positive", "main"} <= funcs, "required functions absent")
    unsafe_calls = [node.func.id for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in {"eval", "exec"}]
    require(not unsafe_calls, f"unsafe dynamic execution found: {unsafe_calls}")

    positive_observation = positive()
    negative_count = negative(positive_observation)
    print(json.dumps({"selftest":"PASS","positive":1,"negative":negative_count,"ast_guard":True,"source_head":HEAD}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
