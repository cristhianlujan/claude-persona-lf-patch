"""Deterministic semantic coverage validator for J10_TEST_COVERAGE v0.6.

Validates the exact five-property J10 envelope, traceability matrix, controlled
test environment, worker/judge independence, semantic test coverage, exact
fixtures and runtime registration. The validator is read-only and emits the
canonical LF judge-result envelope through ``lf_common``.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import re
from pathlib import Path
from typing import Any

from lf_common import (
    ValidationInputError,
    emit,
    failure,
    load_json,
    result_object,
    sha256_file,
)

JUDGE = "J10_TEST_COVERAGE"
JUDGE_VERSION = "v0.6"
REGISTRATION = "supabase://private.lf_skill_artifacts/ART_SCRIPT_VALIDATE_TEST_COVERAGE"
PLACEHOLDERS = {"", "todo", "tbd", "placeholder", "example", "n/a"}
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_TOP_LEVEL = {
    "story_pack",
    "critical_rules",
    "fixtures",
    "traceability_matrix",
    "test_environment",
}
ASSERTIONS = (
    "input_envelope_valid",
    "traceability_matrix_valid",
    "test_environment_valid",
    "worker_judge_independence",
    "acceptance_criteria_without_test",
    "critical_rule_without_test",
    "permission_without_negative_test",
    "tenant_rule_without_cross_tenant_test",
    "state_transition_without_state_test",
    "idempotent_action_without_duplicate_test",
    "critical_error_without_test",
    "mutable_shared_resource_without_concurrency_test",
    "tests_without_exact_fixture",
    "tests_without_expected_result",
    "tests_without_traceability_ref",
    "orphan_tests",
    "vacuous_pass_count",
)


def _object(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationInputError(f"{name}_must_be_object")
    return value


def _code(item: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _nonempty_text(value: Any, minimum: int = 3) -> bool:
    return (
        isinstance(value, str)
        and len(value.strip()) >= minimum
        and value.strip().lower() not in PLACEHOLDERS
    )


def _nonempty_string_list(value: Any) -> bool:
    return (
        isinstance(value, list)
        and bool(value)
        and all(_nonempty_text(item, 2) for item in value)
    )


def _fixture_exact(fixture: Any) -> bool:
    if not isinstance(fixture, dict):
        return False
    required = (
        "actor",
        "tenant",
        "initial_state",
        "exact_inputs",
        "steps",
        "expected_result",
        "evidence_path",
    )
    if set(required) - set(fixture):
        return False
    if not _nonempty_text(fixture.get("actor")) or not _nonempty_text(
        fixture.get("tenant")
    ):
        return False
    if not isinstance(fixture.get("initial_state"), dict) or not isinstance(
        fixture.get("exact_inputs"), dict
    ):
        return False
    if not _nonempty_string_list(fixture.get("steps")):
        return False
    return _nonempty_text(fixture.get("expected_result"), 5) and _nonempty_text(
        fixture.get("evidence_path"), 3
    )


def _trace_entry_valid(value: Any) -> bool:
    if isinstance(value, str):
        return _nonempty_text(value, 3)
    if isinstance(value, list):
        return bool(value) and all(_nonempty_text(item, 3) for item in value)
    if isinstance(value, dict):
        refs = value.get("refs", value.get("source_refs", value.get("evidence_refs")))
        return _trace_entry_valid(refs)
    return False


def _runtime_meta() -> dict[str, str]:
    path = Path(__file__).resolve()
    return {
        "semantic_validator_path": str(path),
        "semantic_validator_sha256": sha256_file(path),
        "semantic_validator_registration": REGISTRATION,
    }


def _runtime_blockers(
    *,
    executor_identity: str | None,
    worker_identity: str | None,
    judge_version: str | None,
    registered_sha256: str | None,
    registration: str | None,
    runtime_available: bool,
    meta: dict[str, str],
) -> list[str]:
    blockers: list[str] = []
    executor = str(executor_identity or "").strip()
    worker = str(worker_identity or "").strip()
    version = str(judge_version or "").strip()
    registered_sha = str(registered_sha256 or "").strip()
    registered_at = str(registration or "").strip()

    if not runtime_available:
        blockers.append("semantic_validator_unavailable")
    if not registered_at or registered_at != REGISTRATION:
        blockers.append("semantic_validator_unregistered")
    if registered_sha and not SHA_RE.fullmatch(registered_sha):
        blockers.append("semantic_validator_sha_unreconciled")
    elif registered_sha != meta["semantic_validator_sha256"]:
        blockers.append("semantic_validator_sha_unreconciled")
    if not executor:
        blockers.append("executor_identity_missing")
    if not worker:
        blockers.append("worker_identity_missing")
    if not version:
        blockers.append("judge_version_missing")
    elif version != JUDGE_VERSION:
        blockers.append("judge_version_mismatch")
    if executor and worker and executor == worker:
        blockers.append("worker_judge_independence_broken")
    return sorted(set(blockers))


def validate_payload(
    payload: dict[str, Any],
    *,
    executor_identity: str,
    worker_identity: str,
) -> tuple[dict[str, int], dict[str, Any]]:
    exact_envelope = set(payload) == EXPECTED_TOP_LEVEL
    story = payload.get("story_pack")
    rules = payload.get("critical_rules")
    fixtures = payload.get("fixtures")
    traceability = payload.get("traceability_matrix")
    environment = payload.get("test_environment")

    envelope_types_valid = (
        isinstance(story, dict)
        and isinstance(rules, list)
        and isinstance(fixtures, dict)
        and isinstance(traceability, dict)
        and isinstance(environment, dict)
    )

    story_obj = story if isinstance(story, dict) else {}
    core = story_obj.get("core")
    core_obj = core if isinstance(core, dict) else {}
    criteria = core_obj.get("acceptance_criteria")
    criteria_list = criteria if isinstance(criteria, list) else []
    tests = story_obj.get("tests")
    tests_list = tests if isinstance(tests, list) else []
    rule_list = rules if isinstance(rules, list) else []
    fixture_map = fixtures if isinstance(fixtures, dict) else {}
    trace_obj = traceability if isinstance(traceability, dict) else {}
    env_obj = environment if isinstance(environment, dict) else {}

    criterion_codes: set[str] = set()
    malformed_criteria = 0
    for raw in criteria_list:
        if not isinstance(raw, dict):
            malformed_criteria += 1
            continue
        code = _code(raw, "criterion_code")
        if not code:
            malformed_criteria += 1
        else:
            criterion_codes.add(code)

    rule_map: dict[str, dict[str, Any]] = {}
    malformed_rules = 0
    for raw in rule_list:
        if not isinstance(raw, dict):
            malformed_rules += 1
            continue
        code = _code(raw, "rule_code", "code")
        if not code:
            malformed_rules += 1
        else:
            rule_map[code] = raw

    criteria_trace = trace_obj.get("criteria")
    rules_trace = trace_obj.get("rules")
    traceability_valid = (
        isinstance(criteria_trace, dict)
        and isinstance(rules_trace, dict)
        and set(criteria_trace) >= criterion_codes
        and set(rules_trace) >= set(rule_map)
        and all(_trace_entry_valid(criteria_trace.get(code)) for code in criterion_codes)
        and all(_trace_entry_valid(rules_trace.get(code)) for code in rule_map)
    )

    environment_valid = all(
        _nonempty_string_list(env_obj.get(key))
        for key in ("actors", "tenants", "initial_states", "data_sets", "restrictions")
    )

    test_by_code: dict[str, dict[str, Any]] = {}
    referenced_criteria: set[str] = set()
    referenced_rules: set[str] = set()
    orphan = 0
    no_expected = 0
    no_trace = 0
    no_fixture = 0
    vacuous = malformed_criteria + malformed_rules

    for raw in tests_list:
        if not isinstance(raw, dict):
            vacuous += 1
            continue
        test_code = _code(raw, "test_code")
        if not test_code or test_code in test_by_code:
            vacuous += 1
            continue
        test_by_code[test_code] = raw
        criterion_ref = raw.get("criterion_ref")
        rule_ref = raw.get("rule_ref")
        if isinstance(criterion_ref, str) and criterion_ref.strip():
            referenced_criteria.add(criterion_ref.strip())
        if isinstance(rule_ref, str) and rule_ref.strip():
            referenced_rules.add(rule_ref.strip())
        if not criterion_ref and not rule_ref:
            no_trace += 1
            orphan += 1
        elif criterion_ref and criterion_ref not in criterion_codes:
            orphan += 1
        elif rule_ref and rule_ref not in rule_map:
            orphan += 1
        if not _nonempty_text(raw.get("expected_result"), 5):
            no_expected += 1
        if not _fixture_exact(fixture_map.get(test_code)):
            no_fixture += 1
        if not _nonempty_string_list(raw.get("steps")):
            vacuous += 1

    def uncovered_rules(predicate, family: str | None = None, negative: bool | None = None) -> int:
        missing = 0
        for code, rule in rule_map.items():
            if not predicate(rule):
                continue
            covered = False
            for test in tests_list:
                if not isinstance(test, dict) or test.get("rule_ref") != code:
                    continue
                if family and test.get("family") != family:
                    continue
                if negative is not None and bool(test.get("negative")) is not negative:
                    continue
                covered = True
                break
            if not covered:
                missing += 1
        return missing

    checks = {
        "input_envelope_valid": 0 if exact_envelope and envelope_types_valid else 1,
        "traceability_matrix_valid": 0 if traceability_valid else 1,
        "test_environment_valid": 0 if environment_valid else 1,
        "worker_judge_independence": 0
        if executor_identity and worker_identity and executor_identity != worker_identity
        else 1,
        "acceptance_criteria_without_test": len(criterion_codes - referenced_criteria),
        "critical_rule_without_test": len(set(rule_map) - referenced_rules),
        "permission_without_negative_test": uncovered_rules(
            lambda r: r.get("family") == "PERMISSION"
            or r.get("requires_negative") is True,
            "PERMISSION",
            True,
        ),
        "tenant_rule_without_cross_tenant_test": uncovered_rules(
            lambda r: r.get("tenant_rule") is True, "TENANT", True
        ),
        "state_transition_without_state_test": uncovered_rules(
            lambda r: r.get("family") == "STATE", "STATE", None
        ),
        "idempotent_action_without_duplicate_test": uncovered_rules(
            lambda r: r.get("idempotent") is True, "IDEMPOTENCY", None
        ),
        "critical_error_without_test": uncovered_rules(
            lambda r: r.get("critical_error") is True, "ERROR", None
        ),
        "mutable_shared_resource_without_concurrency_test": uncovered_rules(
            lambda r: r.get("mutable_shared_resource") is True, "CONCURRENCY", None
        ),
        "tests_without_exact_fixture": no_fixture,
        "tests_without_expected_result": no_expected,
        "tests_without_traceability_ref": no_trace,
        "orphan_tests": orphan,
        "vacuous_pass_count": vacuous
        + (1 if not criterion_codes or not test_by_code else 0),
    }

    evidence = {
        "checks": checks,
        "acceptance_criteria_count": len(criteria_list),
        "critical_rule_count": len(rule_list),
        "test_case_count": len(tests_list),
        "negative_test_count": sum(
            1
            for test in tests_list
            if isinstance(test, dict) and test.get("negative") is True
        ),
        "exact_fixture_count": sum(
            1 for value in fixture_map.values() if _fixture_exact(value)
        ),
        "families_covered": sorted(
            {
                str(test.get("family"))
                for test in tests_list
                if isinstance(test, dict) and test.get("family")
            }
        ),
        "traceability_matrix_summary": {
            "criteria_expected": len(criterion_codes),
            "criteria_mapped": sum(
                1 for code in criterion_codes if _trace_entry_valid(
                    criteria_trace.get(code) if isinstance(criteria_trace, dict) else None
                )
            ),
            "rules_expected": len(rule_map),
            "rules_mapped": sum(
                1 for code in rule_map if _trace_entry_valid(
                    rules_trace.get(code) if isinstance(rules_trace, dict) else None
                )
            ),
        },
        "test_environment_summary": {
            key: len(env_obj.get(key, [])) if isinstance(env_obj.get(key), list) else 0
            for key in ("actors", "tenants", "initial_states", "data_sets", "restrictions")
        },
        "worker_identity": worker_identity,
        "executor_identity": executor_identity,
    }
    return checks, evidence


def _repair_for(assertion_id: str) -> dict[str, Any]:
    targets = {
        "input_envelope_valid": "$",
        "traceability_matrix_valid": "$.traceability_matrix",
        "test_environment_valid": "$.test_environment",
        "worker_judge_independence": "$.worker_identity",
        "tests_without_exact_fixture": "$.fixtures",
        "orphan_tests": "$.story_pack.tests",
    }
    return failure(
        assertion_id,
        targets.get(assertion_id, f"$.evidence.checks.{assertion_id}"),
        f"Repair semantic coverage until {assertion_id}=0",
    )


def build_result(
    payload: dict[str, Any],
    evidence_refs: list[str],
    retry_count: int,
    *,
    executor_identity: str | None,
    worker_identity: str | None,
    judge_version: str | None,
    registered_sha256: str | None,
    registration: str | None,
    runtime_available: bool = True,
    input_path: Path | None = None,
    command: str | None = None,
) -> dict[str, Any]:
    meta = _runtime_meta()
    blockers = _runtime_blockers(
        executor_identity=executor_identity,
        worker_identity=worker_identity,
        judge_version=judge_version,
        registered_sha256=registered_sha256,
        registration=registration,
        runtime_available=runtime_available,
        meta=meta,
    )
    executor = str(executor_identity or "").strip()
    worker = str(worker_identity or "").strip()

    if blockers:
        checks = {name: 0 for name in ASSERTIONS}
        checks["worker_judge_independence"] = (
            1 if "worker_judge_independence_broken" in blockers else 0
        )
        evidence = {
            "checks": checks,
            "runtime": meta,
            "registered_runtime_sha256": registered_sha256,
            "registration": registration,
            "worker_identity": worker or "MISSING",
            "executor_identity": executor or "MISSING",
            "input_path": str(input_path) if input_path else None,
        }
        if input_path and input_path.is_file():
            evidence["input_sha256"] = sha256_file(input_path)
        return result_object(
            JUDGE,
            [],
            evidence,
            evidence_refs or ["evidence:inline"],
            blocking_assertions=blockers,
            forced_result="BLOCKED",
            retry_count=retry_count,
            judge_version=judge_version or "MISSING",
            executor_identity=executor or "MISSING",
            command=command or "J10 runtime preflight",
        )

    checks, evidence = validate_payload(
        payload,
        executor_identity=executor,
        worker_identity=worker,
    )
    evidence["runtime"] = meta
    evidence["registered_runtime_sha256"] = registered_sha256
    evidence["registration"] = registration
    if input_path and input_path.is_file():
        evidence["input_path"] = str(input_path)
        evidence["input_sha256"] = sha256_file(input_path)
    else:
        canonical = json.dumps(
            payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
        import hashlib
        evidence["input_sha256"] = hashlib.sha256(canonical).hexdigest()

    failed = [name for name in ASSERTIONS if checks.get(name) != 0]
    repairs = [_repair_for(name) for name in failed]
    return result_object(
        JUDGE,
        failed,
        evidence,
        evidence_refs or ["evidence:inline"],
        repairs,
        retry_count=retry_count,
        judge_version=JUDGE_VERSION,
        executor_identity=executor,
        command=command,
    )


def run(input_path: Path, evidence_refs: list[str], retry_count: int) -> int:
    payload = _object(load_json(input_path), "input")
    out = build_result(
        payload,
        evidence_refs,
        retry_count,
        executor_identity=os.getenv("LF_EXECUTOR_IDENTITY"),
        worker_identity=os.getenv("LF_WORKER_IDENTITY"),
        judge_version=os.getenv("LF_JUDGE_VERSION"),
        registered_sha256=os.getenv("LF_VALIDATOR_REGISTERED_SHA256"),
        registration=os.getenv("LF_VALIDATOR_REGISTRATION"),
        runtime_available=os.getenv("LF_VALIDATOR_AVAILABLE", "true").lower()
        not in {"0", "false", "no"},
        input_path=input_path,
    )
    return emit(out)


def _positive_payload() -> dict[str, Any]:
    criterion = {
        "criterion_code": "AC-1",
        "given": "account exists",
        "when": "user requests",
        "then": "result is shown",
        "source_ref": "SRC-1",
    }
    rule = {
        "rule_code": "PERM-1",
        "family": "PERMISSION",
        "requires_negative": True,
        "source_ref": "SRC-PERM-1",
    }
    test = {
        "test_code": "TEST-1",
        "family": "PERMISSION",
        "criterion_ref": "AC-1",
        "rule_ref": "PERM-1",
        "preconditions": ["account exists"],
        "steps": ["request with unauthorized role"],
        "expected_result": "access is denied",
        "negative": True,
        "critical": True,
        "automatable": True,
        "evidence_path": "evidence/TEST-1.json",
    }
    fixture = {
        "actor": "UNAUTHORIZED_USER",
        "tenant": "TENANT-A",
        "initial_state": {"authenticated": True},
        "exact_inputs": {"record_id": "R-1"},
        "steps": ["request record R-1"],
        "expected_result": "access is denied",
        "evidence_path": "evidence/TEST-1.json",
    }
    return {
        "story_pack": {
            "core": {"acceptance_criteria": [criterion]},
            "tests": [test],
        },
        "critical_rules": [rule],
        "fixtures": {"TEST-1": fixture},
        "traceability_matrix": {
            "criteria": {"AC-1": ["SRC-1"]},
            "rules": {"PERM-1": ["SRC-PERM-1"]},
        },
        "test_environment": {
            "actors": ["AUTHORIZED_USER", "UNAUTHORIZED_USER"],
            "tenants": ["TENANT-A", "TENANT-B"],
            "initial_states": ["READY"],
            "data_sets": ["DATASET-1"],
            "restrictions": ["NO_PRODUCTION_DATA"],
        },
    }


def _negative_case(
    name: str,
    payload: dict[str, Any],
    expected_result: str,
    expected_assertion: str,
    *,
    executor: str | None,
    worker: str | None,
    version: str | None,
    registered_sha: str | None,
    registration: str | None,
    runtime_available: bool = True,
) -> dict[str, Any]:
    out = build_result(
        payload,
        [f"self-test://{name}"],
        0,
        executor_identity=executor,
        worker_identity=worker,
        judge_version=version,
        registered_sha256=registered_sha,
        registration=registration,
        runtime_available=runtime_available,
        command=f"self-test:{name}",
    )
    signals = set(out["failed_assertions"]) | set(out["blocking_assertions"])
    return {
        "name": name,
        "expected_result": expected_result,
        "actual_result": out["result"],
        "expected_assertion": expected_assertion,
        "signals": sorted(signals),
        "passed": out["result"] == expected_result
        and expected_assertion in signals,
    }


def self_test() -> int:
    good = _positive_payload()
    meta = _runtime_meta()
    sha = meta["semantic_validator_sha256"]
    executor = "J10_INDEPENDENT_EXECUTOR"
    worker = "STORY_TEST_DERIVER_WORKER"

    positive = build_result(
        good,
        ["self-test://positive"],
        0,
        executor_identity=executor,
        worker_identity=worker,
        judge_version=JUDGE_VERSION,
        registered_sha256=sha,
        registration=REGISTRATION,
        command="self-test:positive",
    )

    tests: list[dict[str, Any]] = []

    x = copy.deepcopy(good)
    x.pop("traceability_matrix")
    tests.append(_negative_case(
        "missing_traceability_matrix", x, "RETURN_TO_WORKER",
        "input_envelope_valid", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    x = copy.deepcopy(good)
    x.pop("test_environment")
    tests.append(_negative_case(
        "missing_test_environment", x, "RETURN_TO_WORKER",
        "input_envelope_valid", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    x = copy.deepcopy(good)
    x["traceability_matrix"]["criteria"]["AC-1"] = []
    tests.append(_negative_case(
        "invalid_traceability_matrix", x, "RETURN_TO_WORKER",
        "traceability_matrix_valid", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    x = copy.deepcopy(good)
    x["test_environment"]["tenants"] = []
    tests.append(_negative_case(
        "invalid_test_environment", x, "RETURN_TO_WORKER",
        "test_environment_valid", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    x = copy.deepcopy(good)
    x["fixtures"] = {}
    tests.append(_negative_case(
        "missing_exact_fixture", x, "RETURN_TO_WORKER",
        "tests_without_exact_fixture", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    x = copy.deepcopy(good)
    x["story_pack"]["tests"][0]["expected_result"] = ""
    tests.append(_negative_case(
        "empty_expected_result", x, "RETURN_TO_WORKER",
        "tests_without_expected_result", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    x = copy.deepcopy(good)
    x["story_pack"]["tests"][0]["criterion_ref"] = "AC-UNKNOWN"
    tests.append(_negative_case(
        "orphan_test", x, "RETURN_TO_WORKER",
        "orphan_tests", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    x = copy.deepcopy(good)
    x["story_pack"]["tests"][0]["steps"] = ["todo"]
    tests.append(_negative_case(
        "vacuous_test", x, "RETURN_TO_WORKER",
        "vacuous_pass_count", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    tests.append(_negative_case(
        "missing_runtime", good, "BLOCKED",
        "semantic_validator_unavailable", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION,
        runtime_available=False
    ))

    tests.append(_negative_case(
        "unregistered_runtime", good, "BLOCKED",
        "semantic_validator_unregistered", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=""
    ))

    tests.append(_negative_case(
        "runtime_sha_mismatch", good, "BLOCKED",
        "semantic_validator_sha_unreconciled", executor=executor, worker=worker,
        version=JUDGE_VERSION, registered_sha="0" * 64, registration=REGISTRATION
    ))

    tests.append(_negative_case(
        "missing_executor_identity", good, "BLOCKED",
        "executor_identity_missing", executor=None, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    tests.append(_negative_case(
        "missing_worker_identity", good, "BLOCKED",
        "worker_identity_missing", executor=executor, worker=None,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    tests.append(_negative_case(
        "worker_self_executes", good, "BLOCKED",
        "worker_judge_independence_broken", executor=worker, worker=worker,
        version=JUDGE_VERSION, registered_sha=sha, registration=REGISTRATION
    ))

    tests.append(_negative_case(
        "missing_judge_version", good, "BLOCKED",
        "judge_version_missing", executor=executor, worker=worker,
        version=None, registered_sha=sha, registration=REGISTRATION
    ))

    summary = {
        "positive_pass": positive["result"] == "PASS_WITH_EVIDENCE",
        "positive_assertions_passed": positive["assertions_passed"],
        "positive_assertions_total": positive["assertions_total"],
        "positive_checks": positive["evidence"]["checks"],
        "negative_cases": tests,
        "negative_passed": sum(1 for test in tests if test["passed"]),
        "negative_total": len(tests),
        "runtime_sha256": sha,
        "registration": REGISTRATION,
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0 if (
        summary["positive_pass"]
        and summary["positive_assertions_passed"] == len(ASSERTIONS)
        and summary["positive_assertions_total"] == len(ASSERTIONS)
        and summary["negative_passed"] == summary["negative_total"]
    ) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path)
    parser.add_argument("--evidence-ref", action="append", default=[])
    parser.add_argument("--retry-count", type=int, default=0)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.input is None:
        raise ValidationInputError("input_required")
    return run(args.input, args.evidence_ref, args.retry_count)


def _guarded_main() -> int:
    try:
        return main()
    except ValidationInputError as exc:
        meta = _runtime_meta()
        out = result_object(
            JUDGE,
            [],
            {
                "checks": {name: 0 for name in ASSERTIONS},
                "input_error": str(exc),
                "runtime": meta,
            },
            ["evidence:inline"],
            blocking_assertions=[str(exc)],
            forced_result="BLOCKED",
            judge_version=os.getenv("LF_JUDGE_VERSION") or "MISSING",
            executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "MISSING",
            command="J10 guarded input handler",
        )
        return emit(out)


if __name__ == "__main__":
    raise SystemExit(_guarded_main())
