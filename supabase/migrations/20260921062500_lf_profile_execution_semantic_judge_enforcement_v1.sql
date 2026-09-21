begin;
-- LF_CI_ROLLBACK_GOVERNED_ACTOR_V1: ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF

do $pre$
declare c int;
begin
  select count(*) into c
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and coalesce((e.manifest->>'production_apply_authorized')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260921062500_lf_profile_execution_semantic_judge_enforcement_v1.sql';
  if c<>1 then raise exception 'PROFILE_SEMANTIC_JUDGE_PRE_RUNTIME_UPDATE_ACTOR_COUNT:%',c; end if;
  if not exists (select 1 from public.lf_operation_step_contracts where operation_code='EJECUCION_PERFIL_LF' and step_id='semantic_judge' and status='ACTIVE_ENFORCEMENT') then
    raise exception 'PROFILE_SEMANTIC_JUDGE_STEP_MISSING';
  end if;
end
$pre$;

create or replace function public.lf_profile_execution_trust_validation_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  event_id bigint;
  budget_event_id bigint;
  receipt jsonb;
  expected_digest text;
  context_step public.lf_operation_execution_steps%rowtype;
  context_binding public.lf_operation_step_judge_bindings%rowtype;
  baseline_step public.lf_operation_execution_steps%rowtype;
  baseline_binding public.lf_operation_step_judge_bindings%rowtype;
  baseline jsonb;
  contract jsonb;
  snapshot_path text[];
  digest_path text[];
  output_snapshot jsonb;
  output_digest text;
  transport jsonb;
  hard jsonb := '[]'::jsonb;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_step_id,'')),'') is null
     or p_evidence_payload is null
     or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_TRUST_INPUT_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or e.operation_code<>'EJECUCION_PERFIL_LF' or e.target_type<>'PERFIL' or e.status<>'IN_PROGRESS' then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_BINDING_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if p_step_id='context_admission' then
    if coalesce((p_evidence_payload->>'server_validated')::boolean,false) is not true
       or p_evidence_payload->>'compiler_ref'<>'public.fn_lf_router_preflight_v1'
       or p_evidence_payload->>'profile_source_mode'<>'JIT_BY_REF'
       or p_evidence_payload->>'jit_resolver_ref'<>'supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY'
       or p_evidence_payload->>'context_budget_status' not in ('GREEN','YELLOW')
       or jsonb_typeof(p_evidence_payload->'delivery')<>'object'
       or jsonb_typeof(p_evidence_payload->'lazy_refs')<>'object'
    then
      hard:=hard||jsonb_build_array('context_admission_shape_invalid');
    else
      event_id:=(p_evidence_payload->>'context_event_id')::bigint;
      budget_event_id:=(p_evidence_payload->>'context_budget_event_id')::bigint;
      select payload->'context_receipt' into receipt
      from public.lf_eventos
      where id=event_id and created_by_execution_id=p_execution_id and payload->>'producer'='fn_lf_router_preflight_v1';
      if receipt is null then hard:=hard||jsonb_build_array('context_event_readback_missing');
      else
        expected_digest:='sha256:'||encode(extensions.digest(convert_to(receipt::text,'UTF8'),'sha256'),'hex');
        if p_evidence_payload->>'context_receipt_digest' is distinct from expected_digest
           or p_evidence_payload->>'context_receipt_ref' is distinct from 'supabase://public.lf_eventos/'||event_id::text||'#context_receipt'
           or coalesce((receipt#>>'{delivery,jit_only}')::boolean,false) is not true
           or coalesce((receipt#>>'{delivery,policy_payloads}')::boolean,true) is not false
           or coalesce((receipt#>>'{delivery,full_ekb_entries}')::boolean,true) is not false
           or coalesce((receipt#>>'{delivery,full_readmes}')::boolean,true) is not false
           or receipt#>>'{context_budget,status}' not in ('GREEN','YELLOW')
        then hard:=hard||jsonb_build_array('context_receipt_readback_mismatch'); end if;
      end if;
      if not exists (
        select 1 from private.lf_context_budget_events_v2
        where id=budget_event_id and execution_id=p_execution_id and evidence_event_id=event_id and context_status in ('GREEN','YELLOW')
      ) then hard:=hard||jsonb_build_array('context_budget_readback_mismatch'); end if;
    end if;

  elsif p_step_id='execute_profile' then
    select * into context_binding from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF' and step_id='context_admission' and status='ACTIVE_ENFORCEMENT';
    select * into context_step from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='context_admission';
    if not found or context_step.status<>context_binding.clean_result_value then
      hard:=hard||jsonb_build_array('context_admission_predecessor_not_clean');
    else
      transport:=p_evidence_payload->'context_transport';
      if p_evidence_payload->>'context_receipt_digest' is distinct from context_step.evidence_payload->>'context_receipt_digest'
         or p_evidence_payload->>'context_receipt_ref' is distinct from context_step.evidence_payload->>'context_receipt_ref'
         or jsonb_typeof(transport)<>'object'
         or transport->>'profile_source_mode'<>'JIT_BY_REF'
         or transport->>'jit_resolver_ref'<>'supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY'
         or coalesce((transport->>'jit_only')::boolean,false) is not true
         or coalesce((transport->>'policy_payloads')::boolean,true) is not false
         or coalesce((transport->>'full_ekb_entries')::boolean,true) is not false
         or coalesce((transport->>'full_readmes')::boolean,true) is not false
         or coalesce((transport->>'full_prefetch_count')::integer,0)<>0
         or jsonb_typeof(transport->'hydrated_refs')<>'array'
      then hard:=hard||jsonb_build_array('execute_profile_context_transport_invalid'); end if;
    end if;

    select * into baseline_binding from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF' and step_id='research_baseline_freeze' and status='ACTIVE_ENFORCEMENT';
    select * into baseline_step from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='research_baseline_freeze';
    if not found or baseline_step.status<>baseline_binding.clean_result_value then
      hard:=hard||jsonb_build_array('research_baseline_predecessor_not_clean');
    else
      baseline:=baseline_step.evidence_payload->'research_baseline_binding';
      if p_evidence_payload->>'research_baseline_ref' is distinct from baseline_step.evidence_payload->>'baseline_receipt_ref'
         or p_evidence_payload->>'research_baseline_digest' is distinct from baseline->>'baseline_digest' then
        hard:=hard||jsonb_build_array('research_baseline_execute_binding_mismatch');
      end if;
      if baseline->>'applicability'='REQUIRED' then
        contract:=e.manifest->'research_baseline_contract';
        if jsonb_typeof(contract)<>'object'
           or jsonb_typeof(contract->'output_snapshot_path')<>'array'
           or jsonb_typeof(contract->'output_digest_path')<>'array' then
          hard:=hard||jsonb_build_array('research_baseline_contract_missing');
        else
          select array_agg(value order by ord)
            into snapshot_path
          from jsonb_array_elements_text(contract->'output_snapshot_path') with ordinality x(value,ord);
          select array_agg(value order by ord)
            into digest_path
          from jsonb_array_elements_text(contract->'output_digest_path') with ordinality x(value,ord);
          if jsonb_typeof(p_evidence_payload->'profile_output')<>'object' then
            hard:=hard||jsonb_build_array('research_baseline_output_missing');
          else
            output_snapshot:=(p_evidence_payload->'profile_output')#>snapshot_path;
            output_digest:=(p_evidence_payload->'profile_output')#>>digest_path;
            if output_snapshot is distinct from baseline->'baseline_snapshot'
               or output_digest is distinct from baseline->>'baseline_digest' then
              hard:=hard||jsonb_build_array('research_baseline_output_mutated');
            end if;
          end if;
        end if;
      end if;
    end if;

  elsif p_step_id='semantic_judge' then
    select * into context_binding from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF' and step_id='output_validate' and status='ACTIVE_ENFORCEMENT';
    select * into context_step from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='output_validate';
    if not found or context_step.status<>context_binding.clean_result_value then
      hard:=hard||jsonb_build_array('output_validate_predecessor_not_clean');
    end if;
    if jsonb_typeof(p_evidence_payload->'semantic_judge_result')<>'object'
       or p_evidence_payload#>>'{semantic_judge_result,status}' is distinct from 'PASS'
       or jsonb_typeof(p_evidence_payload->'unsupported_claims')<>'array'
       or jsonb_array_length(p_evidence_payload->'unsupported_claims')<>0 then
      hard:=hard||jsonb_build_array('semantic_judge_not_pass');
    end if;
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'hard_fails',hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  return jsonb_build_object(
    'valid',true,'code','PROFILE_EXECUTION_SERVER_VALIDATED',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
end
$fn$;

comment on function public.lf_profile_execution_trust_validation_v1(text,text,jsonb) is
'Server trust boundary for EJECUCION_PERFIL_LF. Enforces context transport, exact pre-research baseline binding, and derives semantic_judge clean state only from an explicit PASS with zero unsupported claims after clean output_validate.';

do $post$
begin
  if position('semantic_judge_not_pass' in pg_get_functiondef('public.lf_profile_execution_trust_validation_v1(text,text,jsonb)'::regprocedure))=0 then
    raise exception 'PROFILE_SEMANTIC_JUDGE_POST_ENFORCEMENT_MISSING';
  end if;
end
$post$;

commit;
