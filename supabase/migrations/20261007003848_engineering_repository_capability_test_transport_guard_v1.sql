-- Repository capability transport guard v1.
-- RUN_TEST is the existing router transport for versioned repository capability execution.
-- It is not a request to discover/execute a test-case set. Semantic acceptance remains
-- owned by ENGINEERING_ASSERTION_CONTRACT_V1 and its persisted assertion receipt.

do $pre$
declare
  v_md5 text;
begin
  v_md5:=md5(pg_get_functiondef(
    'programacion.fn_engineering_packet_apply_test_contract_guard_v1(jsonb,jsonb)'::regprocedure
  ));
  if v_md5 is distinct from '582441a9b0db6c4f79702fe518469d9f' then
    raise exception 'REPOSITORY_CAPABILITY_TEST_GUARD_BASE_DRIFT expected=582441a9b0db6c4f79702fe518469d9f actual=%',v_md5;
  end if;
end;
$pre$;

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
  v_exec jsonb;
  v_capability_code text;
begin
  if coalesce(p_packet->>'status','')<>'READY'
     or coalesce(p_packet->>'execution_capability','')<>'RUN_TEST' then
    return p_packet;
  end if;

  -- RUN_TEST is also the intentionally reused transport surface for repository
  -- capability execution. Do not force test-case semantics onto that transport.
  -- The subsequent assertion guard validates provider output + consumer semantics
  -- and requires a persisted machine-verifiable assertion receipt before DONE.
  if v_kind='TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION' then
    v_exec:=coalesce(p_action_spec->'capability_execution','{}'::jsonb);
    v_capability_code:=nullif(btrim(coalesce(v_exec->>'capability_code','')),'');

    v_valid:=
      jsonb_typeof(v_exec)='object'
      and v_exec->>'contract'='ENGINEERING_REPOSITORY_CAPABILITY_EXECUTION_V1'
      and v_capability_code is not null
      and nullif(btrim(coalesce(v_exec->>'implementation_ref','')),'') is not null
      and nullif(btrim(coalesce(v_exec->>'current_version','')),'') is not null
      and coalesce(v_exec->>'manifest_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce((v_exec->>'result_evidence_required')::boolean,false);

    if v_valid then
      return p_packet || jsonb_build_object(
        'test_contract_guard',jsonb_build_object(
          'status','PASS',
          'mode','REPOSITORY_CAPABILITY_TRANSPORT',
          'capability_code',v_capability_code,
          'transport_operation','RUN_TEST',
          'semantic_result_gate_owner','ENGINEERING_ASSERTION_CONTRACT_V1',
          'assertion_guard_required',true,
          'fallback_case_discovery','FORBIDDEN'
        )
      );
    end if;

    return (
      p_packet || jsonb_build_object(
        'status','BLOCK_REPOSITORY_CAPABILITY_TRANSPORT_CONTRACT_INCOMPLETE',
        'execution_allowed',false,
        'test_contract_guard',jsonb_build_object(
          'status','BLOCK',
          'mode','REPOSITORY_CAPABILITY_TRANSPORT',
          'reason','REPOSITORY_CAPABILITY_EXECUTION_CONTRACT_AND_RESULT_EVIDENCE_REQUIRED',
          'fallback_case_discovery','FORBIDDEN'
        ),
        'block_reasons',
          coalesce(p_packet->'block_reasons','[]'::jsonb)
          || jsonb_build_array('REPOSITORY_CAPABILITY_TRANSPORT_CONTRACT_INCOMPLETE')
      )
    ) - 'connector_plan'
      || jsonb_build_object('connector_plan','[]'::jsonb);
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
is 'Distinguishes RUN_TEST semantic test execution from RUN_TEST transport used by versioned repository capabilities. Repository capability outputs are governed by ENGINEERING_ASSERTION_CONTRACT_V1 and persisted assertion receipts.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-REPOSITORY-CAPABILITY-RUNTEST-TRANSPORT-001',
  'ENGINEERING_ORCHESTRATION',
  'Repository capability RUN_TEST transport must not require a test-case contract',
  'The packet router intentionally reuses RUN_TEST as the transport operation for TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION, but the generic test contract guard treated every RUN_TEST packet as semantic test execution and blocked released repository capabilities with BLOCK_TEST_EXECUTION_CONTRACT_MISSING.',
  'Transport capability and semantic action kind were conflated at the test-contract boundary.',
  'REPOSITORY_CAPABILITY_TRANSPORT_MISCLASSIFIED_AS_TEST_CASE_EXECUTION',
  'When action_kind is TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION, validate ENGINEERING_REPOSITORY_CAPABILITY_EXECUTION_V1 identity/currentness/result-evidence requirements and delegate semantic acceptance to ENGINEERING_ASSERTION_CONTRACT_V1. Preserve strict exact-test contracts for actual test executions.',
  'PASS when repository capability packets report test_contract_guard.mode=REPOSITORY_CAPABILITY_TRANSPORT plus assertion_gate=PASS, while DECLARED_CAPABILITY_TEST_EXECUTION continues to require exact test_code/pass_when and malformed repository execution contracts remain blocked.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_packet_apply_test_contract_guard_v1; supabase://programacion.fn_engineering_packet_apply_assertion_guard_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'Repository capability execution packet compilation',
  'supabase://programacion.fn_engineering_packet_apply_test_contract_guard_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();
