-- ENGINEERING systemic repair handlers v1.
-- Generic deterministic repair for runtime error contracts + blocker resolvers.
-- No unit-specific handler branches. Unit/checkpoint facts remain data.

create or replace function programacion.fn_engineering_missing_typed_sanitize_v1(
  p_missing_typed jsonb
) returns jsonb
language sql
immutable
as $f$
select coalesce(
  jsonb_agg(
    case
      when upper(coalesce(x.value->>'kind',''))='DELIVERABLE'
        then x.value || jsonb_build_object(
          'blocking',false,
          'resolution_class','CHECKPOINT_OWNED_DELIVERABLE',
          'sanitized_by','ENGINEERING_SOURCE_GAP_RESOLVER_V1'
        )
      else x.value
    end
    order by x.ord
  ),
  '[]'::jsonb
)
from jsonb_array_elements(coalesce(p_missing_typed,'[]'::jsonb))
with ordinality x(value,ord);
$f$;

create or replace function programacion.fn_engineering_transition_repair_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_requested_status text,
  p_context jsonb default '{}'::jsonb,
  p_apply boolean default true
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  v_status text:=upper(nullif(btrim(coalesce(p_requested_status,'')),''));
  v_actor text:=coalesce(nullif(p_context->>'actor',''),'ENGINEERING_TRANSITION_REPAIR_V1');
  v_evidence text:=nullif(p_context->>'evidence_ref','');
  v_detail text:=nullif(p_context->>'detail','');
  v_result jsonb;
begin
  if v_status in ('DONE','NOT_APPLICABLE','IN_PROGRESS') then
    if v_status in ('DONE','NOT_APPLICABLE')
       and coalesce(v_evidence,v_detail) is null then
      return jsonb_build_object(
        'schema_version','ENGINEERING_TRANSITION_REPAIR_V1',
        'status','INPUT_REQUIRED_EVIDENCE',
        'requested_status',v_status,
        'state_changed',false
      );
    end if;

    if not p_apply then
      return jsonb_build_object(
        'schema_version','ENGINEERING_TRANSITION_REPAIR_V1',
        'status','DRY_RUN_READY',
        'requested_status',v_status,
        'state_changed',false
      );
    end if;

    v_result:=programacion.fn_engineering_checkpoint_transition_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,v_status,v_evidence,v_actor,v_detail
    );
    return jsonb_build_object(
      'schema_version','ENGINEERING_TRANSITION_REPAIR_V1',
      'status','REPAIRED',
      'mode','ALLOWED_TRANSITION',
      'requested_status',v_status,
      'result',v_result,
      'state_changed',true
    );
  end if;

  if v_status='BLOCKED' then
    if nullif(p_context->>'blocker_code','') is null
       or nullif(p_context->>'description','') is null
       or nullif(p_context->>'required_action','') is null
       or nullif(p_context->>'source_ref','') is null then
      return jsonb_build_object(
        'schema_version','ENGINEERING_TRANSITION_REPAIR_V1',
        'status','INPUT_REQUIRED_BLOCKER_FIELDS',
        'required',jsonb_build_array(
          'blocker_code','description','required_action','source_ref'
        ),
        'state_changed',false
      );
    end if;

    if not p_apply then
      return jsonb_build_object(
        'schema_version','ENGINEERING_TRANSITION_REPAIR_V1',
        'status','DRY_RUN_READY',
        'mode','BLOCKER_PROTOCOL',
        'state_changed',false
      );
    end if;

    perform programacion.fn_engineering_blocker_open_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,
      p_context->>'blocker_code',
      p_context->>'description',
      p_context->>'required_action',
      p_context->>'source_ref',
      v_actor
    );

    v_result:=programacion.fn_engineering_checkpoint_transition_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,'IN_PROGRESS',
      coalesce(v_evidence,p_context->>'source_ref'),
      v_actor,
      coalesce(v_detail,'Blocked through canonical blocker protocol')
    );

    return jsonb_build_object(
      'schema_version','ENGINEERING_TRANSITION_REPAIR_V1',
      'status','REPAIRED',
      'mode','BLOCKER_OPEN_THEN_IN_PROGRESS',
      'result',v_result,
      'state_changed',true
    );
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_TRANSITION_REPAIR_V1',
    'status','INPUT_REQUIRED_SUPPORTED_STATUS',
    'received',p_requested_status,
    'allowed',jsonb_build_array('DONE','NOT_APPLICABLE','IN_PROGRESS','BLOCKED'),
    'free_translation','FORBIDDEN',
    'state_changed',false
  );
end;
$f$;

create or replace function programacion.fn_engineering_heartbeat_normalize_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_phase text,
  p_step_code text default null,
  p_detail jsonb default '{}'::jsonb,
  p_evidence_ref text default null,
  p_actor text default 'ENGINEERING_HEARTBEAT_NORMALIZER_V1',
  p_apply boolean default true
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  v_phase text:=upper(nullif(btrim(coalesce(p_phase,'')),''));
  v_step text:=nullif(btrim(coalesce(p_step_code,'')),'');
  v_spec jsonb;
  v_valid boolean:=false;
  v_result jsonb;
begin
  if v_phase not in (
    'ACTION_STARTED','STEP_STARTED','STEP_DONE',
    'CONNECTOR_BLOCKED','RETRYING','ACTION_DONE','ACTION_FAILED'
  ) then
    return jsonb_build_object(
      'schema_version','ENGINEERING_HEARTBEAT_NORMALIZER_V1',
      'status','INPUT_REQUIRED_CANONICAL_PHASE',
      'received_phase',p_phase,
      'free_translation','FORBIDDEN',
      'state_changed',false
    );
  end if;

  if v_phase in ('ACTION_STARTED','ACTION_DONE','ACTION_FAILED') then
    v_step:=null;
  elsif v_phase in ('STEP_STARTED','STEP_DONE') then
    if v_step is null then
      return jsonb_build_object(
        'schema_version','ENGINEERING_HEARTBEAT_NORMALIZER_V1',
        'status','INPUT_REQUIRED_EXACT_STEP',
        'phase',v_phase,
        'state_changed',false
      );
    end if;
    v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
      p_plan_code,p_unit_code,p_checkpoint_code
    );
    select exists(
      select 1
      from jsonb_array_elements_text(coalesce(v_spec->'action_steps','[]'::jsonb)) s(step_code)
      where s.step_code=v_step
    ) into v_valid;
    if not v_valid then
      return jsonb_build_object(
        'schema_version','ENGINEERING_HEARTBEAT_NORMALIZER_V1',
        'status','INPUT_REQUIRED_EXACT_STEP',
        'phase',v_phase,
        'received_step',v_step,
        'allowed_steps',coalesce(v_spec->'action_steps','[]'::jsonb),
        'connector_seq_as_step','FORBIDDEN',
        'connector_operation_as_step','FORBIDDEN',
        'state_changed',false
      );
    end if;
  elsif v_step is not null then
    v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
      p_plan_code,p_unit_code,p_checkpoint_code
    );
    select exists(
      select 1
      from jsonb_array_elements_text(coalesce(v_spec->'action_steps','[]'::jsonb)) s(step_code)
      where s.step_code=v_step
    ) into v_valid;
    if not v_valid then
      v_step:=null;
    end if;
  end if;

  if not p_apply then
    return jsonb_build_object(
      'schema_version','ENGINEERING_HEARTBEAT_NORMALIZER_V1',
      'status','DRY_RUN_READY',
      'phase',v_phase,
      'step_code',v_step,
      'state_changed',false
    );
  end if;

  v_result:=programacion.fn_engineering_checkpoint_heartbeat_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_phase,v_step,p_actor,
    coalesce(p_detail,'{}'::jsonb),p_evidence_ref
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_HEARTBEAT_NORMALIZER_V1',
    'status','REPAIRED',
    'phase',v_phase,
    'step_code',v_step,
    'result',v_result,
    'state_changed',true
  );
end;
$f$;

create or replace function programacion.fn_engineering_source_gap_resolve_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_apply boolean default true
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  v_meta jsonb;
  v_input jsonb;
  v_missing_before jsonb;
  v_missing_after jsonb;
  v_result jsonb;
  v_current jsonb;
begin
  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  if v_meta is null then
    return jsonb_build_object('schema_version','ENGINEERING_SOURCE_GAP_RESOLVER_V1','status','UNIT_NOT_FOUND','state_changed',false);
  end if;

  v_input:=coalesce(
    v_meta#>array['source_pack_v2','checkpoint_inputs',p_checkpoint_code],
    v_meta#>array['source_pack_v1','checkpoint_inputs',p_checkpoint_code]
  );

  if coalesce(jsonb_typeof(v_input),'')<>'object' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_SOURCE_GAP_RESOLVER_V1',
      'status','INPUT_REQUIRED_CANONICAL_CHECKPOINT_INPUT',
      'inference','FORBIDDEN',
      'state_changed',false
    );
  end if;

  v_missing_before:=coalesce(v_input->'missing_typed','[]'::jsonb);
  v_missing_after:=programacion.fn_engineering_missing_typed_sanitize_v1(v_missing_before);

  if v_missing_after=v_missing_before
     and v_meta#>array['source_pack_v2','checkpoint_inputs',p_checkpoint_code] is not null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_SOURCE_GAP_RESOLVER_V1',
      'status','ALREADY_SANITIZED',
      'missing_typed',v_missing_after,
      'state_changed',false
    );
  end if;

  if not p_apply then
    return jsonb_build_object(
      'schema_version','ENGINEERING_SOURCE_GAP_RESOLVER_V1',
      'status','DRY_RUN_READY',
      'missing_typed_before',v_missing_before,
      'missing_typed_after',v_missing_after,
      'state_changed',false
    );
  end if;

  v_result:=programacion.fn_engineering_checkpoint_input_upsert_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,
    coalesce(v_input#>'{inputs,queries}','[]'::jsonb),
    coalesce(v_input#>'{inputs,db_objects}','[]'::jsonb),
    coalesce(v_input#>'{inputs,assets}','[]'::jsonb),
    coalesce(v_input#>'{inputs,events}','[]'::jsonb),
    coalesce(v_input#>'{inputs,artifacts}','[]'::jsonb),
    coalesce(v_input->'missing','[]'::jsonb),
    v_missing_after,
    coalesce(v_input->'resolved_authorities','{}'::jsonb)
  );

  v_current:=programacion.fn_engineering_source_pack_currentness_v1(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_SOURCE_GAP_RESOLVER_V1',
    'status','REPAIRED',
    'input_upsert',v_result,
    'currentness',v_current,
    'missing_typed_before',v_missing_before,
    'missing_typed_after',v_missing_after,
    'state_changed',true
  );
end;
$f$;

create or replace function programacion.fn_engineering_source_pack_materialize_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_apply boolean default true
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  v_result jsonb;
  v_after jsonb;
begin
  v_result:=programacion.fn_engineering_source_gap_resolve_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,p_apply
  );
  if coalesce(v_result->>'status','') in ('UNIT_NOT_FOUND','INPUT_REQUIRED_CANONICAL_CHECKPOINT_INPUT') then
    return v_result || jsonb_build_object(
      'schema_version','ENGINEERING_SOURCE_PACK_MATERIALIZER_V1',
      'canonical_input_only',true
    );
  end if;

  if p_apply then
    v_after:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_SOURCE_PACK_MATERIALIZER_V1',
    'status',case
      when not p_apply then 'DRY_RUN_READY'
      when coalesce(v_after#>>'{execution_readiness,source_currentness,status}','')='CURRENT' then 'REPAIRED'
      else 'MATERIALIZED_RECHECK_REQUIRED'
    end,
    'source_gap_result',v_result,
    'post_source_currentness',case when p_apply then v_after#>'{execution_readiness,source_currentness}' else null end,
    'state_changed',coalesce((v_result->>'state_changed')::boolean,false)
  );
end;
$f$;

create or replace function programacion.fn_engineering_routing_handler_resolve_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_apply boolean default true
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  v_meta jsonb;
  v_tx jsonb;
  v_routes jsonb;
  v_route jsonb;
  v_item jsonb;
  v_new_caps jsonb:='[]'::jsonb;
  v_descriptor jsonb;
  v_handler text;
  v_after jsonb;
begin
  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED'
  for update;

  if v_meta is null then
    return jsonb_build_object('schema_version','ENGINEERING_ROUTING_HANDLER_RESOLVER_V1','status','UNIT_NOT_FOUND','state_changed',false);
  end if;

  v_tx:=v_meta#>array['transversal_execution_v1',p_checkpoint_code];
  if v_tx is null then
    return jsonb_build_object('schema_version','ENGINEERING_ROUTING_HANDLER_RESOLVER_V1','status','NOT_TRANSVERSAL','state_changed',false);
  end if;

  v_routes:=programacion.fn_engineering_checkpoint_routing_resolution_v1(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if v_routes->>'status'='READY' then
    return jsonb_build_object('schema_version','ENGINEERING_ROUTING_HANDLER_RESOLVER_V1','status','ALREADY_READY','routing',v_routes,'state_changed',false);
  end if;

  for v_item in
    select value from jsonb_array_elements(coalesce(v_tx->'capabilities','[]'::jsonb))
  loop
    v_descriptor:=programacion.fn_engineering_capability_execution_descriptor_v1(v_item->>'capability_code');

    if v_descriptor->>'status'<>'RESOLVED'
       or coalesce(v_descriptor->>'release_state','')<>'RELEASED' then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ROUTING_HANDLER_RESOLVER_V1',
        'status','INPUT_REQUIRED_CURRENT_RELEASED_CAPABILITY',
        'capability_code',v_item->>'capability_code',
        'descriptor',v_descriptor,
        'state_changed',false
      );
    end if;

    v_handler:=case v_descriptor->>'handler_class'
      when 'REPOSITORY_EXECUTOR' then 'REPOSITORY_CAPABILITY_EXECUTOR'
      when 'REPOSITORY_COMPARATOR' then 'REPOSITORY_COMPARATOR_EXECUTOR'
      when 'SUPABASE_NATIVE_FUNCTION' then 'SUPABASE_NATIVE_FUNCTION_EXECUTOR'
      when 'SUPABASE_READ_ONLY_MEASURE' then 'SUPABASE_READ_ONLY_MEASURE'
      when 'SUPABASE_POLICY_READBACK' then 'CAPABILITY_CURRENT_READBACK'
      when 'GOVERNANCE_CONTRACT_READBACK' then 'CAPABILITY_CURRENT_READBACK'
      else null
    end;

    if v_handler is null then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ROUTING_HANDLER_RESOLVER_V1',
        'status','INPUT_REQUIRED_HANDLER_CLASS',
        'capability_code',v_item->>'capability_code',
        'handler_class',v_descriptor->>'handler_class',
        'state_changed',false
      );
    end if;

    v_new_caps:=v_new_caps||jsonb_build_array(
      v_item || jsonb_build_object(
        'handler',v_handler,
        'handler_resolved_by','ENGINEERING_ROUTING_HANDLER_RESOLVER_V1'
      )
    );
  end loop;

  v_tx:=jsonb_set(v_tx,'{capabilities}',v_new_caps,true);
  v_tx:=jsonb_set(v_tx,'{activation}','"ACTIVE"'::jsonb,true);

  if not p_apply then
    return jsonb_build_object(
      'schema_version','ENGINEERING_ROUTING_HANDLER_RESOLVER_V1',
      'status','DRY_RUN_READY',
      'resolved_transversal_execution',v_tx,
      'state_changed',false
    );
  end if;

  update programacion.engineering_plan_units pu
     set unit_metadata=jsonb_set(
       coalesce(pu.unit_metadata,'{}'::jsonb),
       '{transversal_execution_v1}',
       coalesce(pu.unit_metadata->'transversal_execution_v1','{}'::jsonb)
         || jsonb_build_object(p_checkpoint_code,v_tx),
       true
     )
   where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  v_after:=programacion.fn_engineering_checkpoint_routing_resolution_v1(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if v_after->>'status'<>'READY' then
    raise exception 'ENGINEERING_ROUTING_HANDLER_POSTCHECK_FAILED:%/%/%:%',
      p_plan_code,p_unit_code,p_checkpoint_code,v_after;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_ROUTING_HANDLER_RESOLVER_V1',
    'status','REPAIRED',
    'routing',v_after,
    'state_changed',true
  );
end;
$f$;

create or replace function programacion.fn_engineering_upstream_evidence_resolve_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_apply boolean default true
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  v_before jsonb;
  v_after jsonb;
  v_status text;
begin
  v_before:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  v_status:=coalesce(v_before->>'status','');

  if v_status='READY' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_UPSTREAM_EVIDENCE_RESOLVER_V1',
      'status','RESOLVED',
      'action_spec_status','READY',
      'state_changed',false
    );
  end if;

  if v_status not in (
    'BLOCK_CAPABILITY_CUTOVER_NOT_REGISTERED',
    'BLOCK_UPSTREAM_BUNDLE_PENDING',
    'BLOCK_UPSTREAM_CAPABILITY_CUTOVER_PENDING',
    'BLOCK_UPSTREAM_OWNER_BINDING_PENDING',
    'BLOCK_UPSTREAM_RECEIPT_PENDING'
  ) then
    return jsonb_build_object(
      'schema_version','ENGINEERING_UPSTREAM_EVIDENCE_RESOLVER_V1',
      'status','NOT_APPLICABLE',
      'action_spec_status',v_status,
      'state_changed',false
    );
  end if;

  -- Fresh canonical re-evaluation is the rebind. No local substitute is authored.
  v_after:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_UPSTREAM_EVIDENCE_RESOLVER_V1',
    'status',case when v_after->>'status'='READY' then 'RESOLVED' else 'WAIT_UPSTREAM' end,
    'blocker_before',v_status,
    'action_spec_status_after',v_after->>'status',
    'rebind_rule','FRESH_CANONICAL_AUTHORITY_ONLY',
    'local_substitute','FORBIDDEN',
    'state_changed',false
  );
end;
$f$;

create or replace function programacion.fn_engineering_independence_receipt_resolve_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_apply boolean default true
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  v_meta jsonb;
  v_spec jsonb;
  v_req jsonb;
  v_ctx jsonb;
  v_measure jsonb;
  v_candidate jsonb;
  v_packet jsonb;
  v_readiness jsonb;
  v_after jsonb;
begin
  select pu.unit_metadata into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if coalesce(v_spec->>'status','')<>'BLOCK_INDEPENDENCE_RECEIPT_REQUIRED' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_INDEPENDENCE_RECEIPT_RESOLVER_V1',
      'status',case when v_spec->>'status'='READY' then 'RESOLVED' else 'NOT_APPLICABLE' end,
      'action_spec_status',v_spec->>'status',
      'state_changed',false
    );
  end if;

  v_req:=coalesce(v_spec->'required_evidence_contract','{}'::jsonb);
  v_ctx:=coalesce(
    v_meta#>array['runtime_repair_inputs_v1',p_checkpoint_code,'independence_context'],
    v_req->'execution_context',
    '{}'::jsonb
  );

  v_measure:=public.lf_independent_assurance_measure_v1(
    coalesce(nullif(v_req->>'dependency_schema',''),'programacion'),
    v_req->>'producer_root',
    v_req->>'reviewer_root',
    coalesce((nullif(v_req->>'max_depth',''))::int,8),
    v_ctx
  );

  if coalesce(v_measure->>'state','')<>'INDEPENDENT'
     or coalesce(v_measure#>>'{dependency_dimension,state}','')<>'INDEPENDENT'
     or coalesce(v_measure#>>'{data_dimension,state}','')<>'INDEPENDENT'
     or coalesce(v_measure#>>'{author_dimension,state}','')<>'INDEPENDENT' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_INDEPENDENCE_RECEIPT_RESOLVER_V1',
      'status','EVIDENCE_REQUIRED',
      'measure',v_measure,
      'required_state','INDEPENDENT',
      'required_dimensions',jsonb_build_array('DEPENDENCIES','DATA','AUTHOR'),
      'state_changed',false
    );
  end if;

  v_candidate:=v_spec || jsonb_build_object(
    'status','READY',
    'precision','INDEPENDENCE_RECEIPT_BOUND_V1',
    'contract_family','INDEPENDENCE_RECEIPT_READBACK',
    'independence_receipt',v_measure,
    'handler_requirement',null,
    'blocking_codes','[]'::jsonb
  );

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_candidate,
    coalesce(programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code)->'execution_input','{}'::jsonb)
  );
  v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_candidate,v_packet
  );

  if v_packet->>'status'<>'READY'
     or not coalesce((v_readiness#>>'{gates,COMPILE_READY}')::boolean,false) then
    return jsonb_build_object(
      'schema_version','ENGINEERING_INDEPENDENCE_RECEIPT_RESOLVER_V1',
      'status','PATCH_REJECTED',
      'measure',v_measure,
      'packet_status',v_packet->>'status',
      'readiness',v_readiness,
      'state_changed',false
    );
  end if;

  if not p_apply then
    return jsonb_build_object(
      'schema_version','ENGINEERING_INDEPENDENCE_RECEIPT_RESOLVER_V1',
      'status','DRY_RUN_READY',
      'measure',v_measure,
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
   where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  v_after:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);

  if v_after#>>'{action_spec,status}'<>'READY' then
    raise exception 'ENGINEERING_INDEPENDENCE_RECEIPT_POSTCHECK_FAILED:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_INDEPENDENCE_RECEIPT_RESOLVER_V1',
    'status','REPAIRED',
    'measure',v_measure,
    'post_action_spec_status',v_after#>>'{action_spec,status}',
    'state_changed',true
  );
end;
$f$;

-- Preserve the existing 13-class dispatcher as an internal core exactly once.
do $rename$
begin
  if to_regprocedure('programacion.fn_engineering_checkpoint_repair_dispatch_v2_core(text,text,text,text,boolean)') is null then
    if to_regprocedure('programacion.fn_engineering_checkpoint_repair_dispatch_v2(text,text,text,text,boolean)') is null then
      raise exception 'ENGINEERING_REPAIR_DISPATCH_V2_MISSING';
    end if;
    alter function programacion.fn_engineering_checkpoint_repair_dispatch_v2(text,text,text,text,boolean)
      rename to fn_engineering_checkpoint_repair_dispatch_v2_core;
  end if;
end;
$rename$;

create or replace function programacion.fn_engineering_checkpoint_repair_dispatch_v2(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_error_code text default null,
  p_apply boolean default true
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $f$
declare
  v_boot jsonb;
  v_spec jsonb;
  v_status text;
  v_meta jsonb;
  v_runtime jsonb;
  v_error text:=nullif(btrim(coalesce(p_error_code,'')),'');
  v_result jsonb;
begin
  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);

  if v_boot#>>'{current_checkpoint,checkpoint_code}' is distinct from p_checkpoint_code then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2_1',
      'status','NOT_CURRENT',
      'current_checkpoint',v_boot#>>'{current_checkpoint,checkpoint_code}',
      'supported_error_classes',20,
      'state_changed',false
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
    return v_result || jsonb_build_object(
      'repair_family','INDEPENDENCE_RECEIPT',
      'supported_error_classes',20
    );
  end if;

  if v_status in (
    'BLOCK_CAPABILITY_CUTOVER_NOT_REGISTERED',
    'BLOCK_UPSTREAM_BUNDLE_PENDING',
    'BLOCK_UPSTREAM_CAPABILITY_CUTOVER_PENDING',
    'BLOCK_UPSTREAM_OWNER_BINDING_PENDING',
    'BLOCK_UPSTREAM_RECEIPT_PENDING'
  ) then
    v_result:=programacion.fn_engineering_upstream_evidence_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    return v_result || jsonb_build_object(
      'repair_family','UPSTREAM_EVIDENCE',
      'supported_error_classes',20
    );
  end if;

  if exists(
    select 1
    from jsonb_array_elements(coalesce(v_spec->'source_pack_missing_typed','[]'::jsonb)) m(value)
    where coalesce((m.value->>'blocking')::boolean,false)
  ) then
    v_result:=programacion.fn_engineering_source_gap_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    if coalesce(v_result->>'status','') not in ('ALREADY_SANITIZED','NOT_APPLICABLE') then
      return v_result || jsonb_build_object(
        'repair_family','SOURCE_GAP',
        'supported_error_classes',20
      );
    end if;
  end if;

  if v_error='CHECKPOINT_TRANSITION_STATUS_UNSUPPORTED' then
    v_result:=programacion.fn_engineering_transition_repair_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,
      v_runtime#>>'{transition_request,requested_status}',
      coalesce(v_runtime->'transition_request','{}'::jsonb),
      p_apply
    );
    return v_result || jsonb_build_object(
      'repair_family','TRANSITION_NORMALIZATION',
      'detected_error',v_error,
      'supported_error_classes',20
    );
  end if;

  if v_error in ('HEARTBEAT_PHASE_UNSUPPORTED','HEARTBEAT_STEP_UNDECLARED') then
    v_result:=programacion.fn_engineering_heartbeat_normalize_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,
      v_runtime#>>'{heartbeat,phase}',
      v_runtime#>>'{heartbeat,step_code}',
      coalesce(v_runtime#>'{heartbeat,detail}','{}'::jsonb),
      v_runtime#>>'{heartbeat,evidence_ref}',
      coalesce(nullif(v_runtime#>>'{heartbeat,actor}',''),'ENGINEERING_REPAIR_DISPATCH_V2'),
      p_apply
    );
    return v_result || jsonb_build_object(
      'repair_family','HEARTBEAT_NORMALIZATION',
      'detected_error',v_error,
      'supported_error_classes',20
    );
  end if;

  if v_error='SOURCE_PACK_MISSING' then
    v_result:=programacion.fn_engineering_source_pack_materialize_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    return v_result || jsonb_build_object(
      'repair_family','SOURCE_PACK_MATERIALIZATION',
      'detected_error',v_error,
      'supported_error_classes',20
    );
  end if;

  if v_error='ROUTING_HANDLER_PENDING' then
    v_result:=programacion.fn_engineering_routing_handler_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_apply
    );
    return v_result || jsonb_build_object(
      'repair_family','ROUTING_HANDLER',
      'detected_error',v_error,
      'supported_error_classes',20
    );
  end if;

  v_result:=programacion.fn_engineering_checkpoint_repair_dispatch_v2_core(
    p_plan_code,p_unit_code,p_checkpoint_code,p_error_code,p_apply
  );

  return v_result || jsonb_build_object(
    'schema_version','ENGINEERING_CHECKPOINT_REPAIR_DISPATCH_V2_1',
    'supported_error_classes',20
  );
end;
$f$;

comment on function programacion.fn_engineering_checkpoint_repair_dispatch_v2(text,text,text,text,boolean)
is 'Single public repair router. 20 deterministic classes: existing 13 core classes + transition normalization, heartbeat normalization, source-pack materialization, routing handler resolution, upstream evidence, source gap and independence receipt. Owner decisions remain fail-closed human authority.';

-- Error contracts now expose executable repair handlers rather than textual next_action only.
create or replace function programacion.fn_engineering_error_contract_v1(p_error_code text)
returns jsonb
language sql
stable
as $f$
select case p_error_code
  when 'CHECKPOINT_TRANSITION_STATUS_UNSUPPORTED' then
    jsonb_build_object(
      'error_code',p_error_code,'retry',false,
      'allowed_transition_values',jsonb_build_array('DONE','NOT_APPLICABLE','IN_PROGRESS'),
      'checkpoint_storage_values',jsonb_build_array('PENDING','IN_PROGRESS','BLOCKED','DONE','NOT_APPLICABLE'),
      'blocking_protocol',jsonb_build_object(
        'entrypoint','programacion.fn_engineering_blocker_open_v1',
        'blocker_status','OPEN',
        'checkpoint_transition_after_blocker','IN_PROGRESS',
        'required_fields',jsonb_build_array('blocker_code','description','required_action','source_ref','actor')
      ),
      'repair_handler','programacion.fn_engineering_transition_repair_v1',
      'next_action','USE_BLOCKER_PROTOCOL_OR_ALLOWED_TRANSITION'
    )
  when 'HEARTBEAT_PHASE_UNSUPPORTED' then
    jsonb_build_object(
      'error_code',p_error_code,'retry',false,
      'allowed_phases',jsonb_build_array('ACTION_STARTED','STEP_STARTED','STEP_DONE','CONNECTOR_BLOCKED','RETRYING','ACTION_DONE','ACTION_FAILED'),
      'repair_handler','programacion.fn_engineering_heartbeat_normalize_v1',
      'next_action','USE_DECLARED_PHASE_ONLY'
    )
  when 'HEARTBEAT_STEP_UNDECLARED' then
    jsonb_build_object(
      'error_code',p_error_code,'retry',false,
      'step_code_source','ACTION_SPEC_ACTION_STEPS_ONLY',
      'action_started_step_code',null,'action_done_step_code',null,'action_failed_step_code',null,
      'connector_seq_is_step_code',false,'connector_operation_is_step_code',false,
      'repair_handler','programacion.fn_engineering_heartbeat_normalize_v1',
      'next_action','USE_EXACT_DECLARED_ACTION_STEP_OR_NULL_FOR_ACTION_BOUNDARY'
    )
  when 'WRITE_ACTION_UNSPECIFIED' then
    jsonb_build_object(
      'error_code',p_error_code,'retry',false,
      'required_any_of',jsonb_build_array('canonical_entrypoint','exact_sql','call_template','canonical_mutation_mode'),
      'forbidden',jsonb_build_array('INFER_WRITE_FROM_READ_QUERIES','DISCOVER_MUTATION_DURING_EXECUTION','TRY_SCHEMA_VALUES_UNTIL_ONE_WORKS'),
      'next_action','FIX_ACTION_SPEC_OR_PACKET_BEFORE_EXECUTION'
    )
  when 'SOURCE_PACK_MISSING' then
    jsonb_build_object(
      'error_code',p_error_code,'retry',false,
      'repair_handler','programacion.fn_engineering_source_pack_materialize_v1',
      'next_action','MATERIALIZE_CHECKPOINT_SOURCE_PACK_BEFORE_EXECUTION'
    )
  when 'SOURCE_PACK_STALE_CURRENTNESS' then
    jsonb_build_object(
      'error_code',p_error_code,'retry',false,
      'next_action','SANITIZE_SOURCE_PACK_AGAINST_LIVE_AUTHORITY'
    )
  when 'ROUTING_HANDLER_PENDING' then
    jsonb_build_object(
      'error_code',p_error_code,'retry',false,
      'repair_handler','programacion.fn_engineering_routing_handler_resolve_v1',
      'next_action','RESOLVE_HANDLER_BEFORE_EXECUTION'
    )
  else
    jsonb_build_object(
      'error_code',coalesce(p_error_code,'UNKNOWN'),'retry',false,
      'next_action','STOP_AND_USE_CANONICAL_PREFLIGHT'
    )
end;
$f$;

-- Systemic sanitation: checkpoint-owned DELIVERABLE is construction work, never a missing-source blocker.
do $sanitize$
declare
  r record;
  x jsonb;
begin
  for r in
    select pu.unit_code,c.checkpoint_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    join programacion.engineering_work_items w on w.id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.disposition='ASSIGNED'
      and w.status not in ('DONE','CANCELLED')
      and c.status not in ('DONE','NOT_APPLICABLE')
      and exists (
        select 1
        from jsonb_array_elements(coalesce(
          coalesce(
            pu.unit_metadata#>array['source_pack_v2','checkpoint_inputs',c.checkpoint_code],
            pu.unit_metadata#>array['source_pack_v1','checkpoint_inputs',c.checkpoint_code]
          )->'missing_typed','[]'::jsonb
        )) m(value)
        where upper(coalesce(m.value->>'kind',''))='DELIVERABLE'
          and coalesce((m.value->>'blocking')::boolean,false)
      )
  loop
    x:=programacion.fn_engineering_source_gap_resolve_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',r.unit_code,r.checkpoint_code,true
    );
    if coalesce(x->>'status','') not in ('REPAIRED','ALREADY_SANITIZED') then
      raise exception 'ENGINEERING_SOURCE_GAP_SANITATION_FAILED:%/%:%',r.unit_code,r.checkpoint_code,x;
    end if;
  end loop;
end;
$sanitize$;

-- Resolve currently known deterministic routing-handler debt generically.
do $routing$
declare
  r record;
  x jsonb;
begin
  for r in
    select pu.unit_code,c.checkpoint_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    join programacion.engineering_work_items w on w.id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.disposition='ASSIGNED'
      and w.status not in ('DONE','CANCELLED')
      and c.status not in ('DONE','NOT_APPLICABLE')
      and programacion.fn_engineering_checkpoint_routing_resolution_v1(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
      )->>'status'='HANDLER_IMPLEMENTATION_REQUIRED'
  loop
    x:=programacion.fn_engineering_routing_handler_resolve_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',r.unit_code,r.checkpoint_code,true
    );
    if coalesce(x->>'status','') not in ('REPAIRED','ALREADY_READY') then
      raise exception 'ENGINEERING_ROUTING_HANDLER_REPAIR_FAILED:%/%:%',r.unit_code,r.checkpoint_code,x;
    end if;
  end loop;
end;
$routing$;

do $post$
declare
  v_deliverable_blockers integer;
  v_routing_pending integer;
  v_m97 jsonb;
  v_m810a jsonb;
  v_m810b jsonb;
begin
  with cp as (
    select pu.unit_code,c.checkpoint_code,
           coalesce(
             pu.unit_metadata#>array['source_pack_v2','checkpoint_inputs',c.checkpoint_code],
             pu.unit_metadata#>array['source_pack_v1','checkpoint_inputs',c.checkpoint_code]
           ) input
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    join programacion.engineering_work_items w on w.id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.disposition='ASSIGNED'
      and w.status not in ('DONE','CANCELLED')
      and c.status not in ('DONE','NOT_APPLICABLE')
  )
  select count(*) into v_deliverable_blockers
  from cp
  cross join lateral jsonb_array_elements(coalesce(input->'missing_typed','[]'::jsonb)) m(value)
  where upper(coalesce(m.value->>'kind',''))='DELIVERABLE'
    and coalesce((m.value->>'blocking')::boolean,false);

  if v_deliverable_blockers<>0 then
    raise exception 'ENGINEERING_DELIVERABLE_BLOCKING_SANITATION_INCOMPLETE:%',v_deliverable_blockers;
  end if;

  select count(*) into v_routing_pending
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.disposition='ASSIGNED'
    and w.status not in ('DONE','CANCELLED')
    and c.status not in ('DONE','NOT_APPLICABLE')
    and programacion.fn_engineering_checkpoint_routing_resolution_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
    )->>'status'='HANDLER_IMPLEMENTATION_REQUIRED';

  if v_routing_pending<>0 then
    raise exception 'ENGINEERING_ROUTING_HANDLER_PENDING_REMAINS:%',v_routing_pending;
  end if;

  v_m97:=programacion.fn_engineering_source_pack_currentness_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.7','TYPED_SCHEMA'
  );
  if coalesce((v_m97->>'missing_typed_count')::int,0)<>1 then
    raise exception 'ENGINEERING_M97_EXPECTED_ONE_NONBLOCKING_DELIVERABLE_MISSING:%',v_m97;
  end if;

  v_m810a:=programacion.fn_engineering_checkpoint_routing_resolution_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M8.10','BENCH_VIA_TPERF'
  );
  v_m810b:=programacion.fn_engineering_checkpoint_routing_resolution_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M8.10','PHASE_BUDGET'
  );
  if v_m810a->>'status'<>'READY' or v_m810b->>'status'<>'READY' then
    raise exception 'ENGINEERING_M810_ROUTING_POSTCHECK_FAILED:%:%',v_m810a,v_m810b;
  end if;
end;
$post$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-SYSTEMIC-REPAIR-HANDLERS-003',
  'ENGINEERING_ORCHESTRATION',
  'Runtime error contracts and recurring blocker families require executable generic resolvers',
  'Five declared runtime errors had only textual next actions, while upstream/source/independence blocker families required repeated manual handling.',
  'The public repair dispatcher covered compile and six runtime families but did not own transition normalization, heartbeat normalization, source-pack materialization, routing resolution or recurring evidence-blocker resolution.',
  'ERROR_OR_BLOCKER_FAMILY -> SINGLE_PUBLIC_DISPATCH -> GENERIC_HANDLER -> REVALIDATE_CURRENT_CHECKPOINT',
  'Keep fn_engineering_checkpoint_repair_dispatch_v2 as the single public router. Owner decisions remain human-only. DELIVERABLE missing_typed entries are non-blocking checkpoint-owned construction work.',
  'PASS when public dispatcher reports supported_error_classes=20; blocking DELIVERABLE count is zero; M8.10 PERFORMANCE_EXACT_SOURCE_BENCHMARK and TIMEOUT_PHASE_BUDGET_POLICY routing resolve READY; unknown inputs remain fail-closed.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_checkpoint_repair_dispatch_v2',
  'EXECUTION',
  array['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Systemic generic repair handlers',
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
