-- Evidence verification must occur while its evaluation is PENDING; PASS finalization comes after VERIFIED provenance.

create or replace function programacion.fn_agent_task_pending_worker_evidence_v1(p_task_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare v jsonb;
begin
  if p_task_id is null or p_task_id < 1 then raise exception 'AGENT_TASK_ID_INVALID'; end if;
  select jsonb_build_object(
    'execution_id',ex.id,'request_ref',ex.request_ref,'head_sha',ex.head_sha,
    'source_snapshot_sha256',ex.source_snapshot_sha256,'context_pack_id',cp.id,'context_pack_sha256',cp.context_sha256,
    'evaluation_id',eva.id,'evaluation_status',eva.resultado,
    'evidence_id',ev.id,'evidence_sha256',ev.sha256,'source_system',ev.source_system,'source_ref',ev.source_ref,
    'worker_receipt_status',ev.metadata#>>'{worker_receipt,status}'
  ) into v
  from programacion.ejecuciones ex
  join programacion.context_packs cp on cp.execution_id=ex.id and cp.estado='COMPLETE' and cp.digest_version=2
  join programacion.objetivos_ejecucion obj on obj.execution_id=ex.id
  join programacion.evaluaciones eva on eva.objetivo_id=obj.id and eva.resultado='PENDING'
  join programacion.evidencias ev on ev.evaluacion_id=eva.id
  where ex.request_ref='agent-task://'||p_task_id::text and ex.estado='RUNNING'
    and ev.tipo='VERIFIED_WORKER_RECEIPT' and ev.source_system='PROGRAMMING_AGENT_WORKER'
    and ev.sha256=ev.metadata->>'receipt_sha256' and ev.metadata#>>'{worker_receipt,status}'='PASS'
    and ev.metadata#>>'{worker_receipt,execution_id}'=ex.id::text
    and ev.metadata#>>'{worker_receipt,context_pack_id}'=cp.id::text
    and ev.metadata#>>'{worker_receipt,context_pack_sha256}'=cp.context_sha256
    and not exists(select 1 from programacion.evidence_verifications vv where vv.evidence_id=ev.id and vv.verification_status='VERIFIED')
  order by ex.id desc,ev.id desc limit 1;
  if v is null then raise exception 'PENDING_WORKER_EVIDENCE_NOT_FOUND: agent-task://%',p_task_id; end if;
  return v;
end;
$function$;

create or replace function programacion.fn_external_verify_worker_evidence_v1(
  p_execution_id bigint,p_evidence_id bigint,p_expected_head_sha text,p_expected_evidence_sha256 text,
  p_expected_source_system text,p_expected_source_ref text,p_verification_method text,p_verifier_identity text,
  p_verification_payload jsonb,p_verification_ref text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_ex programacion.ejecuciones%rowtype; v_ev programacion.evidencias%rowtype; v_cp programacion.context_packs%rowtype;
  v_eval_status text; v_eval_id bigint; v_token text; v_channel_hash text; v_token_hash text; v_subject_sha text;
  v_receipt_id bigint; v_receipt_sha text; v_verification_id bigint; v_verification_sha text;
  v_subject_payload jsonb; v_receipt_payload jsonb;
begin
  if p_verification_payload is null or jsonb_typeof(p_verification_payload)<>'object' then raise exception 'EXTERNAL_VERIFICATION_PAYLOAD_REQUIRED'; end if;
  if p_verification_method <> 'GITHUB_ACTIONS_OIDC_EXACT_EVIDENCE_V1' then raise exception 'EXTERNAL_VERIFICATION_METHOD_INVALID'; end if;
  if p_verifier_identity !~ '^github-actions://cristhianlujan/claude-persona-lf-patch/\.github/workflows/story-agent-evidence-verifier\.yml@refs/heads/main#run-[0-9]+$' then raise exception 'EXTERNAL_VERIFIER_IDENTITY_INVALID'; end if;
  if length(btrim(coalesce(p_verification_ref,'')))=0 then raise exception 'EXTERNAL_VERIFICATION_REF_REQUIRED'; end if;

  select * into v_ex from programacion.ejecuciones where id=p_execution_id;
  if not found then raise exception 'EXTERNAL_VERIFY_EXECUTION_NOT_FOUND'; end if;
  if v_ex.estado<>'RUNNING' or v_ex.request_ref!~'^agent-task://[1-9][0-9]*$' then raise exception 'EXTERNAL_VERIFY_AGENT_TASK_RUNNING_REQUIRED'; end if;
  if v_ex.head_sha is distinct from p_expected_head_sha then raise exception 'EXTERNAL_VERIFY_HEAD_MISMATCH'; end if;

  select ev.*,eva.resultado,eva.id into v_ev,v_eval_status,v_eval_id
  from programacion.evidencias ev
  join programacion.evaluaciones eva on eva.id=ev.evaluacion_id
  join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id and obj.execution_id=v_ex.id
  where ev.id=p_evidence_id;
  if not found then raise exception 'EXTERNAL_VERIFY_EVIDENCE_NOT_FOUND'; end if;
  if v_eval_status<>'PENDING' then raise exception 'EXTERNAL_VERIFY_EVALUATION_PENDING_REQUIRED'; end if;
  if v_ev.tipo<>'VERIFIED_WORKER_RECEIPT' then raise exception 'EXTERNAL_VERIFY_WORKER_RECEIPT_REQUIRED'; end if;
  if v_ev.sha256 is distinct from p_expected_evidence_sha256 then raise exception 'EXTERNAL_VERIFY_EVIDENCE_SHA_MISMATCH'; end if;
  if v_ev.source_system is distinct from p_expected_source_system then raise exception 'EXTERNAL_VERIFY_SOURCE_SYSTEM_MISMATCH'; end if;
  if v_ev.source_ref is distinct from p_expected_source_ref then raise exception 'EXTERNAL_VERIFY_SOURCE_REF_MISMATCH'; end if;
  if v_ev.source_system<>'PROGRAMMING_AGENT_WORKER' then raise exception 'EXTERNAL_VERIFY_WORKER_SOURCE_REQUIRED'; end if;
  if p_verifier_identity=v_ev.source_system or p_verifier_identity=v_ev.source_ref then raise exception 'EXTERNAL_VERIFY_SELF_VERIFICATION_FORBIDDEN'; end if;

  select * into v_cp from programacion.context_packs where execution_id=v_ex.id and estado='COMPLETE' and digest_version=2;
  if not found then raise exception 'EXTERNAL_VERIFY_CONTEXT_PACK_REQUIRED'; end if;
  if v_ev.metadata#>>'{worker_receipt,status}'<>'PASS'
     or v_ev.metadata#>>'{worker_receipt,execution_id}'<>v_ex.id::text
     or v_ev.metadata#>>'{worker_receipt,context_pack_id}'<>v_cp.id::text
     or v_ev.metadata#>>'{worker_receipt,context_pack_sha256}'<>v_cp.context_sha256 then raise exception 'EXTERNAL_VERIFY_WORKER_RECEIPT_BINDING_INVALID'; end if;

  if p_verification_payload->>'execution_id' is distinct from v_ex.id::text
     or p_verification_payload->>'evidence_id' is distinct from v_ev.id::text
     or p_verification_payload->>'head_sha' is distinct from v_ex.head_sha
     or p_verification_payload->>'evidence_sha256' is distinct from v_ev.sha256
     or p_verification_payload->>'source_system' is distinct from v_ev.source_system
     or p_verification_payload->>'source_ref' is distinct from v_ev.source_ref
     or p_verification_payload->>'verification_status' is distinct from 'VERIFIED'
     or p_verification_payload->>'verifier_identity' is distinct from p_verifier_identity then raise exception 'EXTERNAL_VERIFY_PAYLOAD_IDENTITY_MISMATCH'; end if;
  if exists(select 1 from programacion.evidence_verifications where evidence_id=v_ev.id and verification_status='VERIFIED') then raise exception 'EXTERNAL_VERIFY_DUPLICATE_VERIFIED_EVIDENCE'; end if;

  select decrypted_secret into v_token from vault.decrypted_secrets where name='EVIDENCE_VERIFIER_V1_TOKEN' order by created_at desc limit 1;
  if length(coalesce(v_token,''))<32 then raise exception 'EVIDENCE_VERIFIER_V1_VAULT_SECRET_MISSING'; end if;
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex');
  select secret_sha256 into v_channel_hash from programacion.provenance_channels where channel_code='EVIDENCE_VERIFIER_V1';
  if v_channel_hash is distinct from v_token_hash then raise exception 'EVIDENCE_VERIFIER_V1_VAULT_CHANNEL_HASH_MISMATCH'; end if;

  v_subject_payload:=jsonb_build_object('evidence_id',v_ev.id,'evidence_sha256',v_ev.sha256,'source_system',v_ev.source_system,
    'source_ref',v_ev.source_ref,'verification_status','VERIFIED','verification_method',p_verification_method,
    'verifier_identity',p_verifier_identity,'verification_payload',p_verification_payload);
  v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_subject_payload);
  v_receipt_payload:=p_verification_payload||jsonb_build_object('execution_id',v_ex.id,'head_sha',v_ex.head_sha,
    'subject_type','evidence_verification','subject_ref','evidence:'||v_ev.id::text,'subject_sha256',v_subject_sha,
    'verification_status','VERIFIED','verifier_identity',p_verifier_identity);

  select id,receipt_sha256 into v_receipt_id,v_receipt_sha from programacion.issue_provenance_receipt(
    'EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',v_ex.id,v_ex.head_sha,'evidence_verification',
    'evidence:'||v_ev.id::text,v_subject_sha,p_verifier_identity,p_verification_ref,v_receipt_payload);
  insert into programacion.evidence_verifications(evidence_id,evidence_sha256,source_system,source_ref,verification_status,
    verification_method,verifier_identity,verification_payload,authority_receipt_id)
  values(v_ev.id,v_ev.sha256,v_ev.source_system,v_ev.source_ref,'VERIFIED',p_verification_method,p_verifier_identity,p_verification_payload,v_receipt_id)
  returning id,verification_sha256 into v_verification_id,v_verification_sha;
  return jsonb_build_object('status','VERIFIED','execution_id',v_ex.id,'evaluation_id',v_eval_id,'evidence_id',v_ev.id,
    'authority_receipt_id',v_receipt_id,'authority_receipt_sha256',v_receipt_sha,
    'evidence_verification_id',v_verification_id,'evidence_verification_sha256',v_verification_sha);
end;
$function$;
