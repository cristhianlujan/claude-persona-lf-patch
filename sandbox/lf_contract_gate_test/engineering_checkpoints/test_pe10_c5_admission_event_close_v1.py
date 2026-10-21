#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
matches=list((ROOT/"supabase/migrations").glob("*_lf_pe10_c5_admission_event_close_v1.sql"))
assert len(matches)==1, f"EXPECTED_ONE_C5_CLOSE_MIGRATION:{matches}"
src=matches[0].read_text(encoding="utf-8")

required=[
  "PROFILE_EVOLUTION_CUTOVER_ADMITTED",
  "'contract_mode','VALIDATION_ACCEPTANCE'",
  "'architecture-closure/v2'",
  "fn_create_lf_event_type_contract_request_v2",
  "EVENT_TYPE_CONTRACT_CHANGE_APPROVED",
  "fn_approve_lf_event_type_contract_request_v2",
  "fn_apply_lf_event_type_contract_change_v2",
  "d5225fea-9218-4e94-8cbe-d35335632b55",
  "731e93ae-a230-4172-ad6c-f2fb4c9024d6",
  "ae10a7bb-0e99-4589-a7c7-38e61af506b0",
  "586b92af62baa5d54a9726a5a3deedcf316d81c102fd0af76e0d54df05887c15",
  "be86ad8ab314156382c804b6c20ade503cd38503b7f161c0e36ca3913d3760d5",
  "'status','ADMIT_CUTOVER'",
  "'target','SINGLE_DYNAMIC_PROFILE_UPDATER_V02'",
  "'executor_mode','GPT_NATIVE'",
  "'selected_method_ids',jsonb_build_array('CAUSAL_ANALYSIS','SELF_REFINE')",
  "'native_conversation_scope','EXISTING_CONVERSATION_ONLY'",
  "'production_activation_authorized',false",
  "'cutover_eligible',false",
  "verification_queries,0",
  "v_gate.admissible_events IS DISTINCT FROM 1",
  "fn_engineering_checkpoint_assertion_record_v1",
  "fn_engineering_checkpoint_transition_v1",
  "'DONE'",
  "PE10_C5_CLOSE_POSTSTATE_INVALID",
  "LF-PE10-C5-ADMISSION-EVENT-TYPE-MISSING-20261021-001",
  "LF-PE10-C5-VALIDATION-ACCEPTANCE-SCHEMA-MISMATCH-20261021-001",
]
for item in required:
  assert item in src, f"MISSING:{item}"

# It closes C5 only; deployment and step activation are explicit negatives.
for forbidden in [
  "UPDATE public.lf_operation_registry",
  "UPDATE public.lf_policy_versions",
  "SET active=true",
  "'PE10_C6','DONE'",
  "'PE10_C7','DONE'",
  "'production_activation_authorized',true",
  "'cutover_eligible',true",
]:
  assert forbidden not in src, f"FORBIDDEN:{forbidden}"

assert "version='v0.1' AND status='PRODUCCION_CONTROLADA'" in src
assert "version='v0.2'" in src
assert "step_id IN ('method_selection','evolution_decision')" in src
assert "AND active) <> 0" in src
print("PASS PE10_C5_ADMISSION_EVENT_CLOSE_SOURCE_GUARDS")

assert "fn_lf_typed_evidence_payload_valid_v3" not in src
