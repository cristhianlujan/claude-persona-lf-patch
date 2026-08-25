create or replace function programacion.fn_guard_test_contract_hidden_authority_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare
  v_task programacion.agent_tasks%rowtype;
  v_attestation_id bigint;
begin
  if tg_op<>'UPDATE' or old.status<>'DRAFT' or new.status<>'SEALED' then return new; end if;
  select * into v_task from programacion.agent_tasks where id=new.task_id;
  if v_task.id is null or v_task.definition_status<>'SEALED' then raise exception 'TEST_CONTRACT_CURRENT_TASK_REQUIRED:%',new.task_id; end if;
  if exists(select 1 from programacion.agent_tasks t where t.task_code=v_task.task_code and t.definition_status='SEALED' and (t.task_version>v_task.task_version or (t.task_version=v_task.task_version and t.id>v_task.id))) then raise exception 'TEST_CONTRACT_CURRENT_TASK_REQUIRED:%',new.task_id; end if;
  select a.id into v_attestation_id
  from programacion.authority_attestations a
  join programacion.authority_challenges c on c.id=a.challenge_id
  where a.authority_role='programacion_auditor'
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
    and (a.attestation_payload->>'receipt_contract_version')::integer>=3
    and a.attestation_payload->>'agent_task_id'=v_task.id::text
    and a.attestation_payload->>'task_sha256'=coalesce(v_task.task_sha256,'')
    and a.attestation_payload->>'hidden_oracle_ref'=new.hidden_oracle_ref
    and a.attestation_payload->>'hidden_oracle_sha256'=new.hidden_oracle_sha256
    and a.attestation_payload->>'generation_source_sha256'=new.generation_source_sha256
  order by a.id desc limit 1;
  if v_attestation_id is null then raise exception 'TEST_CONTRACT_INDEPENDENT_HIDDEN_AUTHORITY_REQUIRED:%',new.task_id; end if;
  return new;
end;
$$;

create trigger trg_test_contract_hidden_authority_guard before update of status on programacion.test_contracts for each row execute function programacion.fn_guard_test_contract_hidden_authority_v1();