-- Story Agent E2E / PROG-020 / AUD24-F03
-- Fail-closed authority hardening for Worker v10 terminal gate materialization.
-- Reuses authority_challenges/authority_attestations; no new canonical table or authority channel.

create or replace function programacion.fn_guard_authority_challenge_insert()
returns trigger
language plpgsql
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_payload jsonb;
begin
  if current_user <> 'postgres' then
    raise exception 'authority challenge creation requires control-plane postgres; current_user=%',current_user;
  end if;
  if new.expires_at <= now() then
    raise exception 'authority challenge expiry must be in the future';
  end if;
  if new.repo_full_name not in (
    'cristhianlujan/programming-agent',
    'cristhianlujan/libertad-financiera'
  ) then
    raise exception 'unexpected authority challenge repository %',new.repo_full_name;
  end if;
  if new.repo_full_name='cristhianlujan/libertad-financiera'
     and new.purpose<>'STORY_AGENT_WORKER_V10_ORIGIN_V1' then
    raise exception 'libertad-financiera authority challenge purpose is not allowed: %',new.purpose;
  end if;
  new.created_by_db_principal := current_user;
  v_payload:=jsonb_build_object(
    'schema_version',1,
    'repo_full_name',new.repo_full_name,
    'head_sha',new.head_sha,
    'challenge_nonce',new.challenge_nonce::text,
    'required_roles',to_jsonb(new.required_roles),
    'purpose',new.purpose,
    'expires_at',to_jsonb(new.expires_at),
    'created_by_db_principal',new.created_by_db_principal
  );
  new.challenge_sha256 := programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$function$;

create or replace function programacion.fn_agent_task_worker_v10_authority_context_v2(
  p_evaluation_id bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_execution_id bigint;
  v_base_head_sha text;
  v_gate_code text;
  v_evidence_id bigint;
  v_evidence_sha256 text;
  v_source_ref text;
  v_receipt jsonb;
  v_candidate_head_sha text;
  v_origin programacion.authority_attestations%rowtype;
  v_origin_challenge programacion.authority_challenges%rowtype;
  v_hidden programacion.authority_attestations%rowtype;
  v_hidden_challenge programacion.authority_challenges%rowtype;
  v_hidden_id bigint;
  v_expected_result text;
  v_origin_ok boolean:=false;
  v_hidden_ok boolean:=false;
begin
  select ex.id,ex.head_sha,g.gate_codigo,ev.id,ev.sha256,ev.source_ref,
         ev.metadata->'worker_v10_receipt'
    into v_execution_id,v_base_head_sha,v_gate_code,v_evidence_id,v_evidence_sha256,
         v_source_ref,v_receipt
  from programacion.evaluaciones eva
  join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id
  join programacion.ejecuciones ex on ex.id=obj.execution_id
  join programacion.gates g on g.id=obj.gate_id
  join programacion.evidencias ev on ev.evaluacion_id=eva.id
  where eva.id=p_evaluation_id
    and ex.request_ref='agent-task://21'
    and g.gate_codigo in(
      'G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY',
      'G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY'
    )
    and ev.tipo='WORKER_V10_VALIDATION_RECEIPT'
    and ev.source_system='STORY_AGENT_WORKER_V10_RUNNER'
  order by ev.id desc
  limit 1;

  if v_execution_id is null then
    return jsonb_build_object('applicable',false,'origin_ok',false,'hidden_ok',false);
  end if;

  v_candidate_head_sha:=v_receipt->>'candidate_head_sha';
  if coalesce(v_candidate_head_sha,'')!~'^[0-9a-f]{40}$' then
    return jsonb_build_object(
      'applicable',true,'origin_ok',false,'hidden_ok',false,
      'reason','WORKER_V10_CANDIDATE_HEAD_INVALID'
    );
  end if;

  v_expected_result:=case v_gate_code
    when 'G_WORKER_SOURCE_IDENTITY' then v_receipt#>>'{source_identity,status}'
    when 'G_WORKER_PATCH_POLICY' then v_receipt#>>'{patch_policy,status}'
    when 'G_WORKER_ACCEPTANCE' then
      case when v_receipt#>>'{visible_acceptance,status}'='PASS'
             and v_receipt#>>'{hidden_acceptance,status}'='PASS'
           then 'PASS' else 'FAIL' end
    when 'G_WORKER_DELIVERY_BOUNDARY' then
      case when v_receipt#>>'{delivery_boundary,status}'='PASS'
             and v_receipt#>>'{visible_acceptance,status}'='PASS'
             and v_receipt#>>'{hidden_acceptance,status}'='PASS'
           then 'PASS' else 'FAIL' end
    else 'FAIL'
  end;
  if v_expected_result not in('PASS','FAIL','BLOCKED') then
    v_expected_result:='FAIL';
  end if;

  select a.*,c.*
    into v_origin,v_origin_challenge
  from programacion.authority_attestations a
  join programacion.authority_challenges c on c.id=a.challenge_id
  where a.authority_role='programacion_verifier'
    and c.repo_full_name='cristhianlujan/libertad-financiera'
    and c.head_sha=v_candidate_head_sha
    and c.purpose='STORY_AGENT_WORKER_V10_ORIGIN_V1'
    and a.attestation_payload->>'schema_version'='1'
    and a.attestation_payload->>'authority_scope'='WORKER_V10_ORIGIN'
    and a.attestation_payload->>'verdict'='PASS'
    and a.attestation_payload->'independent'='true'::jsonb
    and a.attestation_payload->'github_run_observed'='true'::jsonb
    and a.attestation_payload->'receipt_observed'='true'::jsonb
    and a.attestation_payload->>'execution_id'=v_execution_id::text
    and a.attestation_payload->>'base_head_sha'=v_base_head_sha
    and a.attestation_payload->>'candidate_head_sha'=v_candidate_head_sha
    and a.attestation_payload->>'source_ref'=v_source_ref
    and a.attestation_payload->>'receipt_sha256'=v_evidence_sha256
    and a.attestation_payload->>'source_identity_status'=coalesce(v_receipt#>>'{source_identity,status}','')
    and a.attestation_payload->>'patch_policy_status'=coalesce(v_receipt#>>'{patch_policy,status}','')
    and a.attestation_payload->>'visible_acceptance_status'=coalesce(v_receipt#>>'{visible_acceptance,status}','')
    and a.attestation_payload->>'hidden_acceptance_status'=coalesce(v_receipt#>>'{hidden_acceptance,status}','')
    and a.attestation_payload->>'delivery_boundary_status'=coalesce(v_receipt#>>'{delivery_boundary,status}','')
    and a.attestation_payload->>'hidden_result_sha256'=coalesce(v_receipt#>>'{hidden_acceptance,result_sha256}','')
  order by a.id desc
  limit 1;

  v_origin_ok:=v_origin.id is not null;

  if v_origin_ok
     and coalesce(v_origin.attestation_payload->>'hidden_authority_attestation_id','')~'^[0-9]+$' then
    v_hidden_id:=(v_origin.attestation_payload->>'hidden_authority_attestation_id')::bigint;
    select a.*,c.*
      into v_hidden,v_hidden_challenge
    from programacion.authority_attestations a
    join programacion.authority_challenges c on c.id=a.challenge_id
    where a.id=v_hidden_id
      and a.authority_role='programacion_auditor'
      and c.repo_full_name='cristhianlujan/programming-agent'
      and c.purpose='PROGRAMMING_AGENT_HIDDEN_AUTHORITY_AUD24_F03_V1'
      and a.attestation_payload->>'schema_version'='1'
      and a.attestation_payload->>'authority_scope'='HIDDEN_ORACLE_AUDIT'
      and a.attestation_payload->>'finding_code'='AUD24-F03'
      and a.attestation_payload->>'verdict'='PASS'
      and a.attestation_payload->'independent'='true'::jsonb
      and a.attestation_payload->'semantic_nonreconstructibility_verified'='true'::jsonb
      and a.attestation_payload->'replay_binding_verified'='true'::jsonb
      and a.attestation_payload->'hidden_output_nonexposure_verified'='true'::jsonb
      and a.attestation_payload->>'audited_head_sha'=c.head_sha
      and coalesce(a.attestation_payload->>'broker_function_sha256','')~'^[0-9a-f]{64}$'
      and coalesce(a.attestation_payload->>'broker_policy_id','')~'^[0-9a-f]{64}$'
      and coalesce(a.attestation_payload->>'receipt_contract_version','')~'^[0-9]+$'
      and (a.attestation_payload->>'receipt_contract_version')::integer>=3;
    v_hidden_ok:=v_hidden.id is not null;
  end if;

  return jsonb_build_object(
    'applicable',true,
    'execution_id',v_execution_id,
    'gate_code',v_gate_code,
    'base_head_sha',v_base_head_sha,
    'candidate_head_sha',v_candidate_head_sha,
    'worker_evidence_id',v_evidence_id,
    'worker_receipt_sha256',v_evidence_sha256,
    'worker_source_ref',v_source_ref,
    'expected_result',v_expected_result,
    'origin_ok',v_origin_ok,
    'origin_attestation_id',v_origin.id,
    'origin_attestation_sha256',v_origin.attestation_sha256,
    'hidden_ok',v_hidden_ok,
    'hidden_authority_attestation_id',v_hidden.id,
    'hidden_authority_attestation_sha256',v_hidden.attestation_sha256
  );
end;
$function$;

create or replace function programacion.fn_guard_worker_v10_authority_materialization_v2()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_ctx jsonb;
  v_gate_code text;
  v_expected text;
begin
  if tg_op<>'UPDATE' or old.resultado<>'PENDING' or new.resultado='PENDING' then
    return new;
  end if;

  v_ctx:=programacion.fn_agent_task_worker_v10_authority_context_v2(old.id);
  if coalesce((v_ctx->>'applicable')::boolean,false)=false then
    return new;
  end if;

  v_gate_code:=v_ctx->>'gate_code';
  v_expected:=v_ctx->>'expected_result';

  if coalesce((v_ctx->>'origin_ok')::boolean,false)=false then
    raise exception 'WORKER_V10_EXTERNAL_ORIGIN_ATTESTATION_REQUIRED:%',old.id;
  end if;
  if new.resultado is distinct from v_expected then
    raise exception 'WORKER_V10_TERMINAL_RESULT_MISMATCH: evaluation=% expected=% got=%',old.id,v_expected,new.resultado;
  end if;
  if v_gate_code in('G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY')
     and coalesce((v_ctx->>'hidden_ok')::boolean,false)=false then
    raise exception 'WORKER_V10_INDEPENDENT_HIDDEN_AUTHORITY_REQUIRED:%',old.id;
  end if;

  new.detalles:=coalesce(new.detalles,'{}'::jsonb)||jsonb_build_object(
    'worker_origin_authority_attestation_id',(v_ctx->>'origin_attestation_id')::bigint,
    'worker_origin_authority_attestation_sha256',v_ctx->>'origin_attestation_sha256',
    'hidden_authority_attestation_id',case
      when nullif(v_ctx->>'hidden_authority_attestation_id','') is null then null
      else (v_ctx->>'hidden_authority_attestation_id')::bigint end,
    'hidden_authority_attestation_sha256',v_ctx->>'hidden_authority_attestation_sha256',
    'authority_hardening_contract','WORKER_V10_AUTHORITY_HARDENING_V2'
  );
  return new;
end;
$function$;

revoke all on function programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)
  from public,anon,authenticated,programacion_builder;
revoke all on function programacion.fn_guard_worker_v10_authority_materialization_v2()
  from public,anon,authenticated,programacion_builder;
grant execute on function programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)
  to programacion_verifier,programacion_auditor,postgres;

drop trigger if exists trg_evaluaciones_worker_v10_authority_guard on programacion.evaluaciones;
create trigger trg_evaluaciones_worker_v10_authority_guard
before update of resultado on programacion.evaluaciones
for each row
execute function programacion.fn_guard_worker_v10_authority_materialization_v2();

-- Fail closed until an external verifier attestation exists; no execution 91 mutation.
do $selftest$
declare v jsonb;
begin
  v:=programacion.fn_agent_task_worker_v10_authority_context_v2(-1);
  if coalesce((v->>'applicable')::boolean,true) then
    raise exception 'SELFTEST_WORKER_V10_AUTHORITY_NONAPPLICABLE_FAILED';
  end if;
  if has_function_privilege('programacion_builder','programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)','EXECUTE') then
    raise exception 'SELFTEST_WORKER_V10_AUTHORITY_CONTEXT_EXPOSED_TO_BUILDER';
  end if;
end;
$selftest$;
