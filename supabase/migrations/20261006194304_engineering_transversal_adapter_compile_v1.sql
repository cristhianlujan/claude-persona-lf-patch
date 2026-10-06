-- Root fix: compile explicit transversal adapters into the existing four-capability router.
-- Scope: action-spec compilation only. No fifth router capability and no domain mutation.

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
set search_path = programacion, public, pg_catalog
as $function$
declare
  v_base jsonb;
  v_code text;
  v_handler text;
  v_req jsonb;
  v_desc jsonb;
  v_input jsonb;
  v_impl text;
  v_version text;
  v_manifest_sha256 text;
  v_query text;
begin
  v_base := programacion.fn_engineering_transversal_capability_action_spec_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,p_item,p_base
  );

  v_code := case
    when jsonb_typeof(p_item)='string' then trim(both '"' from p_item::text)
    else nullif(btrim(coalesce(p_item->>'capability_code','')),'')
  end;

  v_handler := case
    when jsonb_typeof(p_item)='object' then nullif(btrim(coalesce(p_item->>'handler','')),'')
    when v_code='CONTROL_EQUIVALENCE_JUDGE' then 'T_EQUIV_SHADOW'
    else null
  end;

  if v_handler not in (
    'REPOSITORY_COMPARATOR_EXECUTOR',
    'REPOSITORY_CAPABILITY_EXECUTOR',
    'SUPABASE_NATIVE_FUNCTION_EXECUTOR',
    'SUPABASE_READ_ONLY_MEASURE'
  ) then
    return v_base;
  end if;

  v_req := programacion.fn_engineering_transversal_handler_requirement_v1(
    v_code,v_handler,p_item
  );

  if coalesce((v_req->>'inputs_complete')::boolean,false)=false then
    return v_base;
  end if;

  v_desc := coalesce(v_req->'descriptor','{}'::jsonb);
  v_input := coalesce(v_req->'execution_input','{}'::jsonb);
  v_impl := nullif(btrim(coalesce(v_desc->>'implementation_ref','')),'');

  if v_handler='SUPABASE_READ_ONLY_MEASURE' then
    if v_code<>'INDEPENDENT_ASSURANCE' then
      return v_base || jsonb_build_object(
        'status','BLOCK_TRANSVERSAL_MEASURE_ADAPTER_UNSUPPORTED',
        'precision','STRUCTURAL_TRANSVERSAL_ADAPTER_V2',
        'transversal_capability_code',v_code,
        'transversal_handler',v_handler,
        'handler_requirement',v_req
      );
    end if;

    if v_impl is null then
      return v_base || jsonb_build_object(
        'status','BLOCK_TRANSVERSAL_MEASURE_IMPLEMENTATION_REF_MISSING',
        'precision','STRUCTURAL_TRANSVERSAL_ADAPTER_V2',
        'transversal_capability_code',v_code,
        'transversal_handler',v_handler,
        'handler_requirement',v_req
      );
    end if;

    v_query := format(
      'select public.lf_independent_assurance_measure_v1(%L,%L,%L,%s,%L::jsonb) as result',
      v_input->>'dependency_schema',
      v_input->>'producer_root',
      v_input->>'reviewer_root',
      (v_input->>'max_depth')::int,
      coalesce(v_input->'context','{}'::jsonb)::text
    );

    return v_base || jsonb_build_object(
      'status','READY',
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','STRUCTURAL_TRANSVERSAL_ADAPTER_V2',
      'action_kind','VERIFY_QUERY_ONCE',
      'recipe_mode','EXECUTE_READ_ONLY_MEASURE',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'transversal_capability_code',v_code,
      'transversal_handler',v_handler,
      'handler_requirement',v_req,
      'verification_queries',jsonb_build_array(v_query),
      'expected',concat_ws(
        ' | ',
        nullif(v_base->>'expected',''),
        'Execute exact CURRENT read-only measure with declared inputs'
      ),
      'action_steps',jsonb_build_array(
        'READ_CURRENT_CAPABILITY_AUTHORITY',
        'EXECUTE_DECLARED_READ_ONLY_MEASURE',
        'ASSERT_MEASURE_RESULT',
        'PERSIST_TRANSVERSAL_STEP_DONE',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'forbidden',
        coalesce(v_base->'forbidden','[]'::jsonb)
        || jsonb_build_array(
          'MUTATE_DOMAIN_DATA',
          'INFER_UNDECLARED_MEASURE_ARGUMENTS',
          'REEXECUTE_DEPENDENCY_OWNED_TESTS'
        )
    );
  end if;

  if v_handler in ('REPOSITORY_CAPABILITY_EXECUTOR','REPOSITORY_COMPARATOR_EXECUTOR') then
    if v_impl is null then
      return v_base || jsonb_build_object(
        'status','BLOCK_TRANSVERSAL_REPOSITORY_IMPLEMENTATION_REF_MISSING',
        'precision','STRUCTURAL_TRANSVERSAL_ADAPTER_V2',
        'transversal_capability_code',v_code,
        'transversal_handler',v_handler,
        'handler_requirement',v_req
      );
    end if;

    select c.version,c.manifest_sha256
      into v_version,v_manifest_sha256
    from public.lf_capability_current c
    join public.lf_capability_version_registry v
      on v.capability_code=c.capability_code
     and v.version=c.version
     and v.release_state='RELEASED'
    where c.capability_code=v_code;

    if v_version is null or v_manifest_sha256 is null then
      return v_base || jsonb_build_object(
        'status','BLOCK_TRANSVERSAL_REPOSITORY_CURRENT_RELEASE_MISSING',
        'precision','STRUCTURAL_TRANSVERSAL_ADAPTER_V2',
        'transversal_capability_code',v_code,
        'transversal_handler',v_handler,
        'handler_requirement',v_req
      );
    end if;

    return v_base || jsonb_build_object(
      'status','READY',
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','STRUCTURAL_TRANSVERSAL_ADAPTER_V2',
      'action_kind','TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION',
      'recipe_mode','EXECUTE_REPOSITORY_CAPABILITY',
      'requires_material_execution',true,
      'mutation_policy','CAPABILITY_CONTRACT_ONLY',
      'transversal_capability_code',v_code,
      'transversal_handler',v_handler,
      'handler_requirement',v_req,
      'capability_execution',jsonb_build_object(
        'contract','ENGINEERING_REPOSITORY_CAPABILITY_EXECUTION_V1',
        'capability_code',v_code,
        'handler',v_handler,
        'implementation_ref',v_impl,
        'current_version',v_version,
        'manifest_sha256',v_manifest_sha256,
        'execution_input',v_input,
        'source_policy','CURRENT_EXACT_MANIFEST',
        'result_evidence_required',true,
        'domain_mutation','FORBIDDEN_UNLESS_CAPABILITY_CONTRACT_EXPLICIT'
      ),
      'action_steps',jsonb_build_array(
        'RESOLVE_CURRENT_EXACT_CAPABILITY_SOURCE',
        'EXECUTE_CAPABILITY_WITH_DECLARED_INPUT',
        'CAPTURE_TYPED_RESULT_EVIDENCE',
        'PERSIST_TRANSVERSAL_STEP_DONE',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'forbidden',
        coalesce(v_base->'forbidden','[]'::jsonb)
        || jsonb_build_array(
          'CREATE_FIFTH_ROUTER_CAPABILITY',
          'EXECUTE_NON_CURRENT_CAPABILITY_SOURCE',
          'INFER_UNDECLARED_EXECUTION_INPUT',
          'SYNTHETIC_PASS_WITHOUT_CAPABILITY_EXECUTION'
        )
    );
  end if;

  -- Native functions can be read-only or mutating. Do not infer that boundary.
  if v_handler='SUPABASE_NATIVE_FUNCTION_EXECUTOR' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_NATIVE_EXECUTION_MODE_REQUIRED',
      'precision','STRUCTURAL_TRANSVERSAL_ADAPTER_V2',
      'transversal_capability_code',v_code,
      'transversal_handler',v_handler,
      'handler_requirement',v_req,
      'required_contract',jsonb_build_object(
        'execution_mode','READ_ONLY|WRITE_DB',
        'implementation_ref_required',true,
        'argument_source','execution_input'
      )
    );
  end if;

  return v_base;
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
set search_path = programacion, public, pg_catalog
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

create or replace function programacion.fn_engineering_execution_packet_apply_transversal_adapter_v1(
  p_packet jsonb,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path = programacion, public, pg_catalog
as $function$
declare
  v_exec jsonb;
  v_impl text;
  v_plan jsonb;
begin
  if coalesce(p_action_spec->>'status','')<>'READY'
     or coalesce(p_action_spec->>'action_kind','')<>'TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION' then
    return p_packet;
  end if;

  v_exec:=coalesce(p_action_spec->'capability_execution','{}'::jsonb);
  v_impl:=nullif(btrim(coalesce(v_exec->>'implementation_ref','')),'');

  if v_impl is null
     or coalesce(v_exec->>'manifest_sha256','') !~ '^[0-9a-f]{64}$'
     or nullif(btrim(coalesce(v_exec->>'current_version','')),'') is null then
    return p_packet || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_REPOSITORY_EXECUTOR_CONTRACT_INCOMPLETE'
    );
  end if;

  v_plan:=programacion.fn_engineering_plan_add_transition_args_v1(
    jsonb_build_array(
      jsonb_build_object(
        'seq',1,
        'provider','GITHUB',
        'operation','RUN_TEST',
        'capability','RUN_TEST',
        'mode','REPOSITORY_CAPABILITY',
        'targets',jsonb_build_array(
          jsonb_build_object(
            'path',v_impl,
            'version',v_exec->>'current_version',
            'manifest_sha256',v_exec->>'manifest_sha256'
          )
        ),
        'capability_execution',v_exec,
        'executor_contract',jsonb_build_object(
          'executor','ENGINEERING_REPOSITORY_CAPABILITY_EXECUTOR_V1',
          'source_policy','CURRENT_EXACT_MANIFEST',
          'implementation_ref',v_impl,
          'current_version',v_exec->>'current_version',
          'manifest_sha256',v_exec->>'manifest_sha256',
          'execution_input',coalesce(v_exec->'execution_input','{}'::jsonb),
          'fetch_exact_repository_source',true,
          'execute_capability_entrypoint',true,
          'capture_result_evidence',true,
          'synthetic_pass','FORBIDDEN',
          'domain_mutation',coalesce(v_exec->>'domain_mutation','FORBIDDEN')
        )
      ),
      jsonb_build_object(
        'seq',2,
        'provider','SUPABASE',
        'operation','CHECKPOINT_TRANSITION'
      )
    ),
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  return p_packet || jsonb_build_object(
    'status','READY',
    'execution_capability','RUN_TEST',
    'capability_mode','REPOSITORY_CAPABILITY',
    'requires_material_execution',true,
    'effective_action_kind','TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION',
    'verification_mode','CAPABILITY_OWNED',
    'block_reasons','[]'::jsonb,
    'connector_plan',v_plan,
    'mutation_policy','CAPABILITY_CONTRACT_ONLY'
  );
end;
$function$;

create or replace function programacion.fn_engineering_execution_packet_from_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb,
  p_execution_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path = programacion, public, pg_catalog
as $function$
declare
  v_packet jsonb;
  v_budget int;
  v_spec jsonb := coalesce(p_action_spec,'{}'::jsonb);
  v_material boolean := coalesce((p_action_spec->>'requires_material_execution')::boolean,false);
  v_kind text := coalesce(p_action_spec->>'action_kind','');
  v_title text := coalesce(p_action_spec->>'checkpoint_title','');
begin
  if v_material
     and v_kind not in ('READBACK_ONCE','OBSERVE_ONCE','DECISION_GATE','TERMINAL_RECONCILE') then
    v_spec := jsonb_set(
      v_spec,
      '{checkpoint_title}',
      to_jsonb('execute material: ' || v_title),
      true
    );
  end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec,p_execution_input
  );

  v_packet:=programacion.fn_engineering_execution_packet_apply_transversal_adapter_v1(
    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
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

  v_packet:=programacion.fn_engineering_packet_apply_read_budget_v1(
    v_packet,v_budget
  );

  v_packet:=programacion.fn_engineering_packet_apply_governed_merge_v1(v_packet);

  return v_packet || jsonb_build_object(
    'readonly_policy',jsonb_build_object(
      'scope','EXPLICIT_READ_ACTIONS_ONLY',
      'materiality_authority','ACTION_SPEC_REQUIRES_MATERIAL_EXECUTION',
      'title_based_materiality_downgrade','FORBIDDEN',
      'material_actions_allowed',jsonb_build_array('WRITE_DB','WRITE_GIT','RUN_TEST')
    )
  );
end;
$function$;

comment on function programacion.fn_engineering_transversal_capability_action_spec_v2(text,text,text,jsonb,jsonb)
is 'Compiles complete transversal repository handlers to RUN_TEST and supported read-only measures to READ without creating a fifth router capability; incomplete or ambiguous handlers fail closed.';

comment on function programacion.fn_engineering_execution_packet_apply_transversal_adapter_v1(jsonb,text,text,text,jsonb)
is 'Overlays executable repository-capability RUN_TEST packets using CURRENT exact manifest source and declared execution_input.';

-- EKB: preserve the root-cause record and update the expected validation contract.
update public.lf_error_knowledge
set validacion =
  'PASS when complete SUPABASE_READ_ONLY_MEASURE compiles to exact READ/VERIFY query; complete repository capabilities with implementation_ref compile to RUN_TEST with CURRENT exact manifest; missing implementation_ref remains fail-closed; no fifth router capability; incomplete inputs retain precise blockers.'
where codigo='ENGINEERING-TRANSVERSAL-ADAPTER-COMPILATION-GAP-001';
