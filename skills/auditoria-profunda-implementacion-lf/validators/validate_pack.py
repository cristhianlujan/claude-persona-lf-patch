#!/usr/bin/env python3
"""LF convention + substantive package integrity. Does not grant runtime status."""
import ast
import json
import re
import subprocess
import sys
from pathlib import Path

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
REQUIRED = ["SKILL.md", "README.md", "contracts/main_contract.md", "contracts/missing_input_policy.md",
    "schemas/output.schema.json", "schemas/missing_input.schema.json", "judges/context_spec_judge.md",
    "judges/score_rubric.md", "judges/mini_judge.md", "checklists/preflight_checklist.md",
    "checklists/priority_checklist.md", "examples/good_output.json", "examples/bad_output.json",
    "examples/self_repair_output.json", "fixtures/happy_path/input.json", "fixtures/missing_inputs/input.json",
    "fixtures/unsafe_or_blocked/input.json", "fixtures/self_repair/bad_output.json",
    "evals/eval_matrix.json", "evals/test_acceptance.py", "evals/test_pilot.py", "evals/test_integrity.py",
    "handoffs/to_quality_pack.handoff.json", "adapters/github_pack_adapter.md", "adapters/document_patch_adapter.md",
    "references/defect_taxonomy.json", "references/ekb_snapshot.json", "references/promotion_sql_readback.json",
    "references/ekb_current_snapshot.json", "references/governance_current_readback.json", "reports/forward_test.json",
    "reports/pilot_report.json", "reports/pilot_trace.json", "registration/asset_registration_candidate_v1.json",
    "contracts/reporting_and_contract_depth_v2.md", "schemas/audit_input_v2.schema.json",
    "schemas/audit_report_v2.schema.json", "schemas/judge_result_v2.schema.json", "schemas/quality_handoff_v2.schema.json",
    "references/contract_profiles_v2.json", "validators/validate_audit_v2.py", "scripts/audit_v2.py",
    "scripts/scan_pass_emitters.py", "scripts/render_audit_v2.py", "scripts/contract_reviews_v2.py",
    "scripts/build_report_v2.py", "evals/test_reporting_v2.py", "reports/perfil_ig_perfil_v2.json",
    "reports/perfil_ig_perfil_v2.md", "reports/perfil_ig_perfil_v2.html"]


def validate():
    errors = ["MISSING_REQUIRED_FILE:" + name for name in REQUIRED if not (PACK / name).is_file()]
    for path in PACK.rglob("*.json"):
        try:
            json.loads(path.read_text(encoding="utf8"))
        except (ValueError, OSError) as exc:
            errors.append("INVALID_JSON:" + str(path) + ":" + str(exc))
    for path in PACK.rglob("*.py"):
        try:
            ast.parse(path.read_text(encoding="utf8"), filename=str(path))
        except SyntaxError as exc:
            errors.append("INVALID_PYTHON:" + str(exc))
    skill = (PACK / "SKILL.md").read_text(encoding="utf8")
    if "TODO" in skill or "name: auditoria-profunda-implementacion-lf" not in skill:
        errors.append("SKILL_FRONTMATTER_OR_PLACEHOLDER_INVALID")
    for path in PACK.rglob("*.md"):
        for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf8")):
            if "://" not in target and not target.startswith("#") and not (path.parent / target.split("#")[0]).exists():
                errors.append("BROKEN_MARKDOWN_LINK:" + str(path.relative_to(PACK)) + ":" + target)
    if not errors:
        matrix = json.loads((PACK / "evals/eval_matrix.json").read_text())
        tests = ast.parse((PACK / "evals/test_acceptance.py").read_text())
        methods = {n.name for n in ast.walk(tests) if isinstance(n, ast.FunctionDef)}
        if {c["case_id"] for c in matrix["cases"]} != {"A" + str(i).zfill(2) for i in range(1, 11)}:
            errors.append("INITIAL_ACCEPTANCE_CASES_INCOMPLETE")
        for case in matrix["cases"]:
            if case["test"] not in methods:
                errors.append("EVAL_TEST_NOT_IMPLEMENTED:" + case["test"])
        reg = json.loads((PACK / "registration/asset_registration_candidate_v1.json").read_text())
        if reg["status"] != "CANDIDATE_SOURCE_ONLY_NOT_REGISTERED" or any(reg[k] for k in
                ("runtime_enabled", "production_authorized", "promotion_authorized", "catalog_registration_applied")):
            errors.append("UNAUTHORIZED_REGISTRATION_OR_EFFECT_CLAIM")
        legacy = subprocess.run([sys.executable, str(ROOT / "skills/skill_creator/validators/validate_pack.py"), str(PACK)],
                                text=True, capture_output=True, timeout=20)
        if legacy.returncode:
            errors.append("LF_SKILL_CREATOR_CONVENTION:" + legacy.stdout + legacy.stderr)
        from validate_report import validate as validate_report
        errors.extend(validate_report(json.loads((PACK / "reports/pilot_report.json").read_text()), ROOT))
        from validate_audit_v2 import validate as validate_audit_v2
        errors.extend(validate_audit_v2(json.loads((PACK / "reports/perfil_ig_perfil_v2.json").read_text()), ROOT))
    return errors


if __name__ == "__main__":
    problems = validate()
    print(json.dumps({"status": "PASS" if not problems else "FAIL", "errors": problems,
                      "runtime_enabled": False, "promotion_authorized": False}, ensure_ascii=False, indent=2))
    raise SystemExit(bool(problems))
