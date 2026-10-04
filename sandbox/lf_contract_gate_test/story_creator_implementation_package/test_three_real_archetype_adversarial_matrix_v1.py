#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
MATRIX_PATH = HERE / "fixtures" / "three_real_archetype_adversarial_matrix_v1.json"
CONTRACT_PATH = HERE / "story_creator_implementation_contract_v2.json"
BINDING_PATH = HERE / "programming_agent_story_consumer_binding_v1.json"

EXPECTED_CASES = {f"RC-{n:03d}" for n in range(25, 37)}
EXPECTED_ARCHETYPES = {
    "BULK_UPLOAD_WIZARD": ("B2B-CARGA-002", "B2B_APP_SHELL"),
    "CLIENT_OFFER_HOME": ("HOME_002", "CLIENT_APP_SHELL"),
    "CLIENT_ACCESS_RECOVERY": ("REC_001", "CLIENT_APP_SHELL"),
}
MANDATORY_COVERAGE = {
    "FALSE_READY_MISSING_PRECONDITION",
    "API",
    "NFR",
    "MOBILE",
    "ANALYTICS",
    "PHYSICAL_MAPPING",
    "DESIGN_AUTHORITY",
}


def validate(matrix: dict, contract: dict, binding: dict) -> list[str]:
    errors: list[str] = []
    if matrix.get("schema_version") != "STORY_THREE_REAL_ARCHETYPE_ADVERSARIAL_MATRIX_V1":
        return ["MATRIX_SCHEMA_INVALID"]
    if matrix.get("owner_scope") != "SUPER_ADMIN":
        errors.append("OWNER_SCOPE_NOT_SUPER_ADMIN")

    archetypes = matrix.get("archetypes", [])
    if len(archetypes) != 3:
        errors.append("ARCHETYPE_COUNT_NOT_THREE")
    observed: dict[str, tuple[str, str]] = {}
    for a in archetypes:
        code = a.get("archetype_code")
        screen = a.get("screen", {})
        if screen.get("screen_code") == "ONB_004":
            errors.append("ONB004_REUSED_AS_ADDITIONAL_ARCHETYPE")
        if screen.get("screen_active") is not True or screen.get("module_active") is not True:
            errors.append(f"ARCHETYPE_NOT_ACTIVE:{code}")
        if not screen.get("id") or not screen.get("module_code") or not screen.get("app_shell_code"):
            errors.append(f"ARCHETYPE_IDENTITY_INCOMPLETE:{code}")
        observed[code] = (screen.get("screen_code"), screen.get("app_shell_code"))
    if observed != EXPECTED_ARCHETYPES:
        errors.append("ARCHETYPE_IDENTITY_DRIFT")
    if {shell for _, shell in observed.values()} != {"B2B_APP_SHELL", "CLIENT_APP_SHELL"}:
        errors.append("CROSS_SHELL_REPRESENTATION_MISSING")

    cases = matrix.get("cases", [])
    ids = [c.get("case_id") for c in cases]
    if len(cases) != 12 or set(ids) != EXPECTED_CASES or len(ids) != len(set(ids)):
        errors.append("RC025_RC036_COVERAGE_NOT_EXACT")
    counts = Counter(c.get("archetype_code") for c in cases)
    if counts != Counter({k: 4 for k in EXPECTED_ARCHETYPES}):
        errors.append("ARCHETYPE_CASE_DISTRIBUTION_NOT_4_EACH")

    tags = {tag for c in cases for tag in c.get("coverage_tags", [])}
    missing_tags = sorted(MANDATORY_COVERAGE - tags)
    if missing_tags:
        errors.append("MANDATORY_FAILURE_COVERAGE_MISSING:" + ",".join(missing_tags))

    for c in cases:
        cid = c.get("case_id")
        if c.get("archetype_code") not in EXPECTED_ARCHETYPES:
            errors.append(f"UNKNOWN_ARCHETYPE:{cid}")
        if c.get("expected_decision") != "BLOCKED_AFFECTED_SCOPE":
            errors.append(f"FAILURE_NOT_FAIL_CLOSED:{cid}")
        if not c.get("trigger") or not c.get("required_evidence") or not c.get("authority_rule_ref"):
            errors.append(f"CASE_NOT_AUDITABLE:{cid}")

    by_id = {c.get("case_id"): c for c in cases if c.get("case_id")}
    rc027 = by_id.get("RC-027")
    if rc027 is not None and "DESIGN_AUTHORITY" not in rc027.get("coverage_tags", []):
        errors.append("RC027_DESIGN_AUTHORITY_NOT_COVERED")
    rc028 = by_id.get("RC-028")
    if rc028 is not None and rc028.get("archetype_code") != "BULK_UPLOAD_WIZARD":
        errors.append("RC028_NOT_BOUND_TO_B2B_ARCHETYPE")
    rc033 = by_id.get("RC-033")
    if rc033 is not None and not {"NFR", "MOBILE", "ANALYTICS"}.issubset(rc033.get("coverage_tags", [])):
        errors.append("RC033_NFR_MOBILE_ANALYTICS_COVERAGE_MISSING")
    rc031 = by_id.get("RC-031")
    if rc031 is not None and rc031.get("authority_rule_ref") != "system-invariant://I12-ORACLE-ISOLATION":
        errors.append("RC031_ORACLE_ISOLATION_AUTHORITY_DRIFT")
    rc030 = by_id.get("RC-030")
    if rc030 is not None and not rc030.get("authority_rule_ref", "").startswith(binding.get("schema_version", "") + "#"):
        errors.append("RC030_LOSSLESS_BINDING_AUTHORITY_DRIFT")
    rc036 = by_id.get("RC-036")
    if rc036 is not None and not rc036.get("authority_rule_ref", "").startswith(binding.get("schema_version", "") + "#"):
        errors.append("RC036_COMPATIBILITY_AUTHORITY_DRIFT")

    if contract.get("material_requirement_contract", {}).get("blocking_rule") != "UNRESOLVED_REQUIRED_BLOCKS_AFFECTED_SCOPE_ONLY":
        errors.append("CURRENT_CONTRACT_LOCAL_BLOCKING_DRIFT")
    if contract.get("authority_precedence", {}).get("design_literals_require_canonical_design_authority") is not True:
        errors.append("CURRENT_CONTRACT_DESIGN_AUTHORITY_DRIFT")
    if contract.get("implementation_action_contract", {}).get("scope_inflation_forbidden") is not True:
        errors.append("CURRENT_CONTRACT_SCOPE_INFLATION_DRIFT")
    if binding.get("handoff_projection", {}).get("lossy_summary_forbidden") is not True:
        errors.append("CURRENT_BINDING_LOSSY_SUMMARY_DRIFT")
    if binding.get("currentness_and_reread", {}).get("downstream_reinference_forbidden") is not True:
        errors.append("CURRENT_BINDING_REINFERENCE_DRIFT")
    return errors


def main() -> int:
    matrix = json.loads(MATRIX_PATH.read_text(encoding="utf-8"))
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    binding = json.loads(BINDING_PATH.read_text(encoding="utf-8"))

    tests: list[dict] = []
    errors = validate(matrix, contract, binding)
    tests.append({"case": "three_real_archetypes_12_failure_classes", "ok": not errors, "errors": errors})

    mut = copy.deepcopy(matrix)
    mut["cases"] = [c for c in mut["cases"] if c["case_id"] != "RC-033"]
    errs = validate(mut, contract, binding)
    tests.append({"case": "missing_failure_class_negative", "ok": "RC025_RC036_COVERAGE_NOT_EXACT" in errs, "errors": errs})

    mut = copy.deepcopy(matrix)
    mut["archetypes"][0]["screen"]["app_shell_code"] = "CLIENT_APP_SHELL"
    errs = validate(mut, contract, binding)
    tests.append({"case": "cross_frontend_identity_negative", "ok": "ARCHETYPE_IDENTITY_DRIFT" in errs, "errors": errs})

    mut = copy.deepcopy(matrix)
    mut["cases"][0]["expected_decision"] = "PASS"
    errs = validate(mut, contract, binding)
    tests.append({"case": "false_ready_negative", "ok": any(e.startswith("FAILURE_NOT_FAIL_CLOSED:") for e in errs), "errors": errs})

    mut = copy.deepcopy(matrix)
    for c in mut["cases"]:
        c["coverage_tags"] = [t for t in c["coverage_tags"] if t != "DESIGN_AUTHORITY"]
    errs = validate(mut, contract, binding)
    tests.append({"case": "missing_design_authority_negative", "ok": any("DESIGN_AUTHORITY" in e for e in errs), "errors": errs})

    passed = sum(1 for t in tests if t["ok"])
    out = {
        "schema": "SC_M5_3_THREE_REAL_ARCHETYPE_SELF_TEST_V1",
        "archetypes": sorted(EXPECTED_ARCHETYPES),
        "failure_cases": sorted(EXPECTED_CASES),
        "tests_total": len(tests),
        "tests_passed": passed,
        "result": "PASS" if passed == len(tests) else "FAIL",
        "tests": tests,
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
