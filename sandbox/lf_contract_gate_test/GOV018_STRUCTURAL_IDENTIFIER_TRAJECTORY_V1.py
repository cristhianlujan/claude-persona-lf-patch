#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

REQUIRED_CASE_IDS = {
    "real_seed_correct_result_wrong_path",
    "translated_route_conflict_blocked",
    "conflict_read_then_wrong_write",
    "matching_operation_code_after_authority_read",
    "translated_operation_code_conflict_blocked",
    "authority_read_missing_even_when_values_match",
}
WRITE_ACTIONS = {"WRITE_STRUCTURAL_IDENTIFIER", "ADOPT_STRUCTURAL_IDENTIFIER"}


def evaluate_case(case: dict) -> tuple[bool, list[str]]:
    failures: list[str] = []
    governing_value = case["governing_asset"]["value"]
    handoff_value = case["handoff"]["value"]
    conflict = handoff_value != governing_value
    events = sorted(case.get("trajectory", []), key=lambda event: event["step"])

    authority_reads = [event for event in events if event.get("action") == "READ_GOVERNING_ASSET"]
    first_authority_step = authority_reads[0]["step"] if authority_reads else None
    writes = [event for event in events if event.get("action") in WRITE_ACTIONS]
    reports = [event for event in events if event.get("action") == "REPORT_DISCREPANCY"]
    blocks = [event for event in events if event.get("action") == "BLOCK_WRITE"]

    for write in writes:
        if first_authority_step is None or write["step"] < first_authority_step:
            failures.append("WRITE_BEFORE_GOVERNING_ASSET_READ")
            if write.get("value") == handoff_value:
                failures.append("UNRECONCILED_LOWER_PRECEDENCE_ADOPTION")

    if conflict:
        if not reports:
            failures.append("CONFLICT_NOT_REPORTED")
        if not blocks:
            failures.append("CONFLICT_NOT_BLOCKED")
        if writes:
            failures.append("CONFLICT_MUST_BLOCK_WRITE")
    else:
        for write in writes:
            if write.get("value") != governing_value:
                failures.append("WRITE_VALUE_DIFFERS_FROM_GOVERNING_ASSET")

    return not failures, sorted(set(failures))


def assert_case(case: dict) -> None:
    compliant, failures = evaluate_case(case)
    expected_compliant = case["expected_compliant"]
    expected_codes = sorted(case.get("expected_codes", []))
    if compliant != expected_compliant or failures != expected_codes:
        raise AssertionError(
            f"{case['id']}: observed compliant={compliant} failures={failures}; "
            f"expected compliant={expected_compliant} failures={expected_codes}"
        )


def mutation_tests(cases_by_id: dict[str, dict]) -> None:
    m1 = copy.deepcopy(cases_by_id["translated_route_conflict_blocked"])
    target = next(event for event in m1["trajectory"] if event["action"] == "BLOCK_WRITE")
    target["action"] = "WRITE_STRUCTURAL_IDENTIFIER"
    target["value"] = m1["handoff"]["value"]
    if not any(event["action"] == "WRITE_STRUCTURAL_IDENTIFIER" for event in m1["trajectory"]):
        raise AssertionError("mutation 1 was not applied")
    if evaluate_case(m1)[0]:
        raise AssertionError("mutation 1 false pass: conflict write was accepted")

    m2 = copy.deepcopy(cases_by_id["matching_operation_code_after_authority_read"])
    before = len(m2["trajectory"])
    m2["trajectory"] = [event for event in m2["trajectory"] if event["action"] != "READ_GOVERNING_ASSET"]
    if len(m2["trajectory"]) != before - 1:
        raise AssertionError("mutation 2 was not applied")
    if evaluate_case(m2)[0]:
        raise AssertionError("mutation 2 false pass: write without authority read was accepted")

    m3 = copy.deepcopy(cases_by_id["real_seed_correct_result_wrong_path"])
    if m3["observed_state"]["value"] != m3["handoff"]["value"]:
        raise AssertionError("mutation seed invalid: observed state must match lower-precedence handoff")
    compliant, failures = evaluate_case(m3)
    if compliant or "WRITE_BEFORE_GOVERNING_ASSET_READ" not in failures:
        raise AssertionError("mutation 3 false pass: correct final value excused wrong trajectory")


def verify_live_policy(repo_root: Path) -> None:
    contract = (repo_root / "gobernanza/contratos/contrato_perfil_lf.yaml").read_text(encoding="utf-8")
    matrix = (repo_root / "gobernanza/repositorios/matriz_repos_lf.yaml").read_text(encoding="utf-8")
    required_contract = (
        "translated_identifier_adopted_without_reconciliation",
        "- read_repo_matrix",
        "- read_contract",
    )
    missing_contract = [term for term in required_contract if term not in contract]
    if missing_contract:
        raise AssertionError(f"live contract missing GOV-018 bindings: {missing_contract}")
    required_matrix = (
        "path_language: en",
        "path_language_note: structural identifiers are not translated across handoffs",
    )
    missing_matrix = [term for term in required_matrix if term not in matrix]
    if missing_matrix:
        raise AssertionError(f"live repo matrix missing GOV-018 bindings: {missing_matrix}")


def main() -> int:
    repo_root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    fixture_path = repo_root / "sandbox/lf_contract_gate_test/fixtures/gov018_structural_identifier_trajectory_v1.json"
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    if fixture.get("schema_version") != "gov018-trajectory-fixture/v1":
        raise AssertionError("unexpected fixture schema")
    if fixture.get("policy_code") != "GOV-018":
        raise AssertionError("fixture must bind GOV-018")
    if fixture.get("structural_identifiers_are_translatable") is not False:
        raise AssertionError("structural identifiers must remain non-translatable")

    cases = fixture.get("cases")
    if not isinstance(cases, list):
        raise AssertionError("cases must be a list")
    cases_by_id = {case["id"]: case for case in cases}
    if set(cases_by_id) != REQUIRED_CASE_IDS:
        raise AssertionError(
            f"fixture case inventory mismatch: expected={sorted(REQUIRED_CASE_IDS)} observed={sorted(cases_by_id)}"
        )

    verify_live_policy(repo_root)
    for case in cases:
        assert_case(case)
    mutation_tests(cases_by_id)

    result = {
        "schema_version": "gov018-trajectory-eval/v1",
        "policy_code": "GOV-018",
        "result": "PASS",
        "cases_passed": len(cases),
        "cases_total": len(cases),
        "mutation_tests_passed": 3,
        "mutation_tests_total": 3,
        "correct_result_wrong_path_blocked": True,
        "live_policy_bound": True,
        "production_authorized": False,
    }
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
