from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
C = json.loads((ROOT / "contracts/update_step60_judge_rebaseline_v1.json").read_text(encoding="utf-8"))
S = json.loads((ROOT / "contracts/update_judge_semantics_source_v1.json").read_text(encoding="utf-8"))
SQL = (ROOT / "contracts/update_step60_dedicated_judge_materialization_v1.sql").read_text(encoding="utf-8")

keys = set(C["step60_required_evidence_keys"])
authority = C["authority_model"]
dedicated = C["target_topology"]["dedicated_judge_code"]
checks = {
    "exact_operation": C["operation_code"] == "ACTUALIZACION_PERFIL_LF",
    "exact_step_order": C["step_order"] == 60,
    "exact_step_id": C["step_id"] == "pre_write_execution_binding_gate",
    "shared_judge_not_semantic_authority": C["target_topology"]["shared_judge_keeps_step60_semantics"] is False,
    "dedicated_step60_judge": C["target_topology"]["step60_has_dedicated_judge"] is True,
    "single_binding": C["target_topology"]["dedicated_binding_count"] == 1,
    "bound_revision_required": "bound_revision" in keys,
    "execution_binding_required": "execution_bound_to_target_before_change" in keys,
    "existing_keys_preserved": {"execution_id","target_code","target_path","write_plan","pre_write_gate_passed"}.issubset(keys),
    "semantic_source_exact_step": S["step_id"] == C["step_id"],
    "semantic_source_has_pass": len(S["pass_if"]) == 8,
    "semantic_source_has_fail": len(S["fail_if"]) == 9,
    "caller_not_authority": C["caller_assertions_are_authority"] is False,
    "judge_attestation_only": authority["judge_pass_if_fail_if_role"] == "CALLER_ATTESTATION_ONLY",
    "caller_arrays_explicit": authority["assertions_checked_and_hard_fails_checked_are_caller_supplied"] is True,
    "judge_not_currentness_authority": authority["judge_is_deterministic_currentness_authority"] is False,
    "server_context_required": authority["deterministic_authority"] == "SERVER_DERIVED_TRUST_CONTEXT_REQUIRED",
    "source_only": C["activation"]["source_only"] is True,
    "no_live_judge_mutation": C["activation"]["live_judge_mutation_authorized"] is False,
    "no_live_binding_mutation": C["activation"]["live_binding_mutation_authorized"] is False,
    "update_stays_off": C["activation"]["update_write_enabled"] is False,
    "candidate_names_dedicated_judge": dedicated in SQL,
    "candidate_exact_step60_only": "step_id='pre_write_execution_binding_gate'" in SQL and "step_order=60" in SQL,
    "candidate_preserves_seven_keys": json.dumps(C["step60_required_evidence_keys"], separators=(",", ":")) in SQL.replace(" ", ""),
    "candidate_cardinality_guard": "Q9_DEDICATED_STEP60_BINDING_CARDINALITY_INVALID" in SQL,
    "candidate_rolls_back": "rollback;" in SQL.lower(),
    "candidate_marks_attestation": "NOT deterministic currentness authority" in SQL,
    "candidate_no_runtime_enablement": "UPDATE WRITE" not in SQL.upper() or "UPDATE WRITE ENABLED" not in SQL.upper(),
}
required_tests = set(C["required_tests_before_live_materialization"])
expected_tests = {
    "shared_judge_has_no_step60_pass_fail_semantics",
    "dedicated_step60_judge_is_bound_to_exactly_one_step",
    "step60_binding_requires_bound_revision",
    "step60_binding_requires_execution_bound_to_target_before_change",
    "missing_bound_revision_blocks",
    "missing_execution_binding_blocks",
    "caller_assertions_cannot_replace_server_derived_currentness",
    "all_other_13_update_steps_remain_recordable_under_their_own_required_evidence",
}
checks["all_eight_q9_tests_declared"] = required_tests == expected_tests
failed = [k for k,v in checks.items() if not v]
if failed:
    raise SystemExit("FAIL_UPDATE_STEP60_JUDGE_REBASELINE:" + ",".join(failed))
print(f"PASS_UPDATE_STEP60_JUDGE_REBASELINE={sum(checks.values())}/{len(checks)}")
print("Q9_REQUIRED_TESTS=8/8_DECLARED")
print("Q9_MATERIALIZATION_CANDIDATE=ARTIFACT_BOUND_SOURCE_ONLY")
print("JUDGE_PASS_FAIL_ROLE=CALLER_ATTESTATION_ONLY")
print("DETERMINISTIC_AUTHORITY=SERVER_DERIVED_TRUST_CONTEXT_REQUIRED")
print("LIVE_STEP60_DEDICATED_JUDGE_MATERIALIZED=false")
print("UPDATE_WRITE_ENABLED=false")
