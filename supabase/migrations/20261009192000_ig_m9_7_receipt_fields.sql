begin;
-- M9.7/RECEIPT_FIELDS: contract target + bounded consumer adapter for canonical EVIDENCE_LEDGER.
-- EVIDENCE_LEDGER authority and writer remain unchanged. The adapter cannot fabricate a run.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
      jsonb_set(unit_metadata,'{action_specs_v1,RECEIPT_FIELDS,target,declared_objects}',
        jsonb_build_array('programacion.fn_input_governance_shadow_receipt_emit_v1'),true),
      '{action_specs_v1,RECEIPT_FIELDS,authoring_contract,db_targets_exact}',
        jsonb_build_array('programacion.fn_input_governance_shadow_receipt_emit_v1'),true)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.7'
  and disposition='ASSIGNED';

create or replace function programacion.fn_input_governance_shadow_receipt_emit_v1(
  p_receipt jsonb, p_context jsonb
) returns jsonb
language plpgsql security invoker
set search_path to 'pg_catalog','programacion','private','public','extensions'
as $emit$
declare
  v_key text;
  v_receipt_sha256 text;
begin
  if private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',p_receipt) is not true then
    raise exception 'BLOCK_M9_7_SHADOW_RECEIPT_TYPED_INVALID';
  end if;
  if jsonb_typeof(p_context)<>'object' then raise exception 'BLOCK_M9_7_LEDGER_CONTEXT_NOT_OBJECT'; end if;
  foreach v_key in array array[
    'producer_execution_id','producer_capability_code','subject_ref','source_head_sha',
    'source_snapshot_sha256','authority_ref','provider_ref','actor_execution_id'
  ] loop
    if nullif(btrim(coalesce(p_context->>v_key,'')),'') is null then
      raise exception 'BLOCK_M9_7_LEDGER_CONTEXT_MISSING:%',v_key;
    end if;
  end loop;
  if coalesce(p_context->>'source_head_sha','') !~ '^[0-9a-f]{40}$'
     or p_context->>'source_snapshot_sha256' is distinct from p_receipt->>'source_snapshot_sha256'
     or jsonb_typeof(p_context->'verification_payload')<>'object'
     or p_context->'verification_payload'='{}'::jsonb then
    raise exception 'BLOCK_M9_7_LEDGER_CONTEXT_PROVENANCE_INVALID';
  end if;
  v_receipt_sha256:=encode(extensions.digest(convert_to(p_receipt::text,'UTF8'),'sha256'),'hex');
  return public.fn_lf_evidence_ledger_anchor_v1(
    p_context->>'producer_execution_id',
    p_context->>'producer_capability_code',
    'IG_SHADOW_CANDIDATE_COMPARE',
    'IG_SHADOW_COMPARISON',
    'INPUT_GOVERNANCE_SHADOW',
    p_context->>'subject_ref',
    v_receipt_sha256,
    p_context->>'source_head_sha',
    p_context->>'authority_ref',
    'LF_SUPABASE_READBACK_V1',
    'SUPABASE',
    p_context->>'provider_ref',
    'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
    'ANCHORED',
    p_context->'verification_payload',
    jsonb_build_object('typed_evidence_schema_version','ig-shadow-receipt/v1',
      'typed_evidence',p_receipt),
    p_context->>'actor_execution_id'
  );
end
$emit$;

revoke all on function programacion.fn_input_governance_shadow_receipt_emit_v1(jsonb,jsonb) from public;
grant execute on function programacion.fn_input_governance_shadow_receipt_emit_v1(jsonb,jsonb) to service_role;

do $verify$
declare
  v_hash_a text:=repeat('a',64);
  v_payload jsonb;
  v_context jsonb;
  v_before int;
  v_after int;
begin
  select count(*) into v_before from private.lf_evidence_ledger_v1 where receipt_kind='IG_SHADOW_COMPARISON';
  v_payload:=jsonb_build_object(
    'evidence_schema_version','ig-shadow-receipt/v1',
    'current_release_ref','git://release/current','candidate_release_ref','git://release/candidate',
    'current_release_sha256',v_hash_a,
    'candidate_release_sha256',repeat('b',64),
    'source_snapshot_sha256',v_hash_a,
    'comparison',jsonb_build_object('result','MATCH','method_version','hash-compare/v1',
      'current_output_sha256',v_hash_a,'candidate_output_sha256',v_hash_a,'difference_count',0),
    'duration_ms',1,'recorded_at','2026-10-09T19:00:00Z'
  );
  if private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',v_payload) is not true then
    raise exception 'BLOCK_M9_7_EMITTER_TEST_TYPED_SCHEMA_FAILED';
  end if;
  begin
    perform programacion.fn_input_governance_shadow_receipt_emit_v1(v_payload-'source_snapshot_sha256','{}'::jsonb);
    raise exception 'BLOCK_M9_7_EMITTER_TEST_INVALID_ACCEPTED';
  exception when others then
    if sqlerrm <> 'BLOCK_M9_7_SHADOW_RECEIPT_TYPED_INVALID' then raise; end if;
  end;
  begin
    perform programacion.fn_input_governance_shadow_receipt_emit_v1(v_payload,'{}'::jsonb);
    raise exception 'BLOCK_M9_7_EMITTER_TEST_MISSING_CONTEXT_ACCEPTED';
  exception when others then
    if sqlerrm not like 'BLOCK_M9_7_LEDGER_CONTEXT_MISSING:%' then raise; end if;
  end;
  v_context:=jsonb_build_object(
    'producer_execution_id','IG:M9.7:NO_REAL_RUN',
    'producer_capability_code','INPUT_GOVERNANCE_SHADOW',
    'subject_ref','IG:M9.7:NO_REAL_SUBJECT',
    'source_head_sha',repeat('a',40),
    'source_snapshot_sha256',v_hash_a,
    'authority_ref','supabase://test/rollback-only',
    'provider_ref','supabase://test/rollback-only',
    'actor_execution_id','IG:M9.7:NO_ACTIVE_LEDGER_EXECUTION',
    'verification_payload',jsonb_build_object('probe','ROLLBACK_NO_WRITE')
  );
  begin
    perform programacion.fn_input_governance_shadow_receipt_emit_v1(v_payload,v_context);
    raise exception 'BLOCK_M9_7_EMITTER_TEST_UNAUTHORIZED_RUN_ACCEPTED';
  exception when others then
    if sqlerrm not like 'BLOCK_LF_EVIDENCE_LEDGER_EXECUTION_INVALID%' then raise; end if;
  end;
  select count(*) into v_after from private.lf_evidence_ledger_v1 where receipt_kind='IG_SHADOW_COMPARISON';
  if v_after is distinct from v_before then raise exception 'BLOCK_M9_7_EMITTER_TEST_RESIDUAL_RECEIPTS'; end if;
  if not exists(select 1 from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.7'
    and unit_metadata#>'{action_specs_v1,RECEIPT_FIELDS,target,declared_objects}'
        @> '["programacion.fn_input_governance_shadow_receipt_emit_v1"]'::jsonb) then
      raise exception 'BLOCK_M9_7_RECEIPT_FIELDS_CONTRACT_DRIFT';
  end if;
end
$verify$;
commit;
