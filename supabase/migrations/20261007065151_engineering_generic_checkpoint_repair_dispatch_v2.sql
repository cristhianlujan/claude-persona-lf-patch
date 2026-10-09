-- Generic checkpoint repair dispatch v2.
-- One procedure classifies deterministic contract and runtime execution failures.
-- Unit/checkpoint-specific data supplies exact targets; the procedure never invents authority.

create or replace function programacion.fn_engineering_checkpoint_repair_dispatch_v2(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_error_code text default null,
  p_apply boolean default true
)
returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_boot jsonb;
  v_spec jsonb;
  v_packet jsonb;
  v_meta jsonb;
  v_current jsonb;
  v_candidate jsonb;
  v_readiness jsonb;
  v_after jsonb;
  v_work_item_id bigint;
  v_error text := nullif(btrim(coalesce(p_error_code,'')),'');
  v_class text;
  v_runtime_input jsonb;
  v_targets jsonb;
  v_target jsonb;
  v_authoring jsonb;
  v_capability text;
  v_has_route boolean := false;
  v_targets_already boolean := false;
  v_result jsonb;
begin
  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(
    p_plan_code,p_unit_code
  );

  if v_boot#>>'{current_checkpoint,checkpoint_code}' is distinct from p_checkpoint_code then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
      'status','NOT_CURRENT',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'current_checkpoint',v_boot#>>'{current_checkpoint,checkpoint_code}',
      'state_changed',false
    );
  end if;

  v_spec:=coalesce(v_boot->'action_spec','{}'::jsonb);

  -- First: preserve the seven existing deterministic contract-repair families.
  if coalesce(v_spec->>'status','')<>'READY' then
    v_result:=programacion.fn_engineering_contract_repair_dispatch_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );

    if coalesce(v_result->>'status','')='NOT_SUPPORTED' then
      v_result:=programacion.fn_engineering_checkpoint_block_reduce_v1(
        p_plan_code,p_unit_code,p_checkpoint_code,p_apply
      );
    end if;

    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
      'status',coalesce(v_result->>'status','UNKNOWN'),
      'repair_family','CONTRACT_COMPILE',
      'detected_error',v_spec->>'status',
      'result',v_result,
      'supported_error_classes',13,
      'state_changed',coalesce(v_result->>'status','') in ('REPAIRED','REDUCED')
    );
  end if;

  v_packet:=coalesce(v_boot->'execution_packet','{}'::jsonb);
  v_capability:=nullif(v_packet->>'execution_capability','');

  select pu.work_item_id,pu.unit_metadata
    into v_work_item_id,v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_error is null and v_work_item_id is not null then
    select nullif(btrim(coalesce(
             case when left(ltrim(coalesce(u.detail,'')),1)='{'
               then (u.detail::jsonb)#>>'{detail,error_code}' end,
             case when left(ltrim(coalesce(u.detail,'')),1)='{'
               then (u.detail::jsonb)#>>'{detail,provider_error_code}' end,
             ''
           )),'')
      into v_error
    from programacion.engineering_work_updates u
    where u.work_item_id=v_work_item_id
      and u.update_type='PROGRESS'
      and u.summary like 'ACTION_HEARTBEAT|'||p_checkpoint_code||'|%'
      and (
        u.summary like '%ACTION_FAILED%'
        or u.summary like '%CONNECTOR_BLOCKED%'
        or u.summary like '%RETRYING%'
      )
    order by u.observed_at desc,u.id desc
    limit 1;
  end if;

  if v_error is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
      'status','ALREADY_READY',
      'repair_family','NONE',
      'supported_error_classes',13,
      'state_changed',false
    );
  end if;

  v_class:=case
    when v_error in (
      'GITHUB_RUN_TEST_ACTION_UNAVAILABLE_IN_CONNECTED_HOST',
      'RUN_TEST_PROVIDER_HAS_NO_EXECUTION_ACTION',
      'ENGINEERING_RUN_TEST_EXECUTOR_GAP'
    ) then 'RUN_TEST_TRANSPORT'

    when v_error in (
      'WRITE_ACTION_UNSPECIFIED',
      'MUTATE_UNDECLARED_TARGET'
    ) then 'EXACT_MUTATION_TARGET'

    when v_error in (
      'READONLY_POLICY_MISMATCH',
      'READONLY_BLOCKS_MATERIAL_ACTION',
      'READONLY_MATERIAL_ACTION_BLOCKED'
    ) then 'READONLY_SCOPE'

    when v_error in (
      'OBSERVE_ONLY_CONTROL_INCORRECTLY_PROMOTED_TO_GLOBAL_MERGE_BLOCKER',
      'MERGE_FALSE_BLOCK',
      'PASE_OBSERVE_ONLY_BLOCK'
    ) then 'MERGE_POLICY'

    when v_error in (
      'AGENT_OFFLINE',
      'CONNECTOR_SAFETY_BLOCK',
      'CONNECTOR_TEMPORARY_UNAVAILABLE'
    ) then 'TRANSIENT_CONNECTOR'

    when v_error in (
      'STALE_EXPLICIT_BLOCK_OVERRIDE',
      'SOURCE_PACK_STALE_CURRENTNESS'
    ) then 'STALE_AUTHORITY'

    else 'UNSUPPORTED_RUNTIME_ERROR'
  end;

  if v_class='RUN_TEST_TRANSPORT' then
    select exists(
      select 1
      from jsonb_array_elements(coalesce(v_packet->'connector_plan','[]'::jsonb)) x(item)
      where x.item->>'operation'='RUN_TEST'
        and x.item->>'provider'='SENTINELX'
        and x.item#>>'{runner_contract,actual_execution_required}'='true'
    ) into v_has_route;

    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
      'status',case when v_has_route then 'REPAIRED' else 'COMPILER_REPAIR_REQUIRED' end,
      'repair_family',v_class,
      'detected_error',v_error,
      'resolution',case when v_has_route
        then 'USE_CURRENT_SENTINELX_RUN_TEST_ROUTE'
        else 'RUN_TEST_ROUTE_NOT_EXECUTABLE' end,
      'next_action',case when v_has_route
        then 'RETRY_CURRENT_RUN_TEST_ONLY'
        else 'FIX_PACKET_COMPILER_BEFORE_RETRY' end,
      'supported_error_classes',13,
      'state_changed',false
    );
  end if;

  if v_class='READONLY_SCOPE' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
      'status',case
        when coalesce((v_spec->>'requires_material_execution')::boolean,false)
         and coalesce(v_packet#>'{readonly_policy,material_actions_allowed}','[]'::jsonb) ? coalesce(v_capability,'')
        then 'REPAIRED'
        else 'POLICY_REPAIR_REQUIRED'
      end,
      'repair_family',v_class,
      'detected_error',v_error,
      'execution_capability',v_capability,
      'resolution','READONLY_APPLIES_ONLY_TO_EXPLICIT_READ_ACTIONS',
      'supported_error_classes',13,
      'state_changed',false
    );
  end if;

  if v_class='MERGE_POLICY' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
      'status',case
        when v_packet#>>'{process_merge_authorization,auto_merge_when_authorized}'='true'
         and v_packet#>>'{process_merge_authorization,human_approval_required}'='false'
         and v_packet#>>'{process_merge_authorization,pase_policy,observe_only_results_cannot_block_merge}'='true'
        then 'REPAIRED'
        else 'POLICY_REPAIR_REQUIRED'
      end,
      'repair_family',v_class,
      'detected_error',v_error,
      'resolution','USE_EFFECTIVE_PROCESS_MERGE_AUTHORIZATION',
      'next_action','CONTINUE_GOVERNED_MERGE_WHEN_EXACT_PRECONDITIONS_PASS',
      'supported_error_classes',13,
      'state_changed',false
    );
  end if;

  if v_class='TRANSIENT_CONNECTOR' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
      'status','RETRY_SAME_OPERATION_ONCE',
      'repair_family',v_class,
      'detected_error',v_error,
      'retry_scope','CURRENT_PACKET_OPERATION_ONLY',
      'max_immediate_retries',1,
      'on_second_failure','YIELD_CURRENT_UNIT_CONTINUE_SCHEDULER',
      'restart_checkpoint',false,
      'supported_error_classes',13,
      'state_changed',false
    );
  end if;

  if v_class='STALE_AUTHORITY' then
    v_result:=programacion.fn_engineering_checkpoint_block_reduce_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
      'status',coalesce(v_result->>'status','STALE_REPAIR_REQUIRED'),
      'repair_family',v_class,
      'detected_error',v_error,
      'result',v_result,
      'supported_error_classes',13,
      'state_changed',coalesce(v_result->>'status','')='REDUCED'
    );
  end if;

  if v_class='EXACT_MUTATION_TARGET' then
    v_runtime_input:=v_meta#>array['runtime_repair_inputs_v1',p_checkpoint_code];
    v_targets:=v_runtime_input#>'{mutation_target,db_objects}';

    if coalesce(jsonb_typeof(v_targets),'')<>'array'
       or jsonb_array_length(v_targets)=0 then
      return jsonb_build_object(
        'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
        'status','INPUT_REQUIRED_EXACT_TARGETS',
        'repair_family',v_class,
        'detected_error',v_error,
        'required','unit_metadata.runtime_repair_inputs_v1.<checkpoint>.mutation_target.db_objects[]',
        'inference','FORBIDDEN',
        'supported_error_classes',13,
        'state_changed',false
      );
    end if;

    v_current:=v_meta#>array['action_specs_v1',p_checkpoint_code];
    if coalesce(jsonb_typeof(v_current),'')<>'object' then
      return jsonb_build_object(
        'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
        'status','INPUT_REQUIRED_EXPLICIT_ACTION_SPEC',
        'repair_family',v_class,
        'detected_error',v_error,
        'state_changed',false
      );
    end if;

    select not exists(
      select 1
      from jsonb_array_elements_text(v_targets) t(target)
      where not (
        coalesce(v_current#>'{target,declared_objects}','[]'::jsonb) ? t.target
      )
    ) into v_targets_already;

    if v_targets_already then
      return jsonb_build_object(
        'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
        'status','ALREADY_REPAIRED',
        'repair_family',v_class,
        'detected_error',v_error,
        'exact_targets',v_targets,
        'supported_error_classes',13,
        'state_changed',false
      );
    end if;

    v_target:=coalesce(v_current->'target','{}'::jsonb)
      || jsonb_build_object('declared_objects',v_targets);

    v_authoring:=coalesce(v_current->'authoring_contract','{}'::jsonb)
      || jsonb_build_object('db_targets_exact',v_targets);

    v_candidate:=v_current
      || jsonb_build_object(
        'target',v_target,
        'authoring_contract',v_authoring,
        'precision','DETERMINISTIC_RUNTIME_REPAIR_V1',
        'repair_policy',jsonb_build_object(
          'mode','EXACT_RUNTIME_ERROR_REPAIR',
          'error_code',v_error,
          'inference','FORBIDDEN'
        )
      );

    v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,v_candidate,
      coalesce(v_boot->'execution_input','{}'::jsonb)
    );

    v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,v_candidate,v_packet
    );

    if coalesce(v_packet->>'status','')<>'READY'
       or not coalesce((v_readiness#>>'{gates,COMPILE_READY}')::boolean,false)
       or not coalesce((v_readiness#>>'{gates,ACTION_EXACT}')::boolean,false)
       or not coalesce((v_readiness#>>'{gates,ERROR_CLOSED}')::boolean,false) then
      return jsonb_build_object(
        'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
        'status','PATCH_REJECTED',
        'repair_family',v_class,
        'detected_error',v_error,
        'exact_targets',v_targets,
        'packet_status',v_packet->>'status',
        'readiness_gates',v_readiness->'gates',
        'readiness_reasons',v_readiness->'reasons',
        'state_changed',false
      );
    end if;

    if not p_apply then
      return jsonb_build_object(
        'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
        'status','DRY_RUN_READY',
        'repair_family',v_class,
        'detected_error',v_error,
        'exact_targets',v_targets,
        'execution_capability',v_packet->>'execution_capability',
        'supported_error_classes',13,
        'state_changed',false
      );
    end if;

    update programacion.engineering_plan_units pu
       set unit_metadata=jsonb_set(
         coalesce(pu.unit_metadata,'{}'::jsonb),
         '{action_specs_v1}',
         coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
           || jsonb_build_object(p_checkpoint_code,v_candidate),
         true
       )
     where pu.plan_code=p_plan_code
       and pu.unit_code=p_unit_code
       and pu.disposition='ASSIGNED';

    v_after:=programacion.fn_engineering_unit_bootstrap_v3(
      p_plan_code,p_unit_code
    );

    if coalesce(v_after#>>'{action_spec,status}','')<>'READY'
       or coalesce(v_after#>>'{execution_readiness,status}','')<>'READY'
       or coalesce(v_after#>>'{execution_packet,status}','')<>'READY' then
      raise exception 'ENGINEERING_RUNTIME_REPAIR_POSTCHECK_FAILED:%/%/%',
        p_plan_code,p_unit_code,p_checkpoint_code;
    end if;

    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
      'status','REPAIRED',
      'repair_family',v_class,
      'detected_error',v_error,
      'exact_targets',v_targets,
      'post_action_spec_status',v_after#>>'{action_spec,status}',
      'post_packet_status',v_after#>>'{execution_packet,status}',
      'supported_error_classes',13,
      'state_changed',true
    );
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2',
    'status','NOT_SUPPORTED',
    'repair_family',v_class,
    'detected_error',v_error,
    'supported_error_classes',13,
    'state_changed',false
  );
end;
$function$;

comment on function programacion.fn_engineering_checkpoint_repair_dispatch_v2(text,text,text,text,boolean)
is 'Generic deterministic repair dispatcher for seven compile-time contract blocker families plus six runtime execution error families. Exact targets must be supplied as data; inference is forbidden.';

-- Register exact mutation authority for M4.7 as data, not as procedure logic.
update programacion.engineering_plan_units pu
set unit_metadata=jsonb_set(
  coalesce(pu.unit_metadata,'{}'::jsonb),
  '{runtime_repair_inputs_v1}',
  coalesce(pu.unit_metadata->'runtime_repair_inputs_v1','{}'::jsonb)
  || jsonb_build_object(
    'FAIL_BLOCKED_PERSISTED',
    jsonb_build_object(
      'schema_version','ENGINEERING_RUNTIME_REPAIR_INPUT_V1',
      'error_codes',jsonb_build_array('WRITE_ACTION_UNSPECIFIED','MUTATE_UNDECLARED_TARGET'),
      'mutation_target',jsonb_build_object(
        'db_objects',jsonb_build_array(
          'programacion.fn_input_governance_bootstrap_assertions_v1',
          'programacion.fn_input_evaluate_assertion',
          'programacion.fn_input_rebind_assertion',
          'programacion.fn_input_rebind_assertion_specs',
          'programacion.fn_input_governance_bootstrap_validate_v1',
          'programacion.fn_input_governance_validate_v2'
        )
      ),
      'inference','FORBIDDEN'
    )
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M4.7'
  and pu.disposition='ASSIGNED';

-- Keep the canonical executor hook name, but make it use the generic dispatcher
-- even when the action spec is already READY and the failure is runtime/connector scoped.
create or replace function programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(
  p_plan_code text,
  p_unit_code text
)
returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  boot jsonb;
  cp text;
  st text;
  repair jsonb;
  changed boolean:=false;
begin
  boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  cp:=nullif(btrim(coalesce(boot#>>'{current_checkpoint,checkpoint_code}','')),'');

  if cp is null then
    return boot||jsonb_build_object(
      'contract_repair_auto',
      jsonb_build_object(
        'schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V3',
        'status','NOT_APPLICABLE',
        'reason','NO_CURRENT_CHECKPOINT',
        'supported_error_classes',13
      )
    );
  end if;

  st:=coalesce(boot#>>'{action_spec,status}','');

  repair:=programacion.fn_engineering_checkpoint_repair_dispatch_v2(
    p_plan_code,p_unit_code,cp,null,true
  );

  changed:=coalesce((repair->>'state_changed')::boolean,false);

  if changed then
    boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  end if;

  return boot||jsonb_build_object(
    'contract_repair_auto',
    jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V3',
      'checkpoint_code',cp,
      'detected_action_spec_status',st,
      'supported_error_classes',13,
      'result',repair,
      'rebootstrap_after_repair',changed
    )
  );
end;
$function$;

-- Apply the generic runtime repair to the currently known M4.7 error.
do $repair$
declare
  r jsonb;
begin
  r:=programacion.fn_engineering_checkpoint_repair_dispatch_v2(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M4.7',
    'FAIL_BLOCKED_PERSISTED',
    'WRITE_ACTION_UNSPECIFIED',
    true
  );

  if coalesce(r->>'status','') not in ('REPAIRED','ALREADY_REPAIRED') then
    raise exception 'ENGINEERING_GENERIC_RUNTIME_REPAIR_M4_7_FAILED:%',r;
  end if;
end;
$repair$;

do $selftest$
declare
  r_m47 jsonb;
  r_m49 jsonb;
begin
  r_m47:=programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.7'
  );

  if r_m47#>>'{action_spec,status}'<>'READY'
     or r_m47#>>'{execution_packet,status}'<>'READY'
     or not (
       coalesce(r_m47#>'{action_spec,target,declared_objects}','[]'::jsonb)
         ? 'programacion.fn_input_governance_validate_v2'
     ) then
    raise exception 'ENGINEERING_GENERIC_REPAIR_SELFTEST_M4_7_FAIL:%',
      r_m47#>'{action_spec,target,declared_objects}';
  end if;

  r_m49:=programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.9'
  );

  if r_m49#>>'{execution_packet,connector_plan,1,operation}'='RUN_TEST'
     and r_m49#>>'{execution_packet,connector_plan,1,provider}'<>'SENTINELX' then
    raise exception 'ENGINEERING_GENERIC_REPAIR_SELFTEST_RUN_TEST_FAIL:%',
      r_m49#>'{execution_packet,connector_plan,1}';
  end if;
end;
$selftest$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-GENERIC-CHECKPOINT-REPAIR-DISPATCH-002',
  'ENGINEERING_ORCHESTRATION',
  'Checkpoint repair is dispatched by error family, never by unit-specific procedure',
  'Contract and runtime failures were repaired by separate paths, allowing connector, readonly, merge and exact-target errors to fall back to manual handling.',
  'Repair routing was organized by implementation layer instead of deterministic error family.',
  'KNOWN_ERROR -> GENERIC_REPAIR_DISPATCH -> EXACT_HANDLER -> SAME_CHECKPOINT_CONTINUATION',
  'Use fn_engineering_checkpoint_repair_dispatch_v2. It preserves the seven existing contract families and adds six runtime families: RUN_TEST transport, exact mutation target, readonly scope, merge policy, transient connector and stale authority. Unit-specific facts are inputs only; handler logic never branches on unit code.',
  'PASS when dispatcher reports supported_error_classes=13; M4.7 WRITE_ACTION_UNSPECIFIED is repaired from exact registered targets; RUN_TEST packets use SentinelX; transient connector errors retry only the failed operation once; unknown errors remain fail-closed.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_checkpoint_repair_dispatch_v2',
  'EXECUTION',
  array['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Generic deterministic checkpoint repair',
  'supabase://programacion.fn_engineering_checkpoint_repair_dispatch_v2'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();
