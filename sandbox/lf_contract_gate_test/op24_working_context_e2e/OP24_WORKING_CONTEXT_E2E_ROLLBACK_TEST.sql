\set ON_ERROR_STOP on

-- Baselines must be restored exactly after rollback.
select count(*) as pre_protected_channels
from programacion.provenance_channels
where channel_code='SOURCE_VERIFIER_PROTECTED_V1' \gset

select count(*) as pre_protected_receipts
from programacion.provenance_receipts
where issuer_channel='SOURCE_VERIFIER_PROTECTED_V1' \gset

select count(*) as pre_protected_secrets
from vault.secrets
where name='op24_source_verifier_protected_token_v1' \gset

begin;
\ir ../op24_working_context_source_verifier_issuer/OP24_WORKING_CONTEXT_SOURCE_VERIFIER_ISSUER_V1.sql
\ir ../op24_working_context_budget_gate/OP24_WORKING_CONTEXT_BUDGET_GATE_V1.sql
\ir ../op24_working_context_admission_gate/OP24_WORKING_CONTEXT_ADMISSION_GATE_V1.sql

do $e2e$
declare
  v_execution_id bigint;
  v_head_sha text;
  v_request_ref text;
  v_fragment jsonb;
  v_selected jsonb;
  v_query jsonb;
  v_context_sha256 text;
  v_receipt_id bigint;
  v_retrieval_id bigint;
  v_admission jsonb;
begin
  select cp.execution_id,e.head_sha,e.request_ref
    into v_execution_id,v_head_sha,v_request_ref
  from programacion.context_packs cp
  join programacion.ejecuciones e on e.id=cp.execution_id
  where cp.estado='COMPLETE'
    and cp.digest_version=2
    and e.request_ref is not null
  order by cp.created_at desc
  limit 1;

  if v_execution_id is null then
    raise exception 'E2E_COMPLETE_CONTEXT_PACK_V2_REQUIRED';
  end if;

  v_fragment := jsonb_build_object(
    'source','OP24_E2E_SOURCE',
    'record_id','OP24-WORKING-CONTEXT-E2E-001',
    'title','OP24 Working Context E2E rollback fragment',
    'content','rollback-only integrated Working Context evidence',
    'score',100,
    'reasons',jsonb_build_array('e2e_rollback_canary'),
    'provenance',jsonb_build_object(
      'snapshot_sha256',repeat('a',64),
      'source_ref','rollback://op24/working-context/e2e'
    )
  );
  v_fragment := v_fragment || jsonb_build_object(
    'content_sha256',programacion.fn_v09_sha256_jsonb(jsonb_build_object(
      'source',v_fragment->'source',
      'record_id',v_fragment->'record_id',
      'title',v_fragment->'title',
      'content',v_fragment->'content',
      'provenance',v_fragment->'provenance'
    ))
  );
  v_selected := jsonb_build_array(v_fragment);
  v_query := jsonb_build_object(
    'required_sources',jsonb_build_array('OP24_E2E_SOURCE'),
    'required_record_ids',jsonb_build_array('OP24-WORKING-CONTEXT-E2E-001')
  );
  v_context_sha256 := programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,
    'status','PASS',
    'query',v_query,
    'selected',v_selected,
    'missing_critical_context','[]'::jsonb,
    'filtered_counts','{}'::jsonb
  ));

  select r.id into v_receipt_id
  from programacion.issue_retrieval_pass_provenance_receipt_v1(
    v_execution_id,
    v_head_sha,
    v_request_ref,
    v_context_sha256,
    'OP24_INDEPENDENT_E2E_ROLLBACK_CANARY',
    'rollback://op24/working-context/e2e/evidence',
    jsonb_build_object(
      'kind','RETRIEVAL_PASS',
      'verdict','PASS',
      'independent',true,
      'execution_id',v_execution_id::text,
      'head_sha',v_head_sha,
      'request_ref',v_request_ref,
      'context_sha256',v_context_sha256,
      'verifier_identity','OP24_INDEPENDENT_E2E_ROLLBACK_CANARY',
      'evidence_ref','rollback://op24/working-context/e2e/evidence',
      'evidence_sha256',repeat('b',64)
    )
  ) r;

  if v_receipt_id is null then
    raise exception 'E2E_RETRIEVAL_PASS_RECEIPT_REQUIRED';
  end if;

  insert into programacion.retrieval_runs(
    execution_id,head_sha,query,status,context_sha256,
    missing_critical_context,filtered_counts,selected_payload,provenance_receipt_id
  ) values (
    v_execution_id,v_head_sha,v_query,'PASS',v_context_sha256,
    '[]'::jsonb,'{}'::jsonb,v_selected,v_receipt_id
  ) returning id into v_retrieval_id;

  insert into private.lf_context_budget_events_v2(
    id,execution_id,estimated_tokens,context_status,source,recommendation,recorded_at,evidence_event_id
  ) overriding system value values (
    99024030,v_request_ref,800,'GREEN','OP24_WORKING_CONTEXT_E2E_ROLLBACK',null,clock_timestamp(),null
  );

  v_admission := private.sbx_fn_lf_working_context_admission_v1(
    v_execution_id,
    v_retrieval_id,
    v_request_ref,
    v_request_ref,
    'LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1',
    'LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1',
    1000,
    interval '1 hour'
  );

  if coalesce((v_admission->>'conditions_met')::boolean,false) is not true then
    raise exception 'E2E_ADMISSION_MUST_PASS:%',v_admission;
  end if;
  if jsonb_array_length(v_admission->'errors') <> 0 then
    raise exception 'E2E_ADMISSION_ERRORS_MUST_BE_EMPTY:%',v_admission;
  end if;
  if v_admission->>'retrieval_provenance_issuer_channel' <> 'SOURCE_VERIFIER_PROTECTED_V1' then
    raise exception 'E2E_PROTECTED_CHANNEL_NOT_BOUND:%',v_admission;
  end if;
  if coalesce((v_admission->'budget'->>'authorized')::boolean,false) is not true then
    raise exception 'E2E_GREEN_BUDGET_MUST_PASS:%',v_admission;
  end if;
  if coalesce((v_admission->>'digest_equality_required')::boolean,true) is not false then
    raise exception 'E2E_DUAL_HASH_SEMANTICS_REQUIRED:%',v_admission;
  end if;
  if coalesce((v_admission->>'model_call_authorized')::boolean,true) is not false then
    raise exception 'E2E_SANDBOX_MUST_NOT_AUTHORIZE_MODEL_CALL:%',v_admission;
  end if;
end;
$e2e$;

rollback;

-- Exact no-residue checks.
do $post$
begin
  if to_regprocedure('private.sbx_fn_lf_working_context_budget_gate_v1(text,bigint,interval)') is not null then
    raise exception 'E2E_BUDGET_GATE_RESIDUE';
  end if;
  if to_regprocedure('private.sbx_fn_lf_working_context_admission_v1(bigint,bigint,text,text,text,text,bigint,interval)') is not null then
    raise exception 'E2E_ADMISSION_GATE_RESIDUE';
  end if;
  if to_regprocedure('programacion.issue_retrieval_pass_provenance_receipt_v1(bigint,text,text,text,text,text,jsonb)') is not null then
    raise exception 'E2E_PROTECTED_ISSUER_FUNCTION_RESIDUE';
  end if;
  if exists(select 1 from private.lf_context_budget_events_v2 where id=99024030) then
    raise exception 'E2E_BUDGET_EVENT_RESIDUE';
  end if;
end
$post$;

select case when count(*)=:'pre_protected_channels'::bigint then true else false end as protected_channel_baseline_restored
from programacion.provenance_channels
where channel_code='SOURCE_VERIFIER_PROTECTED_V1';

select case when count(*)=:'pre_protected_receipts'::bigint then true else false end as protected_receipt_baseline_restored
from programacion.provenance_receipts
where issuer_channel='SOURCE_VERIFIER_PROTECTED_V1';

select case when count(*)=:'pre_protected_secrets'::bigint then true else false end as protected_secret_baseline_restored
from vault.secrets
where name='op24_source_verifier_protected_token_v1';
