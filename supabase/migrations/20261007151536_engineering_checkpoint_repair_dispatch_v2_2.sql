create or replace function programacion.fn_engineering_checkpoint_repair_dispatch_v2(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,
  p_error_code text default null,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_boot jsonb; v_spec jsonb; v_status text; v_meta jsonb; v_runtime jsonb;
  v_error text:=nullif(btrim(coalesce(p_error_code,'')),'');
  v_result jsonb; v_blocker_result jsonb;
begin
  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);

  if v_boot#>>'{current_checkpoint,checkpoint_code}' is distinct from p_checkpoint_code then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2_2',
      'status','NOT_CURRENT','current_checkpoint',v_boot#>>'{current_checkpoint,checkpoint_code}',
      'supported_error_classes',25,'state_changed',false
    );
  end if;

  v_spec:=coalesce(v_boot->'action_spec','{}'::jsonb);
  v_status:=coalesce(v_spec->>'status','');

  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';
  v_runtime:=v_meta#>array['runtime_repair_inputs_v1',p_checkpoint_code];

  if v_status='BLOCK_INDEPENDENCE_RECEIPT_REQUIRED' then
    v_result:=programacion.fn_engineering_independence_receipt_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    return v_result||jsonb_build_object('repair_family','INDEPENDENCE_RECEIPT','supported_error_classes',25);
  end if;

  if v_status in (
    'BLOCK_CAPABILITY_CUTOVER_NOT_REGISTERED','BLOCK_UPSTREAM_BUNDLE_PENDING',
    'BLOCK_UPSTREAM_CAPABILITY_CUTOVER_PENDING','BLOCK_UPSTREAM_OWNER_BINDING_PENDING',
    'BLOCK_UPSTREAM_RECEIPT_PENDING'
  ) then
    v_result:=programacion.fn_engineering_upstream_evidence_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    return v_result||jsonb_build_object('repair_family','UPSTREAM_EVIDENCE','supported_error_classes',25);
  end if;

  if exists(
    select 1 from jsonb_array_elements(coalesce(v_spec->'source_pack_missing_typed','[]'::jsonb)) m(value)
    where coalesce((m.value->>'blocking')::boolean,false)
  ) then
    v_result:=programacion.fn_engineering_source_gap_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    if coalesce(v_result->>'status','') not in ('ALREADY_SANITIZED','NOT_APPLICABLE') then
      return v_result||jsonb_build_object('repair_family','SOURCE_GAP','supported_error_classes',25);
    end if;
  end if;

  v_blocker_result:=programacion.fn_engineering_blocker_family_dispatch_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,p_apply
  );
  if coalesce(v_blocker_result->>'status','')<>'NOT_APPLICABLE' then
    return v_blocker_result||jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2_2',
      'supported_error_classes',25
    );
  end if;

  if v_error='CHECKPOINT_TRANSITION_STATUS_UNSUPPORTED' then
    v_result:=programacion.fn_engineering_transition_repair_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,
      v_runtime#>>'{transition_request,requested_status}',
      coalesce(v_runtime->'transition_request','{}'::jsonb),p_apply
    );
    return v_result||jsonb_build_object(
      'repair_family','TRANSITION_NORMALIZATION','detected_error',v_error,'supported_error_classes',25
    );
  end if;

  if v_error in ('HEARTBEAT_PHASE_UNSUPPORTED','HEARTBEAT_STEP_UNDECLARED') then
    v_result:=programacion.fn_engineering_heartbeat_normalize_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,
      v_runtime#>>'{heartbeat,phase}',v_runtime#>>'{heartbeat,step_code}',
      coalesce(v_runtime#>'{heartbeat,detail}','{}'::jsonb),
      v_runtime#>>'{heartbeat,evidence_ref}',
      coalesce(nullif(v_runtime#>>'{heartbeat,actor}',''),'ENGINEERING_REPAIR_DISPATCH_V2'),p_apply
    );
    return v_result||jsonb_build_object(
      'repair_family','HEARTBEAT_NORMALIZATION','detected_error',v_error,'supported_error_classes',25
    );
  end if;

  if v_error='SOURCE_PACK_MISSING' then
    v_result:=programacion.fn_engineering_source_pack_materialize_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    return v_result||jsonb_build_object(
      'repair_family','SOURCE_PACK_MATERIALIZATION','detected_error',v_error,'supported_error_classes',25
    );
  end if;

  if v_error='ROUTING_HANDLER_PENDING' then
    v_result:=programacion.fn_engineering_routing_handler_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    return v_result||jsonb_build_object(
      'repair_family','ROUTING_HANDLER','detected_error',v_error,'supported_error_classes',25
    );
  end if;

  v_result:=programacion.fn_engineering_checkpoint_repair_dispatch_v2_core(
    p_plan_code,p_unit_code,p_checkpoint_code,p_error_code,p_apply
  );

  return v_result||jsonb_build_object(
    'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2_2',
    'supported_error_classes',25
  );
end; $$;