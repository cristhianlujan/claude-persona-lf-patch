#!/usr/bin/env python3
import json
import sys
from pathlib import Path

REQUIRED = [
    "SKILL.md", "README.md", "contracts/main_contract.md", "schemas/output.schema.json",
    "judges/score_rubric.md", "judges/mini_judge.md", "evals/eval_matrix.json",
    "handoffs/to_quality_pack.handoff.json", "examples/good_output.json",
    "examples/bad_output.json", "manifest.json"
]


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
    failures = []
    for rel in REQUIRED:
        p = root / rel
        if not p.is_file() or not p.read_text(encoding="utf-8").strip():
            failures.append(f"MISSING_OR_EMPTY:{rel}")

    if failures:
        print(json.dumps({"status":"FAIL","failures":failures}, indent=2)); return 1

    manifest = load(root / "manifest.json")
    schema = load(root / "schemas/output.schema.json")
    evals = load(root / "evals/eval_matrix.json")
    good = load(root / "examples/good_output.json")
    bad = load(root / "examples/bad_output.json")
    handoff = load(root / "handoffs/to_quality_pack.handoff.json")

    expected_manifest = {
        "operation":"CREACION_PERFIL_LF", "document_status":"CANDIDATO",
        "operational_status":"READ_ONLY", "runtime":"NO_HABILITADO",
        "automatic_impact":"BLOQUEADO", "runtime_enabled":False,
        "production_authorization":False, "exposes_user_facing_output":True
    }
    for key, value in expected_manifest.items():
        if manifest.get(key) != value:
            failures.append(f"MANIFEST_BOUNDARY:{key}")

    if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
        failures.append("OUTPUT_SCHEMA_NOT_STRICT_OBJECT")
    props = schema.get("properties") or {}
    for field in ("status","user_payload","internal_envelope","evidence_map"):
        if field not in props:
            failures.append(f"OUTPUT_SCHEMA_FIELD_MISSING:{field}")
    status_enum = ((props.get("status") or {}).get("enum") or [])
    if "READY_FOR_REVIEW" not in status_enum or "BLOCKED" not in status_enum:
        failures.append("OUTPUT_SCHEMA_STATUS_NOT_CLOSED")

    opportunities = ((good.get("user_payload") or {}).get("opportunities") or [])
    lanes = {x.get("lane") for x in opportunities if isinstance(x, dict)}
    if not {"ADJACENT","BUSINESS","DATA","FRONTIER"}.issubset(lanes):
        failures.append("GOOD_CASE_LANE_BREADTH_MISSING")
    if not (good.get("internal_envelope") or {}).get("frontier_present"):
        failures.append("GOOD_CASE_FRONTIER_MISSING")
    if (good.get("internal_envelope") or {}).get("redundancy_check") != "PASS":
        failures.append("GOOD_CASE_REDUNDANCY_NOT_PASS")
    if (good.get("internal_envelope") or {}).get("scope_guard_passed") is not True:
        failures.append("GOOD_CASE_SCOPE_GUARD_NOT_PASS")
    if not all(isinstance(x, dict) and x.get("experiment") and isinstance(x.get("requires_scope_change"), bool) for x in opportunities):
        failures.append("GOOD_CASE_EXPERIMENTABILITY_MISSING")

    bad_env = bad.get("internal_envelope") or {}
    if bad_env.get("redundancy_check") != "FAIL" or bad_env.get("frontier_present") is not False:
        failures.append("BAD_CASE_DOES_NOT_EXPOSE_COMMODITY_FAILURE")
    if bad.get("status") != "RETURN_TO_WORKER_FOR_DIVERGENCE":
        failures.append("BAD_CASE_STATUS_INVALID")

    cases = evals.get("cases") or []
    if len(cases) < 4:
        failures.append("EVAL_CASE_COUNT_LT_4")
    ids = {c.get("id") for c in cases if isinstance(c, dict)}
    required_ids = {
        "excel_bulk_upload_expands_beyond_commodity", "commodity_only_set_is_rejected",
        "redundant_variants_are_rejected", "silent_scope_mutation_is_blocked"
    }
    if not required_ids.issubset(ids):
        failures.append("EVAL_REQUIRED_CASES_MISSING")
    for case in cases:
        assertions = case.get("assertions") if isinstance(case, dict) else None
        if not assertions or any(not isinstance(a,str) or len(a.strip()) < 12 for a in assertions):
            failures.append(f"EVAL_ASSERTION_WEAK:{case.get('id') if isinstance(case,dict) else 'UNKNOWN'}")

    context = set(handoff.get("required_receiver_context") or [])
    required_context = {"deliverable_artifact_ref","main_contract_ref","output_schema_ref","evidence_map","score_rubric_ref","blocking_codes","remaining_risks"}
    if not required_context.issubset(context):
        failures.append("HANDOFF_CONTEXT_INCOMPLETE")
    if handoff.get("next_gate") != "SEMANTIC_QUALITY_REVIEW":
        failures.append("HANDOFF_NEXT_GATE_INVALID")

    skill = (root / "SKILL.md").read_text(encoding="utf-8").lower()
    contract = (root / "contracts/main_contract.md").read_text(encoding="utf-8").lower()
    for token in ("frontier", "adjacent", "scope", "read-only"):
        if token not in skill:
            failures.append(f"SKILL_SEMANTIC_TOKEN_MISSING:{token}")
    for token in ("user_payload", "internal_envelope", "evidence", "authority limits"):
        if token not in contract:
            failures.append(f"CONTRACT_SEMANTIC_TOKEN_MISSING:{token}")

    result = {
        "status":"PASS" if not failures else "FAIL",
        "profile":"opportunity_expander",
        "quality_pack":"EXPLORATORY_PROFILE_QUALITY_PACK_V0_1",
        "checks":{
            "breadth": "PASS" if not failures else "SEE_FAILURES",
            "frontier_required": True,
            "scope_guard": True,
            "runtime_authorized": False,
            "production_authorized": False,
            "semantic_quality_review":"NOT_EXECUTED"
        },
        "failures":failures
    }
    print(json.dumps(result, indent=2))
    return 0 if not failures else 1

if __name__ == "__main__":
    raise SystemExit(main())
