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
JUDGE_VERSION = "v0.7"
REGISTRATION = "supabase://private.lf_skill_artifacts/ART_SCRIPT_VALIDATE_TEST_COVERAGE"
PLACEHOLDERS = {"", "todo", "tbd", "placeholder", "example", "n/a"}
TEST_KINDS = {
    "POSITIVE",
    "NEGATIVE",
    "BOUNDARY",
    "REGRESSION",
    "DUPLICATE_RETRY",
    "CONCURRENCY_INTERLEAVING",
    "FAILURE_PATH",
}
TAUTOLOGICAL_ORACLES = {
    "expected result",
    "expected result occurs",
    "result matches expected result",
    "returns expected result",
    "the expected result is returned",
    "test passes",
    "the test passes",
    "resultado esperado",
    "ocurre el resultado esperado",
    "el resultado coincide con el esperado",
    "la prueba pasa",
    "success",
    "ok",
}
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


def _normalize_text(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return " ".join(re.sub(r"[^\w]+", " ", value.casefold(), flags=re.UNICODE).split())


def _coverage_kind(test: dict[str, Any]) -> str:
    raw = test.get("coverage_kind")
    if isinstance(raw, str) and raw.strip():
        return raw.strip().upper()
    return "NEGATIVE" if test.get("negative") is True else "POSITIVE"


def _oracle_text_valid(value: Any, test: dict[str, Any] | None = None) -> bool:
    if not _nonempty_text(value, 5):
        return False
    normalized = _normalize_text(value)
    if normalized in TAUTOLOGICAL_ORACLES:
        return False
    if test:
        for candidate in list(test.get("steps") or []) + list(test.get("preconditions") or []):
            if normalized and normalized == _normalize_text(candidate):
                return False
    return True


def _fixture_exact(fixture: Any, test: dict[str, Any] | None = None) -> bool:
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
    if not _oracle_text_valid(fixture.get("expected_result")) or not _nonempty_text(
        fixture.get("evidence_path"), 3
    ):
        return False
    if test is None:
        return True
    if _normalize_text(fixture.get("expected_result")) != _normalize_text(
        test.get("expected_result")
    ):
        return False
    fixture_steps = [_normalize_text(x) for x in fixture.get("steps", [])]
    test_steps = [_normalize_text(x) for x in test.get("steps", [])]
    if fixture_steps != test_steps:
        return False
    if str(fixture.get("evidence_path") or "").strip() != str(
        test.get("evidence_path") or ""
    ).strip():
        return False
    return True


def _trace_entry_oracles(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    raw = value.get("oracles")
    if not isinstance(raw, dict):
        return {}
    return {
        str(key).upper(): str(item).strip()
        for key, item in raw.items()
        if str(key).upper() in TEST_KINDS and _nonempty_text(item, 5)
    }


def _trace_entry_requirements(value: Any) -> set[str]:
    if not isinstance(value, dict):
        return set()
    raw = value.get("coverage_requirements")
    if not isinstance(raw, list):
        return set()
    return {
        str(item).upper()
        for item in raw
        if isinstance(item, str) and str(item).upper() in TEST_KINDS
    }


def _special_fixture_valid(kind: str, fixture: Any) -> bool:
    if not isinstance(fixture, dict):
        return False
    exact_inputs = fixture.get("exact_inputs")
    steps = fixture.get("steps")
    inputs = exact_inputs if isinstance(exact_inputs, dict) else {}
    step_list = steps if isinstance(steps, list) else []

    if kind == "BOUNDARY":
        return any(
            key in inputs and inputs.get(key) is not None
            for key in (
                "boundary_value",
                "boundary_values",
                "min_value",
                "max_value",
                "out_of_range_value",
            )
        )
    if kind == "REGRESSION":
        return _nonempty_text(inputs.get("regression_case_id"), 3) and (
            _nonempty_text(inputs.get("baseline_ref"), 3)
            or _nonempty_text(inputs.get("previous_behavior_ref"), 3)
        )
    if kind == "DUPLICATE_RETRY":
        attempts = inputs.get("attempts")
        duplicate_requests = inputs.get("duplicate_requests")
        retry_sequence = inputs.get("retry_sequence")
        return (
            isinstance(attempts, int) and attempts >= 2
        ) or (
            isinstance(duplicate_requests, list) and len(duplicate_requests) >= 2
        ) or (
            isinstance(retry_sequence, list) and len(retry_sequence) >= 2
        ) or (
            _nonempty_text(inputs.get("idempotency_key"), 3) and len(step_list) >= 2
        )
    if kind == "CONCURRENCY_INTERLEAVING":
        concurrent_requests = inputs.get("concurrent_requests")
        concurrent_actors = inputs.get("concurrent_actors")
        return len(step_list) >= 2 and (
            isinstance(concurrent_requests, list) and len(concurrent_requests) >= 2
            or isinstance(concurrent_actors, list) and len(concurrent_actors) >= 2
        )
    if kind == "FAILURE_PATH":
        failure_injection = inputs.get("failure_injection")
        return (
            isinstance(failure_injection, dict) and bool(failure_injection)
        ) or _nonempty_text(failure_injection, 3) or _nonempty_text(
            inputs.get("dependency_state"), 3
        ) or _nonempty_text(inputs.get("error_code"), 3)
    return True


def _source_oracle(
    test: dict[str, Any],
    *,
    criterion_map: dict[str, dict[str, Any]],
    criteria_trace: Any,
    rules_trace: Any,
) -> tuple[str | None, str]:
    kind = _coverage_kind(test)
    criterion_ref = test.get("criterion_ref")
    rule_ref = test.get("rule_ref")

    if (
        kind == "POSITIVE"
        and test.get("negative") is not True
        and isinstance(criterion_ref, str)
        and criterion_ref in criterion_map
    ):
        oracle = criterion_map[criterion_ref].get("then")
        if _nonempty_text(oracle, 5):
            return str(oracle).strip(), f"criterion:{criterion_ref}#then"

    if isinstance(rule_ref, str) and isinstance(rules_trace, dict):
        oracles = _trace_entry_oracles(rules_trace.get(rule_ref))
        if kind in oracles:
            return oracles[kind], f"traceability.rules:{rule_ref}.oracles.{kind}"

    if isinstance(criterion_ref, str) and isinstance(criteria_trace, dict):
        oracles = _trace_entry_oracles(criteria_trace.get(criterion_ref))
        if kind in oracles:
            return oracles[kind], f"traceability.criteria:{criterion_ref}.oracles.{kind}"

    return None, "source_oracle_missing"


def _expected_result_status(
    test: dict[str, Any],
    *,
    criterion_map: dict[str, dict[str, Any]],
    criteria_trace: Any,
    rules_trace: Any,
) -> tuple[bool, str, str | None]:
    expected = test.get("expected_result")
    if not _oracle_text_valid(expected, test):
        return False, "tautological_or_missing_expected_result", None
    oracle, oracle_ref = _source_oracle(
        test,
        criterion_map=criterion_map,
        criteria_trace=criteria_trace,
        rules_trace=rules_trace,
    )
    if oracle is None:
        return False, "source_oracle_missing", None
    if not _oracle_text_valid(oracle):
        return False, "source_oracle_invalid", oracle_ref
    if _normalize_text(expected) != _normalize_text(oracle):
        return False, "source_oracle_mismatch", oracle_ref
    return True, "source_oracle_match", oracle_ref


def _rule_requirements(rule: dict[str, Any], trace_entry: Any) -> set[str]:
    required = {"POSITIVE", "NEGATIVE"}
    required |= _trace_entry_requirements(trace_entry)
    if rule.get("requires_boundary") is True:
        required.add("BOUNDARY")
    if rule.get("requires_regression") is True:
        required.add("REGRESSION")
    if rule.get("idempotent") is True:
        required.add("DUPLICATE_RETRY")
    if rule.get("critical_error") is True or rule.get("dependency_failure") is True:
        required.add("FAILURE_PATH")
    if rule.get("mutable_shared_resource") is True:
        required.add("CONCURRENCY_INTERLEAVING")
    return required


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

    criterion_map: dict[str, dict[str, Any]] = {}
    malformed_criteria = 0
    for raw in criteria_list:
        if not isinstance(raw, dict):
            malformed_criteria += 1
            continue
        code = _code(raw, "criterion_code")
        if not code or code in criterion_map:
            malformed_criteria += 1
        else:
            criterion_map[code] = raw
    criterion_codes = set(criterion_map)

    rule_map: dict[str, dict[str, Any]] = {}
    malformed_rules = 0
    for raw in rule_list:
        if not isinstance(raw, dict):
            malformed_rules += 1
            continue
        code = _code(raw, "rule_code", "code")
        if not code or code in rule_map:
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
    records: list[dict[str, Any]] = []
    orphan = 0
    no_expected = 0
    no_trace = 0
    no_fixture = 0
    vacuous = malformed_criteria + malformed_rules
    oracle_issue_codes: dict[str, str] = {}
    fixture_issue_codes: list[str] = []
    unknown_kind_codes: list[str] = []

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
        trace_ok = True
        if not criterion_ref and not rule_ref:
            no_trace += 1
            orphan += 1
            trace_ok = False
        if criterion_ref and criterion_ref not in criterion_codes:
            orphan += 1
            trace_ok = False
        if rule_ref and rule_ref not in rule_map:
            orphan += 1
            trace_ok = False

        explicit_kind = raw.get("coverage_kind")
        kind = _coverage_kind(raw)
        kind_ok = kind in TEST_KINDS
        if explicit_kind is not None and not kind_ok:
            unknown_kind_codes.append(test_code)
            vacuous += 1

        fixture = fixture_map.get(test_code)
        fixture_ok = _fixture_exact(fixture, raw)
        if not fixture_ok:
            no_fixture += 1
            fixture_issue_codes.append(test_code)

        oracle_ok, oracle_reason, oracle_ref = _expected_result_status(
            raw,
            criterion_map=criterion_map,
            criteria_trace=criteria_trace,
            rules_trace=rules_trace,
        )
        if not oracle_ok:
            no_expected += 1
            oracle_issue_codes[test_code] = oracle_reason

        steps_ok = _nonempty_string_list(raw.get("steps"))
        if not steps_ok:
            vacuous += 1

        records.append({
            "test": raw,
            "test_code": test_code,
            "kind": kind,
            "fixture": fixture,
            "fixture_ok": fixture_ok,
            "oracle_ok": oracle_ok,
            "oracle_ref": oracle_ref,
            "trace_ok": trace_ok,
            "kind_ok": kind_ok,
            "steps_ok": steps_ok,
            "valid": fixture_ok and oracle_ok and trace_ok and kind_ok and steps_ok,
        })

    valid_records = [record for record in records if record["valid"]]
    criterion_positive = {
        record["test"].get("criterion_ref")
        for record in valid_records
        if record["kind"] == "POSITIVE"
        and record["test"].get("negative") is not True
        and record["test"].get("criterion_ref") in criterion_codes
    }
    criteria_without_positive = sorted(criterion_codes - criterion_positive)

    rules_missing_polarity: list[dict[str, Any]] = []
    for code in sorted(rule_map):
        bound = [record for record in valid_records if record["test"].get("rule_ref") == code]
        has_positive = any(record["test"].get("negative") is not True for record in bound)
        has_negative = any(record["test"].get("negative") is True for record in bound)
        missing = []
        if not has_positive:
            missing.append("POSITIVE")
        if not has_negative:
            missing.append("NEGATIVE")
        if missing:
            rules_missing_polarity.append({"rule_code": code, "missing": missing})

    def rule_test_exists(
        code: str,
        *,
        family: str | None = None,
        negative: bool | None = None,
        kind: str | None = None,
        tenant_scope: str | None = None,
        require_special_fixture: bool = False,
    ) -> bool:
        for record in valid_records:
            test = record["test"]
            if test.get("rule_ref") != code:
                continue
            if family and test.get("family") != family:
                continue
            if negative is not None and bool(test.get("negative")) is not negative:
                continue
            if kind and record["kind"] != kind:
                continue
            if tenant_scope and test.get("tenant_scope") != tenant_scope:
                continue
            if require_special_fixture and not _special_fixture_valid(
                kind or record["kind"], record["fixture"]
            ):
                continue
            return True
        return False

    permission_missing: list[str] = []
    tenant_missing: list[str] = []
    state_missing: list[str] = []
    idempotency_missing: list[str] = []
    critical_error_missing: list[str] = []
    concurrency_missing: list[str] = []
    boundary_missing: list[str] = []
    regression_missing: list[str] = []

    for code, rule in sorted(rule_map.items()):
        if (rule.get("family") == "PERMISSION" or rule.get("requires_negative") is True) and not rule_test_exists(
            code, family="PERMISSION", negative=True
        ):
            permission_missing.append(code)
        if rule.get("tenant_rule") is True and not rule_test_exists(
            code, family="TENANT", negative=True, tenant_scope="CROSS_TENANT"
        ):
            tenant_missing.append(code)
        if rule.get("family") == "STATE" and not rule_test_exists(
            code, family="STATE", negative=True
        ):
            state_missing.append(code)
        if rule.get("idempotent") is True and not rule_test_exists(
            code,
            family="IDEMPOTENCY",
            kind="DUPLICATE_RETRY",
            require_special_fixture=True,
        ):
            idempotency_missing.append(code)
        if (rule.get("critical_error") is True or rule.get("dependency_failure") is True) and not rule_test_exists(
            code,
            family="ERROR",
            negative=True,
            kind="FAILURE_PATH",
            require_special_fixture=True,
        ):
            critical_error_missing.append(code)
        if rule.get("mutable_shared_resource") is True and not rule_test_exists(
            code,
            family="CONCURRENCY",
            kind="CONCURRENCY_INTERLEAVING",
            require_special_fixture=True,
        ):
            concurrency_missing.append(code)

        trace_entry = rules_trace.get(code) if isinstance(rules_trace, dict) else None
        requirements = _rule_requirements(rule, trace_entry)
        if "BOUNDARY" in requirements and not rule_test_exists(
            code, kind="BOUNDARY", require_special_fixture=True
        ):
            boundary_missing.append(code)
        if "REGRESSION" in requirements and not rule_test_exists(
            code, kind="REGRESSION", require_special_fixture=True
        ):
            regression_missing.append(code)

    checks = {
        "input_envelope_valid": 0 if exact_envelope and envelope_types_valid else 1,
        "traceability_matrix_valid": 0 if traceability_valid else 1,
        "test_environment_valid": 0 if environment_valid else 1,
        "worker_judge_independence": 0
        if executor_identity and worker_identity and executor_identity != worker_identity
        else 1,
        "acceptance_criteria_without_test": len(criteria_without_positive),
        "critical_rule_without_test": len(rules_missing_polarity),
        "permission_without_negative_test": len(permission_missing),
        "tenant_rule_without_cross_tenant_test": len(tenant_missing),
        "state_transition_without_state_test": len(state_missing),
        "idempotent_action_without_duplicate_test": len(idempotency_missing),
        "critical_error_without_test": len(critical_error_missing),
        "mutable_shared_resource_without_concurrency_test": len(concurrency_missing),
        "tests_without_exact_fixture": no_fixture,
        "tests_without_expected_result": no_expected,
        "tests_without_traceability_ref": no_trace,
        "orphan_tests": orphan,
        "vacuous_pass_count": vacuous
        + len(boundary_missing)
        + len(regression_missing)
        + (1 if not criterion_codes or not test_by_code else 0),
    }

    evidence = {
        "checks": checks,
        "acceptance_criteria_count": len(criteria_list),
        "critical_rule_count": len(rule_list),
        "test_case_count": len(tests_list),
        "positive_test_count": sum(
            1 for record in records if record["test"].get("negative") is not True
        ),
        "negative_test_count": sum(
            1 for record in records if record["test"].get("negative") is True
        ),
        "exact_fixture_count": sum(
            1 for record in records if record["fixture_ok"]
        ),
        "families_covered": sorted(
            {
                str(record["test"].get("family"))
                for record in records
                if record["test"].get("family")
            }
        ),
        "coverage_kinds_covered": sorted({record["kind"] for record in records}),
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
        "semantic_quality_breakdown": {
            "criteria_without_valid_positive": criteria_without_positive,
            "rules_missing_positive_or_negative": rules_missing_polarity,
            "permission_negative_missing": permission_missing,
            "tenant_cross_tenant_missing": tenant_missing,
            "state_negative_missing": state_missing,
            "idempotency_duplicate_retry_missing": idempotency_missing,
            "failure_path_missing": critical_error_missing,
            "concurrency_interleaving_missing": concurrency_missing,
            "boundary_missing": boundary_missing,
            "regression_missing": regression_missing,
            "oracle_issues": oracle_issue_codes,
            "fixture_issues": sorted(set(fixture_issue_codes)),
            "unknown_coverage_kind": sorted(set(unknown_kind_codes)),
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
        "given": "account R-1 exists",
        "when": "authorized user requests R-1",
        "then": "record R-1 is displayed to the authorized user",
        "source_ref": "SRC-1",
    }
    rule = {
        "rule_code": "PERM-1",
        "family": "PERMISSION",
        "requires_negative": True,
        "tenant_rule": False,
        "idempotent": False,
        "critical_error": False,
        "dependency_failure": False,
        "mutable_shared_resource": False,
        "requires_boundary": False,
        "requires_regression": False,
        "source_ref": "SRC-PERM-1",
    }
    tests = [
        {
            "test_code": "TEST-AC-1-POS",
            "family": "FUNCTIONAL",
            "coverage_kind": "POSITIVE",
            "criterion_ref": "AC-1",
            "rule_ref": None,
            "preconditions": ["account R-1 exists"],
            "steps": ["authorized user requests record R-1"],
            "expected_result": "record R-1 is displayed to the authorized user",
            "negative": False,
            "critical": True,
            "automatable": True,
            "evidence_path": "evidence/TEST-AC-1-POS.json",
        },
        {
            "test_code": "TEST-PERM-1-POS",
            "family": "PERMISSION",
            "coverage_kind": "POSITIVE",
            "criterion_ref": None,
            "rule_ref": "PERM-1",
            "preconditions": ["authorized user has read permission"],
            "steps": ["authorized user requests record R-1"],
            "expected_result": "record R-1 is returned to an authorized user",
            "negative": False,
            "critical": True,
            "automatable": True,
            "evidence_path": "evidence/TEST-PERM-1-POS.json",
        },
        {
            "test_code": "TEST-PERM-1-NEG",
            "family": "PERMISSION",
            "coverage_kind": "NEGATIVE",
            "criterion_ref": None,
            "rule_ref": "PERM-1",
            "preconditions": ["user lacks read permission"],
            "steps": ["unauthorized user requests record R-1"],
            "expected_result": "access is denied and no record attributes are returned",
            "negative": True,
            "critical": True,
            "automatable": True,
            "evidence_path": "evidence/TEST-PERM-1-NEG.json",
        },
    ]
    fixtures = {
        "TEST-AC-1-POS": {
            "actor": "AUTHORIZED_USER",
            "tenant": "TENANT-A",
            "initial_state": {"authenticated": True},
            "exact_inputs": {"record_id": "R-1"},
            "steps": ["authorized user requests record R-1"],
            "expected_result": "record R-1 is displayed to the authorized user",
            "evidence_path": "evidence/TEST-AC-1-POS.json",
        },
        "TEST-PERM-1-POS": {
            "actor": "AUTHORIZED_USER",
            "tenant": "TENANT-A",
            "initial_state": {"authenticated": True, "permission": "READ"},
            "exact_inputs": {"record_id": "R-1"},
            "steps": ["authorized user requests record R-1"],
            "expected_result": "record R-1 is returned to an authorized user",
            "evidence_path": "evidence/TEST-PERM-1-POS.json",
        },
        "TEST-PERM-1-NEG": {
            "actor": "UNAUTHORIZED_USER",
            "tenant": "TENANT-A",
            "initial_state": {"authenticated": True, "permission": "NONE"},
            "exact_inputs": {"record_id": "R-1"},
            "steps": ["unauthorized user requests record R-1"],
            "expected_result": "access is denied and no record attributes are returned",
            "evidence_path": "evidence/TEST-PERM-1-NEG.json",
        },
    }
    return {
        "story_pack": {
            "core": {"acceptance_criteria": [criterion]},
            "tests": tests,
        },
        "critical_rules": [rule],
        "fixtures": fixtures,
        "traceability_matrix": {
            "criteria": {
                "AC-1": {
                    "refs": ["SRC-1"],
                    "oracles": {
                        "NEGATIVE": "record R-1 is not displayed when authorization is missing"
                    },
                }
            },
            "rules": {
                "PERM-1": {
                    "refs": ["SRC-PERM-1"],
                    "coverage_requirements": ["POSITIVE", "NEGATIVE"],
                    "oracles": {
                        "POSITIVE": "record R-1 is returned to an authorized user",
                        "NEGATIVE": "access is denied and no record attributes are returned",
                    },
                }
            },
        },
        "test_environment": {
            "actors": ["AUTHORIZED_USER", "UNAUTHORIZED_USER"],
            "tenants": ["TENANT-A", "TENANT-B"],
            "initial_states": ["READY"],
            "data_sets": ["DATASET-1"],
            "restrictions": ["NO_PRODUCTION_DATA"],
        },
    }


def _special_positive_payload() -> dict[str, Any]:
    payload = copy.deepcopy(_positive_payload())

    def add_rule(rule: dict[str, Any], oracles: dict[str, str]) -> None:
        code = str(rule["rule_code"])
        payload["critical_rules"].append(rule)
        payload["traceability_matrix"]["rules"][code] = {
            "refs": [str(rule["source_ref"])],
            "coverage_requirements": sorted(
                _rule_requirements(rule, {"coverage_requirements": []})
            ),
            "oracles": oracles,
        }

    def add_test(
        *,
        code: str,
        rule_code: str,
        family: str,
        kind: str,
        expected: str,
        negative: bool,
        exact_inputs: dict[str, Any],
        steps: list[str] | None = None,
        tenant_scope: str | None = None,
    ) -> None:
        test_steps = steps or [f"execute {code.lower()} against controlled fixture"]
        test = {
            "test_code": code,
            "family": family,
            "coverage_kind": kind,
            "criterion_ref": None,
            "rule_ref": rule_code,
            "preconditions": ["controlled precondition is established"],
            "steps": test_steps,
            "expected_result": expected,
            "negative": negative,
            "critical": True,
            "automatable": True,
            "evidence_path": f"evidence/{code}.json",
        }
        if tenant_scope is not None:
            test["tenant_scope"] = tenant_scope
        payload["story_pack"]["tests"].append(test)
        payload["fixtures"][code] = {
            "actor": "AUTHORIZED_USER",
            "tenant": "TENANT-A",
            "initial_state": {"state": "READY"},
            "exact_inputs": exact_inputs,
            "steps": test_steps,
            "expected_result": expected,
            "evidence_path": f"evidence/{code}.json",
        }

    add_rule(
        {
            "rule_code": "VAL-1",
            "family": "VALIDATION",
            "requires_negative": False,
            "tenant_rule": False,
            "idempotent": False,
            "critical_error": False,
            "dependency_failure": False,
            "mutable_shared_resource": False,
            "requires_boundary": True,
            "requires_regression": True,
            "source_ref": "SRC-VAL-1",
        },
        {
            "POSITIVE": "value 10 is accepted",
            "NEGATIVE": "value 101 is rejected",
            "BOUNDARY": "boundary value 100 is accepted",
            "REGRESSION": "previously valid value 10 remains accepted",
        },
    )
    add_test(code="TEST-VAL-POS", rule_code="VAL-1", family="VALIDATION", kind="POSITIVE", expected="value 10 is accepted", negative=False, exact_inputs={"value": 10})
    add_test(code="TEST-VAL-NEG", rule_code="VAL-1", family="VALIDATION", kind="NEGATIVE", expected="value 101 is rejected", negative=True, exact_inputs={"value": 101})
    add_test(code="TEST-VAL-BOUNDARY", rule_code="VAL-1", family="VALIDATION", kind="BOUNDARY", expected="boundary value 100 is accepted", negative=False, exact_inputs={"boundary_value": 100})
    add_test(code="TEST-VAL-REGRESSION", rule_code="VAL-1", family="VALIDATION", kind="REGRESSION", expected="previously valid value 10 remains accepted", negative=False, exact_inputs={"regression_case_id": "REG-VAL-1", "baseline_ref": "BASELINE-v1", "value": 10})

    add_rule(
        {
            "rule_code": "STATE-1",
            "family": "STATE",
            "requires_negative": False,
            "tenant_rule": False,
            "idempotent": False,
            "critical_error": False,
            "dependency_failure": False,
            "mutable_shared_resource": False,
            "requires_boundary": False,
            "requires_regression": False,
            "source_ref": "SRC-STATE-1",
        },
        {"POSITIVE": "valid transition moves READY to DONE", "NEGATIVE": "invalid transition is rejected and READY is preserved"},
    )
    add_test(code="TEST-STATE-POS", rule_code="STATE-1", family="STATE", kind="POSITIVE", expected="valid transition moves READY to DONE", negative=False, exact_inputs={"from": "READY", "to": "DONE"})
    add_test(code="TEST-STATE-NEG", rule_code="STATE-1", family="STATE", kind="NEGATIVE", expected="invalid transition is rejected and READY is preserved", negative=True, exact_inputs={"from": "READY", "to": "UNKNOWN"})

    add_rule(
        {
            "rule_code": "IDEM-1",
            "family": "IDEMPOTENCY",
            "requires_negative": False,
            "tenant_rule": False,
            "idempotent": True,
            "critical_error": False,
            "dependency_failure": False,
            "mutable_shared_resource": False,
            "requires_boundary": False,
            "requires_regression": False,
            "source_ref": "SRC-IDEM-1",
        },
        {"POSITIVE": "first request creates one effect", "NEGATIVE": "duplicate request does not create a second effect", "DUPLICATE_RETRY": "two attempts with the same idempotency key create one effect"},
    )
    add_test(code="TEST-IDEM-POS", rule_code="IDEM-1", family="IDEMPOTENCY", kind="POSITIVE", expected="first request creates one effect", negative=False, exact_inputs={"idempotency_key": "IDEM-K-1"})
    add_test(code="TEST-IDEM-NEG", rule_code="IDEM-1", family="IDEMPOTENCY", kind="NEGATIVE", expected="duplicate request does not create a second effect", negative=True, exact_inputs={"idempotency_key": "IDEM-K-1", "attempts": 2}, steps=["send first request with IDEM-K-1", "send duplicate request with IDEM-K-1"])
    add_test(code="TEST-IDEM-DUP", rule_code="IDEM-1", family="IDEMPOTENCY", kind="DUPLICATE_RETRY", expected="two attempts with the same idempotency key create one effect", negative=True, exact_inputs={"idempotency_key": "IDEM-K-1", "attempts": 2}, steps=["send first request with IDEM-K-1", "retry same request with IDEM-K-1"])

    add_rule(
        {
            "rule_code": "ERR-1",
            "family": "ERROR",
            "requires_negative": False,
            "tenant_rule": False,
            "idempotent": False,
            "critical_error": True,
            "dependency_failure": False,
            "mutable_shared_resource": False,
            "requires_boundary": False,
            "requires_regression": False,
            "source_ref": "SRC-ERR-1",
        },
        {"POSITIVE": "healthy dependency returns the requested result", "NEGATIVE": "dependency error is surfaced as controlled failure", "FAILURE_PATH": "dependency timeout returns controlled error without partial commit"},
    )
    add_test(code="TEST-ERR-POS", rule_code="ERR-1", family="ERROR", kind="POSITIVE", expected="healthy dependency returns the requested result", negative=False, exact_inputs={"dependency_state": "HEALTHY"})
    add_test(code="TEST-ERR-FAIL", rule_code="ERR-1", family="ERROR", kind="FAILURE_PATH", expected="dependency timeout returns controlled error without partial commit", negative=True, exact_inputs={"failure_injection": {"type": "TIMEOUT"}})

    add_rule(
        {
            "rule_code": "DEP-1",
            "family": "ERROR",
            "requires_negative": False,
            "tenant_rule": False,
            "idempotent": False,
            "critical_error": False,
            "dependency_failure": True,
            "mutable_shared_resource": False,
            "requires_boundary": False,
            "requires_regression": False,
            "source_ref": "SRC-DEP-1",
        },
        {"POSITIVE": "available dependency completes the operation", "NEGATIVE": "unavailable dependency blocks the operation", "FAILURE_PATH": "dependency unavailable produces controlled failure and no write"},
    )
    add_test(code="TEST-DEP-POS", rule_code="DEP-1", family="ERROR", kind="POSITIVE", expected="available dependency completes the operation", negative=False, exact_inputs={"dependency_state": "AVAILABLE"})
    add_test(code="TEST-DEP-FAIL", rule_code="DEP-1", family="ERROR", kind="FAILURE_PATH", expected="dependency unavailable produces controlled failure and no write", negative=True, exact_inputs={"dependency_state": "UNAVAILABLE"})

    add_rule(
        {
            "rule_code": "CONC-1",
            "family": "CONCURRENCY",
            "requires_negative": False,
            "tenant_rule": False,
            "idempotent": False,
            "critical_error": False,
            "dependency_failure": False,
            "mutable_shared_resource": True,
            "requires_boundary": False,
            "requires_regression": False,
            "source_ref": "SRC-CONC-1",
        },
        {"POSITIVE": "single request updates shared resource once", "NEGATIVE": "competing request cannot create an invalid duplicate", "CONCURRENCY_INTERLEAVING": "two competing requests preserve one valid shared state"},
    )
    add_test(code="TEST-CONC-POS", rule_code="CONC-1", family="CONCURRENCY", kind="POSITIVE", expected="single request updates shared resource once", negative=False, exact_inputs={"request_id": "REQ-1"})
    add_test(code="TEST-CONC-NEG", rule_code="CONC-1", family="CONCURRENCY", kind="NEGATIVE", expected="competing request cannot create an invalid duplicate", negative=True, exact_inputs={"request_id": "REQ-2"})
    add_test(code="TEST-CONC-INTERLEAVE", rule_code="CONC-1", family="CONCURRENCY", kind="CONCURRENCY_INTERLEAVING", expected="two competing requests preserve one valid shared state", negative=True, exact_inputs={"concurrent_requests": ["REQ-A", "REQ-B"]}, steps=["start REQ-A against shared resource", "interleave REQ-B before REQ-A commits", "read back the shared resource"])

    return payload


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
    extended = _special_positive_payload()
    meta = _runtime_meta()
    sha = meta["semantic_validator_sha256"]
    executor = "J10_INDEPENDENT_EXECUTOR"
    worker = "STORY_TEST_DERIVER_WORKER"

    def build_good(payload: dict[str, Any], label: str) -> dict[str, Any]:
        return build_result(
            payload,
            [f"self-test://{label}"],
            0,
            executor_identity=executor,
            worker_identity=worker,
            judge_version=JUDGE_VERSION,
            registered_sha256=sha,
            registration=REGISTRATION,
            command=f"self-test:{label}",
        )

    positive = build_good(good, "positive")
    extended_positive = build_good(extended, "extended-positive")
    tests: list[dict[str, Any]] = []

    def negative_case(name: str, payload: dict[str, Any], assertion: str, expected: str = "RETURN_TO_WORKER", **overrides: Any) -> None:
        tests.append(_negative_case(
            name,
            payload,
            expected,
            assertion,
            executor=overrides.get("executor", executor),
            worker=overrides.get("worker", worker),
            version=overrides.get("version", JUDGE_VERSION),
            registered_sha=overrides.get("registered_sha", sha),
            registration=overrides.get("registration", REGISTRATION),
            runtime_available=overrides.get("runtime_available", True),
        ))

    x = copy.deepcopy(good); x.pop("traceability_matrix")
    negative_case("missing_traceability_matrix", x, "input_envelope_valid")

    x = copy.deepcopy(good); x.pop("test_environment")
    negative_case("missing_test_environment", x, "input_envelope_valid")

    x = copy.deepcopy(good); x["traceability_matrix"]["criteria"]["AC-1"] = []
    negative_case("invalid_traceability_matrix", x, "traceability_matrix_valid")

    x = copy.deepcopy(good); x["test_environment"]["tenants"] = []
    negative_case("invalid_test_environment", x, "test_environment_valid")

    x = copy.deepcopy(good); x["fixtures"].pop("TEST-AC-1-POS")
    negative_case("missing_exact_fixture", x, "tests_without_exact_fixture")

    x = copy.deepcopy(good); x["story_pack"]["tests"][0]["expected_result"] = ""
    negative_case("empty_expected_result", x, "tests_without_expected_result")

    x = copy.deepcopy(good); x["story_pack"]["tests"][0]["criterion_ref"] = "AC-UNKNOWN"
    negative_case("orphan_test", x, "orphan_tests")

    x = copy.deepcopy(good); x["story_pack"]["tests"][0]["steps"] = ["todo"]
    negative_case("vacuous_test", x, "vacuous_pass_count")

    negative_case("missing_runtime", good, "semantic_validator_unavailable", expected="BLOCKED", runtime_available=False)
    negative_case("unregistered_runtime", good, "semantic_validator_unregistered", expected="BLOCKED", registration="")
    negative_case("runtime_sha_mismatch", good, "semantic_validator_sha_unreconciled", expected="BLOCKED", registered_sha="0" * 64)
    negative_case("missing_executor_identity", good, "executor_identity_missing", expected="BLOCKED", executor=None)
    negative_case("missing_worker_identity", good, "worker_identity_missing", expected="BLOCKED", worker=None)
    negative_case("worker_self_executes", good, "worker_judge_independence_broken", expected="BLOCKED", executor=worker)
    negative_case("missing_judge_version", good, "judge_version_missing", expected="BLOCKED", version=None)

    # P3 false-pass regressions.
    x = copy.deepcopy(good)
    ac = next(t for t in x["story_pack"]["tests"] if t["test_code"] == "TEST-AC-1-POS")
    ac.update({"coverage_kind": "NEGATIVE", "negative": True, "expected_result": "record R-1 is not displayed when authorization is missing"})
    x["fixtures"]["TEST-AC-1-POS"]["expected_result"] = ac["expected_result"]
    negative_case("AC_NEGATIVE_ONLY", x, "acceptance_criteria_without_test")

    x = copy.deepcopy(good)
    x["story_pack"]["tests"] = [t for t in x["story_pack"]["tests"] if t["test_code"] != "TEST-PERM-1-POS"]
    x["fixtures"].pop("TEST-PERM-1-POS")
    negative_case("CRITICAL_RULE_NEGATIVE_ONLY", x, "critical_rule_without_test")

    x = copy.deepcopy(extended)
    x["story_pack"]["tests"] = [t for t in x["story_pack"]["tests"] if t["test_code"] != "TEST-VAL-BOUNDARY"]
    x["fixtures"].pop("TEST-VAL-BOUNDARY")
    negative_case("BOUNDARY_CASE_MISSING", x, "vacuous_pass_count")

    x = copy.deepcopy(extended)
    x["story_pack"]["tests"] = [t for t in x["story_pack"]["tests"] if t["test_code"] != "TEST-VAL-REGRESSION"]
    x["fixtures"].pop("TEST-VAL-REGRESSION")
    negative_case("REGRESSION_CASE_MISSING", x, "vacuous_pass_count")

    x = copy.deepcopy(good)
    x["story_pack"]["core"]["acceptance_criteria"][0]["then"] = "expected result occurs"
    ac = next(t for t in x["story_pack"]["tests"] if t["test_code"] == "TEST-AC-1-POS")
    ac["expected_result"] = "expected result occurs"
    x["fixtures"]["TEST-AC-1-POS"]["expected_result"] = "expected result occurs"
    negative_case("TAUTOLOGICAL_EXPECTED_RESULT", x, "tests_without_expected_result")

    x = copy.deepcopy(good)
    x["fixtures"]["TEST-AC-1-POS"]["expected_result"] = "record R-2 is displayed to the authorized user"
    negative_case("FIXTURE_EXPECTED_MISMATCH", x, "tests_without_exact_fixture")

    x = copy.deepcopy(extended)
    x["story_pack"]["tests"] = [t for t in x["story_pack"]["tests"] if t["test_code"] != "TEST-STATE-NEG"]
    x["fixtures"].pop("TEST-STATE-NEG")
    negative_case("STATE_INVARIANT_WITHOUT_NEGATIVE", x, "state_transition_without_state_test")

    x = copy.deepcopy(extended)
    x["fixtures"]["TEST-IDEM-DUP"]["exact_inputs"] = {"idempotency_key": "IDEM-K-1", "attempts": 1}
    x["fixtures"]["TEST-IDEM-DUP"]["steps"] = ["send first request with IDEM-K-1"]
    x["story_pack"]["tests"] = [
        ({**t, "steps": ["send first request with IDEM-K-1"]} if t["test_code"] == "TEST-IDEM-DUP" else t)
        for t in x["story_pack"]["tests"]
    ]
    negative_case("IDEMPOTENT_WITHOUT_RETRY_DUPLICATE", x, "idempotent_action_without_duplicate_test")

    x = copy.deepcopy(extended)
    err = next(t for t in x["story_pack"]["tests"] if t["test_code"] == "TEST-ERR-FAIL")
    err.update({"coverage_kind": "NEGATIVE", "expected_result": "dependency error is surfaced as controlled failure"})
    x["fixtures"]["TEST-ERR-FAIL"]["expected_result"] = err["expected_result"]
    negative_case("CRITICAL_ERROR_WITHOUT_NEGATIVE", x, "critical_error_without_test")

    x = copy.deepcopy(extended)
    dep = next(t for t in x["story_pack"]["tests"] if t["test_code"] == "TEST-DEP-FAIL")
    dep.update({"coverage_kind": "NEGATIVE", "expected_result": "unavailable dependency blocks the operation"})
    x["fixtures"]["TEST-DEP-FAIL"]["expected_result"] = dep["expected_result"]
    negative_case("DEPENDENCY_FAILURE_PATH_MISSING", x, "critical_error_without_test")

    x = copy.deepcopy(extended)
    x["fixtures"]["TEST-CONC-INTERLEAVE"]["exact_inputs"] = {"concurrent_requests": ["REQ-A"]}
    negative_case("CONCURRENCY_WITH_SINGLE_THREAD_TEST", x, "mutable_shared_resource_without_concurrency_test")

    # Real false-pass shape: a positive AC oracle contradicts the source `then`.
    x = copy.deepcopy(good)
    ac = next(t for t in x["story_pack"]["tests"] if t["test_code"] == "TEST-AC-1-POS")
    ac["expected_result"] = "invalid state is accepted and replaces the prior valid state"
    x["fixtures"]["TEST-AC-1-POS"]["expected_result"] = ac["expected_result"]
    negative_case("REAL_CANDIDATE_WRONG_ORACLE", x, "tests_without_expected_result")

    summary = {
        "positive_pass": positive["result"] == "PASS_WITH_EVIDENCE",
        "positive_assertions_passed": positive["assertions_passed"],
        "positive_assertions_total": positive["assertions_total"],
        "extended_positive_pass": extended_positive["result"] == "PASS_WITH_EVIDENCE",
        "extended_positive_assertions_passed": extended_positive["assertions_passed"],
        "extended_positive_assertions_total": extended_positive["assertions_total"],
        "negative_cases": tests,
        "negative_passed": sum(1 for test in tests if test["passed"]),
        "negative_total": len(tests),
        "runtime_sha256": sha,
        "registration": REGISTRATION,
        "judge_version": JUDGE_VERSION,
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0 if (
        summary["positive_pass"]
        and summary["extended_positive_pass"]
        and summary["positive_assertions_passed"] == len(ASSERTIONS)
        and summary["positive_assertions_total"] == len(ASSERTIONS)
        and summary["extended_positive_assertions_passed"] == len(ASSERTIONS)
        and summary["extended_positive_assertions_total"] == len(ASSERTIONS)
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