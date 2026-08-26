-- STORY_AGENT pre-audit AUD-018 / AUD-037
-- Strengthen the existing evidence verifier path. No new table, orchestrator, canonical source, promotion, or production action.

create or replace function programacion.fn_assert_worker_direct_readback_v2(
  p_execution_id bigint,
  p_evidence_id bigint,
  p_verification_payload jsonb
) returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_ex programacion.ejecuciones%rowtype;
  v_ev programacion.evidencias%rowtype;
  v_cp programacion.context_packs%rowtype;
  v_task programacion.agent_tasks%rowtype;
  v_receipt jsonb;
  v_observed jsonb;
  v_independent jsonb;
  v_expected_files jsonb;
  v_observed_files jsonb;
  v_expected_count integer;
  v_observed_count integer;
  v_semantic text;
  v_mutation text;
  v_auth text;
begin
  if p_verification_payload is null or jsonb_typeof(p_verification_payload)<>'object' then
    raise exception 'EXTERNAL_VERIFY_V2_PAYLOAD_REQUIRED';
  end if;
  v_observed:=p_verification_payload->'observed';
  if v_observed is null or jsonb_typeof(v_observed)<>'object' then
    raise exception 'EXTERNAL_VERIFY_V2_OBSERVED_REQUIRED';
  end if;
  if coalesce(v_observed->>'observed_sha256','')!~'^[0-9a-f]{64}$'
     or v_observed->>'observed_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_observed-'observed_sha256') then
    raise exception 'EXTERNAL_VERIFY_V2_OBSERVED_SHA_MISMATCH';
  end if;

  select * into v_ex from programacion.ejecuciones where id=p_execution_id;
  if not found then raise exception 'EXTERNAL_VERIFY_V2_EXECUTION_NOT_FOUND'; end if;
  select ev.* into v_ev
  from programacion.evidencias ev
  join programacion.evaluaciones eva on eva.id=ev.evaluacion_id
  join programacion.objetivos_ejecucion oe on oe.id=eva.objetivo_id and oe.execution_id=v_ex.id
  where ev.id=p_evidence_id;
  if not found then raise exception 'EXTERNAL_VERIFY_V2_EVIDENCE_NOT_FOUND'; end if;
  select * into v_cp from programacion.context_packs where execution_id=v_ex.id and estado='COMPLETE' and digest_version=2;
  if not found then raise exception 'EXTERNAL_VERIFY_V2_CONTEXT_PACK_REQUIRED'; end if;
  select t.* into v_task from programacion.agent_tasks t where v_ex.request_ref='agent-task://'||t.id::text;
  if not found or v_task.definition_status<>'SEALED' then raise exception 'EXTERNAL_VERIFY_V2_TASK_REQUIRED'; end if;

  v_receipt:=v_ev.metadata->'worker_receipt';
  if coalesce(v_receipt->>'proof_contract_version','')<>'2' then raise exception 'EXTERNAL_VERIFY_V2_PROOF_CONTRACT_REQUIRED'; end if;
  if v_receipt->>'proof_source' is distinct from 'GITHUB_ACTIONS_JOB' then raise exception 'EXTERNAL_VERIFY_V2_PROOF_SOURCE_REQUIRED'; end if;

  if p_verification_payload->>'github_repository' is distinct from 'cristhianlujan/libertad-financiera'
     or p_verification_payload->>'github_repository_id' is distinct from '1301234955'
     or p_verification_payload->>'github_workflow_ref' is distinct from 'cristhianlujan/libertad-financiera/.github/workflows/hmo-001-machine-evidence-verifier.yml@refs/heads/lf/story-agent-machine-evidence-verifier-aud18-20260826'
     or p_verification_payload->>'github_workflow_sha' is distinct from 'e6a2dfbc13e3176e084680cb9da8c5ed5f073228'
     or coalesce(p_verification_payload->>'github_run_id','')!~'^[1-9][0-9]*$' then
    raise exception 'EXTERNAL_VERIFY_V2_VERIFIER_IDENTITY_PAYLOAD_MISMATCH';
  end if;

  if v_observed->>'remote_readback_status' is distinct from 'PASS'
     or v_observed->>'github_repository' is distinct from 'cristhianlujan/libertad-financiera'
     or v_observed->>'github_repository_id' is distinct from '1301234955' then
    raise exception 'EXTERNAL_VERIFY_V2_REMOTE_READBACK_INVALID';
  end if;
  if v_observed->>'producer_run_id' is distinct from v_receipt->>'github_actions_run_id'
     or v_observed->>'producer_run_id' is distinct from regexp_replace(v_ev.source_ref,'^.*/actions/runs/([0-9]+)$','\1') then
    raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_RUN_MISMATCH';
  end if;
  if v_observed->>'producer_job_id' is distinct from v_receipt->>'github_job_id' then
    raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_JOB_MISMATCH';
  end if;
  if v_observed->>'producer_run_conclusion' is distinct from 'success'
     or v_observed->>'producer_job_conclusion' is distinct from 'success' then
    raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_NOT_SUCCESS';
  end if;
  if v_observed->>'producer_workflow_path' is distinct from '.github/workflows/hmo-001-e2e-evidence.yml'
     or v_observed->>'producer_workflow_sha' is distinct from v_receipt->>'workflow_sha'
     or v_observed->>'producer_tested_head_sha' is distinct from v_ex.head_sha then
    raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_BINDING_MISMATCH';
  end if;
  if v_observed->>'remote_tree_sha' is distinct from v_cp.repository_inventory->>'git_tree_sha' then
    raise exception 'EXTERNAL_VERIFY_V2_TREE_SHA_MISMATCH';
  end if;

  v_expected_files:=to_jsonb(v_task.files_expected);
  v_observed_files:=v_observed->'remote_changed_files';
  if coalesce(jsonb_typeof(v_observed_files),'')<>'array' then raise exception 'EXTERNAL_VERIFY_V2_CHANGED_FILES_REQUIRED'; end if;
  select count(*) into v_expected_count from jsonb_array_elements_text(v_expected_files);
  select count(*) into v_observed_count from jsonb_array_elements_text(v_observed_files);
  if v_expected_count<>v_observed_count
     or exists(select 1 from jsonb_array_elements_text(v_expected_files) e(x) where not exists(select 1 from jsonb_array_elements_text(v_observed_files) o(x) where o.x=e.x))
     or exists(select 1 from jsonb_array_elements_text(v_observed_files) o(x) where not exists(select 1 from jsonb_array_elements_text(v_expected_files) e(x) where e.x=o.x)) then
    raise exception 'EXTERNAL_VERIFY_V2_CHANGED_FILES_MISMATCH';
  end if;
  if coalesce(v_observed->>'remote_changed_files_sha256','')!~'^[0-9a-f]{64}$'
     or v_observed->>'remote_changed_files_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_observed_files) then
    raise exception 'EXTERNAL_VERIFY_V2_CHANGED_FILES_SHA_MISMATCH';
  end if;
  if coalesce(jsonb_typeof(v_observed->'remote_file_blobs'),'')<>'object'
     or coalesce(v_observed->>'remote_file_blobs_sha256','')!~'^[0-9a-f]{64}$'
     or v_observed->>'remote_file_blobs_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_observed->'remote_file_blobs') then
    raise exception 'EXTERNAL_VERIFY_V2_REMOTE_BLOBS_SHA_MISMATCH';
  end if;
  if exists(select 1 from jsonb_array_elements_text(v_expected_files) e(x) where not ((v_observed->'remote_file_blobs') ? e.x))
     or exists(select 1 from jsonb_object_keys(v_observed->'remote_file_blobs') o(x) where not exists(select 1 from jsonb_array_elements_text(v_expected_files) e(x) where e.x=o.x)) then
    raise exception 'EXTERNAL_VERIFY_V2_REMOTE_BLOBS_SET_MISMATCH';
  end if;

  v_independent:=v_observed->'independent_execution';
  if coalesce(jsonb_typeof(v_independent),'')<>'object'
     or v_independent->>'status' is distinct from 'PASS'
     or v_independent->>'tested_head_sha' is distinct from v_ex.head_sha
     or v_independent->>'build' is distinct from 'PASS'
     or v_independent->>'lint' is distinct from 'PASS' then
    raise exception 'EXTERNAL_VERIFY_V2_INDEPENDENT_EXECUTION_INVALID';
  end if;
  if coalesce(v_independent->>'execution_sha256','')!~'^[0-9a-f]{64}$'
     or v_independent->>'execution_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_independent-'execution_sha256') then
    raise exception 'EXTERNAL_VERIFY_V2_EXECUTION_SHA_MISMATCH';
  end if;
  if coalesce((v_independent#>>'{semantic,passed_count}')::integer,0)<1
     or v_independent#>>'{semantic,passed_count}' is distinct from v_independent#>>'{semantic,total_count}'
     or coalesce((v_independent#>>'{semantic,failed_count}')::integer,-1)<>0 then
    raise exception 'EXTERNAL_VERIFY_V2_SEMANTIC_NOT_FULL_PASS';
  end if;
  if coalesce((v_independent#>>'{mutation,passed_count}')::integer,0)<1
     or v_independent#>>'{mutation,passed_count}' is distinct from v_independent#>>'{mutation,total_count}'
     or coalesce((v_independent#>>'{mutation,failed_count}')::integer,-1)<>0 then
    raise exception 'EXTERNAL_VERIFY_V2_MUTATION_NOT_FULL_PASS';
  end if;
  if coalesce((v_independent#>>'{auth_regression,passed_count}')::integer,0)<1
     or v_independent#>>'{auth_regression,passed_count}' is distinct from v_independent#>>'{auth_regression,total_count}'
     or coalesce((v_independent#>>'{auth_regression,failed_count}')::integer,-1)<>0 then
    raise exception 'EXTERNAL_VERIFY_V2_AUTH_NOT_FULL_PASS';
  end if;
  v_semantic:=(v_independent#>>'{semantic,passed_count}')||'/'||(v_independent#>>'{semantic,total_count}')||' PASS';
  v_mutation:=(v_independent#>>'{mutation,passed_count}')||'/'||(v_independent#>>'{mutation,total_count}')||' PASS';
  v_auth:=(v_independent#>>'{auth_regression,passed_count}')||'/'||(v_independent#>>'{auth_regression,total_count}')||' PASS';
  if v_semantic is distinct from v_receipt#>>'{tests,semantic}'
     or v_mutation is distinct from v_receipt#>>'{tests,mutation}'
     or v_auth is distinct from v_receipt#>>'{tests,auth_regression}' then
    raise exception 'EXTERNAL_VERIFY_V2_INDEPENDENT_SUMMARY_MISMATCH';
  end if;
end;
$function$;

revoke all on function programacion.fn_assert_worker_direct_readback_v2(bigint,bigint,jsonb) from public,anon,authenticated;
grant execute on function programacion.fn_assert_worker_direct_readback_v2(bigint,bigint,jsonb) to service_role;

create or replace function programacion.fn_external_verify_worker_evidence_v1(
 p_execution_id bigint, p_evidence_id bigint, p_expected_head_sha text, p_expected_evidence_sha256 text,
 p_expected_source_system text, p_expected_source_ref text, p_verification_method text,
 p_verifier_identity text, p_verification_payload jsonb, p_verification_ref text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_ex programacion.ejecuciones%rowtype; v_ev programacion.evidencias%rowtype; v_cp programacion.context_packs%rowtype;
  v_eval_status text; v_eval_id bigint; v_token text; v_channel_hash text; v_token_hash text; v_subject_sha text;
  v_receipt_id bigint; v_receipt_sha text; v_verification_id bigint; v_verification_sha text;
  v_subject_payload jsonb; v_receipt_payload jsonb; v_worker_receipt jsonb; v_proof_version text;
begin
  if p_verification_payload is null or jsonb_typeof(p_verification_payload)<>'object' then raise exception 'EXTERNAL_VERIFICATION_PAYLOAD_REQUIRED'; end if;
  if length(btrim(coalesce(p_verification_ref,'')))=0 then raise exception 'EXTERNAL_VERIFICATION_REF_REQUIRED'; end if;

  select * into v_ex from programacion.ejecuciones where id=p_execution_id;
  if not found then raise exception 'EXTERNAL_VERIFY_EXECUTION_NOT_FOUND'; end if;
  if v_ex.estado<>'RUNNING' or v_ex.request_ref!~'^agent-task://[1-9][0-9]*$' then raise exception 'EXTERNAL_VERIFY_AGENT_TASK_RUNNING_REQUIRED'; end if;
  if v_ex.head_sha is distinct from p_expected_head_sha then raise exception 'EXTERNAL_VERIFY_HEAD_MISMATCH'; end if;

  select ev.* into v_ev from programacion.evidencias ev
  join programacion.evaluaciones eva on eva.id=ev.evaluacion_id
  join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id and obj.execution_id=v_ex.id
  where ev.id=p_evidence_id;
  if not found then raise exception 'EXTERNAL_VERIFY_EVIDENCE_NOT_FOUND'; end if;
  select resultado,id into v_eval_status,v_eval_id from programacion.evaluaciones where id=v_ev.evaluacion_id;
  if v_eval_status<>'PENDING' then raise exception 'EXTERNAL_VERIFY_EVALUATION_PENDING_REQUIRED'; end if;
  if v_ev.tipo<>'VERIFIED_WORKER_RECEIPT' then raise exception 'EXTERNAL_VERIFY_WORKER_RECEIPT_REQUIRED'; end if;
  if v_ev.sha256 is distinct from p_expected_evidence_sha256 then raise exception 'EXTERNAL_VERIFY_EVIDENCE_SHA_MISMATCH'; end if;
  if v_ev.source_system is distinct from p_expected_source_system then raise exception 'EXTERNAL_VERIFY_SOURCE_SYSTEM_MISMATCH'; end if;
  if v_ev.source_ref is distinct from p_expected_source_ref then raise exception 'EXTERNAL_VERIFY_SOURCE_REF_MISMATCH'; end if;
  if v_ev.source_system<>'PROGRAMMING_AGENT_WORKER' then raise exception 'EXTERNAL_VERIFY_WORKER_SOURCE_REQUIRED'; end if;

  v_worker_receipt:=v_ev.metadata->'worker_receipt';
  v_proof_version:=coalesce(v_worker_receipt->>'proof_contract_version','1');
  if v_proof_version='2' then
    if p_verification_method<>'GITHUB_ACTIONS_OIDC_GITHUB_API_EVIDENCE_V2' then raise exception 'EXTERNAL_VERIFY_V2_METHOD_REQUIRED'; end if;
    if p_verifier_identity!~'^github-actions://cristhianlujan/libertad-financiera/[.]github/workflows/hmo-001-machine-evidence-verifier[.]yml@refs/heads/lf/story-agent-machine-evidence-verifier-aud18-20260826#run-[0-9]+$' then raise exception 'EXTERNAL_VERIFIER_IDENTITY_INVALID'; end if;
    perform programacion.fn_assert_worker_direct_readback_v2(v_ex.id,v_ev.id,p_verification_payload);
  else
    if p_verification_method<>'GITHUB_ACTIONS_OIDC_EXACT_EVIDENCE_V1' then raise exception 'EXTERNAL_VERIFICATION_METHOD_INVALID'; end if;
    if p_verifier_identity!~'^github-actions://cristhianlujan/claude-persona-lf-patch/[.]github/workflows/story-agent-evidence-verifier[.]yml@refs/heads/main#run-[0-9]+$' then raise exception 'EXTERNAL_VERIFIER_IDENTITY_INVALID'; end if;
  end if;
  if p_verifier_identity=v_ev.source_system or p_verifier_identity=v_ev.source_ref then raise exception 'EXTERNAL_VERIFY_SELF_VERIFICATION_FORBIDDEN'; end if;

  select * into v_cp from programacion.context_packs where execution_id=v_ex.id and estado='COMPLETE' and digest_version=2;
  if not found then raise exception 'EXTERNAL_VERIFY_CONTEXT_PACK_REQUIRED'; end if;
  if v_worker_receipt->>'status'<>'PASS'
     or v_worker_receipt->>'execution_id'<>v_ex.id::text
     or v_worker_receipt->>'context_pack_id'<>v_cp.id::text
     or v_worker_receipt->>'context_pack_sha256'<>v_cp.context_sha256 then raise exception 'EXTERNAL_VERIFY_WORKER_RECEIPT_BINDING_INVALID'; end if;
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

  if v_proof_version='2' then
    update programacion.evaluaciones
    set resultado='PASS',finished_at=now(),
        resumen='PASS after independent direct GitHub readback and exact-head machine re-execution.',
        detalles=detalles||jsonb_build_object('evidence_verification_id',v_verification_id,'evidence_verification_sha256',v_verification_sha,
          'authority_receipt_id',v_receipt_id,'authority_receipt_sha256',v_receipt_sha,'external_verification_method',p_verification_method)
    where id=v_eval_id;
  end if;

  return jsonb_build_object('status','VERIFIED','execution_id',v_ex.id,'evaluation_id',v_eval_id,'evidence_id',v_ev.id,
    'authority_receipt_id',v_receipt_id,'authority_receipt_sha256',v_receipt_sha,
    'evidence_verification_id',v_verification_id,'evidence_verification_sha256',v_verification_sha);
end;
$function$;

create or replace function programacion.fn_agent_task_worker_context_receipt_ok(p_execution_id bigint)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select exists(
    select 1
    from programacion.ejecuciones ex
    join programacion.context_packs cp on cp.execution_id=ex.id and cp.estado='COMPLETE' and cp.digest_version=2
    join programacion.objetivos_ejecucion obj on obj.execution_id=ex.id
    join programacion.evaluaciones eva on eva.objetivo_id=obj.id and eva.resultado='PASS'
    join programacion.evidencias ev on ev.evaluacion_id=eva.id
    where ex.id=p_execution_id
      and ex.request_ref~'^agent-task://[1-9][0-9]*$'
      and programacion.fn_evaluation_pass_evidence_valid_v1(eva.id)
      and ev.tipo='VERIFIED_WORKER_RECEIPT'
      and ev.source_system='PROGRAMMING_AGENT_WORKER'
      and ev.sha256=ev.metadata->>'receipt_sha256'
      and ev.metadata#>>'{worker_receipt,status}'='PASS'
      and ev.metadata#>>'{worker_receipt,execution_id}'=ex.id::text
      and ev.metadata#>>'{worker_receipt,context_pack_id}'=cp.id::text
      and ev.metadata#>>'{worker_receipt,context_pack_sha256}'=cp.context_sha256
      and programacion.fn_evidence_pass_compatible_v1(ev.id)
      and (
        coalesce(ev.metadata#>>'{worker_receipt,proof_contract_version}','1')<>'2'
        or exists(
          select 1 from programacion.evidence_verifications vv
          where vv.evidence_id=ev.id and vv.verification_status='VERIFIED'
            and vv.evidence_sha256=ev.sha256 and vv.source_system=ev.source_system and vv.source_ref=ev.source_ref
            and vv.verification_method='GITHUB_ACTIONS_OIDC_GITHUB_API_EVIDENCE_V2'
            and vv.verification_payload#>>'{observed,remote_readback_status}'='PASS'
            and vv.verification_payload#>>'{observed,independent_execution,status}'='PASS'
            and vv.authority_receipt_id is not null
        )
      )
  );
$function$;

-- Keep the existing materializer, but bind proof-v2 materialization to the new externally observed verifier identity
-- and preserve legacy V1 compatibility. The changes are deterministic patches over the immediately preceding canonical definition.
do $patch$
declare v_ddl text;
begin
  select pg_get_functiondef(p.oid) into v_ddl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_agent_task_materialize_verified_machine_gates_v1' and p.prokind='f';
  if v_ddl is null then raise exception 'MACHINE_GATE_MATERIALIZER_NOT_FOUND'; end if;
  if position('github-actions://cristhianlujan/claude-persona-lf-patch/[.]github/workflows/story-agent-evidence-verifier[.]yml@refs/heads/main#run-[0-9]+' in v_ddl)=0 then
    raise exception 'MACHINE_GATE_MATERIALIZER_EXPECTED_IDENTITY_NOT_FOUND';
  end if;
  v_ddl:=replace(v_ddl,
    "if p_verifier_identity !~ '^github-actions://cristhianlujan/claude-persona-lf-patch/[.]github/workflows/story-agent-evidence-verifier[.]yml@refs/heads/main#run-[0-9]+$' then",
    "if not (p_verifier_identity ~ '^github-actions://cristhianlujan/claude-persona-lf-patch/[.]github/workflows/story-agent-evidence-verifier[.]yml@refs/heads/main#run-[0-9]+$' or p_verifier_identity ~ '^github-actions://cristhianlujan/libertad-financiera/[.]github/workflows/hmo-001-machine-evidence-verifier[.]yml@refs/heads/lf/story-agent-machine-evidence-verifier-aud18-20260826#run-[0-9]+$') then");
  v_ddl:=replace(v_ddl,
    "if v_source_verification_id is null then raise exception 'MACHINE_GATE_SOURCE_VERIFICATION_NOT_FOUND:%',v_source_ev.id; end if;",
    "if v_source_verification_id is null then raise exception 'MACHINE_GATE_SOURCE_VERIFICATION_NOT_FOUND:%',v_source_ev.id; end if; if coalesce(v_source_ev.metadata#>>'{worker_receipt,proof_contract_version}','1')='2' and not exists(select 1 from programacion.evidence_verifications vv where vv.id=v_source_verification_id and vv.verification_method='GITHUB_ACTIONS_OIDC_GITHUB_API_EVIDENCE_V2' and vv.verification_payload#>>'{observed,remote_readback_status}'='PASS' and vv.verification_payload#>>'{observed,independent_execution,status}'='PASS') then raise exception 'MACHINE_GATE_DIRECT_READBACK_V2_REQUIRED:%',v_source_ev.id; end if;");
  execute v_ddl;
end;
$patch$;
