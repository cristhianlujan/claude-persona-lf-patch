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
  v_safe_payload jsonb;
  v_subject_sha text;
  v_receipt_id bigint;
  v_receipt_sha text;
  v_verification_id bigint;
  v_verification_sha text;
  v_subject_payload jsonb;
  v_receipt_payload jsonb;
begin
  if p_verification_payload is null or jsonb_typeof(p_verification_payload)<>'object' then raise exception 'EXTERNAL_V10_VERIFICATION_PAYLOAD_REQUIRED'; end if;
  v_token:=p_verification_payload->>'channel_token';
  if length(coalesce(v_token,''))<32 then raise exception 'EXTERNAL_V10_CHANNEL_TOKEN_REQUIRED'; end if;
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex');
  select secret_sha256 into v_channel_hash from programacion.provenance_channels where channel_code='EVIDENCE_VERIFIER_V1';
  if v_channel_hash is distinct from v_token_hash then raise exception 'EXTERNAL_V10_CHANNEL_TOKEN_MISMATCH'; end if;
  v_safe_payload:=p_verification_payload-'channel_token';
  if p_verification_method <> 'GITHUB_ACTIONS_OIDC_WORKER_V10_EVIDENCE_V1' then raise exception 'EXTERNAL_V10_VERIFICATION_METHOD_INVALID'; end if;
  if p_verifier_identity !~ '^github-actions://cristhianlujan/claude-persona-lf-patch/[.]github/workflows/story-agent-evidence-verifier[.]yml@refs/heads/main#run-[0-9]+$' then raise exception 'EXTERNAL_V10_VERIFIER_IDENTITY_INVALID'; end if;
  if length(btrim(coalesce(p_verification_ref,'')))=0 then raise exception 'EXTERNAL_V10_VERIFICATION_REF_REQUIRED'; end if;
  select * into v_ex from programacion.ejecuciones where id=p_execution_id;
  if not found then raise exception 'EXTERNAL_V10_VERIFY_EXECUTION_NOT_FOUND'; end if;
  if v_ex.estado<>'RUNNING' or v_ex.request_ref!~'^agent-task://[1-9][0-9]*$' then raise exception 'EXTERNAL_V10_VERIFY_AGENT_TASK_RUNNING_REQUIRED'; end if;
  if v_ex.head_sha is distinct from p_expected_head_sha then raise exception 'EXTERNAL_V10_VERIFY_HEAD_MISMATCH'; end if;
  begin v_task_id:=substring(v_ex.request_ref from 14)::bigint; exception when others then raise exception 'EXTERNAL_V10_VERIFY_AGENT_TASK_REF_INVALID'; end;
  select * into v_task from programacion.agent_tasks where id=v_task_id;
  if v_task.id is null or v_task.definition_status<>'SEALED' then raise exception 'EXTERNAL_V10_VERIFY_CURRENT_TASK_REQUIRED:%',v_task_id; end if;
  select t.id into v_current_task_id from programacion.agent_tasks t where t.task_code=v_task.task_code and t.definition_status='SEALED' order by t.task_version desc,t.id desc limit 1;
  if v_current_task_id is distinct from v_task_id then raise exception 'EXTERNAL_V10_VERIFY_CURRENT_TASK_REQUIRED:% current=%',v_task_id,v_current_task_id; end if;
  select ev.* into v_ev from programacion.evidencias ev join programacion.evaluaciones eva on eva.id=ev.evaluacion_id join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id and obj.execution_id=v_ex.id where ev.id=p_evidence_id;
  if not found then raise exception 'EXTERNAL_V10_VERIFY_EVIDENCE_NOT_FOUND'; end if;
  select eva.resultado,eva.id,g.gate_codigo into v_eval_status,v_eval_id,v_gate_code from programacion.evaluaciones eva join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id join programacion.gates g on g.id=obj.gate_id where eva.id=v_ev.evaluacion_id and obj.execution_id=v_ex.id;
  if not found then raise exception 'EXTERNAL_V10_VERIFY_EVALUATION_BINDING_NOT_FOUND'; end if;
  if v_eval_status<>'PENDING' then raise exception 'EXTERNAL_V10_VERIFY_EVALUATION_PENDING_REQUIRED'; end if;
  if v_gate_code not in('G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY','G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY') then raise exception 'EXTERNAL_V10_VERIFY_GATE_NOT_ALLOWED'; end if;
  if v_ev.tipo<>'WORKER_V10_VALIDATION_RECEIPT' then raise exception 'EXTERNAL_V10_VERIFY_RECEIPT_REQUIRED'; end if;
  if v_ev.sha256 is distinct from p_expected_evidence_sha256 then raise exception 'EXTERNAL_V10_VERIFY_EVIDENCE_SHA_MISMATCH'; end if;
  if v_ev.source_system is distinct from p_expected_source_system then raise exception 'EXTERNAL_V10_VERIFY_SOURCE_SYSTEM_MISMATCH'; end if;
  if v_ev.source_ref is distinct from p_expected_source_ref then raise exception 'EXTERNAL_V10_VERIFY_SOURCE_REF_MISMATCH'; end if;
  if v_ev.source_system<>'STORY_AGENT_WORKER_V10_RUNNER' then raise exception 'EXTERNAL_V10_VERIFY_SOURCE_REQUIRED'; end if;
  if p_verifier_identity=v_ev.source_system or p_verifier_identity=v_ev.source_ref then raise exception 'EXTERNAL_V10_VERIFY_SELF_VERIFICATION_FORBIDDEN'; end if;
  v_receipt:=v_ev.metadata->'worker_v10_receipt';
  if v_receipt is null or jsonb_typeof(v_receipt)<>'object' then raise exception 'EXTERNAL_V10_VERIFY_RECEIPT_OBJECT_REQUIRED'; end if;
  v_candidate_head_sha:=v_receipt->>'candidate_head_sha';
  if coalesce(v_candidate_head_sha,'')!~'^[0-9a-f]{40}$' then raise exception 'EXTERNAL_V10_VERIFY_CANDIDATE_HEAD_INVALID'; end if;
  if coalesce(v_receipt#>>'{source_identity,status}','') not in ('PASS','FAIL','BLOCKED') or coalesce(v_receipt#>>'{patch_policy,status}','') not in ('PASS','FAIL','BLOCKED') or coalesce(v_receipt#>>'{visible_acceptance,status}','') not in ('PASS','FAIL','BLOCKED') or coalesce(v_receipt#>>'{hidden_acceptance,status}','') not in ('PASS','FAIL','BLOCKED') or coalesce(v_receipt#>>'{delivery_boundary,status}','') not in ('PASS','FAIL','BLOCKED') then raise exception 'EXTERNAL_V10_VERIFY_STATUS_INVALID'; end if;
  if v_receipt#>>'{hidden_acceptance,status}'='PASS' and coalesce(v_receipt#>>'{hidden_acceptance,result_sha256}','')!~'^[0-9a-f]{64}$' then raise exception 'EXTERNAL_V10_VERIFY_HIDDEN_RESULT_SHA_INVALID'; end if;
  if v_safe_payload->>'execution_id' is distinct from v_ex.id::text or v_safe_payload->>'agent_task_id' is distinct from v_task.id::text or v_safe_payload->>'task_code' is distinct from v_task.task_code or v_safe_payload->>'task_version' is distinct from v_task.task_version::text or v_safe_payload->>'task_sha256' is distinct from coalesce(v_task.task_sha256,'') or v_safe_payload->>'evidence_id' is distinct from v_ev.id::text or v_safe_payload->>'head_sha' is distinct from v_ex.head_sha or v_safe_payload->>'candidate_head_sha' is distinct from v_candidate_head_sha or v_safe_payload->>'evidence_sha256' is distinct from v_ev.sha256 or v_safe_payload->>'source_system' is distinct from v_ev.source_system or v_safe_payload->>'source_ref' is distinct from v_ev.source_ref or v_safe_payload->>'verification_status' is distinct from 'VERIFIED' or v_safe_payload->>'verifier_identity' is distinct from p_verifier_identity then raise exception 'EXTERNAL_V10_VERIFY_PAYLOAD_IDENTITY_MISMATCH'; end if;
  if exists(select 1 from programacion.evidence_verifications where evidence_id=v_ev.id and verification_status='VERIFIED') then raise exception 'EXTERNAL_V10_VERIFY_DUPLICATE_VERIFIED_EVIDENCE'; end if;
  v_subject_payload:=jsonb_build_object('evidence_id',v_ev.id,'evidence_sha256',v_ev.sha256,'source_system',v_ev.source_system,'source_ref',v_ev.source_ref,'verification_status','VERIFIED','verification_method',p_verification_method,'verifier_identity',p_verifier_identity,'verification_payload',v_safe_payload);
  v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_subject_payload);
  v_receipt_payload:=v_safe_payload||jsonb_build_object('execution_id',v_ex.id,'head_sha',v_ex.head_sha,'subject_type','evidence_verification','subject_ref','evidence:'||v_ev.id::text,'subject_sha256',v_subject_sha,'verification_status','VERIFIED','verifier_identity',p_verifier_identity);
  select id,receipt_sha256 into v_receipt_id,v_receipt_sha from programacion.issue_provenance_receipt('EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',v_ex.id,v_ex.head_sha,'evidence_verification','evidence:'||v_ev.id::text,v_subject_sha,p_verifier_identity,p_verification_ref,v_receipt_payload);
  insert into programacion.evidence_verifications(evidence_id,evidence_sha256,source_system,source_ref,verification_status,verification_method,verifier_identity,verification_payload,authority_receipt_id) values(v_ev.id,v_ev.sha256,v_ev.source_system,v_ev.source_ref,'VERIFIED',p_verification_method,p_verifier_identity,v_safe_payload,v_receipt_id) returning id,verification_sha256 into v_verification_id,v_verification_sha;
  return jsonb_build_object('status','VERIFIED','execution_id',v_ex.id,'evaluation_id',v_eval_id,'gate_code',v_gate_code,'evidence_id',v_ev.id,'candidate_head_sha',v_candidate_head_sha,'authority_receipt_id',v_receipt_id,'authority_receipt_sha256',v_receipt_sha,'evidence_verification_id',v_verification_id,'evidence_verification_sha256',v_verification_sha);
end;
$function$;

do $selftest$
declare vdef text; verr text;
begin
  select pg_get_functiondef(p.oid) into vdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_external_verify_worker_v10_evidence_v1';
  if position('vault.decrypted_secrets' in vdef)>0 then raise exception 'SELFTEST_V10_VAULT_DEPENDENCY_REMAINS'; end if;
  if position('channel_token' in vdef)=0 or position('v_safe_payload' in vdef)=0 then raise exception 'SELFTEST_V10_EXTERNAL_TOKEN_OR_REDACTION_MISSING'; end if;
  begin
    perform programacion.fn_external_verify_worker_v10_evidence_v1(0,0,repeat('a',40),repeat('b',64),'STORY_AGENT_WORKER_V10_RUNNER','github-actions://invalid','GITHUB_ACTIONS_OIDC_WORKER_V10_EVIDENCE_V1','github-actions://cristhianlujan/claude-persona-lf-patch/.github/workflows/story-agent-evidence-verifier.yml@refs/heads/main#run-1',jsonb_build_object('channel_token',repeat('x',64)),'selftest://wrong-token');
    raise exception 'SELFTEST_V10_WRONG_TOKEN_ACCEPTED';
  exception when others then
    verr:=sqlerrm;
    if verr not like '%EXTERNAL_V10_CHANNEL_TOKEN_MISMATCH%' then raise; end if;
  end;
end;
$selftest$;
