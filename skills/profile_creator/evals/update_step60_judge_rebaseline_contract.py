from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
C = json.loads((ROOT / "contracts/update_step60_judge_rebaseline_v1.json").read_text(encoding="utf-8"))
S = json.loads((ROOT / "contracts/update_judge_semantics_source_v1.json").read_text(encoding="utf-8"))
SQL = (ROOT / "contracts/update_step60_dedicated_judge_materialization_v1.sql").read_text(encoding="utf-8")
keys=set(C["step60_required_evidence_keys"]); authority=C["authority_model"]; live=C["activation"]; rb=C["live_test_readback"]
checks={
 "exact_operation":C["operation_code"]=="ACTUALIZACION_PERFIL_LF",
 "exact_step":C["step_order"]==60 and C["step_id"]=="pre_write_execution_binding_gate",
 "dedicated_topology":C["target_topology"]["step60_has_dedicated_judge"] is True and C["target_topology"]["dedicated_binding_count"]==1,
 "shared_structural":C["target_topology"]["shared_judge_keeps_step60_semantics"] is False,
 "seven_keys":len(keys)==7 and {"bound_revision","execution_bound_to_target_before_change"}.issubset(keys),
 "semantic_source_8_9":len(S["pass_if"])==8 and len(S["fail_if"])==9,
 "caller_not_authority":C["caller_assertions_are_authority"] is False and authority["judge_pass_if_fail_if_role"]=="CALLER_ATTESTATION_ONLY",
 "server_authority_required":authority["deterministic_authority"]=="SERVER_DERIVED_TRUST_CONTEXT_REQUIRED" and authority["judge_is_deterministic_currentness_authority"] is False,
 "live_materialized":live["source_only"] is False and live["live_judge_materialized"] is True and live["live_binding_materialized"] is True,
 "provenance_completed":live["materialization_execution_final_status"]=="COMPLETED",
 "live_sha_pinned":live["live_judge_sha"]=="bef12f5dd3c08db63b92faf64f77703acf9172288dc0547e0de56241d1521557",
 "update_stays_off":live["update_write_enabled"] is False,
 "live_8_of_8":rb["tests_passed"]==8 and rb["tests_total"]==8 and all(v is True for k,v in rb.items() if k not in {"tests_passed","tests_total","note"}),
 "candidate_names_judge":C["target_topology"]["dedicated_judge_code"] in SQL,
 "candidate_exact_step60":"step_id='pre_write_execution_binding_gate'" in SQL and "step_order=60" in SQL,
 "candidate_cardinality_guard":"Q9_DEDICATED_STEP60_BINDING_CARDINALITY_INVALID" in SQL,
 "candidate_rollback_reference":"rollback;" in SQL.lower(),
}
expected={"shared_judge_has_no_step60_pass_fail_semantics","dedicated_step60_judge_is_bound_to_exactly_one_step","step60_binding_requires_bound_revision","step60_binding_requires_execution_bound_to_target_before_change","missing_bound_revision_blocks","missing_execution_binding_blocks","caller_assertions_cannot_replace_server_derived_currentness","all_other_13_update_steps_remain_on_shared_structural_binding"}
checks["eight_tests_named"]=set(C["required_tests_before_live_materialization"])==expected
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit("FAIL_UPDATE_STEP60_JUDGE_REBASELINE:"+",".join(failed))
print(f"PASS_UPDATE_STEP60_JUDGE_REBASELINE={sum(checks.values())}/{len(checks)}")
print("Q9_LIVE_READBACK_TESTS=8/8")
print("JUDGE_PASS_FAIL_ROLE=CALLER_ATTESTATION_ONLY")
print("DETERMINISTIC_AUTHORITY=SERVER_DERIVED_TRUST_CONTEXT_REQUIRED")
print("LIVE_STEP60_DEDICATED_JUDGE_MATERIALIZED=true")
print("UPDATE_WRITE_ENABLED=false")
