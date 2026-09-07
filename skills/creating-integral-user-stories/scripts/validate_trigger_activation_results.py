#!/usr/bin/env python3
"""Evaluate observed Story Creator activation decisions against the frozen trigger bank.

This is a judge, not an activation runtime. It never fabricates model output. The caller must
supply an observation produced by an external executor/runtime. The judge binds its evidence
to exact repository HEAD and source artifacts, computes every assertion itself, and rejects
missing/duplicate/unknown cases and canonical-state mutation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

JUDGE_VERSION = "trigger-activation-results-judge/v1"
OBSERVATION_SCHEMA = "trigger-activation-observation/v1"
EVIDENCE_SCHEMA = "trigger-activation-evidence/v1"
ALLOWED_ACTIVATIONS = {"ACTIVATE", "DO_NOT_ACTIVATE", "NEEDS_SOURCE_CONTEXT"}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def git_output(repo_root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo_root), *args], text=True).strip()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def artifact_binding(repo_root: Path, relative_path: str) -> dict[str, str]:
    path = repo_root / relative_path
    raw = path.read_bytes()
    return {
        "relative_path": relative_path,
        "sha256": sha256_bytes(raw),
        "git_blob": git_output(repo_root, "rev-parse", f"HEAD:{relative_path}"),
    }


def add_assertion(
    rows: list[dict[str, Any]],
    *,
    case_id: str,
    code: str,
    operator: str,
    actual: Any,
    expected: Any,
    blocking: bool = True,
) -> None:
    if operator == "equals":
        passed = actual == expected
    elif operator == "set_equals":
        passed = isinstance(actual, list) and isinstance(expected, list) and sorted(actual) == sorted(expected)
    else:
        raise ValueError(f"unsupported operator: {operator}")
    rows.append(
        {
            "case_id": case_id,
            "code": code,
            "operator": operator,
            "actual": actual,
            "expected": expected,
            "blocking": blocking,
            "passed": passed,
        }
    )


def evaluate_observation(registry: dict[str, Any], observation: dict[str, Any]) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    assertions: list[dict[str, Any]] = []

    if observation.get("schema_version") != OBSERVATION_SCHEMA:
        errors.append("OBSERVATION_SCHEMA_MISMATCH")
    if observation.get("skill_code") != registry.get("skill_code"):
        errors.append("SKILL_CODE_MISMATCH")
    if not str(observation.get("executor_identity", "")).strip():
        errors.append("EXECUTOR_IDENTITY_MISSING")
    if not str(observation.get("runtime_identity", "")).strip():
        errors.append("RUNTIME_IDENTITY_MISSING")

    declared_cases = registry.get("cases")
    observed_rows = observation.get("results")
    if not isinstance(declared_cases, list) or not declared_cases:
        errors.append("REGISTRY_CASES_INVALID")
        return assertions, errors
    if not isinstance(observed_rows, list) or not observed_rows:
        errors.append("OBSERVATION_RESULTS_EMPTY")
        return assertions, errors

    expected_by_id = {row.get("id"): row for row in declared_cases if isinstance(row, dict) and row.get("id")}
    if len(expected_by_id) != len(declared_cases):
        errors.append("REGISTRY_CASE_IDS_NOT_UNIQUE")
        return assertions, errors

    supported_case_assertions = {
        "A01_ACTIVATES_ON_SCREEN_WORK",
        "A02_NO_ACTIVATION_UNRELATED",
        "A14_BLOCKS_INSUFFICIENT_SOURCE",
        "A15_NO_CANONICAL_MUTATION_DURING_TRIGGER_EVAL",
    }
    for case in declared_cases:
        declared = {row.get("code") for row in case.get("assertions", []) if isinstance(row, dict)}
        critical = set(case.get("critical_assertions", []))
        unsupported = sorted(code for code in declared if code not in supported_case_assertions)
        if unsupported:
            errors.append(f"UNSUPPORTED_DECLARED_ASSERTION:{case.get('id')}:{','.join(unsupported)}")
        if not critical <= declared:
            errors.append(f"CRITICAL_ASSERTION_NOT_DECLARED:{case.get('id')}")
        if "A15_NO_CANONICAL_MUTATION_DURING_TRIGGER_EVAL" not in declared:
            errors.append(f"NO_MUTATION_ASSERTION_MISSING:{case.get('id')}")

    observed_by_id: dict[str, dict[str, Any]] = {}
    for row in observed_rows:
        if not isinstance(row, dict):
            errors.append("OBSERVATION_RESULT_NOT_OBJECT")
            continue
        case_id = row.get("id")
        if not isinstance(case_id, str) or not case_id:
            errors.append("OBSERVATION_CASE_ID_MISSING")
            continue
        if case_id in observed_by_id:
            errors.append(f"DUPLICATE_CASE:{case_id}")
            continue
        if case_id not in expected_by_id:
            errors.append(f"UNKNOWN_CASE:{case_id}")
            continue
        observed_by_id[case_id] = row

    missing = sorted(set(expected_by_id) - set(observed_by_id))
    if missing:
        errors.append("MISSING_CASES:" + ",".join(missing))
    extra = sorted(set(observed_by_id) - set(expected_by_id))
    if extra:
        errors.append("EXTRA_CASES:" + ",".join(extra))

    for case_id in [c["id"] for c in declared_cases if isinstance(c, dict) and c.get("id") in observed_by_id]:
        expected_case = expected_by_id[case_id]
        actual_case = observed_by_id[case_id]
        expected_output = expected_case.get("expected", {}).get("output", {})
        expected_activation = expected_output.get("activation")
        actual_activation = actual_case.get("activation")

        if actual_activation not in ALLOWED_ACTIVATIONS:
            errors.append(f"INVALID_ACTIVATION:{case_id}:{actual_activation}")
        add_assertion(
            assertions,
            case_id=case_id,
            code="ACTIVATION_DECISION",
            operator="equals",
            actual=actual_activation,
            expected=expected_activation,
        )

        if "mode" in expected_output:
            add_assertion(
                assertions,
                case_id=case_id,
                code="ACTIVATION_MODE",
                operator="equals",
                actual=actual_case.get("mode"),
                expected=expected_output.get("mode"),
            )

        add_assertion(
            assertions,
            case_id=case_id,
            code="NO_CANONICAL_MUTATION",
            operator="set_equals",
            actual=actual_case.get("state_changes", []),
            expected=expected_case.get("expected", {}).get("state_changes", []),
        )

    return assertions, errors


def positive(assertion_rows: list[dict[str, Any]], structural_errors: list[str]) -> bool:
    """Return true only for a non-vacuous observation with no structural or assertion failures."""
    return bool(assertion_rows) and not structural_errors and all(row.get("passed") is True for row in assertion_rows)


def build_evidence(
    *,
    repo_root: Path,
    registry_path: Path,
    observation_path: Path,
    assertions_path: Path,
    skill_path: Path,
    source_head: str,
    command: str,
    started_at: str,
) -> dict[str, Any]:
    current_head = git_output(repo_root, "rev-parse", "HEAD")
    if source_head != current_head:
        raise ValueError(f"SOURCE_HEAD_MISMATCH expected={source_head} actual={current_head}")

    registry = load_json(registry_path)
    observation = load_json(observation_path)
    assertions_registry = load_json(assertions_path)
    assertion_rows, structural_errors = evaluate_observation(registry, observation)

    source_bindings = {
        "skill": artifact_binding(repo_root, str(skill_path.relative_to(repo_root))),
        "trigger_evals": artifact_binding(repo_root, str(registry_path.relative_to(repo_root))),
        "assertions": artifact_binding(repo_root, str(assertions_path.relative_to(repo_root))),
    }

    # The global assertion registry uses GA* identities. Trigger-local A15 is intentionally
    # owned by trigger-evals.json and is not the same contract as GA15_NO_SELF_APPROVAL.
    expected_global_codes = {
        "GA01_ACTIVATES_ON_SCREEN_WORK",
        "GA02_NO_ACTIVATION_UNRELATED",
        "GA14_BLOCKS_INSUFFICIENT_SOURCE",
    }
    actual_registry_codes = {
        row.get("id") for row in assertions_registry.get("assertions", []) if isinstance(row, dict)
    }
    missing_registry_codes = sorted(expected_global_codes - actual_registry_codes)
    if missing_registry_codes:
        structural_errors.append("ASSERTION_REGISTRY_MISSING:" + ",".join(missing_registry_codes))
    activation_registry_ref = (
        assertions_registry.get("executable_links", {})
        .get("activation_registry", {})
        .get("registry_ref")
    )
    if activation_registry_ref != "evals/trigger-evals.json":
        structural_errors.append("ACTIVATION_REGISTRY_LINK_MISMATCH")

    failed_assertions = [row for row in assertion_rows if not row["passed"]]
    blocking_assertions = [row for row in failed_assertions if row["blocking"]]
    exit_code = 0 if positive(assertion_rows, structural_errors) else 1

    observation_raw = observation_path.read_bytes()
    registry_raw = registry_path.read_bytes()
    input_preimage = {
        "source_head": source_head,
        "registry_sha256": sha256_bytes(registry_raw),
        "observation_sha256": sha256_bytes(observation_raw),
        "source_bindings": source_bindings,
    }

    evidence: dict[str, Any] = {
        "evidence_schema_version": EVIDENCE_SCHEMA,
        "judge_version": JUDGE_VERSION,
        "executor_identity": observation.get("executor_identity"),
        "runtime_identity": observation.get("runtime_identity"),
        "command": command,
        "started_at": started_at,
        "completed_at": utc_now(),
        "source_head": source_head,
        "source_bindings": source_bindings,
        "assertions_total": len(assertion_rows),
        "assertions_passed": sum(1 for row in assertion_rows if row["passed"]),
        "failed_assertions": failed_assertions,
        "blocking_assertions": blocking_assertions,
        "structural_errors": structural_errors,
        "assertion_results": assertion_rows,
        "input_sha256": sha256_bytes(canonical_bytes(input_preimage)),
        "output_sha256": sha256_bytes(observation_raw),
        "exit_code": exit_code,
        "evaluation_scope": "OBSERVED_ACTIVATION_OUTPUT_ONLY",
        "readiness_authority": "NON_AUTHORIZING_UNLESS_OBSERVATION_COMES_FROM_GOVERNED_RUNTIME",
    }
    evidence["evidence_sha256"] = sha256_bytes(canonical_bytes(evidence))
    return evidence


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--observation", type=Path, required=True)
    parser.add_argument("--assertions", type=Path, required=True)
    parser.add_argument("--skill", type=Path, required=True)
    parser.add_argument("--source-head", required=True)
    parser.add_argument("--evidence-out", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    started_at = utc_now()
    command = " ".join(sys.argv)
    try:
        evidence = build_evidence(
            repo_root=args.repo_root.resolve(),
            registry_path=args.registry.resolve(),
            observation_path=args.observation.resolve(),
            assertions_path=args.assertions.resolve(),
            skill_path=args.skill.resolve(),
            source_head=args.source_head,
            command=command,
            started_at=started_at,
        )
    except Exception as exc:
        print(json.dumps({"judge_version": JUDGE_VERSION, "exit_code": 2, "error": str(exc)}, sort_keys=True))
        return 2

    if args.evidence_out:
        args.evidence_out.parent.mkdir(parents=True, exist_ok=True)
        args.evidence_out.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(evidence, sort_keys=True, ensure_ascii=False))
    return int(evidence["exit_code"])


if __name__ == "__main__":
    raise SystemExit(main())