"""Deterministic semantic coverage validator for J10_TEST_COVERAGE.

Validates traceability, exact fixtures, positive/negative coverage, tenant,
state, idempotency, concurrency and critical-error cases. It is read-only and
emits the canonical LF judge-result envelope through ``lf_common``.
"""
from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object

JUDGE = "J10_TEST_COVERAGE"
JUDGE_VERSION = "v0.5"
PLACEHOLDERS = {"", "todo", "tbd", "placeholder", "example", "n/a"}


def _object(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationInputError(f"{name}_must_be_object")
    return value


def _list(value: Any, name: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValidationInputError(f"{name}_must_be_array")
    return value


def _code(item: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _nonempty_text(value: Any, minimum: int = 3) -> bool:
    return isinstance(value, str) and len(value.strip()) >= minimum and value.strip().lower() not in PLACEHOLDERS


def _fixture_exact(fixture: Any) -> bool:
    if not isinstance(fixture, dict):
        return False
    required = ("actor", "tenant", "initial_state", "exact_inputs", "steps", "expected_result", "evidence_path")
    if not all(key in fixture for key in required):
        return False
    if not _nonempty_text(fixture.get("actor")) or not _nonempty_text(fixture.get("tenant")):
        return False
    if not isinstance(fixture.get("initial_state"), dict) or not isinstance(fixture.get("exact_inputs"), dict):
        return False
    steps = fixture.get("steps")
    if not isinstance(steps, list) or not steps or not all(_nonempty_text(step, 5) for step in steps):
        return False
    return _nonempty_text(fixture.get("expected_result"), 5) and _nonempty_text(fixture.get("evidence_path"), 3)


def validate_payload(payload: dict[str, Any]) -> tuple[dict[str, int], dict[str, Any]]:
    story = _object(payload.get("story_pack", payload), "story_pack")
    core = _object(story.get("core"), "story_pack.core")
    criteria = _list(core.get("acceptance_criteria"), "acceptance_criteria")
    tests = _list(story.get("tests"), "tests")
    rules = _list(payload.get("critical_rules", []), "critical_rules")
    fixtures = _object(payload.get("fixtures", {}), "fixtures")

    criterion_codes = {_code(_object(item, "criterion"), "criterion_code") for item in criteria}
    criterion_codes.discard("")
    rule_map = {_code(_object(item, "critical_rule"), "rule_code", "code"): item for item in rules}
    rule_map.pop("", None)

    test_by_code: dict[str, dict[str, Any]] = {}
    referenced_criteria: set[str] = set()
    referenced_rules: set[str] = set()
    orphan = 0
    no_expected = 0
    no_trace = 0
    no_fixture = 0
    vacuous = 0

    for raw in tests:
        test = _object(raw, "test")
        test_code = _code(test, "test_code")
        if not test_code or test_code in test_by_code:
            vacuous += 1
            continue
        test_by_code[test_code] = test
        criterion_ref = test.get("criterion_ref")
        rule_ref = test.get("rule_ref")
        if isinstance(criterion_ref, str) and criterion_ref:
            referenced_criteria.add(criterion_ref)
        if isinstance(rule_ref, str) and rule_ref:
            referenced_rules.add(rule_ref)
        if not criterion_ref and not rule_ref:
            no_trace += 1
            orphan += 1
        elif criterion_ref and criterion_ref not in criterion_codes:
            orphan += 1
        elif rule_ref and rule_ref not in rule_map:
            orphan += 1
        if not _nonempty_text(test.get("expected_result"), 5):
            no_expected += 1
        fixture = fixtures.get(test_code)
        if not _fixture_exact(fixture):
            no_fixture += 1
        steps = test.get("steps")
        if not isinstance(steps, list) or not steps or all(str(step).strip().lower() in PLACEHOLDERS for step in steps):
            vacuous += 1

    def uncovered_rules(predicate, family: str | None = None, negative: bool | None = None) -> int:
        missing = 0
        for code, rule in rule_map.items():
            if not predicate(rule):
                continue
            covered = False
            for test in tests:
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
        "acceptance_criteria_without_test": len(criterion_codes - referenced_criteria),
        "critical_rule_without_test": len(set(rule_map) - referenced_rules),
        "permission_without_negative_test": uncovered_rules(lambda r: r.get("family") == "PERMISSION" or r.get("requires_negative") is True, "PERMISSION", True),
        "tenant_rule_without_cross_tenant_test": uncovered_rules(lambda r: r.get("tenant_rule") is True, "TENANT", True),
        "state_transition_without_state_test": uncovered_rules(lambda r: r.get("family") == "STATE", "STATE", None),
        "idempotent_action_without_duplicate_test": uncovered_rules(lambda r: r.get("idempotent") is True, "IDEMPOTENCY", None),
        "critical_error_without_test": uncovered_rules(lambda r: r.get("critical_error") is True, "ERROR", None),
        "mutable_shared_resource_without_concurrency_test": uncovered_rules(lambda r: r.get("mutable_shared_resource") is True, "CONCURRENCY", None),
        "tests_without_exact_fixture": no_fixture,
        "tests_without_expected_result": no_expected,
        "tests_without_traceability_ref": no_trace,
        "orphan_tests": orphan,
        "vacuous_pass_count": vacuous + (1 if not criteria or not tests else 0),
    }
    evidence = {
        "checks": checks,
        "acceptance_criteria_count": len(criteria),
        "critical_rule_count": len(rules),
        "test_case_count": len(tests),
        "negative_test_count": sum(1 for test in tests if isinstance(test, dict) and test.get("negative") is True),
        "exact_fixture_count": sum(1 for value in fixtures.values() if _fixture_exact(value)),
        "families_covered": sorted({str(test.get("family")) for test in tests if isinstance(test, dict) and test.get("family")}),
    }
    return checks, evidence


def run(input_path: Path, evidence_refs: list[str], retry_count: int) -> int:
    payload = _object(load_json(input_path), "input")
    checks, evidence = validate_payload(payload)
    evidence["input_path"] = str(input_path)
    failed = [key for key, value in checks.items() if value != 0]
    repairs = [failure(key, f"$.evidence.checks.{key}", f"Repair semantic coverage until {key}=0") for key in failed]
    out = result_object(
        JUDGE,
        failed,
        evidence,
        evidence_refs or [f"file:{input_path}"],
        repairs,
        retry_count=retry_count,
        judge_version=JUDGE_VERSION,
        executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_SEMANTIC_VALIDATOR",
    )
    return emit(out)


def _positive_payload() -> dict[str, Any]:
    criterion = {"criterion_code": "AC-1", "given": "account exists", "when": "user requests", "then": "result is shown", "source_ref": "SRC-1"}
    rule = {"rule_code": "PERM-1", "family": "PERMISSION", "requires_negative": True}
    test = {"test_code": "TEST-1", "family": "PERMISSION", "criterion_ref": "AC-1", "rule_ref": "PERM-1", "preconditions": ["account exists"], "steps": ["request with unauthorized role"], "expected_result": "access is denied", "negative": True, "critical": True, "automatable": True, "evidence_path": "evidence/TEST-1.json"}
    fixture = {"actor": "UNAUTHORIZED_USER", "tenant": "TENANT-A", "initial_state": {"authenticated": True}, "exact_inputs": {"record_id": "R-1"}, "steps": ["request record R-1"], "expected_result": "access is denied", "evidence_path": "evidence/TEST-1.json"}
    return {"story_pack": {"core": {"acceptance_criteria": [criterion]}, "tests": [test]}, "critical_rules": [rule], "fixtures": {"TEST-1": fixture}}


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="j10_semantic_") as tmp:
        tmp_path = Path(tmp)
        positive = tmp_path / "positive.json"
        negative = tmp_path / "negative.json"
        positive.write_text(json.dumps(_positive_payload()), encoding="utf-8")
        broken = _positive_payload()
        broken["fixtures"] = {}
        broken["story_pack"]["tests"][0]["expected_result"] = ""
        negative.write_text(json.dumps(broken), encoding="utf-8")
        pos_checks, _ = validate_payload(_object(load_json(positive), "input"))
        neg_checks, _ = validate_payload(_object(load_json(negative), "input"))
        result = {
            "positive_pass": all(value == 0 for value in pos_checks.values()),
            "negative_rejected": neg_checks["tests_without_exact_fixture"] > 0 and neg_checks["tests_without_expected_result"] > 0,
            "positive_checks": pos_checks,
            "negative_checks": neg_checks,
        }
        print(json.dumps(result, sort_keys=True))
        return 0 if result["positive_pass"] and result["negative_rejected"] else 1


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


if __name__ == "__main__":
    raise SystemExit(main_guard(JUDGE, main))
