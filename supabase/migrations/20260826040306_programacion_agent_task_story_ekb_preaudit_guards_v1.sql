-- Story Agent EKB pre-audit hardening v1
-- AUD-018: reject machine-gate PASS receipts backed only by legacy textual summaries.
-- AUD-019/AUD24-F03: require complete sealed AC/INV/NEG coverage + fresh target challenge for any future F03 PASS receipt.
-- No new tables; no guard relaxation; F03 remains fail-closed.

create or replace function programacion.fn_assert_worker_machine_proof_contract_v2(
  p_worker_receipt jsonb,
  p_expected_head_sha text,
  p_expected_source_ref text
)
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_proofs jsonb;
  v_tests jsonb;
  v_proof jsonb;
  v_key text;
  v_run_id text;
  v_expected_count_text text;
  v_passed integer;
  v_total integer;
begin
  if coalesce(jsonb_typeof(p_worker_receipt),'')<>'object' then
    raise exception 'MACHINE_PROOF_WORKER_RECEIPT_REQUIRED';
  end if;
  if p_worker_receipt->>'status'<>'PASS' then return; end if;
  if p_worker_receipt->>'proof_contract_version' is distinct from '2' then
    raise exception 'MACHINE_PROOF_CONTRACT_V2_REQUIRED';
  end if;
  if p_worker_receipt->>'proof_source' is distinct from 'GITHUB_ACTIONS_JOB' then
    raise exception 'MACHINE_PROOF_GITHUB_ACTIONS_SOURCE_REQUIRED';
  end if;
  v_run_id:=p_worker_receipt->>'github_actions_run_id';
  if coalesce(v_run_id,'')!~'^[1-9][0-9]*$' then
    raise exception 'MACHINE_PROOF_RUN_ID_INVALID';
  end if;
  if coalesce(p_expected_source_ref,'')!~('^github-actions://[^/]+/[^/]+/actions/runs/'||v_run_id||'$') then
    raise exception 'MACHINE_PROOF_SOURCE_REF_RUN_MISMATCH';
  end if;
  v_proofs:=p_worker_receipt->'proofs';
  v_tests:=p_worker_receipt->'tests';
  if coalesce(jsonb_typeof(v_proofs),'')<>'object' or coalesce(jsonb_typeof(v_tests),'')<>'object' then
    raise exception 'MACHINE_PROOF_SET_AND_TESTS_REQUIRED';
  end if;
  if coalesce(p_worker_receipt->>'proofs_sha256','')!~'^[0-9a-f]{64}$'
     or p_worker_receipt->>'proofs_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_proofs) then
    raise exception 'MACHINE_PROOF_SET_SHA_MISMATCH';
  end if;

  foreach v_key in array array['build','lint','semantic','mutation'] loop
    v_proof:=v_proofs->v_key;
    if coalesce(jsonb_typeof(v_proof),'')<>'object' then
      raise exception 'MACHINE_PROOF_REQUIRED:%',v_key;
    end if;
    if v_proof->'executed' is distinct from 'true'::jsonb
       or v_proof->>'exit_code' is distinct from '0'
       or v_proof->>'status' is distinct from 'PASS'
       or v_proof->>'conclusion' is distinct from 'success'
       or v_proof->>'tested_head_sha' is distinct from p_expected_head_sha
       or v_proof->>'run_id' is distinct from v_run_id then
      raise exception 'MACHINE_PROOF_EXECUTION_BINDING_INVALID:%',v_key;
    end if;
    if coalesce(v_proof->>'job_id','')!~'^[1-9][0-9]*$'
       or coalesce(v_proof->>'workflow_sha','')!~'^[0-9a-f]{40}$'
       or coalesce(v_proof->>'command_sha256','')!~'^[0-9a-f]{64}$'
       or coalesce(v_proof->>'output_sha256','')!~'^[0-9a-f]{64}$'
       or coalesce(v_proof->>'proof_sha256','')!~'^[0-9a-f]{64}$' then
      raise exception 'MACHINE_PROOF_DIGEST_OR_ID_INVALID:%',v_key;
    end if;
    if v_proof->>'proof_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_proof-'proof_sha256') then
      raise exception 'MACHINE_PROOF_SHA_MISMATCH:%',v_key;
    end if;

    if v_key in ('build','lint') then
      if v_tests->>v_key is distinct from 'PASS' then
        raise exception 'MACHINE_PROOF_LEGACY_SUMMARY_MISMATCH:%',v_key;
      end if;
    else
      if coalesce(v_proof->>'passed_count','')!~'^[1-9][0-9]*$'
         or coalesce(v_proof->>'total_count','')!~'^[1-9][0-9]*$'
         or coalesce(v_proof->>'test_manifest_sha256','')!~'^[0-9a-f]{64}$' then
        raise exception 'MACHINE_PROOF_TEST_COUNTS_INVALID:%',v_key;
      end if;
      v_passed:=(v_proof->>'passed_count')::integer;
      v_total:=(v_proof->>'total_count')::integer;
      if v_passed<>v_total then
        raise exception 'MACHINE_PROOF_TESTS_NOT_FULL_PASS:%',v_key;
      end if;
      v_expected_count_text:=v_passed::text||'/'||v_total::text||' PASS';
      if v_tests->>v_key is distinct from v_expected_count_text then
        raise exception 'MACHINE_PROOF_LEGACY_SUMMARY_MISMATCH:%',v_key;
      end if;
    end if;
  end loop;
end;
$function$;

revoke all on function programacion.fn_assert_worker_machine_proof_contract_v2(jsonb,text,text) from public,anon,authenticated,service_role;
grant execute on function programacion.fn_assert_worker_machine_proof_contract_v2(jsonb,text,text) to postgres;

create or replace function programacion.fn_guard_worker_machine_proof_contract_v2()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
begin
  if new.tipo='VERIFIED_WORKER_RECEIPT'
     and new.source_system='PROGRAMMING_AGENT_WORKER'
     and new.metadata#>>'{worker_receipt,status}'='PASS' then
    perform programacion.fn_assert_worker_machine_proof_contract_v2(new.metadata->'worker_receipt',new.head_sha,new.source_ref);
  end if;
  return new;
end;
$function$;

revoke all on function programacion.fn_guard_worker_machine_proof_contract_v2() from public,anon,authenticated,service_role;
grant execute on function programacion.fn_guard_worker_machine_proof_contract_v2() to postgres;

drop trigger if exists trg_evidencias_machine_proof_v2_guard on programacion.evidencias;
create trigger trg_evidencias_machine_proof_v2_guard
before insert on programacion.evidencias
for each row execute function programacion.fn_guard_worker_machine_proof_contract_v2();

comment on function programacion.fn_assert_worker_machine_proof_contract_v2(jsonb,text,text)
is 'AUD-018 Story Agent guard: PASS worker receipts require proof_contract_version=2 and per-gate GitHub Actions execution proofs with exact-head/run/job/workflow/digest binding; legacy PASS strings alone are rejected.';

create or replace function programacion.fn_assert_f03_criteria_coverage_v2(p_payload jsonb,p_criteria_snapshot jsonb)
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_cov jsonb;
  v_acceptance jsonb;
  v_invariants jsonb;
  v_negative jsonb;
begin
  if coalesce(jsonb_typeof(p_payload),'')<>'object' or coalesce(jsonb_typeof(p_criteria_snapshot),'')<>'object' then
    raise exception 'F03_CRITERIA_COVERAGE_INPUT_REQUIRED';
  end if;
  v_cov:=p_payload->'criteria_coverage';
  v_acceptance:=p_criteria_snapshot->'acceptance_refs';
  v_invariants:=p_criteria_snapshot->'invariant_refs';
  v_negative:=p_criteria_snapshot->'negative_refs';
  if coalesce(jsonb_typeof(v_cov),'')<>'object'
     or coalesce(jsonb_typeof(v_acceptance),'')<>'array'
     or coalesce(jsonb_typeof(v_invariants),'')<>'array'
     or coalesce(jsonb_typeof(v_negative),'')<>'array' then
    raise exception 'F03_CRITERIA_COVERAGE_OBJECT_REQUIRED';
  end if;
  if jsonb_array_length(v_acceptance)<1 or jsonb_array_length(v_invariants)<1 or jsonb_array_length(v_negative)<1 then
    raise exception 'F03_CRITERIA_CATEGORIES_MUST_BE_NONEMPTY';
  end if;
  if v_cov->'coverage_complete' is distinct from 'true'::jsonb
     or v_cov->'semantic_coverage_verified' is distinct from 'true'::jsonb then
    raise exception 'F03_CRITERIA_SEMANTIC_COVERAGE_REQUIRED';
  end if;
  if coalesce(v_cov->>'acceptance_count','')!~'^[0-9]+$'
     or (v_cov->>'acceptance_count')::integer<>jsonb_array_length(v_acceptance)
     or v_cov->>'acceptance_refs_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_acceptance) then
    raise exception 'F03_ACCEPTANCE_COVERAGE_MISMATCH';
  end if;
  if coalesce(v_cov->>'invariant_count','')!~'^[0-9]+$'
     or (v_cov->>'invariant_count')::integer<>jsonb_array_length(v_invariants)
     or v_cov->>'invariant_refs_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_invariants) then
    raise exception 'F03_INVARIANT_COVERAGE_MISMATCH';
  end if;
  if coalesce(v_cov->>'negative_count','')!~'^[0-9]+$'
     or (v_cov->>'negative_count')::integer<>jsonb_array_length(v_negative)
     or v_cov->>'negative_refs_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_negative) then
    raise exception 'F03_NEGATIVE_COVERAGE_MISMATCH';
  end if;
  if coalesce(p_payload->>'criteria_coverage_sha256','')!~'^[0-9a-f]{64}$'
     or p_payload->>'criteria_coverage_sha256' is distinct from programacion.fn_v09_sha256_jsonb(v_cov) then
    raise exception 'F03_CRITERIA_COVERAGE_SHA_MISMATCH';
  end if;
  if coalesce(p_payload->>'semantic_coverage_receipt_sha256','')!~'^[0-9a-f]{64}$'
     or coalesce(p_payload->>'negative_coverage_receipt_sha256','')!~'^[0-9a-f]{64}$' then
    raise exception 'F03_COVERAGE_RECEIPT_DIGESTS_REQUIRED';
  end if;
end;
$function$;

revoke all on function programacion.fn_assert_f03_criteria_coverage_v2(jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function programacion.fn_assert_f03_criteria_coverage_v2(jsonb,jsonb) to postgres;

create or replace function programacion.fn_guard_f03_audit_verdict_contract_v2()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_task programacion.agent_tasks%rowtype;
  v_current_task_id bigint;
  v_tc programacion.test_contracts%rowtype;
  v_ex programacion.ejecuciones%rowtype;
  v_ch programacion.authority_challenges%rowtype;
  v_task_id bigint;
  v_expected_subject_sha text;
begin
  if new.receipt_kind<>'AUDIT_VERDICT'
     or new.issuer_channel<>'F03_OIDC_AUDITOR_V1'
     or new.payload->>'finding_code' is distinct from 'AUD24-F03' then
    return new;
  end if;

  if coalesce(new.payload->>'agent_task_id','')!~'^[1-9][0-9]*$' then raise exception 'F03_AGENT_TASK_ID_REQUIRED'; end if;
  v_task_id:=(new.payload->>'agent_task_id')::bigint;
  select * into v_task from programacion.agent_tasks where id=v_task_id;
  if v_task.id is null or v_task.definition_status<>'SEALED' then raise exception 'F03_CURRENT_SEALED_TASK_REQUIRED:%',v_task_id; end if;
  select t.id into v_current_task_id from programacion.agent_tasks t
  where t.task_code=v_task.task_code and t.definition_status='SEALED'
  order by t.task_version desc,t.id desc limit 1;
  if v_current_task_id is distinct from v_task.id then raise exception 'F03_CURRENT_TASK_REQUIRED:% current=%',v_task.id,v_current_task_id; end if;

  select * into v_tc from programacion.test_contracts
  where task_id=v_task.id and status='SEALED' order by contract_version desc,id desc limit 1;
  if v_tc.id is null then raise exception 'F03_SEALED_TEST_CONTRACT_REQUIRED:%',v_task.id; end if;

  select * into v_ex from programacion.ejecuciones
  where request_ref='agent-task://'||v_task.id::text and estado='RUNNING' order by id desc limit 1;
  if v_ex.id is null then raise exception 'F03_RUNNING_EXECUTION_REQUIRED:%',v_task.id; end if;

  if new.execution_id is not null
     or new.head_sha is distinct from v_ex.head_sha
     or new.subject_type is distinct from 'hidden_oracle_audit'
     or new.subject_ref is distinct from 'agent-task://'||v_task.id::text||'/hidden-oracle' then
    raise exception 'F03_RECEIPT_TARGET_BINDING_INVALID';
  end if;

  v_expected_subject_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,'finding_code','AUD24-F03','agent_task_id',v_task.id,'task_sha256',v_task.task_sha256,
    'hidden_oracle_ref',v_tc.hidden_oracle_ref,'hidden_oracle_sha256',v_tc.hidden_oracle_sha256,
    'generation_source_sha256',v_tc.generation_source_sha256
  ));
  if new.subject_sha256 is distinct from v_expected_subject_sha then raise exception 'F03_SUBJECT_SHA_MISMATCH'; end if;

  if coalesce(new.payload->>'receipt_contract_version','')!~'^[0-9]+$'
     or (new.payload->>'receipt_contract_version')::integer<5
     or new.payload->>'target_execution_id' is distinct from v_ex.id::text
     or new.payload->>'target_repo_full_name' is distinct from v_ex.repo_full_name
     or new.payload->>'target_head_sha' is distinct from v_ex.head_sha
     or new.payload->>'audited_head_sha' is distinct from v_ex.head_sha
     or new.payload->>'task_sha256' is distinct from coalesce(v_task.task_sha256,'')
     or new.payload->>'hidden_oracle_ref' is distinct from v_tc.hidden_oracle_ref
     or new.payload->>'hidden_oracle_sha256' is distinct from v_tc.hidden_oracle_sha256
     or new.payload->>'generation_source_sha256' is distinct from v_tc.generation_source_sha256 then
    raise exception 'F03_PAYLOAD_TARGET_OR_CONTRACT_BINDING_INVALID';
  end if;

  if new.payload->>'verdict' is distinct from 'PASS'
     or new.payload->'independent' is distinct from 'true'::jsonb
     or new.payload->'semantic_nonreconstructibility_verified' is distinct from 'true'::jsonb
     or new.payload->'replay_binding_verified' is distinct from 'true'::jsonb
     or new.payload->'hidden_output_nonexposure_verified' is distinct from 'true'::jsonb
     or new.payload->>'hidden_output' is distinct from 'HASH_ONLY' then
    raise exception 'F03_INDEPENDENCE_OR_NONEXPOSURE_REQUIRED';
  end if;

  perform programacion.fn_assert_f03_criteria_coverage_v2(new.payload,v_tc.criteria_snapshot);

  if coalesce(new.payload->>'challenge_id','')!~'^[1-9][0-9]*$' then raise exception 'F03_CHALLENGE_REQUIRED'; end if;
  select * into v_ch from programacion.authority_challenges where id=(new.payload->>'challenge_id')::bigint;
  if v_ch.id is null or now()>=v_ch.expires_at
     or v_ch.repo_full_name is distinct from v_ex.repo_full_name
     or v_ch.head_sha is distinct from v_ex.head_sha
     or v_ch.purpose is distinct from 'STORY_AGENT_F03_HIDDEN_AUTHORITY_V2'
     or not ('programacion_auditor'=any(v_ch.required_roles))
     or new.payload->>'challenge_nonce' is distinct from v_ch.challenge_nonce::text
     or new.payload->>'challenge_sha256' is distinct from v_ch.challenge_sha256 then
    raise exception 'F03_FRESH_CHALLENGE_BINDING_INVALID';
  end if;
  return new;
end;
$function$;

revoke all on function programacion.fn_guard_f03_audit_verdict_contract_v2() from public,anon,authenticated,service_role;
grant execute on function programacion.fn_guard_f03_audit_verdict_contract_v2() to postgres;

drop trigger if exists trg_provenance_receipts_f03_contract_v2_guard on programacion.provenance_receipts;
create trigger trg_provenance_receipts_f03_contract_v2_guard
before insert on programacion.provenance_receipts
for each row execute function programacion.fn_guard_f03_audit_verdict_contract_v2();

comment on function programacion.fn_guard_f03_audit_verdict_contract_v2()
is 'AUD-019/AUD24-F03 pre-audit guard: future F03 PASS receipt must be current-task/current-execution/head, fresh-challenge bound, nonexposing/nonreconstructible, and prove complete sealed AC/INV/NEG semantic coverage by counts+digests. Does not activate F03.';

create or replace function programacion.fn_guard_authority_challenge_insert()
returns trigger
language plpgsql
set search_path to 'pg_catalog','programacion'
as $function$
declare v_payload jsonb;
begin
  if current_user<>'postgres' then raise exception 'authority challenge creation requires control-plane postgres; current_user=%',current_user; end if;
  if new.expires_at<=now() then raise exception 'authority challenge expiry must be in the future'; end if;
  if new.repo_full_name not in ('cristhianlujan/programming-agent','cristhianlujan/libertad-financiera') then
    raise exception 'unexpected authority challenge repository %',new.repo_full_name;
  end if;
  if new.repo_full_name='cristhianlujan/libertad-financiera'
     and new.purpose not in ('STORY_AGENT_WORKER_V10_ORIGIN_V1','STORY_AGENT_F03_HIDDEN_AUTHORITY_V2') then
    raise exception 'libertad-financiera authority challenge purpose is not allowed: %',new.purpose;
  end if;
  if new.purpose='STORY_AGENT_F03_HIDDEN_AUTHORITY_V2' and not ('programacion_auditor'=any(new.required_roles)) then
    raise exception 'F03 challenge requires programacion_auditor role';
  end if;
  new.created_by_db_principal:=current_user;
  v_payload:=jsonb_build_object('schema_version',1,'repo_full_name',new.repo_full_name,'head_sha',new.head_sha,
    'challenge_nonce',new.challenge_nonce::text,'required_roles',to_jsonb(new.required_roles),'purpose',new.purpose,
    'expires_at',to_jsonb(new.expires_at),'created_by_db_principal',new.created_by_db_principal);
  new.challenge_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$function$;

insert into programacion.task_blockers(task_id,blocker_code,owner_type,owner_ref,required_action,source_ref,status)
select t.id,'AUD018_EXECUTED_MACHINE_PROOF_REQUIRED','STORY_AGENT_WORKER','AUD-018',
       'EMIT_STRUCTURED_GITHUB_ACTIONS_PROOF_CONTRACT_V2','ekb://AUD-018/story-agent-machine-proof-v2','OPEN'
from programacion.agent_tasks t
where t.task_code='HU-HMO-001' and t.definition_status='SEALED'
  and not exists(select 1 from programacion.agent_tasks n where n.task_code=t.task_code and n.definition_status='SEALED' and (n.task_version,n.id)>(t.task_version,t.id))
on conflict (task_id,blocker_code,source_ref) do update
set status='OPEN',owner_type=excluded.owner_type,owner_ref=excluded.owner_ref,required_action=excluded.required_action,
    resolved_at=null,resolved_by=null,resolution_ref=null;

do $$
begin
  if exists(
    select 1 from programacion.evidencias ev
    join programacion.evaluaciones eva on eva.id=ev.evaluacion_id
    join programacion.objetivos_ejecucion oe on oe.id=eva.objetivo_id
    join programacion.ejecuciones ex on ex.id=oe.execution_id
    join programacion.agent_tasks t on ex.request_ref='agent-task://'||t.id::text
    where ex.estado='RUNNING' and ev.tipo='VERIFIED_WORKER_RECEIPT' and ev.source_system='PROGRAMMING_AGENT_WORKER'
      and ev.metadata#>>'{worker_receipt,status}'='PASS'
      and ev.metadata#>>'{worker_receipt,proof_contract_version}' is distinct from '2'
      and not exists(select 1 from programacion.agent_tasks n where n.task_code=t.task_code and n.definition_status='SEALED' and (n.task_version,n.id)>(t.task_version,t.id))
  ) then raise exception 'CURRENT_AGENT_TASK_LEGACY_MACHINE_PASS_RECEIPT_EXISTS'; end if;
end $$;

do $$
begin
  begin
    perform programacion.fn_assert_worker_machine_proof_contract_v2(
      jsonb_build_object('status','PASS','github_actions_run_id','1','tests',jsonb_build_object('build','PASS','lint','PASS','semantic','1/1 PASS','mutation','1/1 PASS')),
      repeat('a',40),'github-actions://owner/repo/actions/runs/1');
    raise exception 'SELFTEST_EXPECTED_MACHINE_PROOF_REJECTION';
  exception when others then
    if sqlerrm='SELFTEST_EXPECTED_MACHINE_PROOF_REJECTION' then raise; end if;
    if position('MACHINE_PROOF_CONTRACT_V2_REQUIRED' in sqlerrm)=0 then raise; end if;
  end;
end $$;
