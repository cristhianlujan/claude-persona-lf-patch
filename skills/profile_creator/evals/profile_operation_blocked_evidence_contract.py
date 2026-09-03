from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
C = json.loads((ROOT / "contracts/profile_operation_blocked_evidence_v1.json").read_text(encoding="utf-8"))
checks = {
    "no_new_table": C["architecture"]["new_table"] is False,
    "no_new_layer": C["architecture"]["new_layer"] is False,
    "existing_step_table": C["architecture"]["persistence"] == "lf_operation_execution_steps",
    "common_recorder_only": C["architecture"]["recorder"] == "lf_record_profile_operation_step_v1",
    "durable_after_binding": C["identity_boundary"]["durable_only_after"][-1] == "active_binding_resolved",
    "no_fake_preidentity_step": C["identity_boundary"]["pre_identity_failures_are_durable_step_evidence"] is False,
    "blocked_status_derived": C["durable_blocked_path"]["status"] == "binding.blocked_result_value",
    "blocking_findings_present": "blocking_findings" in C["durable_blocked_path"]["required_payload_extensions"],
    "attempt_history_present": "attempt_history" in C["durable_blocked_path"]["required_payload_extensions"],
    "caller_not_authority": C["durable_blocked_path"]["caller_status_is_authority"] is False,
    "retry_same_row": C["retry_semantics"]["same_execution_step_row"] is True,
    "blocked_not_terminal": C["retry_semantics"]["blocked_row_is_terminal"] is False,
    "preserve_history": C["retry_semantics"]["previous_attempt_preserved_in_attempt_history"] is True,
    "clean_requires_non_null": C["retry_semantics"]["clean_retry_requires_all_required_evidence_non_null"] is True,
    "trigger_rederives": C["retry_semantics"]["clean_retry_rederives_status_through_trigger"] is True,
    "no_delete_history": C["retry_semantics"]["no_delete_of_blocked_history"] is True,
    "server_trust_block_durable": "PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED" in C["durable_block_codes"],
    "missing_evidence_block_durable": "REQUIRED_EVIDENCE_MISSING" in C["durable_block_codes"],
    "identity_missing_not_durable": "STEP_IDENTITY_MISSING" in C["non_durable_pre_identity_codes"],
    "binding_missing_not_durable": "STEP_JUDGE_BINDING_MISSING" in C["non_durable_pre_identity_codes"],
    "source_only": C["activation"]["source_contract_only"] is True,
    "recorder_not_yet_implemented": C["activation"]["recorder_source_implemented"] is False,
    "live_not_materialized": C["activation"]["live_materialized"] is False,
    "update_off": C["activation"]["update_write_enabled"] is False,
    "retry_tests_present": all(x in C["required_tests"] for x in ["retry_preserves_first_blocked_attempt","retry_with_same_invalid_evidence_remains_blocked","retry_with_complete_clean_evidence_can_transition_only_if_trigger_derives_clean"]),
}
failed=[k for k,v in checks.items() if not v]
if failed:
    raise SystemExit("FAIL_PROFILE_OPERATION_BLOCKED_EVIDENCE:"+",".join(failed))
print(f"PASS_PROFILE_OPERATION_BLOCKED_EVIDENCE={sum(checks.values())}/{len(checks)}")
print("RECORDER_SOURCE_IMPLEMENTED=false")
print("LIVE_MATERIALIZED=false")
print("UPDATE_WRITE_ENABLED=false")
