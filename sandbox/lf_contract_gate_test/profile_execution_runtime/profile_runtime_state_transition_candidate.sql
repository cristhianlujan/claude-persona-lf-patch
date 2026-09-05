-- Strategy 26 / backlog #55
-- SANDBOX CANDIDATE ONLY. DO NOT APPLY AS A MIGRATION.
-- Purpose: materialize the missing governed path from a registered profile
-- NO_HABILITADO state into a bounded CANDIDATE_READ_ONLY state without
-- production enablement, automatic impact, GitHub writes, or R4 claims.
--
-- This candidate intentionally reuses public.lf_operation_* and the existing
-- state catalog. It does not introduce another governance layer.

begin;

-- The operation provenance guard requires a scope-matched governance bootstrap
-- execution for any new operation. This row exists only inside this transaction
-- and is rolled back with the entire sandbox candidate.
insert into public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,
  created_by_execution_id,updated_by_execution_id
)
values (
  'EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_PROTOCOL_REPAIR',
  'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',
  'IN_PROGRESS',
  '{"mode":"STRATEGY26_SANDBOX","router":"ACT-0001","scope":"materialize sandbox-only candidate for missing governed profile runtime-state transition","no_new_agents":true,"no_new_tables":true,"validated_allowed":false,"production_allowed":false,"governance_bootstrap":true,"bootstrap_operation_code":"TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE"}'::jsonb,
  'EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001',
  'EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001'
);

-- S26-GA-STATE-01: a canonical tuple is needed. Existing catalog entries for
-- CANDIDATE_READ_ONLY use estado_operativo=ACTIVO and do not represent the
-- current controlled READ_ONLY profile posture. Never reuse a legacy alias to
-- force the transition.
insert into public.cat_estado_normalizacion_lf(
  estado_original,estado_documental,estado_operativo,nivel_control,
  runtime_estado,impacto_automatico,accion_recomendada,migration_blocker,notas
)
values (
  'CANDIDATO_CONTROLADO_READ_ONLY','CANDIDATO','READ_ONLY','CONTROLADO',
  'CANDIDATE_READ_ONLY','BLOQUEADO','MIGRAR_READ_ONLY',false,
  'Canonical bounded profile canary posture. No automatic impact or production promotion.'
)
on conflict (estado_original) do nothing;

insert into public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id
)
values (
  'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','v0.1-candidate','CANDIDATO_READ_ONLY',
  'SUPABASE_STRUCTURED_OPERATION','Supabase/LF_OPERATION_GOVERNANCE',
  '["public.v_lf_fuente_operativa","public.cat_estado_normalizacion_lf","public.lf_operation_registry","public.lf_operation_contracts","public.lf_operation_step_contracts"]'::jsonb,
  'Strategy26 backlog #55. Narrow reversible transition only: PERFIL CANDIDATO/READ_ONLY/NO_HABILITADO/BLOQUEADO -> CANDIDATO/READ_ONLY/CANDIDATE_READ_ONLY/BLOQUEADO. Candidate only; no automatic promotion, no production, no GitHub write.',
  'PROFILE_OPERATIONS','PROFILE_RUNTIME_STATE','STATE_TRANSITION_PROTOCOL','PERFIL',
  'EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001'
)
on conflict (operation_code) do nothing;

insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,required_before_write,allowed,blocked,
  required_after_write,status,created_by_execution_id
)
values (
  'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',
  'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate',
  'public.lf_operation_contracts/TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF/CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate',
  '["router_read","exact_profile_resolved","source_state_read","target_state_catalog_match","quality_performance_governance_preconditions_not_claimed_as_pass"]'::jsonb,
  '{"asset_type":"PERFIL","single_target":true,"from":{"estado_documental":"CANDIDATO","estado_operativo":"READ_ONLY","runtime_estado":"NO_HABILITADO","impacto_automatico":"BLOQUEADO"},"to":{"estado_documental":"CANDIDATO","estado_operativo":"READ_ONLY","runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"},"github_write":false,"production_enablement":false,"automatic_impact":false,"promotion":false,"reversible":true}'::jsonb,
  '["profile_not_found","ambiguous_profile","state_mismatch","target_state_unregistered","impact_change","production_enablement","runtime_operativo","github_write","mass_transition","automatic_promotion","r4_self_attestation"]'::jsonb,
  '["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked","no_production_promotion","single_target_receipt"]'::jsonb,
  'CANDIDATO_READ_ONLY','EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001'
)
on conflict (operation_code,contract_code) do nothing;

insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,
  resolver_ref,output_payload,pass_condition,block_condition,blocking_code,
  mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,notes,
  created_by_execution_id
)
values
(
 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','router',10,10,
 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate',
 'Resolver ACT-0001 y el PERFIL exacto; no inferir autorización desde capacidad runtime.',
 'public.v_lf_fuente_operativa.ACT-0001','["router_read","profile_code"]'::jsonb,
 '{"required_evidence_keys":["router_read","profile_code"]}'::jsonb,
 '{"missing_required_evidence":true,"ambiguous_profile":true}'::jsonb,
 'BLOCK_PROFILE_RUNTIME_TRANSITION_ROUTER_NOT_CLEAN','DETERMINISTIC_STATE_TRANSITION_CANDIDATE',
 '["router_read","profile_code"]'::jsonb,'source_state_read','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY',
 'Sandbox candidate. No state write from this step.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001'
),
(
 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','source_state_read',20,20,
 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate',
 'Leer el estado fuente exacto de cuatro dimensiones desde v_lf_fuente_operativa.',
 'public.v_lf_fuente_operativa','["source_state"]'::jsonb,
 '{"exact_from_state":{"estado_documental":"CANDIDATO","estado_operativo":"READ_ONLY","runtime_estado":"NO_HABILITADO","impacto_automatico":"BLOQUEADO"}}'::jsonb,
 '{"state_mismatch":true,"unknown_state":true}'::jsonb,
 'BLOCK_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_MISMATCH','DETERMINISTIC_STATE_TRANSITION_CANDIDATE',
 '["source_state"]'::jsonb,'target_state_validate','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY',
 'Fail closed on any source-state drift.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001'
),
(
 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','target_state_validate',30,30,
 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate',
 'Exigir la tupla target canónica exacta en cat_estado_normalizacion_lf.',
 'public.cat_estado_normalizacion_lf','["target_state_catalog_match"]'::jsonb,
 '{"estado_original":"CANDIDATO_CONTROLADO_READ_ONLY","runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}'::jsonb,
 '{"target_state_unregistered":true,"impact_change":true}'::jsonb,
 'BLOCK_PROFILE_RUNTIME_TRANSITION_TARGET_STATE_NOT_CANONICAL','DETERMINISTIC_STATE_TRANSITION_CANDIDATE',
 '["target_state_catalog_match"]'::jsonb,'controlled_write','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY',
 'Catalog registration is a prerequisite, not inferred authority.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001'
),
(
 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','controlled_write',40,40,
 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate',
 'Cambiar solo runtime_estado a CANDIDATE_READ_ONLY para el perfil ligado, preservando CANDIDATO/READ_ONLY/BLOQUEADO.',
 'DETERMINISTIC_SUPABASE_STATE_TRANSITION_CANDIDATE','["transition_receipt","before_state","after_state"]'::jsonb,
 '{"single_target":true,"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO","production_enablement":false}'::jsonb,
 '{"mass_transition":true,"impact_change":true,"runtime_operativo":true,"production_enablement":true}'::jsonb,
 'BLOCK_PROFILE_RUNTIME_TRANSITION_WRITE_NOT_BOUNDED','DETERMINISTIC_STATE_TRANSITION_CANDIDATE',
 '["transition_receipt","before_state","after_state"]'::jsonb,'readback','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY',
 'No execution_sql is provided while the operation remains sandbox candidate.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001'
),
(
 'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','readback',50,50,
 'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate',
 'Verificar que el mismo perfil siga CANDIDATO/READ_ONLY/BLOQUEADO y cambie solo a CANDIDATE_READ_ONLY; re-evaluar Router por separado.',
 'public.v_lf_fuente_operativa','["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"]'::jsonb,
 '{"same_target":true,"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}'::jsonb,
 '{"state_mismatch":true,"automatic_impact_enabled":true,"production_promotion":true}'::jsonb,
 'BLOCK_PROFILE_RUNTIME_TRANSITION_READBACK_FAILED','DETERMINISTIC_STATE_TRANSITION_CANDIDATE',
 '["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"]'::jsonb,null,'RETURN_TO_ROUTER','CANDIDATO_READ_ONLY',
 'Closure requires independent readback. R4 remains a separate later gate.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-20260905-001'
)
on conflict (operation_code,step_id) do nothing;

-- Sandbox assertions. These prove only structural materialization inside this
-- transaction; they do not authorize the controlled_write step.
do $$
begin
  if not exists (
    select 1 from public.cat_estado_normalizacion_lf
    where estado_original='CANDIDATO_CONTROLADO_READ_ONLY'
      and estado_documental='CANDIDATO' and estado_operativo='READ_ONLY'
      and nivel_control='CONTROLADO' and runtime_estado='CANDIDATE_READ_ONLY'
      and impacto_automatico='BLOQUEADO'
  ) then raise exception 'S26_GA_TARGET_STATE_CATALOG_ASSERTION_FAILED'; end if;

  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
      and status='CANDIDATO_READ_ONLY'
  ) then raise exception 'S26_GA_OPERATION_REGISTRY_ASSERTION_FAILED'; end if;

  if (select count(*) from public.lf_operation_step_contracts
      where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF') <> 5
  then raise exception 'S26_GA_STEP_COUNT_ASSERTION_FAILED'; end if;

  if exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
      and step_id='controlled_write' and execution_sql is not null
  ) then raise exception 'S26_GA_SANDBOX_WRITE_EXECUTOR_MUST_BE_ABSENT'; end if;
end;
$$;

rollback;
