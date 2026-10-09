create or replace function programacion.fn_engineering_blocker_family_dispatch_v1(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_work_item_id bigint; v_code text; v_spec_status text; v_dep jsonb; v_result jsonb;
begin
  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    return jsonb_build_object('schema_version','ENGINEERING_BLOCKER_FAMILY_DISPATCH_V1_1',
      'status','UNIT_NOT_FOUND','supported_blocker_families',8,'state_changed',false);
  end if;

  v_spec_status:=coalesce(programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code)->>'status','');

  select b.blocker_code into v_code
  from programacion.engineering_work_blockers b
  where b.work_item_id=v_work_item_id and b.status='OPEN'
  order by b.id limit 1;

  if v_spec_status='BLOCK_OWNER_DECISION_REQUIRED' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_BLOCKER_FAMILY_DISPATCH_V1_1',
      'status','PRESERVED_OWNER_DECISION_REQUIRED','repair_family','OWNER_DECISION_GATE',
      'auto_repair','FORBIDDEN','supported_blocker_families',8,'state_changed',false
    );
  elsif v_code ilike '%TARGET_INCOMPLETE%' then
    v_result:=programacion.fn_engineering_target_completeness_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','TARGET_COMPLETENESS','supported_blocker_families',8);
  elsif v_code ilike '%INVALID_STRUCTURED_SOURCE_REF%' then
    v_result:=programacion.fn_engineering_structured_source_ref_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','STRUCTURED_SOURCE_REF','supported_blocker_families',8);
  elsif v_code ilike '%EVALUATOR_MISSING%' then
    v_result:=programacion.fn_engineering_evaluator_availability_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','EVALUATOR_AVAILABILITY','supported_blocker_families',8);
  elsif v_code ilike '%CURRENTNESS_DRIFT%' then
    v_result:=programacion.fn_engineering_currentness_drift_reconcile_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','CURRENTNESS_DRIFT','supported_blocker_families',8);
  elsif v_code ilike '%CANONICAL_IDENTITY_MISSING%' then
    v_result:=programacion.fn_engineering_canonical_identity_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','CANONICAL_IDENTITY','supported_blocker_families',8);
  elsif v_code ilike '%HISTORY_REEVALUATION_REQUIRED%' then
    v_result:=programacion.fn_engineering_historical_evidence_reevaluate_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','HISTORICAL_EVIDENCE','supported_blocker_families',8);
  elsif v_code='EVIDENCE_LEDGER_EXECUTION_BINDING_MISSING' then
    v_result:=programacion.fn_engineering_execution_context_bind_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','EXECUTION_CONTEXT','supported_blocker_families',8);
  elsif v_code='D-V2.3_ASSURANCE_EVALUATOR_ACTIVATION_DECISION' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_BLOCKER_FAMILY_DISPATCH_V1_1',
      'status','PRESERVED_OWNER_ACTIVATION_REQUIRED','repair_family','OWNER_ACTIVATION_GATE',
      'blocker_code',v_code,'auto_repair','FORBIDDEN',
      'supported_blocker_families',8,'state_changed',false
    );
  end if;

  v_dep:=programacion.fn_engineering_dependency_auto_release_v1(p_plan_code,p_unit_code,p_apply);
  if v_dep->>'status'='WAIT_DEPENDENCIES' then
    return v_dep||jsonb_build_object('repair_family','DEPENDENCY_AUTO_RELEASE','supported_blocker_families',8);
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_BLOCKER_FAMILY_DISPATCH_V1_1',
    'status','NOT_APPLICABLE','blocker_code',v_code,
    'dependency_state',v_dep->>'status',
    'supported_blocker_families',8,'state_changed',false
  );
end; $$;