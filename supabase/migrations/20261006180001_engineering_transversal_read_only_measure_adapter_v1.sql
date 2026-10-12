-- ENGINEERING_TRANSVERSAL_READ_ONLY_MEASURE_ADAPTER_V1
-- Scope: compile declared SUPABASE_READ_ONLY_MEASURE handlers into the existing READ router surface.
-- No fifth router capability. Existing handlers delegate unchanged to V1.
-- EKB: ENGINEERING-TRANSVERSAL-ADAPTER-COMPILATION-GAP-001

create or replace function programacion.fn_engineering_transversal_capability_action_spec_v2(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_item jsonb,
  p_base jsonb
)
returns jsonb
language plpgsql
stable
as $function$
declare
  v_base jsonb;
  v_code text;
  v_handler text;
  v_req jsonb;
  v_input jsonb;
  v_descriptor jsonb;
  v_query text;
  v_max_depth int;
begin
  v_base:=coalesce(
    p_base,
    programacion.fn_engineering_checkpoint_action_spec_v3_legacy(
      p_plan_code,p_unit_code,p_checkpoint_code
    )
  );

  v_code:=case
    when jsonb_typeof(p_item)='string'
      then trim(both '"' from p_item::text)
    else nullif(btrim(coalesce(p_item->>'capability_code','')),'')
  end;

  v_handler:=case
    when jsonb_typeof(p_item)='object'
      then nullif(btrim(coalesce(p_item->>'handler','')),'')
    when v_code='CONTROL_EQUIVALENCE_JUDGE'
      then 'T_EQUIV_SHADOW'
    else null
  end;

  if v_handler <> 'SUPABASE_READ_ONLY_MEASURE' then
    return programacion.fn_engineering_transversal_capability_action_spec_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,p_item,v_base
    );
  end if;

  v_req:=programacion.fn_engineering_transversal_handler_requirement_v1(
    v_code,v_handler,p_item
  );

  if coalesce((v_req->>'inputs_complete')::boolean,false)=false then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_MEASURE_ARGUMENTS_MISSING',
      'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE',
      'transversal_capability_code',v_code,
      'transversal_handler',v_handler,
      'handler_requirement',v_req
    );
  end if;

  v_descriptor:=coalesce(v_req->'descriptor','{}'::jsonb);
  v_input:=coalesce(v_req->'execution_input','{}'::jsonb);

  if coalesce(v_descriptor->>'provider','')<>'SUPABASE'
     or coalesce((v_descriptor->>'database_implementation_exists')::boolean,false)=false then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_MEASURE_IMPLEMENTATION_UNAVAILABLE',
      'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE',
      'transversal_capability_code',v_code,
      'transversal_handler',v_handler,
      'handler_requirement',v_req
    );
  end if;

  if v_code='INDEPENDENT_ASSURANCE' then
    if jsonb_typeof(v_input->'context')<>'object'
       or coalesce(v_input->>'max_depth','') !~ '^[0-9]+$' then
      return v_base || jsonb_build_object(
        'status','BLOCK_TRANSVERSAL_MEASURE_ARGUMENTS_INVALID',
        'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE',
        'transversal_capability_code',v_code,
        'transversal_handler',v_handler,
        'handler_requirement',v_req
      );
    end if;

    v_max_depth:=(v_input->>'max_depth')::int;
    if v_max_depth < 1 or v_max_depth > 64 then
      return v_base || jsonb_build_object(
        'status','BLOCK_TRANSVERSAL_MEASURE_ARGUMENTS_INVALID',
        'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE',
        'transversal_capability_code',v_code,
        'transversal_handler',v_handler,
        'handler_requirement',v_req
      );
    end if;

    v_query:=format(
      'select public.lf_independent_assurance_measure_v1(%L,%L,%L,%s,%L::jsonb) as assurance',
      v_input->>'dependency_schema',
      v_input->>'producer_root',
      v_input->>'reviewer_root',
      v_max_depth,
      (v_input->'context')::text
    );

    return v_base || jsonb_build_object(
      'status','READY',
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE',
      'action_kind','VERIFY_QUERY_ONCE',
      'recipe_mode','EXECUTE_DECLARED_READ_ONLY_MEASURE',
      'requires_material_execution',true,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'transversal_capability_code',v_code,
      'transversal_handler',v_handler,
      'handler_requirement',v_req,
      'target',
        coalesce(v_base->'target','{}'::jsonb)
        || jsonb_build_object(
          'declared_objects',
          coalesce(v_base#>'{target,declared_objects}','[]'::jsonb)
          || jsonb_build_array('public.lf_independent_assurance_measure_v1'),
          'declared_assets',
          coalesce(v_base#>'{target,declared_assets}','[]'::jsonb)
          || jsonb_build_array('INDEPENDENT_ASSURANCE')
        ),
      'verification_queries',jsonb_build_array(v_query),
      'expected','Execute exact INDEPENDENT_ASSURANCE measure; result is evidence for this checkpoint only and must fail closed when independence is not proven.',
      'material_contract',jsonb_build_object(
        'scope','CURRENT_CHECKPOINT_ONLY',
        'heartbeat_required',true,
        'verification_mode','CAPABILITY_OWNED_READ_ONLY_MEASURE',
        'domain_mutation','FORBIDDEN',
        'implementation_ref',v_descriptor->>'implementation_ref'
      ),
      'action_steps',jsonb_build_array(
        'EXECUTE_EXACT_MEASURE',
        'ASSERT_INDEPENDENCE_RESULT',
        'PERSIST_TRANSVERSAL_STEP_DONE',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'forbidden',
        coalesce(v_base->'forbidden','[]'::jsonb)
        || jsonb_build_array(
          'DOWNGRADE_MEASURE_TO_PASSIVE_CURRENT_READBACK',
          'INFER_ARGUMENTS_FROM_TITLE',
          'MUTATE_DOMAIN_DATA'
        )
    );
  end if;

  return v_base || jsonb_build_object(
    'status','BLOCK_TRANSVERSAL_MEASURE_ADAPTER_UNSUPPORTED',
    'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE',
    'transversal_capability_code',v_code,
    'transversal_handler',v_handler,
    'handler_requirement',v_req
  );
end;
$function$;

create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null::text
)
returns jsonb
language plpgsql
stable
as $function$
declare
  v_base jsonb;
  v_tx jsonb;
  v_cp text;
  v_state jsonb;
  v_item jsonb;
  v_spec jsonb;
begin
  v_base:=programacion.fn_engineering_checkpoint_action_spec_v3_legacy(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  if v_base is null then return null; end if;

  v_cp:=coalesce(p_checkpoint_code,v_base->>'checkpoint_code');

  select pu.unit_metadata#>array['transversal_execution_v1',v_cp]
    into v_tx
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  if v_tx is null then return v_base; end if;

  if coalesce(v_tx->>'activation','ACTIVE')='DECLARED_ONLY' then
    return v_base || jsonb_build_object(
      'transversal_execution',v_tx,
      'transversal_gate','DECLARED_NOT_ACTIVATED',
      'transversal_routing_changed',false
    );
  end if;

  if coalesce(v_tx->>'mode','')='SELECT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SELECTOR_RUNTIME_REQUIRED',
      'precision','STRUCTURAL_TRANSVERSAL_SELECT',
      'transversal_execution',v_tx,
      'transversal_gate','SELECTOR_REQUIRED'
    );
  end if;

  if coalesce(v_tx->>'mode','')<>'EXPLICIT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_MODE_INVALID',
      'transversal_execution',v_tx
    );
  end if;

  v_state:=programacion.fn_engineering_transversal_sequence_state_v1(
    p_plan_code,p_unit_code,v_cp
  );

  if coalesce((v_state->>'total')::int,0)=0 then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_CAPABILITIES_MISSING',
      'transversal_execution',v_tx
    );
  end if;

  if coalesce((v_state->>'all_done')::boolean,false) then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SEQUENCE_ALREADY_COMPLETE_REQUIRES_CHECKPOINT_TRANSITION',
      'transversal_execution',v_tx,
      'transversal_sequence',v_state
    );
  end if;

  v_item:=v_state->'current_item';
  v_spec:=programacion.fn_engineering_transversal_capability_action_spec_v2(
    p_plan_code,p_unit_code,v_cp,v_item,v_base
  );

  return v_spec || jsonb_build_object(
    'transversal_execution',v_tx,
    'transversal_sequence',v_state,
    'transversal_gate',
      case when v_spec->>'status'='READY' then 'PASS_CURRENT_ITEM' else 'BLOCK_CURRENT_ITEM' end,
    'forbidden',
      coalesce(v_spec->'forbidden','[]'::jsonb)
      || jsonb_build_array('FALLBACK_TO_TITLE_HEURISTIC_WHEN_EXPLICIT_DECLARED')
  );
end;
$function$;
