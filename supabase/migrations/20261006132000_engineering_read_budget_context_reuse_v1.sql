-- ENGINEERING_READ_BUDGET_CONTEXT_REUSE_V1
-- Generic correction: resolve engineering context once, reuse it through readiness/currentness,
-- and compile multiple declared read components into one connector statement when checkpoint_queries_max=1.
-- Source reconstructed from live pg_get_functiondef after full regression on 2026-10-06.
-- No runtime/production activation beyond the existing engineering control plane.

CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(p_checkpoint_code text, p_action_spec jsonb, p_packet jsonb, p_unit_metadata jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_meta jsonb:=p_unit_metadata;
  v_source jsonb;
  v_source_check jsonb;
  v_tx jsonb;
  v_explicit jsonb;
  v_compile_ready boolean:=false;
  v_source_ready boolean:=false;
  v_source_current boolean:=false;
  v_source_complete boolean:=true;
  v_routing_ready boolean:=false;
  v_action_exact boolean:=false;
  v_error_closed boolean:=false;
  v_material boolean:=false;
  v_cap text;
  v_reasons jsonb:='[]'::jsonb;
  v_pending_handlers int:=0;
  v_blocking_missing int:=0;
  v_has_read boolean:=false;
  v_has_write_git boolean:=false;
  v_has_run_test boolean:=false;
  v_has_exact_write_db boolean:=false;
begin
  if v_meta is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_EXECUTION_READINESS_V1',
      'status','NOT_READY',
      'execution_ready',false,
      'reasons',jsonb_build_array('UNIT_NOT_FOUND'),
      'context_reused',false
    );
  end if;

  v_source:=coalesce(
    v_meta#>array['source_pack_v2','checkpoint_inputs',p_checkpoint_code],
    v_meta#>array['source_pack_v1','checkpoint_inputs',p_checkpoint_code]
  );
  v_explicit:=v_meta#>array['action_specs_v1',p_checkpoint_code];
  v_tx:=v_meta#>array['transversal_execution_v1',p_checkpoint_code];

  v_compile_ready:=
    coalesce(p_action_spec->>'status','')='READY'
    and coalesce(p_packet->>'status','')='READY';

  v_source_ready:=
    v_source is not null
    or v_explicit is not null
    or p_checkpoint_code in ('HANDOFF_EVENT','INDEPENDENT_READBACK_TERMINAL');

  if v_source is not null then
    select count(*)
    into v_blocking_missing
    from jsonb_array_elements(coalesce(v_source->'missing_typed','[]'::jsonb)) x(item)
    where coalesce((x.item->>'blocking')::boolean,false)=true;
  end if;

  v_source_complete:=v_blocking_missing=0;

  v_source_check:=programacion.fn_engineering_source_pack_currentness_from_context_v1(
    v_meta,p_checkpoint_code
  );

  v_source_current:=
    v_source_check->>'status' in ('CURRENT','MISSING')
    and not (
      v_source_check->>'status'='MISSING'
      and not (
        v_explicit is not null
        or p_checkpoint_code in ('HANDOFF_EVENT','INDEPENDENT_READBACK_TERMINAL')
      )
    );

  if v_tx is null then
    v_routing_ready:=true;
  else
    select count(*)
    into v_pending_handlers
    from jsonb_array_elements(coalesce(v_tx->'capabilities','[]'::jsonb)) c(item)
    where coalesce(c.item->>'handler','') in ('','DECLARED_HANDLER_PENDING');

    v_routing_ready:=
      coalesce(v_tx->>'activation','')='ACTIVE'
      and v_pending_handlers=0;
  end if;

  v_material:=coalesce((p_action_spec->>'requires_material_execution')::boolean,false);
  v_cap:=coalesce(p_packet->>'execution_capability','');

  select
    exists(
      select 1
      from jsonb_array_elements(coalesce(p_packet->'connector_plan','[]'::jsonb)) op
      where op->>'operation'='READ'
        and jsonb_array_length(coalesce(op->'queries','[]'::jsonb))>0
    ),
    exists(
      select 1
      from jsonb_array_elements(coalesce(p_packet->'connector_plan','[]'::jsonb)) op
      where op->>'operation'='WRITE_GIT'
        and jsonb_array_length(coalesce(op->'targets','[]'::jsonb))>0
    ),
    exists(
      select 1
      from jsonb_array_elements(coalesce(p_packet->'connector_plan','[]'::jsonb)) op
      where op->>'operation'='RUN_TEST'
        and jsonb_typeof(op->'executor_contract')='object'
    ),
    exists(
      select 1
      from jsonb_array_elements(coalesce(p_packet->'connector_plan','[]'::jsonb)) op
      where op->>'operation'='WRITE_DB'
        and (
          coalesce(op->>'entrypoint','')<>''
          or coalesce(op->>'call_template','')<>''
          or coalesce(op->>'sql','')<>''
          or coalesce(op->>'exact_sql','')<>''
          or coalesce(op->>'mutation_sql','')<>''
          or coalesce(op->>'mode','') in ('CANONICAL_CLOSURE_EVENT')
        )
    )
  into v_has_read,v_has_write_git,v_has_run_test,v_has_exact_write_db;

  v_action_exact:=case v_cap
    when 'READ' then
      v_has_read
      or (
        coalesce(p_action_spec->>'action_kind','')='NOOP'
        and v_material=false
      )
    when 'WRITE_DB' then
      v_has_exact_write_db
      or coalesce(p_action_spec->>'recipe_mode','')='EXECUTE_CANONICAL_CLOSURE_EVENT'
    when 'WRITE_GIT' then
      v_has_write_git
    when 'RUN_TEST' then
      v_has_run_test
    else false
  end;

  v_error_closed:=coalesce(
    jsonb_typeof(p_packet->'error_contracts')='object'
    and jsonb_typeof(p_packet->'retry_policy')='object'
    and jsonb_typeof(p_packet->'anomaly_observation_contract')='object'
    and (
      not v_material
      or jsonb_typeof(p_packet->'heartbeat_contract')='object'
    ),false);

  if not v_compile_ready then
    v_reasons:=v_reasons||jsonb_build_array('COMPILE_NOT_READY');
    if nullif(coalesce(p_action_spec->>'status',''),'') is not null
       and p_action_spec->>'status'<>'READY' then
      v_reasons:=v_reasons||jsonb_build_array(p_action_spec->>'status');
    end if;
  end if;
  if not v_source_ready then
    v_reasons:=v_reasons||jsonb_build_array('SOURCE_PACK_MISSING');
  end if;
  if not v_source_complete then
    v_reasons:=v_reasons||jsonb_build_array('SOURCE_BLOCKING_MISSING');
  end if;
  if v_source_check->>'status'='STALE' then
    v_reasons:=v_reasons||jsonb_build_array('SOURCE_PACK_STALE_CURRENTNESS');
  end if;
  if not v_routing_ready then
    v_reasons:=v_reasons||jsonb_build_array('ROUTING_HANDLER_PENDING');
  end if;
  if v_compile_ready and not v_action_exact then
    v_reasons:=v_reasons||jsonb_build_array(
      case when v_cap='WRITE_DB' then 'WRITE_ACTION_UNSPECIFIED'
           when v_cap='WRITE_GIT' then 'WRITE_GIT_PACKET_INCOMPLETE'
           when v_cap='RUN_TEST' then 'RUN_TEST_PACKET_INCOMPLETE'
           when v_cap='READ' then 'READ_QUERY_MISSING'
           else 'EXECUTION_CAPABILITY_UNRESOLVED'
      end
    );
  end if;
  if not coalesce(v_error_closed,false) then
    v_reasons:=v_reasons||jsonb_build_array('ERROR_CONTRACT_INCOMPLETE');
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_EXECUTION_READINESS_V1',
    'status',case
      when v_compile_ready and v_source_ready and v_source_current
       and v_source_complete and v_routing_ready and v_action_exact and v_error_closed
      then 'READY'
      else 'NOT_READY'
    end,
    'execution_ready',
      v_compile_ready and v_source_ready and v_source_current
      and v_source_complete and v_routing_ready and v_action_exact and v_error_closed,
    'checkpoint_code',p_checkpoint_code,
    'execution_capability',v_cap,
    'gates',jsonb_build_object(
      'COMPILE_READY',v_compile_ready,
      'SOURCE_PRESENT',v_source_ready,
      'SOURCE_CURRENT',v_source_current,
      'SOURCE_COMPLETE',v_source_complete,
      'ROUTING_READY',v_routing_ready,
      'ACTION_EXACT',v_action_exact,
      'ERROR_CLOSED',v_error_closed
    ),
    'source_currentness',v_source_check,
    'source_completeness',jsonb_build_object(
      'blocking_missing_count',v_blocking_missing
    ),
    'routing',jsonb_build_object(
      'activation',v_tx->>'activation',
      'pending_handler_count',v_pending_handlers,
      'action_spec_status',p_action_spec->>'status',
      'transversal_handler',p_action_spec->>'transversal_handler',
      'handler_requirement',p_action_spec->'handler_requirement'
    ),
    'action_exactness',jsonb_build_object(
      'read_query_present',v_has_read,
      'write_db_exact_present',v_has_exact_write_db,
      'write_git_targets_present',v_has_write_git,
      'run_test_contract_present',v_has_run_test
    ),
    'context_reused',true,
    'reasons',v_reasons
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb, p_packet jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_meta jsonb;
begin
  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  return programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(
    p_checkpoint_code,p_action_spec,p_packet,v_meta
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_input_upsert_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_queries jsonb, p_db_objects jsonb DEFAULT '[]'::jsonb, p_assets jsonb DEFAULT '[]'::jsonb, p_events jsonb DEFAULT '[]'::jsonb, p_artifacts jsonb DEFAULT '[]'::jsonb, p_missing jsonb DEFAULT '[]'::jsonb, p_missing_typed jsonb DEFAULT '[]'::jsonb, p_resolved_authorities jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_meta jsonb;
  v_sp jsonb;
  v_inputs jsonb;
  v_budget int;
  v_component_count int;
  v_connector_count int;
  v_bundle text;
  v_q text;
  v_inner text;
  v_plan json;
begin
  if jsonb_typeof(coalesce(p_queries,'[]'::jsonb))<>'array' then
    raise exception 'QUERIES_MUST_BE_ARRAY';
  end if;

  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
  for update;

  if v_meta is null then
    raise exception 'UNIT_NOT_FOUND:%/%',p_plan_code,p_unit_code;
  end if;

  if exists (
    select 1
    from jsonb_array_elements_text(coalesce(p_queries,'[]'::jsonb)) q(value)
    where q.value ~* 'join[[:space:]]+programacion[.]engineering_work_items[[:space:]]+w[[:space:]]+on[[:space:]]+w[.]id[[:space:]]*=[[:space:]]*d[.]work_item_id'
  ) then
    raise exception 'QUERY_SHAPE_REDUNDANT_SOURCE_WORK_ITEM_JOIN: use programacion.fn_engineering_dependency_edges_readback_v1';
  end if;

  if coalesce((v_meta#>>'{source_fast_path_v2,scope_rules,forbid_pg_proc_scan}')::boolean,false)
     and exists (
       select 1 from jsonb_array_elements_text(coalesce(p_queries,'[]'::jsonb)) q(value)
       where q.value ~* '(^|[^a-z0-9_])pg_proc([^a-z0-9_]|$)'
     ) then
    raise exception 'QUERY_SCOPE_FORBIDDEN_PG_PROC_SCAN';
  end if;

  if coalesce((v_meta#>>'{source_fast_path_v2,schema_contract,forbid_information_schema_preflight}')::boolean,false)
     and exists (
       select 1 from jsonb_array_elements_text(coalesce(p_queries,'[]'::jsonb)) q(value)
       where q.value ~* 'information_schema[.]'
     ) then
    raise exception 'QUERY_SCOPE_FORBIDDEN_INFORMATION_SCHEMA_PREFLIGHT';
  end if;

  v_budget:=nullif(
    coalesce(
      v_meta#>>'{source_fast_path_v2,read_budget,checkpoint_queries_max}',
      v_meta#>>'{source_fast_path_v1,preferred_queries_max}'
    ),''
  )::int;
  v_component_count:=jsonb_array_length(coalesce(p_queries,'[]'::jsonb));
  v_connector_count:=v_component_count;

  if v_budget=1 and v_component_count>1 then
    v_bundle:=programacion.fn_engineering_read_bundle_sql_v1(p_queries);
    execute 'explain (format json) '||v_bundle into v_plan;
    v_connector_count:=1;
  else
    for v_q in select value from jsonb_array_elements_text(coalesce(p_queries,'[]'::jsonb))
    loop
      v_q:=regexp_replace(coalesce(v_q,''),'^[[:space:]]+','','');
      if v_q ~* '^explain[[:space:]]*[(][[:space:]]*format[[:space:]]+json[[:space:]]*[)][[:space:]]+' then
        v_inner:=regexp_replace(
          v_q,
          '^explain[[:space:]]*[(][[:space:]]*format[[:space:]]+json[[:space:]]*[)][[:space:]]+',
          '',
          'i'
        );
        perform programacion.fn_engineering_explain_json_v1(v_inner);
      else
        execute 'explain (format json) '||v_q into v_plan;
      end if;
    end loop;
  end if;

  v_sp:=coalesce(v_meta->'source_pack_v2','{}'::jsonb);
  v_inputs:=coalesce(v_sp->'checkpoint_inputs','{}'::jsonb);

  v_inputs:=v_inputs||jsonb_build_object(
    p_checkpoint_code,
    jsonb_build_object(
      'inputs',jsonb_build_object(
        'queries',coalesce(p_queries,'[]'::jsonb),
        'db_objects',coalesce(p_db_objects,'[]'::jsonb),
        'assets',coalesce(p_assets,'[]'::jsonb),
        'events',coalesce(p_events,'[]'::jsonb),
        'artifacts',coalesce(p_artifacts,'[]'::jsonb)
      ),
      'missing',coalesce(p_missing,'[]'::jsonb),
      'missing_typed',coalesce(p_missing_typed,'[]'::jsonb),
      'resolved_authorities_v1',coalesce(p_resolved_authorities,'{}'::jsonb),
      'query_budget_contract',jsonb_build_object(
        'checkpoint_queries_max',v_budget,
        'component_query_count',v_component_count,
        'connector_query_count',v_connector_count,
        'compile_mode',case
          when v_budget=1 and v_component_count>1 then 'ENGINEERING_READ_BUNDLE_V1'
          else 'DIRECT'
        end
      ),
      'materialized_by','programacion.fn_engineering_checkpoint_input_upsert_v1',
      'materialized_at',clock_timestamp()
    )
  );

  v_sp:=v_sp||jsonb_build_object(
    'checkpoint_inputs',v_inputs,
    'checkpoint_inputs_contract','SOURCE_PACK_V2_CHECKPOINT_INPUTS_V1'
  );

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(v_meta,'{source_pack_v2}',v_sp,true)
  where plan_code=p_plan_code
    and unit_code=p_unit_code;

  return jsonb_build_object(
    'status','UPSERTED',
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'query_count',v_component_count,
    'component_query_count',v_component_count,
    'connector_query_count',v_connector_count,
    'checkpoint_queries_max',v_budget,
    'missing_count',jsonb_array_length(coalesce(p_missing,'[]'::jsonb)),
    'blocking_missing_count',(
      select count(*)
      from jsonb_array_elements(coalesce(p_missing_typed,'[]'::jsonb)) x(item)
      where coalesce((x.item->>'blocking')::boolean,false)=true
    )
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_source_query_preflight_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_meta jsonb;
  v_input jsonb;
  v_queries jsonb;
  v_q text;
  v_idx int:=0;
  v_total int:=0;
  v_pass int:=0;
  v_fail int:=0;
  v_errors jsonb:='[]'::jsonb;
  v_plan json;
  v_budget int;
  v_bundle text;
  v_inner text;
begin
  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;

  v_input:=coalesce(
    v_meta#>array['source_pack_v2','checkpoint_inputs',p_checkpoint_code],
    v_meta#>array['source_pack_v1','checkpoint_inputs',p_checkpoint_code]
  );

  if v_input is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_SOURCE_QUERY_PREFLIGHT_V2',
      'status','SOURCE_PACK_MISSING',
      'query_count',0,
      'component_query_count',0,
      'connector_query_count',0
    );
  end if;

  v_queries:=coalesce(v_input#>'{inputs,queries}','[]'::jsonb);
  v_total:=jsonb_array_length(v_queries);
  v_budget:=nullif(
    coalesce(
      v_meta#>>'{source_fast_path_v2,read_budget,checkpoint_queries_max}',
      v_meta#>>'{source_fast_path_v1,preferred_queries_max}'
    ),''
  )::int;

  if v_budget=1 and v_total>1 then
    begin
      v_bundle:=programacion.fn_engineering_read_bundle_sql_v1(v_queries);
      execute 'explain (format json) '||v_bundle into v_plan;
      v_pass:=v_total;
    exception when others then
      v_fail:=v_total;
      v_errors:=jsonb_build_array(jsonb_build_object(
        'query_no',0,
        'scope','COMPILED_READ_BUNDLE',
        'sqlstate',sqlstate,
        'message',sqlerrm
      ));
    end;

    return jsonb_build_object(
      'schema_version','ENGINEERING_SOURCE_QUERY_PREFLIGHT_V2',
      'status',case when v_fail=0 then 'PASS' else 'FAIL' end,
      'query_count',v_total,
      'component_query_count',v_total,
      'connector_query_count',1,
      'checkpoint_queries_max',v_budget,
      'bundled',true,
      'passed',v_pass,
      'failed',v_fail,
      'errors',v_errors
    );
  end if;

  for v_q in
    select value from jsonb_array_elements_text(v_queries)
  loop
    v_idx:=v_idx+1;
    begin
      v_q:=regexp_replace(coalesce(v_q,''),'^[[:space:]]+','','');
      if v_q ~* '^explain[[:space:]]*[(][[:space:]]*format[[:space:]]+json[[:space:]]*[)][[:space:]]+' then
        v_inner:=regexp_replace(
          v_q,
          '^explain[[:space:]]*[(][[:space:]]*format[[:space:]]+json[[:space:]]*[)][[:space:]]+',
          '',
          'i'
        );
        perform programacion.fn_engineering_explain_json_v1(v_inner);
      else
        execute 'explain (format json) '||v_q into v_plan;
      end if;
      v_pass:=v_pass+1;
    exception when others then
      v_fail:=v_fail+1;
      v_errors:=v_errors||jsonb_build_array(jsonb_build_object(
        'query_no',v_idx,
        'sqlstate',sqlstate,
        'message',sqlerrm
      ));
    end;
  end loop;

  return jsonb_build_object(
    'schema_version','ENGINEERING_SOURCE_QUERY_PREFLIGHT_V2',
    'status',case when v_fail=0 then 'PASS' else 'FAIL' end,
    'query_count',v_total,
    'component_query_count',v_total,
    'connector_query_count',v_total,
    'checkpoint_queries_max',v_budget,
    'bundled',false,
    'passed',v_pass,
    'failed',v_fail,
    'errors',v_errors
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_dependency_edges_readback_v1(p_plan_code text, p_source_work_codes text[] DEFAULT NULL::text[], p_dependency_work_codes text[] DEFAULT NULL::text[])
 RETURNS TABLE(source_work_code text, depends_on_work_code text, depends_on_status text, depends_on_title text, dep_unit text, dep_lot text)
 LANGUAGE sql
 STABLE
AS $function$
  select
    src.work_code::text,
    dep.work_code::text,
    dep.status::text,
    dep.title::text,
    pu.unit_code::text,
    pu.lot_code::text
  from programacion.engineering_work_dependencies d
  join programacion.engineering_work_items src on src.id=d.work_item_id
  join programacion.engineering_work_items dep on dep.id=d.depends_on_work_item_id
  left join programacion.engineering_plan_units pu
    on pu.work_item_id=dep.id
   and pu.plan_code=p_plan_code
  where
    (p_source_work_codes is not null and src.work_code=any(p_source_work_codes))
    or
    (p_dependency_work_codes is not null and dep.work_code=any(p_dependency_work_codes))
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_execution_packet_from_spec_core_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb, p_execution_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_packet jsonb;
  v_seq jsonb;
  v_plan jsonb;
  v_last_idx int;
  v_transition jsonb;
  v_new_transition jsonb;
begin
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1_legacy(
    p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec,p_execution_input
  );

  if coalesce((p_action_spec->>'requires_material_execution')::boolean,false) then
    v_packet:=v_packet || jsonb_build_object(
      'heartbeat_contract',jsonb_build_object(
        'entrypoint','programacion.fn_engineering_checkpoint_heartbeat_v1',
        'p_detail_type','JSONB_OBJECT',
        'action_started',jsonb_build_object(
          'p_phase','ACTION_STARTED',
          'p_step_code',null
        ),
        'action_done',jsonb_build_object(
          'p_phase','ACTION_DONE',
          'p_step_code',null
        ),
        'action_failed',jsonb_build_object(
          'p_phase','ACTION_FAILED',
          'p_step_code',null
        ),
        'step_heartbeat_rule','IF STEP_STARTED/STEP_DONE IS USED, p_step_code MUST BE AN EXACT MEMBER OF action_spec.action_steps',
        'step_code_source','ACTION_SPEC_ACTION_STEPS_ONLY',
        'connector_seq_is_step_code',false,
        'connector_operation_is_step_code',false,
        'rebootstrap_after_heartbeat',false,
        'forbidden',jsonb_build_array(
          'CONNECTOR_PLAN_SEQ_AS_STEP_CODE',
          'CONNECTOR_OPERATION_AS_STEP_CODE',
          'TEXT_P_DETAIL_WHEN_JSONB_REQUIRED'
        )
      )
    );
  end if;

  v_packet:=v_packet || jsonb_build_object(
    'error_contracts',jsonb_build_object(
      'checkpoint_transition_status',programacion.fn_engineering_error_contract_v1('CHECKPOINT_TRANSITION_STATUS_UNSUPPORTED'),
      'heartbeat_phase',programacion.fn_engineering_error_contract_v1('HEARTBEAT_PHASE_UNSUPPORTED'),
      'heartbeat_step',programacion.fn_engineering_error_contract_v1('HEARTBEAT_STEP_UNDECLARED'),
      'write_action_unspecified',programacion.fn_engineering_error_contract_v1('WRITE_ACTION_UNSPECIFIED'),
      'source_pack_missing',programacion.fn_engineering_error_contract_v1('SOURCE_PACK_MISSING'),
      'source_pack_stale',programacion.fn_engineering_error_contract_v1('SOURCE_PACK_STALE_CURRENTNESS'),
      'routing_handler_pending',programacion.fn_engineering_error_contract_v1('ROUTING_HANDLER_PENDING')
    )
  );

  v_packet:=v_packet || jsonb_build_object(
    'anomaly_observation_contract',jsonb_build_object(
      'entrypoint','programacion.fn_engineering_execution_observation_v1',
      'record_on',jsonb_build_array(
        'CONNECTOR_BLOCKED','SAFETY_BLOCK','RETRYING','CONTRADICTION',
        'STALE_CURRENTNESS','FALLBACK_SELECTED','ACTION_FAILED',
        'PACKET_INCOMPLETE','SOURCE_PACK_STALE','HANDLER_MISSING'
      ),
      'normal_success_extra_write',false,
      'operation_ref_format','SEQ<seq>_<operation>',
      'detail_fields',jsonb_build_array(
        'query_sha256','elapsed_ms','retry_count','fallback_trigger',
        'provider_error_code','live_value','expected_value'
      )
    )
  );

  v_packet:=programacion.fn_engineering_packet_apply_explicit_test_cases_v1(v_packet,p_action_spec);

  v_seq:=p_action_spec->'transversal_sequence';

  if v_seq is null
     or coalesce(p_action_spec->>'status','')<>'READY'
     or coalesce((v_seq->>'total')::int,0)<=1
     or coalesce((v_seq->>'is_last')::boolean,false) then
    return v_packet;
  end if;

  if coalesce(v_packet->>'status','')<>'READY' then
    return v_packet;
  end if;

  v_plan:=coalesce(v_packet->'connector_plan','[]'::jsonb);
  v_last_idx:=jsonb_array_length(v_plan)-1;

  if v_last_idx<0 then
    return v_packet || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_PACKET_EMPTY'
    );
  end if;

  v_transition:=v_plan->v_last_idx;

  if coalesce(v_transition->>'operation','')<>'CHECKPOINT_TRANSITION' then
    return v_packet || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_FINAL_TRANSITION_MISSING'
    );
  end if;

  v_new_transition:=jsonb_build_object(
    'seq',coalesce((v_transition->>'seq')::int,v_last_idx+1),
    'provider','SUPABASE',
    'operation','CHECKPOINT_TRANSITION',
    'mode','TRANSVERSAL_STEP',
    'entrypoint','programacion.fn_engineering_transversal_step_transition_v1',
    'returns','NEXT_BOOTSTRAP_V3_USE_AS_ONLY_NEXT_STATE',
    'arguments',jsonb_build_object(
      'p_plan_code',p_plan_code,
      'p_unit_code',p_unit_code,
      'p_checkpoint_code',p_checkpoint_code,
      'p_sequence_digest',v_seq->>'sequence_digest',
      'p_capability_index',(v_seq->>'next_index')::int,
      'p_capability_code',v_seq->>'current_capability_code',
      'p_evidence_ref','<FILL: evidence of THIS transversal capability step>',
      'p_actor','<FILL: agent name>',
      'p_detail','<FILL: live result of THIS transversal capability step>'
    ),
    'call_template',format(
      'select programacion.fn_engineering_transversal_step_transition_v1(%L,%L,%L,%L,%s,%L,<p_evidence_ref>,<p_actor>,<p_detail>)',
      p_plan_code,p_unit_code,p_checkpoint_code,
      v_seq->>'sequence_digest',
      (v_seq->>'next_index')::int,
      v_seq->>'current_capability_code'
    )
  );

  v_plan:=(v_plan - v_last_idx) || jsonb_build_array(v_new_transition);

  return jsonb_set(
    v_packet || jsonb_build_object(
      'transversal_sequence_mode','ONE_BY_ONE_REBOOTSTRAP',
      'transversal_sequence',v_seq
    ),
    '{connector_plan}',
    v_plan,
    true
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_execution_packet_from_spec_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb, p_execution_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_packet jsonb;
  v_budget int;
begin
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec,p_execution_input
  );

  v_budget:=nullif(p_action_spec#>>'{read_budget,checkpoint_queries_max}','')::int;

  if v_budget is null then
    select nullif(
      coalesce(
        pu.unit_metadata#>>'{source_fast_path_v2,read_budget,checkpoint_queries_max}',
        pu.unit_metadata#>>'{source_fast_path_v1,preferred_queries_max}'
      ),''
    )::int
    into v_budget
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code
      and pu.unit_code=p_unit_code;
  end if;

  return programacion.fn_engineering_packet_apply_read_budget_v1(
    v_packet,v_budget
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_explain_json_v1(p_sql text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_sql text:=regexp_replace(coalesce(p_sql,''),'^[[:space:]]+','','');
  v_plan json;
begin
  if v_sql !~* '^(select|with)[[:space:]]' then
    raise exception 'EXPLAIN_JSON_NON_READ_QUERY';
  end if;
  if position(';' in v_sql)>0 then
    raise exception 'EXPLAIN_JSON_SEMICOLON_FORBIDDEN';
  end if;

  execute 'explain (format json) '||v_sql into v_plan;
  return v_plan::jsonb;
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_packet_apply_read_budget_v1(p_packet jsonb, p_checkpoint_queries_max integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_plan jsonb:=coalesce(p_packet->'connector_plan','[]'::jsonb);
  v_new_plan jsonb:='[]'::jsonb;
  v_op jsonb;
  v_queries jsonb;
  v_bundle text;
  v_component_count int;
  v_connector_count int:=0;
  v_component_total int:=0;
  v_bundled_ops int:=0;
  v_policy jsonb;
begin
  if p_checkpoint_queries_max is null or p_checkpoint_queries_max<1 then
    return p_packet;
  end if;

  for v_op in select value from jsonb_array_elements(v_plan)
  loop
    if coalesce(v_op->>'operation','')='READ' then
      v_queries:=coalesce(v_op->'queries','[]'::jsonb);
      v_component_count:=jsonb_array_length(v_queries);
      v_component_total:=v_component_total+v_component_count;

      if p_checkpoint_queries_max=1 and v_component_count>1 then
        v_bundle:=programacion.fn_engineering_read_bundle_sql_v1(v_queries);
        v_op:=v_op||jsonb_build_object(
          'component_queries',v_queries,
          'component_query_count',v_component_count,
          'queries',jsonb_build_array(v_bundle),
          'connector_query_count',1,
          'read_bundle_contract','ENGINEERING_READ_BUNDLE_V1',
          'query_budget_applied',true,
          'executor_contract',
            coalesce(v_op->'executor_contract','{}'::jsonb)
            ||jsonb_build_object(
              'query_mode','ONE_STATEMENT_PER_CALL',
              'result_contract','ENGINEERING_READ_BUNDLE_V1',
              'component_query_count',v_component_count,
              'connector_query_count',1
            )
        );
        v_connector_count:=v_connector_count+1;
        v_bundled_ops:=v_bundled_ops+1;
      else
        v_op:=v_op||jsonb_build_object(
          'component_query_count',v_component_count,
          'connector_query_count',v_component_count,
          'query_budget_applied',true
        );
        v_connector_count:=v_connector_count+v_component_count;
      end if;
    end if;

    v_new_plan:=v_new_plan||jsonb_build_array(v_op);
  end loop;

  v_policy:=coalesce(p_packet->'query_execution_policy','{}'::jsonb)
    ||jsonb_build_object(
      'mode','ONE_STATEMENT_PER_CALL',
      'statement_count',v_connector_count,
      'connector_statement_count',v_connector_count,
      'component_statement_count',v_component_total,
      'checkpoint_queries_max',p_checkpoint_queries_max,
      'bundle_when_budget_one',true
    );

  return jsonb_set(
    p_packet||jsonb_build_object(
      'query_execution_policy',v_policy,
      'query_budget_contract',jsonb_build_object(
        'checkpoint_queries_max',p_checkpoint_queries_max,
        'component_query_count',v_component_total,
        'connector_query_count',v_connector_count,
        'bundled_read_operations',v_bundled_ops,
        'enforcement','COMPILED_AT_PACKET_BOUNDARY'
      )
    ),
    '{connector_plan}',
    v_new_plan,
    true
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_read_bundle_sql_v1(p_queries jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare
  v_q text;
  v_i int:=0;
  v_n int;
  v_items text:='';
  v_inner text;
begin
  if jsonb_typeof(coalesce(p_queries,'[]'::jsonb))<>'array' then
    raise exception 'QUERIES_MUST_BE_ARRAY';
  end if;

  v_n:=jsonb_array_length(coalesce(p_queries,'[]'::jsonb));
  if v_n=0 then return null; end if;

  for v_q in select value from jsonb_array_elements_text(p_queries)
  loop
    v_i:=v_i+1;
    v_q:=regexp_replace(coalesce(v_q,''),'^[[:space:]]+','','');

    if position(';' in v_q)>0 then
      raise exception 'READ_BUNDLE_SEMICOLON_FORBIDDEN:%',v_i;
    end if;

    if v_n=1 and v_q ~* '^(select|with)[[:space:]]' then
      return v_q;
    end if;

    if v_items<>'' then v_items:=v_items||','; end if;

    if v_q ~* '^explain[[:space:]]*[(][[:space:]]*format[[:space:]]+json[[:space:]]*[)][[:space:]]+' then
      v_inner:=regexp_replace(
        v_q,
        '^explain[[:space:]]*[(][[:space:]]*format[[:space:]]+json[[:space:]]*[)][[:space:]]+',
        '',
        'i'
      );
      v_items:=v_items||
        format(
          'jsonb_build_object(''query_no'',%s,''rows'',jsonb_build_array(jsonb_build_object(''QUERY PLAN'',programacion.fn_engineering_explain_json_v1(%L))))',
          v_i,v_inner
        );
    elsif v_q ~* '^(select|with)[[:space:]]' then
      v_items:=v_items||
        format(
          'jsonb_build_object(''query_no'',%s,''rows'',coalesce((select jsonb_agg(to_jsonb(q%s)) from (%s) q%s),''[]''::jsonb))',
          v_i,v_i,v_q,v_i
        );
    else
      raise exception 'READ_BUNDLE_NON_READ_QUERY:%',v_i;
    end if;
  end loop;

  return format(
    'select jsonb_build_object(''schema_version'',''ENGINEERING_READ_BUNDLE_V1'',''component_query_count'',%s,''results'',jsonb_build_array(%s)) as read_bundle',
    v_n,v_items
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_source_pack_currentness_from_context_v1(p_unit_metadata jsonb, p_checkpoint_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_meta jsonb:=p_unit_metadata;
  v_source jsonb;
  v_cap_conflicts jsonb;
  v_contract_conflicts jsonb;
  v_conflicts jsonb;
begin
  if v_meta is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_SOURCE_PACK_CURRENTNESS_V1',
      'status','UNIT_NOT_FOUND'
    );
  end if;

  v_source:=coalesce(
    v_meta#>array['source_pack_v2','checkpoint_inputs',p_checkpoint_code],
    v_meta#>array['source_pack_v1','checkpoint_inputs',p_checkpoint_code]
  );

  if v_source is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_SOURCE_PACK_CURRENTNESS_V1',
      'status','MISSING',
      'checkpoint_code',p_checkpoint_code,
      'conflicts','[]'::jsonb,
      'context_reused',true
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'authority_kind','CAPABILITY',
        'missing_text',m.txt,
        'capability_code',r.capability_code,
        'registry_status',r.status,
        'current_version',c.version,
        'release_state',vr.release_state,
        'manifest_sha256',vr.manifest_sha256
      )
      order by r.capability_code,m.txt
    ),
    '[]'::jsonb
  )
  into v_cap_conflicts
  from jsonb_array_elements_text(coalesce(v_source->'missing','[]'::jsonb)) m(txt)
  join public.lf_capability_registry r
    on (
      lower(m.txt) like '%'||lower(r.capability_code)||'%'
      or lower(m.txt) like '%'||lower(replace(r.capability_code,'_',' '))||'%'
    )
  join public.lf_capability_current c using(capability_code)
  join public.lf_capability_version_registry vr
    on vr.capability_code=c.capability_code
   and vr.version=c.version
  where r.status='ACTIVE'
    and vr.release_state='RELEASED'
    and lower(m.txt) not like 'unidad %'
    and lower(m.txt) not like 'dependencia %'
    and (
      lower(m.txt) like '%no está en lf_capability_registry%'
      or lower(m.txt) like '%no estan en lf_capability_registry%'
      or lower(m.txt) like '%no están en lf_capability_registry%'
      or lower(m.txt) like '%no en lf_capability_current%'
      or lower(m.txt) like '%sin versión promovida%'
      or lower(m.txt) like '%solo lf_activos%'
      or lower(m.txt) like 'capacidad %inexistente%'
      or lower(m.txt) like 'capability_ref %no está en lf_capability_registry/current%'
    );

  with aliases as (
    select a.key alias_name,a.value authority
    from jsonb_each(
      coalesce(
        v_meta#>'{plan_inherited_execution_policies_v1,CANONICAL_CONTRACT_AUTHORITIES_V1}',
        '{}'::jsonb
      )
    ) a
  ), candidates as (
    select m.txt,a.alias_name,a.authority,
           public.fn_lf_version_compatibility_current_version_id_v1(
             coalesce(a.authority->>'source_kind','PROGRAMACION_CONTRACT'),
             a.authority->>'source_code',
             null
           ) current_version_id
    from jsonb_array_elements_text(coalesce(v_source->'missing','[]'::jsonb)) m(txt)
    join aliases a
      on lower(m.txt) like '%'||lower(a.alias_name)||'%'
      or lower(m.txt) like '%'||lower(coalesce(a.authority->>'source_code',''))||'%'
  )
  select coalesce(
    jsonb_agg(jsonb_build_object(
      'authority_kind','PROGRAMACION_CONTRACT',
      'missing_text',c.txt,
      'alias',c.alias_name,
      'contract_code',c.authority->>'source_code',
      'current_version_id',c.current_version_id,
      'contract_id',ct.id,
      'contract_state',ct.estado,
      'registry_sha256',ct.especificacion->>'registry_sha256'
    ) order by c.alias_name,c.txt),
    '[]'::jsonb
  )
  into v_contract_conflicts
  from candidates c
  join programacion.contratos ct
    on ct.contrato_codigo=c.authority->>'source_code'
   and ct.version_id=c.current_version_id
  where c.current_version_id is not null;

  v_conflicts:=coalesce(v_cap_conflicts,'[]'::jsonb)
               ||coalesce(v_contract_conflicts,'[]'::jsonb);

  return jsonb_build_object(
    'schema_version','ENGINEERING_SOURCE_PACK_CURRENTNESS_V1',
    'status',case
      when jsonb_array_length(v_conflicts)>0 then 'STALE'
      else 'CURRENT'
    end,
    'checkpoint_code',p_checkpoint_code,
    'source_version',case
      when v_meta#>array['source_pack_v2','checkpoint_inputs',p_checkpoint_code] is not null then 'V2'
      else 'V1'
    end,
    'missing_count',jsonb_array_length(coalesce(v_source->'missing','[]'::jsonb)),
    'missing_typed_count',jsonb_array_length(coalesce(v_source->'missing_typed','[]'::jsonb)),
    'conflicts',v_conflicts,
    'context_reused',true,
    'live_authority_check',true
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_source_pack_currentness_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_meta jsonb;
begin
  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  return programacion.fn_engineering_source_pack_currentness_from_context_v1(
    v_meta,p_checkpoint_code
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_unit_bootstrap_snapshot_v2(p_plan_code text, p_unit_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_payload jsonb;
  v_context jsonb;
  v_action_spec jsonb;
  v_packet jsonb;
  v_cp jsonb;
  v_cp_code text;
  v_cp_title text;
  v_budget int;
  v_subjects jsonb:='[]'::jsonb;
  v_dep_refs jsonb:='[]'::jsonb;
begin
  v_payload:=programacion.fn_engineering_unit_bootstrap_snapshot_v1(
    p_plan_code,p_unit_code
  );

  if not coalesce((v_payload->>'snapshot_fast_path_supported')::boolean,false) then
    return v_payload;
  end if;

  v_context:=v_payload->'context_snapshot';
  v_cp:=v_payload->'current_checkpoint';
  v_cp_code:=v_cp->>'checkpoint_code';
  v_cp_title:=coalesce(v_cp->>'checkpoint_title','');

  v_budget:=nullif(
    coalesce(
      v_context#>>'{unit_metadata,source_fast_path_v2,read_budget,checkpoint_queries_max}',
      v_context#>>'{unit_metadata,source_fast_path_v1,preferred_queries_max}'
    ),''
  )::int;

  v_dep_refs:=coalesce(
    v_context#>'{unit_metadata,dependency_snapshot_v1,refs}',
    '[]'::jsonb
  );

  select coalesce(jsonb_agg(to_jsonb(x.ref) order by x.ref),'[]'::jsonb)
  into v_subjects
  from jsonb_array_elements_text(v_dep_refs) x(ref)
  where position(lower(x.ref) in lower(v_cp_title))>0;

  v_action_spec:=coalesce(v_payload->'action_spec','{}'::jsonb)
    ||jsonb_build_object(
      'read_budget',jsonb_build_object(
        'checkpoint_queries_max',v_budget,
        'enforcement','COMPILED_AT_PACKET_BOUNDARY'
      ),
      'resolved_context',jsonb_build_object(
        'identity_source','BOOTSTRAP_CONTEXT_SNAPSHOT',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'work_code',v_context#>>'{identity,work_code}',
        'checkpoint_code',v_cp_code,
        'dependency_refs',v_dep_refs,
        'semantic_subjects',v_subjects
      ),
      'target',
        coalesce(v_payload#>'{action_spec,target}','{}'::jsonb)
        ||jsonb_build_object(
          'declared_dependency_refs',v_dep_refs,
          'semantic_subjects',v_subjects
        )
    );

  v_packet:=programacion.fn_engineering_packet_apply_read_budget_v1(
    coalesce(v_payload->'execution_packet','{}'::jsonb),
    v_budget
  );

  return v_payload||jsonb_build_object(
    'schema_version','ENGINEERING_UNIT_BOOTSTRAP_V3',
    'engine_variant','SNAPSHOT_FAST_PATH_V2',
    'action_spec',v_action_spec,
    'execution_packet',v_packet,
    'resolved_context_contract',jsonb_build_object(
      'identity_resolution','ONCE_AT_BOOTSTRAP',
      'reuse_downstream',true,
      'fresh_reads_preserved_for',jsonb_build_array('CAPABILITY_CURRENTNESS','CONTRACT_CURRENTNESS','POST_MUTATION_TRANSITION')
    )
  );
end;
$function$


CREATE OR REPLACE FUNCTION programacion.fn_engineering_unit_bootstrap_v3(p_plan_code text, p_unit_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_fast jsonb;
  v_payload jsonb;
  v_cp text;
  v_readiness jsonb;
  v_terminal text;
  v_continuation jsonb;
  v_execution_contract jsonb;
  v_packet jsonb;
begin
  v_fast:=programacion.fn_engineering_unit_bootstrap_snapshot_v2(
    p_plan_code,p_unit_code
  );

  if coalesce((v_fast->>'snapshot_fast_path_supported')::boolean,false) then
    v_payload:=v_fast;
  else
    v_payload:=programacion.fn_engineering_unit_bootstrap_v3_legacy(
      p_plan_code,p_unit_code
    ) || jsonb_build_object(
      'engine_variant','LEGACY_FALLBACK_V3',
      'snapshot_fast_path_supported',false
    );
  end if;

  v_cp:=v_payload#>>'{current_checkpoint,checkpoint_code}';

  if v_cp is not null
     and v_payload->'action_spec' is not null
     and (
       coalesce(jsonb_typeof(v_payload#>'{execution_packet,error_contracts}'),'')<>'object'
       or coalesce(jsonb_typeof(v_payload#>'{execution_packet,anomaly_observation_contract}'),'')<>'object'
       or (
         coalesce((v_payload#>>'{action_spec,requires_material_execution}')::boolean,false)
         and coalesce(jsonb_typeof(v_payload#>'{execution_packet,heartbeat_contract}'),'')<>'object'
       )
     ) then
    v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
      p_plan_code,
      p_unit_code,
      v_cp,
      v_payload->'action_spec',
      coalesce(
        v_payload#>'{execution_packet,execution_input}',
        v_payload->'execution_input',
        '{}'::jsonb
      )
    );

    v_payload:=jsonb_set(
      v_payload,
      '{execution_packet}',
      v_packet,
      true
    );
  end if;

  if v_cp is not null then
    if v_payload#>'{context_snapshot,unit_metadata}' is not null then
      v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(
        v_cp,
        coalesce(v_payload->'action_spec','{}'::jsonb),
        coalesce(v_payload->'execution_packet','{}'::jsonb),
        v_payload#>'{context_snapshot,unit_metadata}'
      );
    else
      v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(
        p_plan_code,
        p_unit_code,
        v_cp,
        coalesce(v_payload->'action_spec','{}'::jsonb),
        coalesce(v_payload->'execution_packet','{}'::jsonb)
      );
    end if;

    v_payload:=v_payload||jsonb_build_object(
      'execution_readiness',v_readiness
    );

    if coalesce(v_payload->>'terminal_action','')='CONTINUE_CURRENT_CHECKPOINT'
       and coalesce((v_readiness->>'execution_ready')::boolean,false)=false then
      v_payload:=v_payload
        || jsonb_build_object(
          'terminal_action','STOP_EXECUTION_PREFLIGHT',
          'execution_allowed',false,
          'preflight_block',jsonb_build_object(
            'status','NOT_READY',
            'checkpoint_code',v_cp,
            'reasons',v_readiness->'reasons',
            'gates',v_readiness->'gates',
            'next_action','FIX_PREFLIGHT_CONTRACT_BEFORE_CONNECTOR_EXECUTION'
          )
        );
    end if;
  end if;

  v_terminal:=coalesce(v_payload->>'terminal_action','');
  v_continuation:=jsonb_build_object(
    'terminal_scope',case
      when v_terminal='CONTINUE_CURRENT_CHECKPOINT' then 'CURRENT_UNIT'
      else 'CURRENT_UNIT_ONLY'
    end,
    'global_stop',false,
    'orchestrator_action',case
      when v_terminal='CONTINUE_CURRENT_CHECKPOINT' then 'EXECUTE_CURRENT_UNIT'
      else 'YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK'
    end,
    'selection_owner','ENGINEERING_SCHEDULER',
    'rule','NON_CONTINUE_TERMINAL_ACTION_STOPS_ONLY_CURRENT_UNIT; SCHEDULER MAY CONTINUE OTHER ELIGIBLE WORK'
  );

  v_execution_contract:=coalesce(v_payload->'execution_contract','{}'::jsonb)
    || jsonb_build_object(
      'terminal_action_scope','CURRENT_UNIT_ONLY_UNLESS_EXPLICIT_GLOBAL_STOP',
      'non_continue_terminal_behavior','YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK',
      'scheduler_continuation_owner','ENGINEERING_SCHEDULER',
      'global_stop_requires_explicit_flag',true
    );

  return v_payload || jsonb_build_object(
    'continuation_contract',v_continuation,
    'execution_contract',v_execution_contract
  );
end;
$function$


-- Canonical sanitation discovered by the generic preflight:
-- replace nonexistent jsonb_object_length(jsonb) with a valid key count.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{source_pack_v1,checkpoint_inputs,CLAUSE_LIST_ASIS,inputs,queries,0}',
  to_jsonb($q$select id,version_id,coalesce((select count(*) from jsonb_object_keys(especificacion)),0) clausulas
from programacion.contratos
where contrato_codigo='INPUT_READINESS_CONTRACT'
order by version_id desc
limit 1$q$::text),
  false
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M0.14'
  and unit_metadata#>>'{source_pack_v1,checkpoint_inputs,CLAUSE_LIST_ASIS,inputs,queries,0}'
      = $old$select id,version_id,coalesce(jsonb_object_length(especificacion),0) clausulas
from programacion.contratos
where contrato_codigo='INPUT_READINESS_CONTRACT'
order by version_id desc
limit 1$old$;
