-- ENGINEERING contract sanitation split 2/4: test and packet guards.

create or replace function programacion.fn_engineering_packet_apply_test_contract_guard_v1(
  p_packet jsonb,
  p_action_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_kind text := coalesce(p_action_spec->>'action_kind','');
  v_test_code text;
  v_valid boolean := false;
begin
  if coalesce(p_packet->>'status','')<>'READY'
     or coalesce(p_packet->>'execution_capability','')<>'RUN_TEST' then
    return p_packet;
  end if;

  if p_packet->'explicit_test_case_set' is not null then
    return p_packet || jsonb_build_object(
      'test_contract_guard',jsonb_build_object(
        'status','PASS',
        'mode','EXPLICIT_TEST_CODES',
        'fallback_case_discovery','FORBIDDEN'
      )
    );
  end if;

  if v_kind='DECLARED_CAPABILITY_TEST_EXECUTION' then
    v_test_code:=
      nullif(btrim(coalesce(
        p_action_spec#>>'{capability_execution,result_contract,test_code}',''
      )),'');
    v_valid:=
      v_test_code is not null
      and coalesce(
        jsonb_array_length(coalesce(p_action_spec->'verification_queries','[]'::jsonb)),
        0
      )>0;

  elsif v_kind='DECLARED_TEST_PERSISTENCE_EXECUTION' then
    v_test_code:='CAPABILITY_OWNED_TEST_PERSISTENCE';
    v_valid:=true;

  elsif jsonb_typeof(p_action_spec->'test_execution_contract')='object' then
    v_test_code:=
      nullif(btrim(coalesce(
        p_action_spec#>>'{test_execution_contract,test_code}',''
      )),'');
    v_valid:=
      coalesce(p_action_spec#>>'{test_execution_contract,mode}','')
        in ('AUTHORED_NEGATIVE','EXPLICIT_VERIFICATION_QUERY')
      and v_test_code is not null
      and coalesce(
        jsonb_array_length(coalesce(p_action_spec->'verification_queries','[]'::jsonb)),
        0
      )>0;
  end if;

  if v_valid then
    return p_packet || jsonb_build_object(
      'test_contract_guard',jsonb_build_object(
        'status','PASS',
        'mode',case
          when v_kind='DECLARED_CAPABILITY_TEST_EXECUTION'
            then 'CAPABILITY_OWNED_EXACT_TEST'
          when v_kind='DECLARED_TEST_PERSISTENCE_EXECUTION'
            then 'CAPABILITY_OWNED_TEST_PERSISTENCE'
          else coalesce(
            p_action_spec#>>'{test_execution_contract,mode}',
            'AUTHORED_NEGATIVE'
          )
        end,
        'test_code',v_test_code,
        'fallback_case_discovery','FORBIDDEN'
      )
    );
  end if;

  return (
    p_packet || jsonb_build_object(
      'status','BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
      'execution_allowed',false,
      'test_contract_guard',jsonb_build_object(
        'status','BLOCK',
        'reason','RUN_TEST_REQUIRES_EXPLICIT_TEST_CODES_OR_EXACT_AUTHORED_TEST_CONTRACT',
        'fallback_case_discovery','FORBIDDEN'
      ),
      'block_reasons',
        coalesce(p_packet->'block_reasons','[]'::jsonb)
        || jsonb_build_array('TEST_EXECUTION_CONTRACT_MISSING')
    )
  ) - 'connector_plan'
    || jsonb_build_object('connector_plan','[]'::jsonb);
end;
$function$;

comment on function programacion.fn_engineering_packet_apply_test_contract_guard_v1(jsonb,jsonb)
is 'RUN_TEST fail-closed guard. Requires explicit catalog cases, a capability-owned exact test, or an exact authored test contract. Implicit case discovery is forbidden.';

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
set search_path to 'programacion','public','pg_catalog'
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

  v_packet:=programacion.fn_engineering_packet_apply_test_contract_guard_v1(
    v_packet,p_action_spec
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

