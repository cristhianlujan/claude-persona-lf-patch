-- STORY_AGENT pre-audit AUD-018 run-id parser fix
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
  if p_verification_payload is null or jsonb_typeof(p_verification_payload)<>'object' then raise exception 'EXTERNAL_VERIFY_V2_PAYLOAD_REQUIRED'; end if;
  v_observed:=p_verification_payload->'observed';
  if v_observed is null or jsonb_typeof(v_observed)<>'object' then raise exception 'EXTERNAL_VERIFY_V2_OBSERVED_REQUIRED'; end if;
  if coalesce(v_observed->>'observed_sha256','')!~'^[0-9a-f]{64}$' or v_observed->>'observed_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_observed-'observed_sha256') then raise exception 'EXTERNAL_VERIFY_V2_OBSERVED_SHA_MISMATCH'; end if;
  select * into v_ex from programacion.ejecuciones where id=p_execution_id; if not found then raise exception 'EXTERNAL_VERIFY_V2_EXECUTION_NOT_FOUND'; end if;
  select ev.* into v_ev from programacion.evidencias ev join programacion.evaluaciones eva on eva.id=ev.evaluacion_id join programacion.objetivos_ejecucion oe on oe.id=eva.objetivo_id and oe.execution_id=v_ex.id where ev.id=p_evidence_id;
  if not found then raise exception 'EXTERNAL_VERIFY_V2_EVIDENCE_NOT_FOUND'; end if;
  select * into v_cp from programacion.context_packs where execution_id=v_ex.id and estado='COMPLETE' and digest_version=2; if not found then raise exception 'EXTERNAL_VERIFY_V2_CONTEXT_PACK_REQUIRED'; end if;
  select t.* into v_task from programacion.agent_tasks t where v_ex.request_ref='agent-task://'||t.id::text; if not found or v_task.definition_status<>'SEALED' then raise exception 'EXTERNAL_VERIFY_V2_TASK_REQUIRED'; end if;
  v_receipt:=v_ev.metadata->'worker_receipt';
  if coalesce(v_receipt->>'proof_contract_version','')<>'2' then raise exception 'EXTERNAL_VERIFY_V2_PROOF_CONTRACT_REQUIRED'; end if;
  if v_receipt->>'proof_source' is distinct from 'GITHUB_ACTIONS_JOB' then raise exception 'EXTERNAL_VERIFY_V2_PROOF_SOURCE_REQUIRED'; end if;
  if p_verification_payload->>'github_repository' is distinct from 'cristhianlujan/libertad-financiera' or p_verification_payload->>'github_repository_id' is distinct from '1301234955'
     or p_verification_payload->>'github_workflow_ref' is distinct from 'cristhianlujan/libertad-financiera/.github/workflows/hmo-001-machine-evidence-verifier.yml@refs/heads/lf/story-agent-machine-evidence-verifier-aud18-20260826'
     or p_verification_payload->>'github_workflow_sha' is distinct from 'e6a2dfbc13e3176e084680cb9da8c5ed5f073228' or coalesce(p_verification_payload->>'github_run_id','')!~'^[1-9][0-9]*$' then raise exception 'EXTERNAL_VERIFY_V2_VERIFIER_IDENTITY_PAYLOAD_MISMATCH'; end if;
  if v_observed->>'remote_readback_status' is distinct from 'PASS' or v_observed->>'github_repository' is distinct from 'cristhianlujan/libertad-financiera' or v_observed->>'github_repository_id' is distinct from '1301234955' then raise exception 'EXTERNAL_VERIFY_V2_REMOTE_READBACK_INVALID'; end if;
  if v_observed->>'producer_run_id' is distinct from v_receipt->>'github_actions_run_id' or v_observed->>'producer_run_id' is distinct from substring(v_ev.source_ref from '/actions/runs/([0-9]+)$') then raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_RUN_MISMATCH'; end if;
  if v_observed->>'producer_job_id' is distinct from v_receipt->>'github_job_id' then raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_JOB_MISMATCH'; end if;
  if v_observed->>'producer_run_conclusion' is distinct from 'success' or v_observed->>'producer_job_conclusion' is distinct from 'success' then raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_NOT_SUCCESS'; end if;
  if v_observed->>'producer_workflow_path' is distinct from '.github/workflows/hmo-001-e2e-evidence.yml' or v_observed->>'producer_workflow_sha' is distinct from v_receipt->>'workflow_sha' or v_observed->>'producer_tested_head_sha' is distinct from v_ex.head_sha then raise exception 'EXTERNAL_VERIFY_V2_PRODUCER_BINDING_MISMATCH'; end if;
  if v_observed->>'remote_tree_sha' is distinct from v_cp.repository_inventory->>'git_tree_sha' then raise exception 'EXTERNAL_VERIFY_V2_TREE_SHA_MISMATCH'; end if;
  v_expected_files:=to_jsonb(v_task.files_expected); v_observed_files:=v_observed->'remote_changed_files';
  if coalesce(jsonb_typeof(v_observed_files),'')<>'array' then raise exception 'EXTERNAL_VERIFY_V2_CHANGED_FILES_REQUIRED'; end if;
  select count(*) into v_expected_count from jsonb_array_elements_text(v_expected_files); select count(*) into v_observed_count from jsonb_array_elements_text(v_observed_files);
  if v_expected_count<>v_observed_count or exists(select 1 from jsonb_array_elements_text(v_expected_files) e(x) where not exists(select 1 from jsonb_array_elements_text(v_observed_files) o(x) where o.x=e.x)) or exists(select 1 from jsonb_array_elements_text(v_observed_files) o(x) where not exists(select 1 from jsonb_array_elements_text(v_expected_files) e(x) where e.x=o.x)) then raise exception 'EXTERNAL_VERIFY_V2_CHANGED_FILES_MISMATCH'; end if;
  if coalesce(v_observed->>'remote_changed_files_sha256','')!~'^[0-9a-f]{64}$' or v_observed->>'remote_changed_files_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_observed_files) then raise exception 'EXTERNAL_VERIFY_V2_CHANGED_FILES_SHA_MISMATCH'; end if;
  if coalesce(jsonb_typeof(v_observed->'remote_file_blobs'),'')<>'object' or coalesce(v_observed->>'remote_file_blobs_sha256','')!~'^[0-9a-f]{64}$' or v_observed->>'remote_file_blobs_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_observed->'remote_file_blobs') then raise exception 'EXTERNAL_VERIFY_V2_REMOTE_BLOBS_SHA_MISMATCH'; end if;
  if exists(select 1 from jsonb_array_elements_text(v_expected_files) e(x) where not ((v_observed->'remote_file_blobs') ? e.x)) or exists(select 1 from jsonb_object_keys(v_observed->'remote_file_blobs') o(x) where not exists(select 1 from jsonb_array_elements_text(v_expected_files) e(x) where e.x=o.x)) then raise exception 'EXTERNAL_VERIFY_V2_REMOTE_BLOBS_SET_MISMATCH'; end if;
  v_independent:=v_observed->'independent_execution';
  if coalesce(jsonb_typeof(v_independent),'')<>'object' or v_independent->>'status' is distinct from 'PASS' or v_independent->>'tested_head_sha' is distinct from v_ex.head_sha or v_independent->>'build' is distinct from 'PASS' or v_independent->>'lint' is distinct from 'PASS' then raise exception 'EXTERNAL_VERIFY_V2_INDEPENDENT_EXECUTION_INVALID'; end if;
  if coalesce(v_independent->>'execution_sha256','')!~'^[0-9a-f]{64}$' or v_independent->>'execution_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_independent-'execution_sha256') then raise exception 'EXTERNAL_VERIFY_V2_EXECUTION_SHA_MISMATCH'; end if;
  if coalesce((v_independent#>>'{semantic,passed_count}')::integer,0)<1 or v_independent#>>'{semantic,passed_count}' is distinct from v_independent#>>'{semantic,total_count}' or coalesce((v_independent#>>'{semantic,failed_count}')::integer,-1)<>0 then raise exception 'EXTERNAL_VERIFY_V2_SEMANTIC_NOT_FULL_PASS'; end if;
  if coalesce((v_independent#>>'{mutation,passed_count}')::integer,0)<1 or v_independent#>>'{mutation,passed_count}' is distinct from v_independent#>>'{mutation,total_count}' or coalesce((v_independent#>>'{mutation,failed_count}')::integer,-1)<>0 then raise exception 'EXTERNAL_VERIFY_V2_MUTATION_NOT_FULL_PASS'; end if;
  if coalesce((v_independent#>>'{auth_regression,passed_count}')::integer,0)<1 or v_independent#>>'{auth_regression,passed_count}' is distinct from v_independent#>>'{auth_regression,total_count}' or coalesce((v_independent#>>'{auth_regression,failed_count}')::integer,-1)<>0 then raise exception 'EXTERNAL_VERIFY_V2_AUTH_NOT_FULL_PASS'; end if;
  v_semantic:=(v_independent#>>'{semantic,passed_count}')||'/'||(v_independent#>>'{semantic,total_count}')||' PASS'; v_mutation:=(v_independent#>>'{mutation,passed_count}')||'/'||(v_independent#>>'{mutation,total_count}')||' PASS'; v_auth:=(v_independent#>>'{auth_regression,passed_count}')||'/'||(v_independent#>>'{auth_regression,total_count}')||' PASS';
  if v_semantic is distinct from v_receipt#>>'{tests,semantic}' or v_mutation is distinct from v_receipt#>>'{tests,mutation}' or v_auth is distinct from v_receipt#>>'{tests,auth_regression}' then raise exception 'EXTERNAL_VERIFY_V2_INDEPENDENT_SUMMARY_MISMATCH'; end if;
end;
$function$;

revoke all on function programacion.fn_assert_worker_direct_readback_v2(bigint,bigint,jsonb) from public,anon,authenticated;
grant execute on function programacion.fn_assert_worker_direct_readback_v2(bigint,bigint,jsonb) to service_role;