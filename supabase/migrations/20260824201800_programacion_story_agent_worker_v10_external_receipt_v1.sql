-- HU-HMO-001 / PROG-017
-- Reuse existing execution/evidence/provenance tables and EVIDENCE_VERIFIER_V1.
-- No new canonical table or authority channel.

create or replace function programacion.fn_agent_task_effective_gate_id_v1(
  p_execution_id bigint,
  p_gate_code text
)
returns bigint
language sql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  with recursive version_chain as (
    select ex.version_id, v.supersedes_version_id, 0 as depth
    from programacion.ejecuciones ex
    join programacion.versiones_agente v on v.id=ex.version_id
    where ex.id=p_execution_id
    union all
    select p.id, p.supersedes_version_id, vc.depth+1
    from version_chain vc
    join programacion.versiones_agente p on p.id=vc.supersedes_version_id
  )
  select g.id
  from version_chain vc
  join programacion.gates g on g.version_id=vc.version_id
  where g.gate_codigo=p_gate_code
    and g.bloqueante=true
    and g.estado in('defined','active')
  order by vc.depth,g.id desc
  limit 1;
$function$;

create or replace function programacion.fn_agent_task_worker_v10_context_v1(p_task_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_ex programacion.ejecuciones%rowtype;
  v_cp programacion.context_packs%rowtype;
  v_task programacion.agent_tasks%rowtype;
  v_tc programacion.test_contracts%rowtype;
  v_ev programacion.evidencias%rowtype;
  v_receipt jsonb;
begin
  if p_task_id is null or p_task_id<1 then raise exception 'AGENT_TASK_ID_INVALID'; end if;

  select ex.* into v_ex
  from programacion.ejecuciones ex
  where ex.request_ref='agent-task://'||p_task_id::text
    and ex.estado='RUNNING'
    and programacion.fn_agent_task_worker_context_receipt_ok(ex.id)
  order by ex.id desc
  limit 1;
  if v_ex.id is null then raise exception 'WORKER_V10_BASE_EXECUTION_NOT_FOUND'; end if;

  select * into v_cp from programacion.context_packs
  where execution_id=v_ex.id and estado='COMPLETE' and digest_version=2;
  if v_cp.id is null then raise exception 'WORKER_V10_CONTEXT_PACK_REQUIRED'; end if;

  select * into v_task from programacion.agent_tasks where id=p_task_id and definition_status='SEALED';
  if v_task.id is null then raise exception 'WORKER_V10_SEALED_TASK_REQUIRED'; end if;
  select * into v_tc from programacion.test_contracts where task_id=p_task_id and status='SEALED';
  if v_tc.id is null then raise exception 'WORKER_V10_SEALED_TEST_CONTRACT_REQUIRED'; end if;

  select ev.* into v_ev
  from programacion.evidencias ev
  join programacion.evaluaciones eva on eva.id=ev.evaluacion_id and eva.resultado='PASS'
  join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id and obj.execution_id=v_ex.id
  where ev.tipo='VERIFIED_WORKER_RECEIPT'
    and ev.source_system='PROGRAMMING_AGENT_WORKER'
    and ev.sha256=ev.metadata->>'receipt_sha256'
    and ev.metadata#>>'{worker_receipt,status}'='PASS'
    and ev.metadata#>>'{worker_receipt,execution_id}'=v_ex.id::text
    and exists(
      select 1 from programacion.evidence_verifications vv
      where vv.evidence_id=ev.id
        and vv.verification_status='VERIFIED'
        and vv.evidence_sha256=ev.sha256
        and vv.source_system=ev.source_system
        and vv.source_ref=ev.source_ref
    )
  order by ev.id desc limit 1;
  if v_ev.id is null then raise exception 'WORKER_V10_VERIFIED_PREDECESSOR_RECEIPT_REQUIRED'; end if;

  v_receipt:=v_ev.metadata->'worker_receipt';
  if coalesce(v_receipt->>'delivered_head_sha','')!~'^[0-9a-f]{40}$' then
    raise exception 'WORKER_V10_DELIVERED_HEAD_INVALID';
  end if;
  if v_receipt->>'oracle_manifest_sha256' is distinct from v_tc.hidden_oracle_sha256 then
    raise exception 'WORKER_V10_ORACLE_BINDING_MISMATCH';
  end if;

  return jsonb_build_object(
    'schema_version',1,
    'execution_id',v_ex.id,
    'request_ref',v_ex.request_ref,
    'task_id',v_task.id,
    'task_code',v_task.task_code||'.v'||v_task.task_version::text,
    'task_sha256',v_task.task_sha256,
    'base_head_sha',v_ex.head_sha,
    'base_source_snapshot_sha256',v_ex.source_snapshot_sha256,
    'candidate_head_sha',v_receipt->>'delivered_head_sha',
    'context_pack_id',v_cp.id,
    'context_pack_sha256',v_cp.context_sha256,
    'worker_evidence_id',v_ev.id,
    'worker_evidence_sha256',v_ev.sha256,
    'worker_source_ref',v_ev.source_ref,
    'test_contract_id',v_tc.id,
    'test_contract_sha256',v_tc.contract_sha256,
    'hidden_oracle_sha256',v_tc.hidden_oracle_sha256,
    'visible_commands',v_tc.visible_commands,
    'write_path_patterns',to_jsonb(v_task.write_path_patterns),
    'protected_path_patterns',to_jsonb(v_task.protected_path_patterns),
    'max_patch_bytes',v_task.max_patch_bytes,
    'max_changed_files',v_task.max_changed_files,
    'allow_deletions',v_task.allow_deletions
  );
end;
$function$;

create or replace function programacion.fn_agent_task_record_worker_v10_receipt_v1(
  p_task_id bigint,
  p_source_ref text,
  p_runner_identity text,
  p_receipt jsonb,
  p_expected_receipt_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_ctx jsonb;
  v_digest text;
  v_gate_code text;
  v_gate_id bigint;
  v_obj_id bigint;
  v_eval_id bigint;
  v_ev_id bigint;
  v_evidence_ids jsonb:='{}'::jsonb;
begin
  if p_receipt is null or jsonb_typeof(p_receipt)<>'object' then raise exception 'WORKER_V10_RECEIPT_OBJECT_REQUIRED'; end if;
  if p_expected_receipt_sha256!~'^[0-9a-f]{64}$' then raise exception 'WORKER_V10_RECEIPT_SHA_INVALID'; end if;
  if p_source_ref!~'^github-actions://cristhianlujan/libertad-financiera/actions/runs/[0-9]+$' then raise exception 'WORKER_V10_SOURCE_REF_INVALID'; end if;
  if p_runner_identity!~'^github-actions://cristhianlujan/libertad-financiera/.github/workflows/hmo-worker-v10-validation.yml@.+#run-[0-9]+$' then raise exception 'WORKER_V10_RUNNER_IDENTITY_INVALID'; end if;

  v_ctx:=programacion.fn_agent_task_worker_v10_context_v1(p_task_id);
  v_digest:=programacion.fn_v09_sha256_jsonb(p_receipt);
  if v_digest is distinct from p_expected_receipt_sha256 then raise exception 'WORKER_V10_RECEIPT_DIGEST_MISMATCH'; end if;

  if p_receipt->>'schema_version' is distinct from '1'
     or p_receipt->>'execution_id' is distinct from v_ctx->>'execution_id'
     or p_receipt->>'task_id' is distinct from v_ctx->>'task_id'
     or p_receipt->>'base_head_sha' is distinct from v_ctx->>'base_head_sha'
     or p_receipt->>'base_source_snapshot_sha256' is distinct from v_ctx->>'base_source_snapshot_sha256'
     or p_receipt->>'candidate_head_sha' is distinct from v_ctx->>'candidate_head_sha'
     or p_receipt->>'worker_evidence_id' is distinct from v_ctx->>'worker_evidence_id'
     or p_receipt->>'worker_evidence_sha256' is distinct from v_ctx->>'worker_evidence_sha256'
     or p_receipt->>'test_contract_sha256' is distinct from v_ctx->>'test_contract_sha256'
     or p_receipt->>'oracle_manifest_sha256' is distinct from v_ctx->>'hidden_oracle_sha256'
  then raise exception 'WORKER_V10_RECEIPT_CONTEXT_BINDING_MISMATCH'; end if;

  if coalesce(p_receipt->>'candidate_source_snapshot_sha256','')!~'^[0-9a-f]{64}$'
     or coalesce(p_receipt->>'patch_sha256','')!~'^[0-9a-f]{64}$'
     or coalesce(p_receipt#>>'{visible_acceptance,result_sha256}','')!~'^[0-9a-f]{64}$'
     or coalesce(p_receipt#>>'{hidden_acceptance,result_sha256}','')!~'^[0-9a-f]{64}$'
  then raise exception 'WORKER_V10_RECEIPT_RESULT_DIGEST_INVALID'; end if;

  if jsonb_typeof(p_receipt->'changed_paths')<>'array'
     or jsonb_array_length(p_receipt->'changed_paths')<1
     or jsonb_array_length(p_receipt->'changed_paths')>(v_ctx->>'max_changed_files')::integer
  then raise exception 'WORKER_V10_CHANGED_PATHS_INVALID'; end if;
  if jsonb_typeof(p_receipt->'governance')<>'object'
     or p_receipt#>'{governance,commit_allowed}' is distinct from 'false'::jsonb
     or p_receipt#>'{governance,push_allowed}' is distinct from 'false'::jsonb
     or p_receipt#>'{governance,merge_allowed}' is distinct from 'false'::jsonb
     or p_receipt#>'{governance,production_allowed}' is distinct from 'false'::jsonb
     or p_receipt#>'{governance,independent_audit_required}' is distinct from 'true'::jsonb
  then raise exception 'WORKER_V10_GOVERNANCE_FLAGS_INVALID'; end if;

  if p_receipt#>>'{source_identity,status}' not in('PASS','FAIL','BLOCKED')
     or p_receipt#>>'{patch_policy,status}' not in('PASS','FAIL','BLOCKED')
     or p_receipt#>>'{visible_acceptance,status}' not in('PASS','FAIL','BLOCKED')
     or p_receipt#>>'{hidden_acceptance,status}' not in('PASS','FAIL','BLOCKED')
     or p_receipt#>>'{delivery_boundary,status}' not in('PASS','FAIL','BLOCKED')
  then raise exception 'WORKER_V10_GATE_STATUS_INVALID'; end if;

  foreach v_gate_code in array array['G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY','G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY'] loop
    v_gate_id:=programacion.fn_agent_task_effective_gate_id_v1((v_ctx->>'execution_id')::bigint,v_gate_code);
    if v_gate_id is null then raise exception 'WORKER_V10_EFFECTIVE_GATE_MISSING:%',v_gate_code; end if;
    select id into v_obj_id from programacion.objetivos_ejecucion
    where execution_id=(v_ctx->>'execution_id')::bigint and gate_id=v_gate_id and aplicabilidad='REQUIRED';
    if v_obj_id is null then raise exception 'WORKER_V10_REQUIRED_OBJECTIVE_MISSING:%',v_gate_code; end if;
    if exists(select 1 from programacion.evaluaciones where objetivo_id=v_obj_id) then
      raise exception 'WORKER_V10_OBJECTIVE_ALREADY_EVALUATED:%',v_gate_code;
    end if;

    insert into programacion.evaluaciones(
      objetivo_id,intento,evaluador_identidad,evaluador_tipo,evaluador_canal,independencia_declarada,
      resultado,resumen,detalles,head_sha,started_at
    ) values (
      v_obj_id,1,p_runner_identity,'auditor','GITHUB_ACTIONS_OIDC_WORKER_V10_RUNNER',false,
      'PENDING','Worker v10 exact-head validation awaiting external OIDC evidence verification.',
      jsonb_build_object('runner_receipt_sha256',v_digest,'source_ref',p_source_ref,'gate_code',v_gate_code),
      v_ctx->>'base_head_sha',now()
    ) returning id into v_eval_id;

    insert into programacion.evidencias(
      evaluacion_id,tipo,source_system,source_ref,sha256,head_sha,resumen,metadata
    ) values (
      v_eval_id,'WORKER_V10_VALIDATION_RECEIPT','STORY_AGENT_WORKER_V10_RUNNER',p_source_ref,v_digest,
      v_ctx->>'base_head_sha','Worker v10 source/patch/visible/hidden/delivery receipt; hidden commands and outputs omitted.',
      jsonb_build_object('worker_v10_receipt',p_receipt,'runner_identity',p_runner_identity,'gate_code',v_gate_code,'receipt_sha256',v_digest)
    ) returning id into v_ev_id;
    v_evidence_ids:=v_evidence_ids||jsonb_build_object(v_gate_code,v_ev_id);
  end loop;

  return jsonb_build_object(
    'status','PENDING_EXTERNAL_VERIFICATION',
    'execution_id',(v_ctx->>'execution_id')::bigint,
    'base_head_sha',v_ctx->>'base_head_sha',
    'candidate_head_sha',v_ctx->>'candidate_head_sha',
    'receipt_sha256',v_digest,
    'evidence_ids',v_evidence_ids
  );
end;
$function$;

create or replace function programacion.fn_agent_task_pending_worker_v10_evidence_v1(p_task_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare v jsonb;
begin
  select jsonb_build_object(
    'execution_id',ex.id,
    'head_sha',ex.head_sha,
    'receipt_sha256',min(ev.sha256),
    'source_ref',min(ev.source_ref),
    'source_system',min(ev.source_system),
    'evidence_ids',jsonb_object_agg(g.gate_codigo,ev.id order by g.gate_codigo),
    'gate_count',count(*)
  ) into v
  from programacion.ejecuciones ex
  join programacion.objetivos_ejecucion obj on obj.execution_id=ex.id
  join programacion.gates g on g.id=obj.gate_id
  join programacion.evaluaciones eva on eva.objetivo_id=obj.id and eva.resultado='PENDING'
  join programacion.evidencias ev on ev.evaluacion_id=eva.id
  where ex.request_ref='agent-task://'||p_task_id::text and ex.estado='RUNNING'
    and g.id=programacion.fn_agent_task_effective_gate_id_v1(ex.id,g.gate_codigo)
    and g.gate_codigo in('G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY','G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY')
    and ev.tipo='WORKER_V10_VALIDATION_RECEIPT'
    and ev.source_system='STORY_AGENT_WORKER_V10_RUNNER'
    and not exists(select 1 from programacion.evidence_verifications vv where vv.evidence_id=ev.id and vv.verification_status='VERIFIED')
  group by ex.id,ex.head_sha
  having count(*)=4 and count(distinct ev.sha256)=1 and count(distinct ev.source_ref)=1 and count(distinct ev.source_system)=1
  order by ex.id desc limit 1;
  if v is null then raise exception 'PENDING_WORKER_V10_EVIDENCE_NOT_FOUND: agent-task://%',p_task_id; end if;
  return v;
end;
$function$;

create or replace function programacion.fn_agent_task_external_verify_worker_v10_evidence_v1(
  p_task_id bigint,
  p_expected_execution_id bigint,
  p_expected_head_sha text,
  p_expected_receipt_sha256 text,
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
  v_ctx jsonb;
  v_token text; v_channel_hash text; v_token_hash text;
  v_record record;
  v_receipt jsonb;
  v_gate_result text;
  v_subject_payload jsonb; v_subject_sha text;
  v_receipt_payload jsonb;
  v_authority_id bigint; v_authority_sha text;
  v_verification_id bigint; v_verification_sha text;
  v_verified_count integer:=0; v_pass_count integer:=0;
begin
  if p_verification_payload is null or jsonb_typeof(p_verification_payload)<>'object' then raise exception 'WORKER_V10_EXTERNAL_PAYLOAD_REQUIRED'; end if;
  if p_verification_method<>'GITHUB_ACTIONS_OIDC_EXACT_EVIDENCE_V1' then raise exception 'WORKER_V10_EXTERNAL_METHOD_INVALID'; end if;
  if p_verifier_identity!~'^github-actions://cristhianlujan/claude-persona-lf-patch/\.github/workflows/story-agent-evidence-verifier\.yml@refs/heads/main#run-[0-9]+$' then raise exception 'WORKER_V10_EXTERNAL_VERIFIER_IDENTITY_INVALID'; end if;
  if p_expected_receipt_sha256!~'^[0-9a-f]{64}$' then raise exception 'WORKER_V10_EXTERNAL_RECEIPT_SHA_INVALID'; end if;
  if length(btrim(coalesce(p_verification_ref,'')))=0 then raise exception 'WORKER_V10_EXTERNAL_VERIFICATION_REF_REQUIRED'; end if;

  select * into v_ex from programacion.ejecuciones where id=p_expected_execution_id;
  if v_ex.id is null or v_ex.estado<>'RUNNING' or v_ex.request_ref is distinct from 'agent-task://'||p_task_id::text then raise exception 'WORKER_V10_EXTERNAL_EXECUTION_INVALID'; end if;
  if v_ex.head_sha is distinct from p_expected_head_sha then raise exception 'WORKER_V10_EXTERNAL_HEAD_MISMATCH'; end if;
  v_ctx:=programacion.fn_agent_task_worker_v10_context_v1(p_task_id);
  if (v_ctx->>'execution_id')::bigint is distinct from v_ex.id then raise exception 'WORKER_V10_EXTERNAL_CONTEXT_EXECUTION_MISMATCH'; end if;

  if p_verification_payload->>'execution_id' is distinct from v_ex.id::text
     or p_verification_payload->>'head_sha' is distinct from v_ex.head_sha
     or p_verification_payload->>'receipt_sha256' is distinct from p_expected_receipt_sha256
     or p_verification_payload->>'source_ref' is distinct from p_expected_source_ref
     or p_verification_payload->>'verification_status' is distinct from 'VERIFIED'
     or p_verification_payload->>'verifier_identity' is distinct from p_verifier_identity
  then raise exception 'WORKER_V10_EXTERNAL_PAYLOAD_IDENTITY_MISMATCH'; end if;

  select decrypted_secret into v_token from vault.decrypted_secrets where name='EVIDENCE_VERIFIER_V1_TOKEN' order by created_at desc limit 1;
  if length(coalesce(v_token,''))<32 then raise exception 'EVIDENCE_VERIFIER_V1_VAULT_SECRET_MISSING'; end if;
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex');
  select secret_sha256 into v_channel_hash from programacion.provenance_channels where channel_code='EVIDENCE_VERIFIER_V1';
  if v_channel_hash is distinct from v_token_hash then raise exception 'EVIDENCE_VERIFIER_V1_VAULT_CHANNEL_HASH_MISMATCH'; end if;

  for v_record in
    select g.gate_codigo,eva.id evaluation_id,ev.*
    from programacion.objetivos_ejecucion obj
    join programacion.gates g on g.id=obj.gate_id
    join programacion.evaluaciones eva on eva.objetivo_id=obj.id and eva.resultado='PENDING'
    join programacion.evidencias ev on ev.evaluacion_id=eva.id
    where obj.execution_id=v_ex.id
      and g.id=programacion.fn_agent_task_effective_gate_id_v1(v_ex.id,g.gate_codigo)
      and g.gate_codigo in('G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY','G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY')
      and ev.tipo='WORKER_V10_VALIDATION_RECEIPT'
      and ev.source_system='STORY_AGENT_WORKER_V10_RUNNER'
      and ev.source_ref=p_expected_source_ref
      and ev.sha256=p_expected_receipt_sha256
    order by g.gate_codigo
  loop
    if exists(select 1 from programacion.evidence_verifications vv where vv.evidence_id=v_record.id and vv.verification_status='VERIFIED') then raise exception 'WORKER_V10_EXTERNAL_DUPLICATE_VERIFICATION:%',v_record.id; end if;
    v_receipt:=v_record.metadata->'worker_v10_receipt';
    if v_receipt is null or programacion.fn_v09_sha256_jsonb(v_receipt) is distinct from p_expected_receipt_sha256 then raise exception 'WORKER_V10_EXTERNAL_EVIDENCE_DIGEST_MISMATCH:%',v_record.id; end if;
    if v_receipt->>'candidate_head_sha' is distinct from v_ctx->>'candidate_head_sha'
       or v_receipt->>'worker_evidence_sha256' is distinct from v_ctx->>'worker_evidence_sha256'
       or v_receipt->>'oracle_manifest_sha256' is distinct from v_ctx->>'hidden_oracle_sha256'
    then raise exception 'WORKER_V10_EXTERNAL_EVIDENCE_BINDING_MISMATCH:%',v_record.id; end if;

    v_subject_payload:=jsonb_build_object(
      'evidence_id',v_record.id,'evidence_sha256',v_record.sha256,'source_system',v_record.source_system,
      'source_ref',v_record.source_ref,'verification_status','VERIFIED','verification_method',p_verification_method,
      'verifier_identity',p_verifier_identity,'verification_payload',p_verification_payload||jsonb_build_object('gate_code',v_record.gate_codigo)
    );
    v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_subject_payload);
    v_receipt_payload:=(p_verification_payload||jsonb_build_object('gate_code',v_record.gate_codigo))||jsonb_build_object(
      'execution_id',v_ex.id,'head_sha',v_ex.head_sha,'subject_type','evidence_verification',
      'subject_ref','evidence:'||v_record.id::text,'subject_sha256',v_subject_sha,
      'verification_status','VERIFIED','verifier_identity',p_verifier_identity
    );
    select id,receipt_sha256 into v_authority_id,v_authority_sha
    from programacion.issue_provenance_receipt(
      'EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',v_ex.id,v_ex.head_sha,
      'evidence_verification','evidence:'||v_record.id::text,v_subject_sha,p_verifier_identity,
      p_verification_ref||'#'||v_record.gate_codigo,v_receipt_payload
    );
    insert into programacion.evidence_verifications(
      evidence_id,evidence_sha256,source_system,source_ref,verification_status,
      verification_method,verifier_identity,verification_payload,authority_receipt_id
    ) values(
      v_record.id,v_record.sha256,v_record.source_system,v_record.source_ref,'VERIFIED',p_verification_method,
      p_verifier_identity,p_verification_payload||jsonb_build_object('gate_code',v_record.gate_codigo),v_authority_id
    ) returning id,verification_sha256 into v_verification_id,v_verification_sha;

    v_gate_result:=case v_record.gate_codigo
      when 'G_WORKER_SOURCE_IDENTITY' then v_receipt#>>'{source_identity,status}'
      when 'G_WORKER_PATCH_POLICY' then v_receipt#>>'{patch_policy,status}'
      when 'G_WORKER_ACCEPTANCE' then case when v_receipt#>>'{visible_acceptance,status}'='PASS' and v_receipt#>>'{hidden_acceptance,status}'='PASS' then 'PASS' else 'FAIL' end
      when 'G_WORKER_DELIVERY_BOUNDARY' then case when v_receipt#>>'{delivery_boundary,status}'='PASS' and v_receipt#>>'{visible_acceptance,status}'='PASS' and v_receipt#>>'{hidden_acceptance,status}'='PASS' then 'PASS' else 'FAIL' end
      else 'FAIL' end;
    if v_gate_result not in('PASS','FAIL','BLOCKED') then v_gate_result:='FAIL'; end if;

    update programacion.evaluaciones set
      evaluador_identidad=p_verifier_identity,
      evaluador_tipo='auditor',
      evaluador_canal='GITHUB_ACTIONS_OIDC_EXACT_EVIDENCE_V1',
      resultado=v_gate_result,
      root_cause_family=case when v_gate_result='FAIL' then 'UNCLASSIFIED_WITH_REASON' else null end,
      detectability=case when v_gate_result='FAIL' then 'LOUD_EARLY' else null end,
      resumen='Worker v10 gate '||v_record.gate_codigo||' externally verified: '||v_gate_result,
      detalles=coalesce(detalles,'{}'::jsonb)||jsonb_build_object(
        'external_verification_id',v_verification_id,'external_verification_sha256',v_verification_sha,
        'authority_receipt_id',v_authority_id,'authority_receipt_sha256',v_authority_sha,
        'candidate_head_sha',v_ctx->>'candidate_head_sha','runner_receipt_sha256',p_expected_receipt_sha256
      ),
      finished_at=now()
    where id=v_record.evaluation_id;

    v_verified_count:=v_verified_count+1;
    if v_gate_result='PASS' then v_pass_count:=v_pass_count+1; end if;
  end loop;

  if v_verified_count<>4 then raise exception 'WORKER_V10_EXTERNAL_GATE_SET_INCOMPLETE:%',v_verified_count; end if;
  return jsonb_build_object(
    'status',case when v_pass_count=4 then 'VERIFIED_PASS' else 'VERIFIED_NONPASS' end,
    'execution_id',v_ex.id,'verified_gate_count',v_verified_count,'pass_gate_count',v_pass_count,
    'receipt_sha256',p_expected_receipt_sha256,'candidate_head_sha',v_ctx->>'candidate_head_sha'
  );
end;
$function$;

create or replace function public.fn_agent_task_worker_v10_context_v1(p_task_id bigint)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','programacion'
as $function$ select programacion.fn_agent_task_worker_v10_context_v1(p_task_id); $function$;

create or replace function public.fn_agent_task_record_worker_v10_receipt_v1(
  p_task_id bigint,p_source_ref text,p_runner_identity text,p_receipt jsonb,p_expected_receipt_sha256 text
)
returns jsonb language sql security definer set search_path to 'pg_catalog','programacion'
as $function$ select programacion.fn_agent_task_record_worker_v10_receipt_v1(p_task_id,p_source_ref,p_runner_identity,p_receipt,p_expected_receipt_sha256); $function$;

create or replace function public.fn_agent_task_pending_worker_v10_evidence_v1(p_task_id bigint)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','programacion'
as $function$ select programacion.fn_agent_task_pending_worker_v10_evidence_v1(p_task_id); $function$;

create or replace function public.fn_agent_task_external_verify_worker_v10_evidence_v1(
  p_task_id bigint,p_expected_execution_id bigint,p_expected_head_sha text,p_expected_receipt_sha256 text,
  p_expected_source_ref text,p_verification_method text,p_verifier_identity text,p_verification_payload jsonb,p_verification_ref text
)
returns jsonb language sql security definer set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.fn_agent_task_external_verify_worker_v10_evidence_v1(
    p_task_id,p_expected_execution_id,p_expected_head_sha,p_expected_receipt_sha256,p_expected_source_ref,
    p_verification_method,p_verifier_identity,p_verification_payload,p_verification_ref
  );
$function$;

revoke all on function programacion.fn_agent_task_effective_gate_id_v1(bigint,text) from public,anon,authenticated;
revoke all on function programacion.fn_agent_task_worker_v10_context_v1(bigint) from public,anon,authenticated;
revoke all on function programacion.fn_agent_task_record_worker_v10_receipt_v1(bigint,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function programacion.fn_agent_task_pending_worker_v10_evidence_v1(bigint) from public,anon,authenticated;
revoke all on function programacion.fn_agent_task_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.fn_agent_task_worker_v10_context_v1(bigint) from public,anon,authenticated;
revoke all on function public.fn_agent_task_record_worker_v10_receipt_v1(bigint,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.fn_agent_task_pending_worker_v10_evidence_v1(bigint) from public,anon,authenticated;
revoke all on function public.fn_agent_task_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.fn_agent_task_worker_v10_context_v1(bigint) to service_role;
grant execute on function public.fn_agent_task_record_worker_v10_receipt_v1(bigint,text,text,jsonb,text) to service_role;
grant execute on function public.fn_agent_task_pending_worker_v10_evidence_v1(bigint) to service_role;
grant execute on function public.fn_agent_task_external_verify_worker_v10_evidence_v1(bigint,bigint,text,text,text,text,text,jsonb,text) to service_role;

-- Fail-closed smoke probes use a transaction-local rollback by raising only on invariant failure.
do $selftest$
declare v_ctx jsonb;
begin
  v_ctx:=programacion.fn_agent_task_worker_v10_context_v1(21);
  if v_ctx->>'execution_id' is distinct from '91' then raise exception 'SELFTEST_WORKER_V10_EXECUTION_BINDING'; end if;
  if v_ctx->>'candidate_head_sha' is distinct from '3b9c76769775fdd96bbdff27cc2e9ca80f9082c6' then raise exception 'SELFTEST_WORKER_V10_CANDIDATE_BINDING'; end if;
  if v_ctx->>'hidden_oracle_sha256' is distinct from '9d80e837d8c095d446813173b00133c772d8891c7f67002cdb3cc33f93cfa7e0' then raise exception 'SELFTEST_WORKER_V10_ORACLE_BINDING'; end if;
  if has_function_privilege('anon','public.fn_agent_task_record_worker_v10_receipt_v1(bigint,text,text,jsonb,text)','EXECUTE')
     or has_function_privilege('authenticated','public.fn_agent_task_record_worker_v10_receipt_v1(bigint,text,text,jsonb,text)','EXECUTE') then
    raise exception 'SELFTEST_WORKER_V10_BROWSER_EXECUTE_EXPOSED';
  end if;
end;
$selftest$;
