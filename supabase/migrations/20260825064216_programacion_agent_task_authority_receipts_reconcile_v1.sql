-- Reconcile Story Agent authority with PROG-ADR-AUTH-001.
-- PostgreSQL LOGIN/session principals are not operational authority gates.
-- Reuse receipt-backed provenance: EVIDENCE_VERIFIER_V1 for Worker v10 evidence
-- and INDEPENDENT_AUDITOR_V1 for AUD24-F03 hidden-oracle audit.
-- authority_challenges/authority_attestations remain historical only.

create or replace function programacion.fn_agent_task_pending_worker_v10_evidence_v1(p_task_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_task programacion.agent_tasks%rowtype;
  v_current_task_id bigint;
  v jsonb;
begin
  if p_task_id is null or p_task_id < 1 then
    raise exception 'AGENT_TASK_ID_INVALID';
  end if;

  select * into v_task from programacion.agent_tasks where id=p_task_id;
  if v_task.id is null then raise exception 'AGENT_TASK_NOT_FOUND:%',p_task_id; end if;
  if v_task.definition_status<>'SEALED' then raise exception 'AGENT_TASK_SEALED_REQUIRED:%',p_task_id; end if;

  select t.id into v_current_task_id
  from programacion.agent_tasks t
  where t.task_code=v_task.task_code and t.definition_status='SEALED'
  order by t.task_version desc,t.id desc
  limit 1;
  if v_current_task_id is distinct from p_task_id then
    raise exception 'AGENT_TASK_CURRENT_VERSION_REQUIRED:% current=%',p_task_id,v_current_task_id;
  end if;

  select coalesce(jsonb_agg(x.payload order by x.evidence_id),'[]'::jsonb) into v
  from (
    select ev.id as evidence_id,
           jsonb_build_object(
             'execution_id',ex.id,
             'request_ref',ex.request_ref,
             'agent_task_id',v_task.id,
             'task_code',v_task.task_code,
             'task_version',v_task.task_version,
             'task_sha256',v_task.task_sha256,
             'head_sha',ex.head_sha,
             'evaluation_id',eva.id,
             'gate_code',g.gate_codigo,
             'evidence_id',ev.id,
             'evidence_sha256',ev.sha256,
             'source_system',ev.source_system,
             'source_ref',ev.source_ref,
             'candidate_head_sha',ev.metadata#>>'{worker_v10_receipt,candidate_head_sha}',
             'worker_receipt_status',case
               when g.gate_codigo='G_WORKER_SOURCE_IDENTITY' then ev.metadata#>>'{worker_v10_receipt,source_identity,status}'
               when g.gate_codigo='G_WORKER_PATCH_POLICY' then ev.metadata#>>'{worker_v10_receipt,patch_policy,status}'
               when g.gate_codigo='G_WORKER_ACCEPTANCE' then case
                 when ev.metadata#>>'{worker_v10_receipt,visible_acceptance,status}'='PASS'
                  and ev.metadata#>>'{worker_v10_receipt,hidden_acceptance,status}'='PASS' then 'PASS' else 'FAIL' end
               when g.gate_codigo='G_WORKER_DELIVERY_BOUNDARY' then case
                 when ev.metadata#>>'{worker_v10_receipt,delivery_boundary,status}'='PASS'
                  and ev.metadata#>>'{worker_v10_receipt,visible_acceptance,status}'='PASS'
                  and ev.metadata#>>'{worker_v10_receipt,hidden_acceptance,status}'='PASS' then 'PASS' else 'FAIL' end
               else 'FAIL' end
           ) as payload
    from programacion.ejecuciones ex
    join programacion.objetivos_ejecucion obj on obj.execution_id=ex.id
    join programacion.gates g on g.id=obj.gate_id
    join programacion.evaluaciones eva on eva.objetivo_id=obj.id and eva.resultado='PENDING'
    join programacion.evidencias ev on ev.evaluacion_id=eva.id
    where ex.request_ref='agent-task://'||p_task_id::text
      and ex.estado='RUNNING'
      and g.gate_codigo in(
        'G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY',
        'G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY'
      )
      and ev.tipo='WORKER_V10_VALIDATION_RECEIPT'
      and ev.source_system='STORY_AGENT_WORKER_V10_RUNNER'
      and jsonb_typeof(ev.metadata->'worker_v10_receipt')='object'
      and coalesce(ev.metadata#>>'{worker_v10_receipt,candidate_head_sha}','')~'^[0-9a-f]{40}$'
      and not exists(
        select 1 from programacion.evidence_verifications vv
        where vv.evidence_id=ev.id and vv.verification_status='VERIFIED'
      )
  ) x;

  if v='[]'::jsonb then
    raise exception 'PENDING_WORKER_V10_EVIDENCE_NOT_FOUND: agent-task://%',p_task_id;
  end if;
  return v;
end;
$function$;

create or replace function programacion.fn_external_verify_worker_v10_evidence_v1(
  p_execution_id bigint,
  p_evidence_id bigint,
  p_expected_head_sha text,
  p_expected_evidence_sha256 text,
  p_expected_source_system text,
  p_expected_source_ref text,
  p_verification_method text,
  p_verifier_identity text,
  p_verification_payload jsonb,
  p_verification_ref text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_ex programacion.ejecuciones%rowtype;
  v_ev programacion.evidencias%rowtype;
  v_eval_status text;
  v_eval_id bigint;
  v_gate_code text;
  v_task_id bigint;
  v_current_task_id bigint;
  v_task programacion.agent_tasks%rowtype;
  v_receipt jsonb;
  v_candidate_head_sha text;
  v_token text;
  v_channel_hash text;
  v_token_hash text;
  v_subject_sha text;
  v_receipt_id bigint;
  v_receipt_sha text;
  v_verification_id bigint;
  v_verification_sha text;
  v_subject_payload jsonb;
  v_receipt_payload jsonb;
begin
  if p_verification_payload is null or jsonb_typeof(p_verification_payload)<>'object' then
    raise exception 'EXTERNAL_V10_VERIFICATION_PAYLOAD_REQUIRED';
  end if;
  if p_verification_method <> 'GITHUB_ACTIONS_OIDC_WORKER_V10_EVIDENCE_V1' then
    raise exception 'EXTERNAL_V10_VERIFICATION_METHOD_INVALID';
  end if;
  if p_verifier_identity !~ '^github-actions://cristhianlujan/claude-persona-lf-patch/\\.github/workflows/story-agent-evidence-verifier\\.yml@refs/heads/main#run-[0-9]+$' then
    raise exception 'EXTERNAL_V10_VERIFIER_IDENTITY_INVALID';
  end if;
  if length(btrim(coalesce(p_verification_ref,'')))=0 then
    raise exception 'EXTERNAL_V10_VERIFICATION_REF_REQUIRED';
  end if;

  select * into v_ex from programacion.ejecuciones where id=p_execution_id;
  if not found then raise exception 'EXTERNAL_V10_VERIFY_EXECUTION_NOT_FOUND'; end if;
  if v_ex.estado<>'RUNNING' or v_ex.request_ref!~'^agent-task://[1-9][0-9]*$' then
    raise exception 'EXTERNAL_V10_VERIFY_AGENT_TASK_RUNNING_REQUIRED';
  end if;
  if v_ex.head_sha is distinct from p_expected_head_sha then
    raise exception 'EXTERNAL_V10_VERIFY_HEAD_MISMATCH';
  end if;

  begin
    v_task_id:=substring(v_ex.request_ref from 14)::bigint;
  exception when others then
    raise exception 'EXTERNAL_V10_VERIFY_AGENT_TASK_REF_INVALID';
  end;
  select * into v_task from programacion.agent_tasks where id=v_task_id;
  if v_task.id is null or v_task.definition_status<>'SEALED' then
    raise exception 'EXTERNAL_V10_VERIFY_CURRENT_TASK_REQUIRED:%',v_task_id;
  end if;
  select t.id into v_current_task_id
  from programacion.agent_tasks t
  where t.task_code=v_task.task_code and t.definition_status='SEALED'
  order by t.task_version desc,t.id desc limit 1;
  if v_current_task_id is distinct from v_task_id then
    raise exception 'EXTERNAL_V10_VERIFY_CURRENT_TASK_REQUIRED:% current=%',v_task_id,v_current_task_id;
  end if;

  select ev.* into v_ev
  from programacion.evidencias ev
  join programacion.evaluaciones eva on eva.id=ev.evaluacion_id
  join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id and obj.execution_id=v_ex.id
  where ev.id=p_evidence_id;
  if not found then raise exception 'EXTERNAL_V10_VERIFY_EVIDENCE_NOT_FOUND'; end if;

  select eva.resultado,eva.id,g.gate_codigo
    into v_eval_status,v_eval_id,v_gate_code
  from programacion.evaluaciones eva
  join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id
  join programacion.gates g on g.id=obj.gate_id
  where eva.id=v_ev.evaluacion_id and obj.execution_id=v_ex.id;
  if not found then raise exception 'EXTERNAL_V10_VERIFY_EVALUATION_BINDING_NOT_FOUND'; end if;
  if v_eval_status<>'PENDING' then raise exception 'EXTERNAL_V10_VERIFY_EVALUATION_PENDING_REQUIRED'; end if;
  if v_gate_code not in(
    'G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY',
    'G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY'
  ) then raise exception 'EXTERNAL_V10_VERIFY_GATE_NOT_ALLOWED'; end if;
  if v_ev.tipo<>'WORKER_V10_VALIDATION_RECEIPT' then raise exception 'EXTERNAL_V10_VERIFY_RECEIPT_REQUIRED'; end if;
  if v_ev.sha256 is distinct from p_expected_evidence_sha256 then raise exception 'EXTERNAL_V10_VERIFY_EVIDENCE_SHA_MISMATCH'; end if;
  if v_ev.source_system is distinct from p_expected_source_system then raise exception 'EXTERNAL_V10_VERIFY_SOURCE_SYSTEM_MISMATCH'; end if;
  if v_ev.source_ref is distinct from p_expected_source_ref then raise exception 'EXTERNAL_V10_VERIFY_SOURCE_REF_MISMATCH'; end if;
  if v_ev.source_system<>'STORY_AGENT_WORKER_V10_RUNNER' then raise exception 'EXTERNAL_V10_VERIFY_SOURCE_REQUIRED'; end if;
  if p_verifier_identity=v_ev.source_system or p_verifier_identity=v_ev.source_ref then
    raise exception 'EXTERNAL_V10_VERIFY_SELF_VERIFICATION_FORBIDDEN';
  end if;

  v_receipt:=v_ev.metadata->'worker_v10_receipt';
  if v_receipt is null or jsonb_typeof(v_receipt)<>'object' then
    raise exception 'EXTERNAL_V10_VERIFY_RECEIPT_OBJECT_REQUIRED';
  end if;
  v_candidate_head_sha:=v_receipt->>'candidate_head_sha';
  if coalesce(v_candidate_head_sha,'')!~'^[0-9a-f]{40}$' then
    raise exception 'EXTERNAL_V10_VERIFY_CANDIDATE_HEAD_INVALID';
  end if;
  if coalesce(v_receipt#>>'{source_identity,status}','') not in ('PASS','FAIL','BLOCKED')
     or coalesce(v_receipt#>>'{patch_policy,status}','') not in ('PASS','FAIL','BLOCKED')
     or coalesce(v_receipt#>>'{visible_acceptance,status}','') not in ('PASS','FAIL','BLOCKED')
     or coalesce(v_receipt#>>'{hidden_acceptance,status}','') not in ('PASS','FAIL','BLOCKED')
     or coalesce(v_receipt#>>'{delivery_boundary,status}','') not in ('PASS','FAIL','BLOCKED') then
    raise exception 'EXTERNAL_V10_VERIFY_STATUS_INVALID';
  end if;
  if v_receipt#>>'{hidden_acceptance,status}'='PASS'
     and coalesce(v_receipt#>>'{hidden_acceptance,result_sha256}','')!~'^[0-9a-f]{64}$' then
    raise exception 'EXTERNAL_V10_VERIFY_HIDDEN_RESULT_SHA_INVALID';
  end if;

  if p_verification_payload->>'execution_id' is distinct from v_ex.id::text
     or p_verification_payload->>'agent_task_id' is distinct from v_task.id::text
     or p_verification_payload->>'task_code' is distinct from v_task.task_code
     or p_verification_payload->>'task_version' is distinct from v_task.task_version::text
     or p_verification_payload->>'task_sha256' is distinct from coalesce(v_task.task_sha256,'')
     or p_verification_payload->>'evidence_id' is distinct from v_ev.id::text
     or p_verification_payload->>'head_sha' is distinct from v_ex.head_sha
     or p_verification_payload->>'candidate_head_sha' is distinct from v_candidate_head_sha
     or p_verification_payload->>'evidence_sha256' is distinct from v_ev.sha256
     or p_verification_payload->>'source_system' is distinct from v_ev.source_system
     or p_verification_payload->>'source_ref' is distinct from v_ev.source_ref
     or p_verification_payload->>'verification_status' is distinct from 'VERIFIED'
     or p_verification_payload->>'verifier_identity' is distinct from p_verifier_identity then
    raise exception 'EXTERNAL_V10_VERIFY_PAYLOAD_IDENTITY_MISMATCH';
  end if;
  if exists(
    select 1 from programacion.evidence_verifications
    where evidence_id=v_ev.id and verification_status='VERIFIED'
  ) then raise exception 'EXTERNAL_V10_VERIFY_DUPLICATE_VERIFIED_EVIDENCE'; end if;

  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='EVIDENCE_VERIFIER_V1_TOKEN'
  order by created_at desc limit 1;
  if length(coalesce(v_token,''))<32 then raise exception 'EVIDENCE_VERIFIER_V1_VAULT_SECRET_MISSING'; end if;
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex');
  select secret_sha256 into v_channel_hash
  from programacion.provenance_channels where channel_code='EVIDENCE_VERIFIER_V1';
  if v_channel_hash is distinct from v_token_hash then
    raise exception 'EVIDENCE_VERIFIER_V1_VAULT_CHANNEL_HASH_MISMATCH';
  end if;

  v_subject_payload:=jsonb_build_object(
    'evidence_id',v_ev.id,
    'evidence_sha256',v_ev.sha256,
    'source_system',v_ev.source_system,
    'source_ref',v_ev.source_ref,
    'verification_status','VERIFIED',
    'verification_method',p_verification_method,
    'verifier_identity',p_verifier_identity,
    'verification_payload',p_verification_payload
  );
  v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_subject_payload);
  v_receipt_payload:=p_verification_payload||jsonb_build_object(
    'execution_id',v_ex.id,
    'head_sha',v_ex.head_sha,
    'subject_type','evidence_verification',
    'subject_ref','evidence:'||v_ev.id::text,
    'subject_sha256',v_subject_sha,
    'verification_status','VERIFIED',
    'verifier_identity',p_verifier_identity
  );

  select id,receipt_sha256 into v_receipt_id,v_receipt_sha
  from programacion.issue_provenance_receipt(
    'EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',
    v_ex.id,v_ex.head_sha,'evidence_verification','evidence:'||v_ev.id::text,
    v_subject_sha,p_verifier_identity,p_verification_ref,v_receipt_payload
  );

  insert into programacion.evidence_verifications(
    evidence_id,evidence_sha256,source_system,source_ref,verification_status,
    verification_method,verifier_identity,verification_payload,authority_receipt_id
  ) values(
    v_ev.id,v_ev.sha256,v_ev.source_system,v_ev.source_ref,'VERIFIED',
    p_verification_method,p_verifier_identity,p_verification_payload,v_receipt_id
  ) returning id,verification_sha256 into v_verification_id,v_verification_sha;

  return jsonb_build_object(
    'status','VERIFIED',
    'execution_id',v_ex.id,
    'evaluation_id',v_eval_id,
    'gate_code',v_gate_code,
    'evidence_id',v_ev.id,
    'candidate_head_sha',v_candidate_head_sha,
    'authority_receipt_id',v_receipt_id,
    'authority_receipt_sha256',v_receipt_sha,
    'evidence_verification_id',v_verification_id,
    'evidence_verification_sha256',v_verification_sha
  );
end;
$function$;

create or replace function programacion.fn_guard_test_contract_hidden_authority_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_task programacion.agent_tasks%rowtype;
  v_subject_sha text;
  v_audit_receipt_id bigint;
begin
  if tg_op<>'UPDATE' or old.status<>'DRAFT' or new.status<>'SEALED' then return new; end if;

  select * into v_task from programacion.agent_tasks where id=new.task_id;
  if v_task.id is null or v_task.definition_status<>'SEALED' then
    raise exception 'TEST_CONTRACT_CURRENT_TASK_REQUIRED:%',new.task_id;
  end if;
  if exists(
    select 1 from programacion.agent_tasks t
    where t.task_code=v_task.task_code and t.definition_status='SEALED'
      and (t.task_version>v_task.task_version or (t.task_version=v_task.task_version and t.id>v_task.id))
  ) then raise exception 'TEST_CONTRACT_CURRENT_TASK_REQUIRED:%',new.task_id; end if;

  v_subject_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,
    'finding_code','AUD24-F03',
    'agent_task_id',v_task.id,
    'task_sha256',v_task.task_sha256,
    'hidden_oracle_ref',new.hidden_oracle_ref,
    'hidden_oracle_sha256',new.hidden_oracle_sha256,
    'generation_source_sha256',new.generation_source_sha256
  ));

  select pr.id into v_audit_receipt_id
  from programacion.provenance_receipts pr
  where pr.receipt_kind='AUDIT_VERDICT'
    and pr.execution_id is null
    and pr.issuer_channel='INDEPENDENT_AUDITOR_V1'
    and pr.subject_type='hidden_oracle_audit'
    and pr.subject_ref='agent-task://'||v_task.id::text||'/hidden-oracle'
    and pr.subject_sha256=v_subject_sha
    and pr.payload->>'verdict'='PASS'
    and pr.payload->'independent'='true'::jsonb
    and length(btrim(coalesce(pr.payload->>'auditor_identity','')))>0
    and pr.payload->>'finding_code'='AUD24-F03'
    and pr.payload->'semantic_nonreconstructibility_verified'='true'::jsonb
    and pr.payload->'replay_binding_verified'='true'::jsonb
    and pr.payload->'hidden_output_nonexposure_verified'='true'::jsonb
    and pr.payload->>'agent_task_id'=v_task.id::text
    and pr.payload->>'task_sha256'=coalesce(v_task.task_sha256,'')
    and pr.payload->>'hidden_oracle_ref'=new.hidden_oracle_ref
    and pr.payload->>'hidden_oracle_sha256'=new.hidden_oracle_sha256
    and pr.payload->>'generation_source_sha256'=new.generation_source_sha256
    and pr.payload->>'audited_head_sha'=pr.head_sha
    and coalesce(pr.payload->>'broker_function_sha256','')~'^[0-9a-f]{64}$'
    and coalesce(pr.payload->>'broker_policy_id','')~'^[0-9a-f]{64}$'
    and coalesce(pr.payload->>'receipt_contract_version','')~'^[0-9]+$'
    and (pr.payload->>'receipt_contract_version')::integer>=3
  order by pr.id desc limit 1;

  if v_audit_receipt_id is null then
    raise exception 'TEST_CONTRACT_INDEPENDENT_HIDDEN_AUTHORITY_REQUIRED:%',new.task_id;
  end if;
  return new;
end;
$function$;

create or replace function programacion.fn_agent_task_worker_v10_authority_context_v2(p_evaluation_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
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
  v_tc programacion.test_contracts%rowtype;
  v_origin_verification_id bigint;
  v_origin_verification_sha256 text;
  v_origin_receipt_id bigint;
  v_origin_receipt_sha256 text;
  v_hidden_subject_sha text;
  v_hidden_receipt_id bigint;
  v_hidden_receipt_sha256 text;
  v_expected_result text;
  v_current_task_ok boolean:=false;
  v_origin_ok boolean:=false;
  v_hidden_ok boolean:=false;
begin
  select ex.id,ex.head_sha,ex.repo_full_name,ex.request_ref,g.gate_codigo,
         ev.id,ev.sha256,ev.source_ref,ev.metadata->'worker_v10_receipt'
    into v_execution_id,v_base_head_sha,v_repo_full_name,v_request_ref,v_gate_code,
         v_evidence_id,v_evidence_sha256,v_source_ref,v_receipt
  from programacion.evaluaciones eva
  join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id
  join programacion.ejecuciones ex on ex.id=obj.execution_id
  join programacion.gates g on g.id=obj.gate_id
  join programacion.evidencias ev on ev.evaluacion_id=eva.id
  where eva.id=p_evaluation_id
    and ex.request_ref~'^agent-task://[1-9][0-9]*$'
    and g.gate_codigo in(
      'G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY',
      'G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY'
    )
    and ev.tipo='WORKER_V10_VALIDATION_RECEIPT'
    and ev.source_system='STORY_AGENT_WORKER_V10_RUNNER'
  order by ev.id desc limit 1;

  if v_execution_id is null then
    return jsonb_build_object('applicable',false,'current_task_ok',false,'origin_ok',false,'hidden_ok',false);
  end if;

  begin
    v_task_id:=substring(v_request_ref from 14)::bigint;
  exception when others then
    return jsonb_build_object(
      'applicable',true,'current_task_ok',false,'origin_ok',false,'hidden_ok',false,
      'reason','WORKER_V10_AGENT_TASK_REF_INVALID'
    );
  end;

  select * into v_task from programacion.agent_tasks where id=v_task_id;
  if v_task.id is null then
    return jsonb_build_object(
      'applicable',true,'agent_task_id',v_task_id,'current_task_ok',false,
      'origin_ok',false,'hidden_ok',false,'reason','WORKER_V10_AGENT_TASK_NOT_FOUND'
    );
  end if;

  select t.id into v_current_task_id
  from programacion.agent_tasks t
  where t.task_code=v_task.task_code and t.definition_status='SEALED'
  order by t.task_version desc,t.id desc limit 1;
  v_current_task_ok:=v_task.definition_status='SEALED' and v_current_task_id=v_task.id;

  v_candidate_head_sha:=v_receipt->>'candidate_head_sha';
  if coalesce(v_candidate_head_sha,'')!~'^[0-9a-f]{40}$' then
    return jsonb_build_object(
      'applicable',true,'agent_task_id',v_task_id,'current_task_id',v_current_task_id,
      'current_task_ok',v_current_task_ok,'origin_ok',false,'hidden_ok',false,
      'reason','WORKER_V10_CANDIDATE_HEAD_INVALID'
    );
  end if;

  v_expected_result:=case v_gate_code
    when 'G_WORKER_SOURCE_IDENTITY' then v_receipt#>>'{source_identity,status}'
    when 'G_WORKER_PATCH_POLICY' then v_receipt#>>'{patch_policy,status}'
    when 'G_WORKER_ACCEPTANCE' then case
      when v_receipt#>>'{visible_acceptance,status}'='PASS'
       and v_receipt#>>'{hidden_acceptance,status}'='PASS' then 'PASS' else 'FAIL' end
    when 'G_WORKER_DELIVERY_BOUNDARY' then case
      when v_receipt#>>'{delivery_boundary,status}'='PASS'
       and v_receipt#>>'{visible_acceptance,status}'='PASS'
       and v_receipt#>>'{hidden_acceptance,status}'='PASS' then 'PASS' else 'FAIL' end
    else 'FAIL' end;
  if v_expected_result not in('PASS','FAIL','BLOCKED') then v_expected_result:='FAIL'; end if;

  if v_current_task_ok then
    select vv.id,vv.verification_sha256,pr.id,pr.receipt_sha256
      into v_origin_verification_id,v_origin_verification_sha256,v_origin_receipt_id,v_origin_receipt_sha256
    from programacion.evidence_verifications vv
    join programacion.provenance_receipts pr on pr.id=vv.authority_receipt_id
    where vv.evidence_id=v_evidence_id
      and vv.verification_status='VERIFIED'
      and vv.evidence_sha256=v_evidence_sha256
      and vv.source_system='STORY_AGENT_WORKER_V10_RUNNER'
      and vv.source_ref=v_source_ref
      and vv.verification_method='GITHUB_ACTIONS_OIDC_WORKER_V10_EVIDENCE_V1'
      and pr.receipt_kind='EVIDENCE_VERIFICATION'
      and pr.execution_id=v_execution_id
      and pr.head_sha=v_base_head_sha
      and pr.issuer_channel='EVIDENCE_VERIFIER_V1'
      and pr.subject_type='evidence_verification'
      and pr.subject_ref='evidence:'||v_evidence_id::text
      and pr.payload->>'verification_status'='VERIFIED'
      and pr.payload->>'verifier_identity'=vv.verifier_identity
      and pr.payload->>'evidence_id'=v_evidence_id::text
      and pr.payload->>'evidence_sha256'=v_evidence_sha256
      and pr.payload->>'source_system'='STORY_AGENT_WORKER_V10_RUNNER'
      and pr.payload->>'source_ref'=v_source_ref
      and pr.payload->>'candidate_head_sha'=v_candidate_head_sha
    order by vv.id desc limit 1;
    v_origin_ok:=v_origin_verification_id is not null;
  end if;

  if v_current_task_ok then
    select * into v_tc
    from programacion.test_contracts
    where task_id=v_task.id and status='SEALED'
    limit 1;
    if v_tc.id is not null then
      v_hidden_subject_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
        'schema_version',1,
        'finding_code','AUD24-F03',
        'agent_task_id',v_task.id,
        'task_sha256',v_task.task_sha256,
        'hidden_oracle_ref',v_tc.hidden_oracle_ref,
        'hidden_oracle_sha256',v_tc.hidden_oracle_sha256,
        'generation_source_sha256',v_tc.generation_source_sha256
      ));
      select pr.id,pr.receipt_sha256 into v_hidden_receipt_id,v_hidden_receipt_sha256
      from programacion.provenance_receipts pr
      where pr.receipt_kind='AUDIT_VERDICT'
        and pr.execution_id is null
        and pr.issuer_channel='INDEPENDENT_AUDITOR_V1'
        and pr.subject_type='hidden_oracle_audit'
        and pr.subject_ref='agent-task://'||v_task.id::text||'/hidden-oracle'
        and pr.subject_sha256=v_hidden_subject_sha
        and pr.payload->>'verdict'='PASS'
        and pr.payload->'independent'='true'::jsonb
        and length(btrim(coalesce(pr.payload->>'auditor_identity','')))>0
        and pr.payload->>'finding_code'='AUD24-F03'
        and pr.payload->'semantic_nonreconstructibility_verified'='true'::jsonb
        and pr.payload->'replay_binding_verified'='true'::jsonb
        and pr.payload->'hidden_output_nonexposure_verified'='true'::jsonb
        and pr.payload->>'agent_task_id'=v_task.id::text
        and pr.payload->>'task_sha256'=coalesce(v_task.task_sha256,'')
        and pr.payload->>'hidden_oracle_ref'=v_tc.hidden_oracle_ref
        and pr.payload->>'hidden_oracle_sha256'=v_tc.hidden_oracle_sha256
        and pr.payload->>'generation_source_sha256'=v_tc.generation_source_sha256
        and pr.payload->>'audited_head_sha'=pr.head_sha
        and coalesce(pr.payload->>'broker_function_sha256','')~'^[0-9a-f]{64}$'
        and coalesce(pr.payload->>'broker_policy_id','')~'^[0-9a-f]{64}$'
        and coalesce(pr.payload->>'receipt_contract_version','')~'^[0-9]+$'
        and (pr.payload->>'receipt_contract_version')::integer>=3
      order by pr.id desc limit 1;
      v_hidden_ok:=v_hidden_receipt_id is not null;
    end if;
  end if;

  return jsonb_build_object(
    'applicable',true,
    'execution_id',v_execution_id,
    'gate_code',v_gate_code,
    'agent_task_id',v_task.id,
    'task_code',v_task.task_code,
    'task_version',v_task.task_version,
    'task_sha256',v_task.task_sha256,
    'current_task_id',v_current_task_id,
    'current_task_ok',v_current_task_ok,
    'base_head_sha',v_base_head_sha,
    'candidate_head_sha',v_candidate_head_sha,
    'worker_evidence_id',v_evidence_id,
    'worker_receipt_sha256',v_evidence_sha256,
    'worker_source_ref',v_source_ref,
    'expected_result',v_expected_result,
    'origin_ok',v_origin_ok,
    'origin_evidence_verification_id',v_origin_verification_id,
    'origin_evidence_verification_sha256',v_origin_verification_sha256,
    'origin_provenance_receipt_id',v_origin_receipt_id,
    'origin_provenance_receipt_sha256',v_origin_receipt_sha256,
    'hidden_ok',v_hidden_ok,
    'hidden_audit_receipt_id',v_hidden_receipt_id,
    'hidden_audit_receipt_sha256',v_hidden_receipt_sha256
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
  if tg_op<>'UPDATE' or old.resultado<>'PENDING' or new.resultado='PENDING' then return new; end if;

  v_ctx:=programacion.fn_agent_task_worker_v10_authority_context_v2(old.id);
  if coalesce((v_ctx->>'applicable')::boolean,false)=false then return new; end if;
  if coalesce((v_ctx->>'current_task_ok')::boolean,false)=false then
    raise exception 'WORKER_V10_CURRENT_AGENT_TASK_REQUIRED: evaluation=% task=% current=%',
      old.id,coalesce(v_ctx->>'agent_task_id','?'),coalesce(v_ctx->>'current_task_id','?');
  end if;

  v_gate_code:=v_ctx->>'gate_code';
  v_expected:=v_ctx->>'expected_result';

  if coalesce((v_ctx->>'origin_ok')::boolean,false)=false then
    raise exception 'WORKER_V10_EXTERNAL_ORIGIN_VERIFICATION_REQUIRED:%',old.id;
  end if;
  if new.resultado is distinct from v_expected then
    raise exception 'WORKER_V10_TERMINAL_RESULT_MISMATCH: evaluation=% expected=% got=%',old.id,v_expected,new.resultado;
  end if;
  if v_gate_code in('G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY')
     and coalesce((v_ctx->>'hidden_ok')::boolean,false)=false then
    raise exception 'WORKER_V10_INDEPENDENT_HIDDEN_AUTHORITY_REQUIRED:%',old.id;
  end if;

  new.detalles:=coalesce(new.detalles,'{}'::jsonb)||jsonb_build_object(
    'agent_task_id',(v_ctx->>'agent_task_id')::bigint,
    'task_sha256',v_ctx->>'task_sha256',
    'worker_origin_evidence_verification_id',(v_ctx->>'origin_evidence_verification_id')::bigint,
    'worker_origin_evidence_verification_sha256',v_ctx->>'origin_evidence_verification_sha256',
    'worker_origin_provenance_receipt_id',(v_ctx->>'origin_provenance_receipt_id')::bigint,
    'worker_origin_provenance_receipt_sha256',v_ctx->>'origin_provenance_receipt_sha256',
    'hidden_audit_receipt_id',case
      when nullif(v_ctx->>'hidden_audit_receipt_id','') is null then null
      else (v_ctx->>'hidden_audit_receipt_id')::bigint end,
    'hidden_audit_receipt_sha256',v_ctx->>'hidden_audit_receipt_sha256',
    'authority_hardening_contract','WORKER_V10_RECEIPT_AUTHORITY_V4'
  );
  return new;
end;
$function$;

create or replace function public.fn_agent_task_pending_worker_v10_evidence_v1(p_task_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.fn_agent_task_pending_worker_v10_evidence_v1(p_task_id);
$function$;

create or replace function public.fn_agent_task_external_verify_worker_v10_evidence_v1(
  p_execution_id bigint,p_evidence_id bigint,p_expected_head_sha text,p_expected_evidence_sha256 text,
  p_expected_source_system text,p_expected_source_ref text,p_verification_method text,p_verifier_identity text,
  p_verification_payload jsonb,p_verification_ref text
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.fn_external_verify_worker_v10_evidence_v1(
    p_execution_id,p_evidence_id,p_expected_head_sha,p_expected_evidence_sha256,
    p_expected_source_system,p_expected_source_ref,p_verification_method,p_verifier_identity,
    p_verification_payload,p_verification_ref
  );
$function$;

revoke all on function programacion.fn_agent_task_pending_worker_v10_evidence_v1(bigint) from public,anon,authenticated;
revoke all on function programacion.fn_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.fn_agent_task_pending_worker_v10_evidence_v1(bigint) from public,anon,authenticated;
revoke all on function public.fn_agent_task_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.fn_agent_task_pending_worker_v10_evidence_v1(bigint) to service_role;
grant execute on function public.fn_agent_task_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,text,jsonb,text) to service_role;

comment on table programacion.authority_challenges is
  'Historical authority-challenge evidence. Not an operational gate after PROG-ADR-AUTH-001.';
comment on table programacion.authority_attestations is
  'Historical authority-attestation evidence. Not required by Worker v10/Test Contract after PROG-ADR-AUTH-001; receipt-backed provenance is authoritative.';

do $selftest$
declare
  v_ctx jsonb;
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_agent_task_worker_v10_authority_context_v2';
  if v_def ilike '%authority_attestations%' or v_def ilike '%fn_assert_external_authority_session%' then
    raise exception 'SELFTEST_WORKER_V10_LEGACY_LOGIN_AUTHORITY_STILL_OPERATIONAL';
  end if;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_guard_test_contract_hidden_authority_v1';
  if v_def ilike '%authority_attestations%' or v_def ilike '%fn_assert_external_authority_session%' then
    raise exception 'SELFTEST_TEST_CONTRACT_LEGACY_LOGIN_AUTHORITY_STILL_OPERATIONAL';
  end if;

  if has_function_privilege('anon','public.fn_agent_task_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,text,jsonb,text)','EXECUTE')
     or has_function_privilege('authenticated','public.fn_agent_task_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,text,jsonb,text)','EXECUTE') then
    raise exception 'SELFTEST_WORKER_V10_EXTERNAL_VERIFIER_EXPOSED_TO_USER';
  end if;

  v_ctx:=programacion.fn_agent_task_worker_v10_authority_context_v2(-1);
  if coalesce((v_ctx->>'applicable')::boolean,true) then
    raise exception 'SELFTEST_WORKER_V10_AUTHORITY_NONAPPLICABLE_FAILED';
  end if;
end;
$selftest$;
