create or replace function programacion.fn_agent_task_worker_v10_authority_context_v2(p_evaluation_id bigint)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','programacion'
as $$
declare
  v_execution_id bigint;
  v_base_head_sha text;
  v_repo_full_name text;
  v_request_ref text;
  v_gate_code text;
  v_evidence_id bigint;
  v_evidence_sha256 text;
  v_source_ref text;
  v_receipt jsonb;
  v_candidate_head_sha text;
  v_task_id bigint;
  v_current_task_id bigint;
  v_task programacion.agent_tasks%rowtype;
  v_origin_id bigint;
  v_origin_sha256 text;
  v_origin_payload jsonb;
  v_hidden_id bigint;
  v_hidden_sha256 text;
  v_hidden_payload jsonb;
  v_expected_result text;
  v_current_task_ok boolean:=false;
  v_origin_ok boolean:=false;
  v_hidden_ok boolean:=false;
begin
  select ex.id,ex.head_sha,ex.repo_full_name,ex.request_ref,g.gate_codigo,ev.id,ev.sha256,ev.source_ref,ev.metadata->'worker_v10_receipt'
    into v_execution_id,v_base_head_sha,v_repo_full_name,v_request_ref,v_gate_code,v_evidence_id,v_evidence_sha256,v_source_ref,v_receipt
  from programacion.evaluaciones eva
  join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id
  join programacion.ejecuciones ex on ex.id=obj.execution_id
  join programacion.gates g on g.id=obj.gate_id
  join programacion.evidencias ev on ev.evaluacion_id=eva.id
  where eva.id=p_evaluation_id
    and ex.request_ref~'^agent-task://[1-9][0-9]*$'
    and g.gate_codigo in('G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY','G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY')
    and ev.tipo='WORKER_V10_VALIDATION_RECEIPT'
    and ev.source_system='STORY_AGENT_WORKER_V10_RUNNER'
  order by ev.id desc limit 1;

  if v_execution_id is null then return jsonb_build_object('applicable',false,'current_task_ok',false,'origin_ok',false,'hidden_ok',false); end if;

  begin v_task_id:=substring(v_request_ref from 14)::bigint;
  exception when others then return jsonb_build_object('applicable',true,'current_task_ok',false,'origin_ok',false,'hidden_ok',false,'reason','WORKER_V10_AGENT_TASK_REF_INVALID'); end;

  select * into v_task from programacion.agent_tasks where id=v_task_id;
  if v_task.id is null then return jsonb_build_object('applicable',true,'agent_task_id',v_task_id,'current_task_ok',false,'origin_ok',false,'hidden_ok',false,'reason','WORKER_V10_AGENT_TASK_NOT_FOUND'); end if;

  select t.id into v_current_task_id from programacion.agent_tasks t
  where t.task_code=v_task.task_code and t.definition_status='SEALED'
  order by t.task_version desc,t.id desc limit 1;
  v_current_task_ok:=v_task.definition_status='SEALED' and v_current_task_id=v_task.id;

  v_candidate_head_sha:=v_receipt->>'candidate_head_sha';
  if coalesce(v_candidate_head_sha,'')!~'^[0-9a-f]{40}$' then
    return jsonb_build_object('applicable',true,'agent_task_id',v_task_id,'current_task_id',v_current_task_id,'current_task_ok',v_current_task_ok,'origin_ok',false,'hidden_ok',false,'reason','WORKER_V10_CANDIDATE_HEAD_INVALID');
  end if;

  v_expected_result:=case v_gate_code
    when 'G_WORKER_SOURCE_IDENTITY' then v_receipt#>>'{source_identity,status}'
    when 'G_WORKER_PATCH_POLICY' then v_receipt#>>'{patch_policy,status}'
    when 'G_WORKER_ACCEPTANCE' then case when v_receipt#>>'{visible_acceptance,status}'='PASS' and v_receipt#>>'{hidden_acceptance,status}'='PASS' then 'PASS' else 'FAIL' end
    when 'G_WORKER_DELIVERY_BOUNDARY' then case when v_receipt#>>'{delivery_boundary,status}'='PASS' and v_receipt#>>'{visible_acceptance,status}'='PASS' and v_receipt#>>'{hidden_acceptance,status}'='PASS' then 'PASS' else 'FAIL' end
    else 'FAIL' end;
  if v_expected_result not in('PASS','FAIL','BLOCKED') then v_expected_result:='FAIL'; end if;

  if v_current_task_ok then
    select a.id,a.attestation_sha256,a.attestation_payload into v_origin_id,v_origin_sha256,v_origin_payload
    from programacion.authority_attestations a join programacion.authority_challenges c on c.id=a.challenge_id
    where a.authority_role='programacion_verifier'
      and c.repo_full_name=v_repo_full_name
      and c.head_sha=v_candidate_head_sha
      and c.purpose='STORY_AGENT_WORKER_V10_ORIGIN_V1'
      and a.attestation_payload->>'schema_version'='2'
      and a.attestation_payload->>'authority_scope'='WORKER_V10_ORIGIN'
      and a.attestation_payload->>'verdict'='PASS'
      and a.attestation_payload->'independent'='true'::jsonb
      and a.attestation_payload->'github_run_observed'='true'::jsonb
      and a.attestation_payload->'receipt_observed'='true'::jsonb
      and a.attestation_payload->>'execution_id'=v_execution_id::text
      and a.attestation_payload->>'agent_task_id'=v_task.id::text
      and a.attestation_payload->>'task_code'=v_task.task_code
      and a.attestation_payload->>'task_version'=v_task.task_version::text
      and a.attestation_payload->>'task_sha256'=coalesce(v_task.task_sha256,'')
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
    order by a.id desc limit 1;
    v_origin_ok:=v_origin_id is not null;
  end if;

  if v_origin_ok and coalesce(v_origin_payload->>'hidden_authority_attestation_id','')~'^[0-9]+$' then
    v_hidden_id:=(v_origin_payload->>'hidden_authority_attestation_id')::bigint;
    select a.attestation_sha256,a.attestation_payload into v_hidden_sha256,v_hidden_payload
    from programacion.authority_attestations a join programacion.authority_challenges c on c.id=a.challenge_id
    where a.id=v_hidden_id and a.authority_role='programacion_auditor'
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
    v_hidden_ok:=v_hidden_sha256 is not null;
  end if;

  return jsonb_build_object('applicable',true,'execution_id',v_execution_id,'gate_code',v_gate_code,'agent_task_id',v_task.id,'task_code',v_task.task_code,'task_version',v_task.task_version,'task_sha256',v_task.task_sha256,'current_task_id',v_current_task_id,'current_task_ok',v_current_task_ok,'base_head_sha',v_base_head_sha,'candidate_head_sha',v_candidate_head_sha,'worker_evidence_id',v_evidence_id,'worker_receipt_sha256',v_evidence_sha256,'worker_source_ref',v_source_ref,'expected_result',v_expected_result,'origin_ok',v_origin_ok,'origin_attestation_id',v_origin_id,'origin_attestation_sha256',v_origin_sha256,'hidden_ok',v_hidden_ok,'hidden_authority_attestation_id',case when v_hidden_ok then v_hidden_id else null end,'hidden_authority_attestation_sha256',v_hidden_sha256);
end;
$$;

create or replace function programacion.fn_guard_worker_v10_authority_materialization_v2()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare v_ctx jsonb;v_gate_code text;v_expected text;
begin
  if tg_op<>'UPDATE' or old.resultado<>'PENDING' or new.resultado='PENDING' then return new; end if;
  v_ctx:=programacion.fn_agent_task_worker_v10_authority_context_v2(old.id);
  if coalesce((v_ctx->>'applicable')::boolean,false)=false then return new; end if;
  if coalesce((v_ctx->>'current_task_ok')::boolean,false)=false then raise exception 'WORKER_V10_CURRENT_AGENT_TASK_REQUIRED: evaluation=% task=% current=%',old.id,coalesce(v_ctx->>'agent_task_id','?'),coalesce(v_ctx->>'current_task_id','?'); end if;
  v_gate_code:=v_ctx->>'gate_code';v_expected:=v_ctx->>'expected_result';
  if coalesce((v_ctx->>'origin_ok')::boolean,false)=false then raise exception 'WORKER_V10_EXTERNAL_ORIGIN_ATTESTATION_REQUIRED:%',old.id; end if;
  if new.resultado is distinct from v_expected then raise exception 'WORKER_V10_TERMINAL_RESULT_MISMATCH: evaluation=% expected=% got=%',old.id,v_expected,new.resultado; end if;
  if v_gate_code in('G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY') and coalesce((v_ctx->>'hidden_ok')::boolean,false)=false then raise exception 'WORKER_V10_INDEPENDENT_HIDDEN_AUTHORITY_REQUIRED:%',old.id; end if;
  new.detalles:=coalesce(new.detalles,'{}'::jsonb)||jsonb_build_object('agent_task_id',(v_ctx->>'agent_task_id')::bigint,'task_sha256',v_ctx->>'task_sha256','worker_origin_authority_attestation_id',(v_ctx->>'origin_attestation_id')::bigint,'worker_origin_authority_attestation_sha256',v_ctx->>'origin_attestation_sha256','hidden_authority_attestation_id',case when nullif(v_ctx->>'hidden_authority_attestation_id','') is null then null else (v_ctx->>'hidden_authority_attestation_id')::bigint end,'hidden_authority_attestation_sha256',v_ctx->>'hidden_authority_attestation_sha256','authority_hardening_contract','WORKER_V10_AUTHORITY_HARDENING_V3');
  return new;
end;
$$;