begin;

create or replace function programacion.fn_agent_task_pending_worker_evidence_v1(p_task_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
  v jsonb;
  v_task programacion.agent_tasks%rowtype;
  v_current_task_id bigint;
begin
  if p_task_id is null or p_task_id < 1 then raise exception 'AGENT_TASK_ID_INVALID'; end if;

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

  select jsonb_build_object(
    'execution_id',ex.id,
    'request_ref',ex.request_ref,
    'head_sha',ex.head_sha,
    'source_snapshot_sha256',ex.source_snapshot_sha256,
    'context_pack_id',cp.id,
    'context_pack_sha256',cp.context_sha256,
    'context_git_tree_sha',cp.repository_inventory->>'git_tree_sha',
    'evaluation_id',eva.id,
    'evaluation_status',eva.resultado,
    'evidence_id',ev.id,
    'evidence_sha256',ev.sha256,
    'source_system',ev.source_system,
    'source_ref',ev.source_ref,
    'worker_receipt_status',ev.metadata#>>'{worker_receipt,status}',
    'producer_run_id',(ev.metadata#>>'{worker_receipt,github_actions_run_id}')::bigint,
    'producer_job_id',(ev.metadata#>>'{worker_receipt,github_job_id}')::bigint,
    'producer_workflow_sha',ev.metadata#>>'{worker_receipt,workflow_sha}',
    'worker_tests',ev.metadata#>'{worker_receipt,tests}',
    'task_files_expected',to_jsonb(v_task.files_expected),
    'max_changed_files',v_task.max_changed_files,
    'allow_deletions',v_task.allow_deletions,
    'comparison_base_head_sha',(
      select prior.head_sha
      from programacion.ejecuciones prior
      where prior.request_ref=ex.request_ref
        and prior.id<ex.id
        and prior.head_sha~'^[0-9a-f]{40}$'
      order by prior.id desc
      limit 1
    )
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
  if coalesce(v->>'comparison_base_head_sha','')!~'^[0-9a-f]{40}$' then
    raise exception 'PENDING_WORKER_EVIDENCE_COMPARISON_BASE_REQUIRED: agent-task://%',p_task_id;
  end if;
  return v;
end;
$function$;

create or replace function programacion.fn_assert_worker_direct_readback_v2(
  p_execution_id bigint,
  p_evidence_id bigint,
  p_verification_payload jsonb
)
returns void
language plpgsql
stable
security definer
set search_path='pg_catalog','programacion'
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
  v_prior_head text;
  v_semantic text;
  v_mutation text;
  v_auth text;
begin
  if p_verification_payload is null or jsonb_typeof(p_verification_payload)<>'object' then raise exception 'EXTERNAL_VERIFY_V2_PAYLOAD_REQUIRED'; end if;
  v_observed:=p_verification_payload->'observed';
  if v_observed is null or jsonb_typeof(v_observed)<>'object' then raise exception 'EXTERNAL_VERIFY_V2_OBSERVED_REQUIRED'; end if;
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

  select * into v_cp
  from programacion.context_packs
  where execution_id=v_ex.id and estado='COMPLETE' and digest_version=2;
  if not found then raise exception 'EXTERNAL_VERIFY_V2_CONTEXT_PACK_REQUIRED'; end if;

  select t.* into v_task
  from programacion.agent_tasks t
  where v_ex.request_ref='agent-task://'||t.id::text;
  if not found or v_task.definition_status<>'SEALED' then raise exception 'EXTERNAL_VERIFY_V2_TASK_REQUIRED'; end if;

  v_receipt:=v_ev.metadata->'worker_receipt';
  if coalesce(v_receipt->>'proof_contract_version','')<>'2' then raise exception 'EXTERNAL_VERIFY_V2_PROOF_CONTRACT_REQUIRED'; end if;
  if v_receipt->>'proof_source' is distinct from 'GITHUB_ACTIONS_JOB' then raise exception 'EXTERNAL_VERIFY_V2_PROOF_SOURCE_REQUIRED'; end if;

  if p_verification_payload->>'github_repository' is distinct from 'cristhianlujan/libertad-financiera'
     or p_verification_payload->>'github_repository_id' is distinct from '1301234955'
     or p_verification_payload->>'github_workflow_ref' is distinct from 'cristhianlujan/libertad-financiera/.github/workflows/hmo-001-machine-evidence-verifier.yml@refs/heads/lf/story-agent-machine-evidence-verifier-aud18-20260826'
     or p_verification_payload->>'github_workflow_sha' is distinct from '11646eab03530d5fd61209609e27c2ec8368639f'
     or coalesce(p_verification_payload->>'github_run_id','')!~'^[1-9][0-9]*$' then
    raise exception 'EXTERNAL_VERIFY_V2_VERIFIER_IDENTITY_PAYLOAD_MISMATCH';
  end if;

  if v_observed->>'remote_readback_status' is distinct from 'PASS'
     or v_observed->>'github_repository' is distinct from 'cristhianlujan/libertad-financiera'
     or v_observed->>'github_repository_id' is distinct from '1301234955' then
    raise exception 'EXTERNAL_VERIFY_V2_REMOTE_READBACK_INVALID';
  end if;

  if v_observed->>'producer_run_id' is distinct from v_receipt->>'github_actions_run_id'
     or v_observed->>'producer_run_id' is distinct from substring(v_ev.source_ref from '/actions/runs/([0-9]+)$') then
    raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_RUN_MISMATCH';
  end if;
  if v_observed->>'producer_job_id' is distinct from v_receipt->>'github_job_id' then raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_JOB_MISMATCH'; end if;
  if v_observed->>'producer_run_conclusion' is distinct from 'success' or v_observed->>'producer_job_conclusion' is distinct from 'success' then raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_NOT_SUCCESS'; end if;
  if v_observed->>'producer_workflow_path' is distinct from '.github/workflows/hmo-001-e2e-evidence.yml'
     or v_observed->>'producer_workflow_sha' is distinct from v_receipt->>'workflow_sha'
     or v_observed->>'producer_tested_head_sha' is distinct from v_ex.head_sha then
    raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_BINDING_MISMATCH';
  end if;
  if v_observed->>'remote_tree_sha' is distinct from v_cp.repository_inventory->>'git_tree_sha' then raise exception 'EXTERNAL_VERIFY_V2_TREE_SHA_MISMATCH'; end if;

  select prior.head_sha into v_prior_head
  from programacion.ejecuciones prior
  where prior.request_ref=v_ex.request_ref and prior.id<v_ex.id and prior.head_sha~'^[0-9a-f]{40}$'
  order by prior.id desc limit 1;
  if v_prior_head is null or v_observed->>'comparison_base_head_sha' is distinct from v_prior_head then
    raise exception 'EXTERNAL_VERIFY_V2_COMPARISON_BASE_MISMATCH';
  end if;

  v_expected_files:=to_jsonb(v_task.files_expected);
  v_observed_files:=v_observed->'remote_changed_files';
  if coalesce(jsonb_typeof(v_observed_files),'')<>'array' then raise exception 'EXTERNAL_VERIFY_V2_CHANGED_FILES_REQUIRED'; end if;
  select count(*) into v_expected_count from jsonb_array_elements_text(v_expected_files);
  select count(*) into v_observed_count from jsonb_array_elements_text(v_observed_files);
  if v_observed_count<1 or v_observed_count>v_task.max_changed_files then raise exception 'EXTERNAL_VERIFY_V2_CHANGED_FILE_COUNT_INVALID'; end if;
  if exists(
    select 1 from jsonb_array_elements_text(v_observed_files) o(x)
    where not exists(select 1 from jsonb_array_elements_text(v_expected_files) e(x) where e.x=o.x)
  ) then
    raise exception 'EXTERNAL_VERIFY_V2_CHANGED_FILES_OUTSIDE_TASK';
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
     or coalesce((v_independent#>>'{semantic,failed_count}')::integer,-1)<>0 then raise exception 'EXTERNAL_VERIFY_V2_SEMANTIC_NOT_FULL_PASS'; end if;
  if coalesce((v_independent#>>'{mutation,passed_count}')::integer,0)<1
     or v_independent#>>'{mutation,passed_count}' is distinct from v_independent#>>'{mutation,total_count}'
     or coalesce((v_independent#>>'{mutation,failed_count}')::integer,-1)<>0 then raise exception 'EXTERNAL_VERIFY_V2_MUTATION_NOT_FULL_PASS'; end if;
  if coalesce((v_independent#>>'{auth_regression,passed_count}')::integer,0)<1
     or v_independent#>>'{auth_regression,passed_count}' is distinct from v_independent#>>'{auth_regression,total_count}'
     or coalesce((v_independent#>>'{auth_regression,failed_count}')::integer,-1)<>0 then raise exception 'EXTERNAL_VERIFY_V2_AUTH_NOT_FULL_PASS'; end if;

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

commit;
