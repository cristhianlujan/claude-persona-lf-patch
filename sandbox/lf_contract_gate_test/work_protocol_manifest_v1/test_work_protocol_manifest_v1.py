#!/usr/bin/env python3
from pathlib import Path
import importlib.util
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
VALIDATOR = ROOT / "gobernanza/judges/validate_work_protocol_manifest_v1.py"
MIGRATION = ROOT / "supabase/migrations/20260922144000_lf_work_protocol_manifest_v1.sql"
SCHEMA = ROOT / "gobernanza/contratos/work_protocol_manifest_v1.schema.json"
G09 = Path(__file__).with_name("g09_cold_replay_v1.py")
spec = importlib.util.spec_from_file_location("wpm", VALIDATOR)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)

cases = mod.self_test()
assert len(cases) >= 15
assert set(cases.values()) == {"PASS"}

fixture = mod.valid_fixture()
result = mod.evaluate(fixture)
assert result["result"] == "PASS_WITH_EVIDENCE"
assert result["progress_percent"] == 100
assert result["authority_current"] is True
assert result["manifest_digest_match"] is True

sql = MIGRATION.read_text(encoding="utf-8")
sql_lower = sql.lower()
schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
obligation_schema = schema["properties"]["obligations"]["items"]
evidence_policy_schema = schema["properties"]["evidence_policy"]
control_policy_schema = schema["properties"]["control_policy"]
controller_policy_schema = schema["properties"]["controller_policy"]
closure_controller_policy_schema = schema["properties"]["closure_controller_policy"]
source_checks = {
    "schema_work_owner_required": "work_owner" in schema["required"] and schema["properties"]["work_owner"]["properties"]["change_mode"]["const"] == "SUPERSEDE_NEW_EXECUTION",
    "sql_work_owner_entry_guard": "LF_WORK_PROTOCOL_OWNER_BINDING_INVALID" in sql and "SUPERSEDE_NEW_EXECUTION" in sql,
    "sql_execution_binding_guard": "LF_WORK_PROTOCOL_EXECUTION_BINDING_MISMATCH" in sql,
    "sql_scope_shape_guard": "jsonb_typeof(p_work_protocol->'authorized_scope'->'read')" in sql,
    "sql_persisted_manifest_guard": "lf_work_protocol_manifest_guard_v1" in sql,
    "sql_insert_guard_trigger": "trg_02_lf_work_protocol_manifest_insert_guard_v1" in sql,
    "sql_update_guard_trigger": "trg_02_lf_work_protocol_manifest_update_guard_v1" in sql,
    "sql_manifest_digest_currentness": "BLOCKED_MANIFEST_DIGEST_MISMATCH" in sql and "manifest_digest_match" in sql,
    "sql_timeout_recovery_checkpoint_channel": "checkpoint_payload->'work_protocol_recovery'" in sql,
    "sql_timeout_recovery_exhaustion_state": "BLOCKED_OPERATIONAL_TIMEOUT" in sql,
    "sql_timeout_not_overloaded_into_step_status": "execution_step_status in ('TIMEOUT_RECOVERING'" not in sql and "es.status in ('TIMEOUT_RECOVERING'" not in sql,
    "sql_gate_contract_projection": "lf_work_protocol_gate_contract_v1" in sql and "normalized_verdict_mapping" in sql,
    "sql_gate_evaluator": "lf_work_protocol_gate_evaluate_v1" in sql and "GATE_JUDGE_BEFORE_DETERMINISTIC_FORBIDDEN" in sql,
    "sql_gate_enforced_in_progress_view": "ge.gate_eval->>'result'<>'PASS'" in sql,
    "sql_missing_future_gate_is_not_failure": "execution_step_status is not null" in sql,
    "schema_gate_type_required": "gate_type" in obligation_schema["required"] and obligation_schema["properties"]["gate_type"]["enum"] == ["ENTRY", "STEP", "EXIT", "CLOSURE"],
    "schema_gate_digest_required": "gate_contract_sha256" in obligation_schema["required"],
    "schema_evidence_policy_required": "evidence_policy" in schema["required"],
    "schema_evidence_freshness_ceiling": evidence_policy_schema["properties"]["max_age_seconds"]["maximum"] == 86400,
    "sql_canonical_verifier_mode": "lf_operation_step_judge_bindings_verifier_mode_check" in sql and "LF_WORK_PROTOCOL_GATE_VERIFIER_MODE_UNSET" in sql,
    "sql_exact_evidence_validator": "lf_work_protocol_evidence_validate_v1" in sql and "LF_WORK_PROTOCOL_EVIDENCE_V1" in sql,
    "sql_existing_append_only_ledger_reused": "private.lf_evidence_ledger_v1" in sql and "create table private.lf_evidence_ledger" not in sql_lower,
    "sql_independent_receipt_required": "INDEPENDENT_LEDGER_RECEIPT_MISSING" in sql and "WORK_PROTOCOL_GATE_EVIDENCE" in sql,
    "sql_evidence_enforced_in_progress_view": "ee.evidence_eval->>'result'<>'PASS'" in sql,
    "sql_stale_evidence_blocks": "BLOCKED_STALE_EVIDENCE" in sql,
    "schema_control_policy_required": "control_policy" in schema["required"] and control_policy_schema["properties"]["scope_change_mode"]["const"] == "SUPERSEDE_NEW_EXECUTION_FULL_REVALIDATION",
    "schema_required_waivers_forbidden": control_policy_schema["properties"]["required_obligation_waivers_allowed"]["const"] is False,
    "schema_obligation_control_flags": all(k in obligation_schema["required"] for k in ("waiver_allowed", "irreversible_effect", "human_approval_required")),
    "sql_control_authority_columns": all(k in sql for k in ("waiver_allowed boolean", "irreversible_effect boolean", "human_approval_required boolean")),
    "sql_control_static_validator": "lf_work_protocol_control_validate_v1" in sql and "WAIVER_FORBIDDEN" in sql and "SUPERSESSION_SCOPE_BINDING_MISMATCH" in sql,
    "sql_control_runtime_validator": "lf_work_protocol_runtime_control_validate_v1" in sql and "WAIVER_AUTHORIZATION_NOT_VERIFIED" in sql,
    "sql_irreversible_step_control": "lf_work_protocol_step_control_evaluate_v1" in sql and "IRREVERSIBLE_HUMAN_APPROVAL_NOT_VERIFIED" in sql,
    "sql_supersession_state": "SUPERSEDED_SCOPE_CHANGE" in sql,
    "sql_no_parallel_control_table": "create table private.lf_work_protocol" not in sql_lower,
    "schema_controller_policy_required": "controller_policy" in schema["required"] and controller_policy_schema["properties"]["dependency_mode"]["const"] == "CANONICAL_DAG",
    "schema_controller_wip_one": controller_policy_schema["properties"]["material_wip_limit"]["const"] == 1,
    "schema_controller_obligation_fields": all(k in obligation_schema["required"] for k in ("depends_on_step_ids", "closure_unit_id", "controller_order", "execution_effect", "parallel_safe")),
    "sql_controller_authority_columns": all(k in sql for k in ("depends_on_step_ids text[]", "closure_unit_id text", "controller_order integer", "execution_effect text", "parallel_safe boolean")),
    "sql_controller_static_validator": "lf_work_protocol_controller_validate_v1" in sql and "CONTROLLER_DAG_CYCLE" in sql,
    "sql_controller_step_state": "lf_work_protocol_step_state_v1" in sql and "STEP_VERIFIED" in sql,
    "sql_controller_plan": "lf_work_protocol_controller_plan_v1" in sql and "PASS_CONTROLLER_PLAN" in sql,
    "sql_controller_fenced_activation": "lf_work_protocol_controller_activate_v1" in sql and "LF_WORK_PROTOCOL_CONTROLLER_STALE_OR_MISSING_LEASE" in sql,
    "sql_controller_step_write_guard": "lf_work_protocol_controller_step_guard_v1" in sql and "LF_WORK_PROTOCOL_CONTROLLER_ACTIVATION_REQUIRED" in sql,
    "sql_controller_reuses_existing_checkpoint": "fn_lf_operation_checkpoint_v1" in sql and "create table public.lf_work_protocol_controller" not in sql_lower,
    "schema_closure_controller_policy_required": "closure_controller_policy" in schema["required"] and closure_controller_policy_schema["properties"]["unit_progression_mode"]["const"] == "CLOSE_OR_BLOCK_WITH_EVIDENCE_BEFORE_NEXT",
    "schema_closure_zero_debt_required": closure_controller_policy_schema["properties"]["global_close_requires_zero_debt"]["const"] is True,
    "sql_closure_controller_static_validator": "lf_work_protocol_closure_controller_validate_v1" in sql and "PASS_CLOSURE_CONTROLLER_FROZEN" in sql,
    "sql_closure_unit_state": "lf_work_protocol_closure_unit_state_v1" in sql and "REOPEN_REQUIRED" in sql and "READY_TO_BLOCK_WITH_EVIDENCE" in sql,
    "sql_closure_receipt_anchor": "lf_work_protocol_closure_mark_v1" in sql and "WORK_PROTOCOL_CLOSURE_CONTROLLER" in sql,
    "sql_closure_reuses_append_only_ledger": "private.lf_evidence_ledger_v1" in sql and "WORK_PROTOCOL_CLOSURE_UNIT" in sql and "WORK_PROTOCOL_BLOCKED_UNIT" in sql,
    "sql_closure_before_next": "BLOCKED_CLOSURE_REQUIRED" in sql and "CLOSE_CURRENT_UNIT_BEFORE_NEXT" in sql,
    "sql_closure_zero_debt_global_close": "BLOCKED_CLOSURE_DEBT" in sql and "CLOSURE_REQUIRED" in sql and "global_close_allowed" in sql,
    "sql_closure_receipt_chain": "previous_unit_receipt_sha256" in sql and "CLOSURE_RECEIPT_STALE_OR_CHAIN_BROKEN" in sql,
    "sql_closure_receipt_selects_current_digest": "(l.subject_sha256=unit_state_sha) desc" in sql,
    "sql_closure_blocker_exact_failed_step": "LF_WORK_PROTOCOL_BLOCKED_CLOSURE_EVIDENCE_NOT_EXACT" in sql and "step_evidence_present" in sql,
    "sql_no_parallel_closure_table": "create table public.lf_work_protocol_closure" not in sql_lower and "create table private.lf_work_protocol_closure" not in sql_lower,
    "sql_full_authority_currentness": all(k in sql for k in (
        "contract_revision_sha256",
        "obligation_set_sha256",
        "policy_set_sha256",
    )),
    "sql_no_table_replacement": all(x not in sql_lower for x in (
        "create table",
        "drop table",
        "truncate table",
    )),
}
assert all(source_checks.values()), source_checks

g09_proc = subprocess.run(
    [sys.executable, str(G09)],
    cwd=ROOT,
    text=True,
    capture_output=True,
    timeout=120,
    check=False,
)
assert g09_proc.returncode == 0, {"stdout": g09_proc.stdout, "stderr": g09_proc.stderr}
g09 = json.loads(g09_proc.stdout)
assert g09["status"] == "PASS", g09
assert g09["gate_count"] == 9, g09
assert g09["dimension_count"] == 5, g09
assert g09["matrix_case_count"] == 45, g09
assert g09["cold_replay"]["status"] == "PASS", g09
assert g09["cold_replay"]["fresh_process_count"] == 2, g09
assert g09["cold_replay"]["byte_equivalent_canonical_json"] is True, g09

print(json.dumps({
    "status": "PASS",
    "case_count": len(cases) + 1 + len(source_checks),
    "cases": cases,
    "source_checks": source_checks,
    "g09_cold_replay": g09,
}, sort_keys=True))
