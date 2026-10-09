
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{transversal_execution_v1,SHADOW_RUN,capabilities}',
  '["CONTROL_EQUIVALENCE_JUDGE"]'::jsonb,
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M3.9';

update public.lf_error_knowledge
set
  ultima_vez=now(),
  updated_at=now(),
  prevencion='Keep the plan capability list ordered and explicit. Execute one capability per bootstrap microloop: action_spec exposes only the current item, the normal singular binder/READ|WRITE_DB|WRITE_GIT|RUN_TEST packet executes it, non-final items close through fn_engineering_transversal_step_transition_v1 and re-bootstrap to the next item, and only the last item uses the normal checkpoint transition. Each item must declare or resolve to a supported handler; never silently skip an unsupported capability.',
  validacion='PASS when a 3-item sequence advances CURRENTNESS_AUTHORITY -> TYPED_EVIDENCE_REGISTRY -> CONTROL_EQUIVALENCE_JUDGE with separate evidence for the first two and the third compiles as READY/RUN_TEST with the normal final CHECKPOINT_TRANSITION; an 8-item explicit array must compile READY with total=8 and exact first item instead of BLOCK_TRANSVERSAL_CAPABILITY_HANDLER_MISSING; single-capability T-EQUIV remains backward compatible.',
  evidencia=concat_ws(E'\n',nullif(evidencia,''),
    '2026-10-05 sequential fix: added fn_engineering_transversal_sequence_state_v1, fn_engineering_transversal_step_transition_v1 and sequence-aware action_spec/packet wrappers while preserving singular binder and READ|WRITE_DB|WRITE_GIT|RUN_TEST engine.',
    '3-step live probe on M3.9 historical SHADOW_RUN: CURRENTNESS_AUTHORITY ACTIVE/CURRENT/RELEASED 1.0.0 -> TRANSVERSAL_STEP_DONE; next=TYPED_EVIDENCE_REGISTRY ACTIVE/CURRENT/RELEASED 3.0.0 -> TRANSVERSAL_STEP_DONE; next=CONTROL_EQUIVALENCE_JUDGE index=3 is_last=true. Final compiled action=DECLARED_CAPABILITY_TEST_EXECUTION, packet READY, execution_capability=RUN_TEST, last_operation=CHECKPOINT_TRANSITION. T-EQUIV material run was intentionally not executed.',
    '8-item compile probe: action_spec READY, total=8, next_index=1, current_capability=CURRENTNESS_AUTHORITY, no handler-missing block. M3.9 then restored to capabilities=[CONTROL_EQUIVALENCE_JUDGE].'
  )
where codigo='ENGINEERING-TRANSVERSAL-MULTI-CAPABILITY-001';
