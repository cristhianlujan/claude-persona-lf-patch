-- LF_CARD_UPDATE_I5_CARRIER_ADAPTER_INTENT_V1
-- Candidate-only carrier adapter envelope. No provider write is authorized by this migration.
-- Google Docs uses requiredRevisionId; GitHub uses exact head + blob SHA.

create or replace function public.lf_validate_carrier_write_guard_shape_v1(
  p_carrier_type text,
  p_binding jsonb,
  p_trust jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
begin
  if p_binding is null or jsonb_typeof(p_binding) is distinct from 'object'
     or p_trust is null or jsonb_typeof(p_trust) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARRIER_GUARD_CONTEXT_INVALID');
  end if;

  if p_carrier_type is distinct from (p_binding->>'carrier_type') then
    return jsonb_build_object('valid',false,'code','CARRIER_GUARD_TYPE_BINDING_MISMATCH');
  end if;

  if p_carrier_type='GOOGLE_DOC_EMBEDDED_BLOCK' then
    if (p_binding->>'provider_write_guard') is distinct from 'requiredRevisionId' then
      return jsonb_build_object('valid',false,'code','GOOGLE_DOC_GUARD_KIND_INVALID');
    end if;
    if (p_trust->>'source') is distinct from 'GOOGLE_DOCS_API_CONNECTOR_FRESH_READ' then
      return jsonb_build_object('valid',false,'code','GOOGLE_DOC_TRUST_SOURCE_INVALID');
    end if;
    if nullif(p_binding->>'document_id','') is null
       or nullif(p_binding->>'carrier_ref','') is null
       or nullif(p_binding->>'block_anchor','') is null
       or nullif(p_binding->>'provider_revision_id','') is null
       or nullif(p_binding->>'content_sha256','') is null then
      return jsonb_build_object('valid',false,'code','GOOGLE_DOC_BINDING_REQUIRED_FIELD_MISSING');
    end if;
    if (p_trust->>'carrier_type') is distinct from p_carrier_type
       or (p_trust->>'carrier_ref') is distinct from (p_binding->>'carrier_ref')
       or (p_trust->>'document_id') is distinct from (p_binding->>'document_id')
       or (p_trust->>'block_anchor_or_path') is distinct from (p_binding->>'block_anchor')
       or (p_trust->>'provider_revision_id') is distinct from (p_binding->>'provider_revision_id')
       or (p_trust->>'content_sha256') is distinct from (p_binding->>'content_sha256')
       or (p_trust->>'provider_write_guard') is distinct from 'requiredRevisionId' then
      return jsonb_build_object('valid',false,'code','GOOGLE_DOC_TRUST_BINDING_MISMATCH');
    end if;
    return jsonb_build_object(
      'valid',true,
      'code','GOOGLE_DOC_GUARD_EXACT',
      'write_route','GOOGLE_DOCS_BATCH_UPDATE',
      'provider_guard_kind','requiredRevisionId',
      'provider_precondition',jsonb_build_object('requiredRevisionId',p_binding->>'provider_revision_id'),
      'bounded_target',jsonb_build_object(
        'document_id',p_binding->>'document_id',
        'tab_id',p_binding->>'tab_id',
        'block_anchor',p_binding->>'block_anchor',
        'anchor_start_index',p_binding->>'anchor_start_index',
        'last_bound_paragraph_end_index',p_binding->>'last_bound_paragraph_end_index'
      )
    );
  elsif p_carrier_type='GITHUB_FILE' then
    if (p_binding->>'provider_write_guard') is distinct from 'EXPECTED_HEAD_AND_BLOB_SHA' then
      return jsonb_build_object('valid',false,'code','GITHUB_GUARD_KIND_INVALID');
    end if;
    if (p_trust->>'source') is distinct from 'GITHUB_API_CONNECTOR_FRESH_READ' then
      return jsonb_build_object('valid',false,'code','GITHUB_TRUST_SOURCE_INVALID');
    end if;
    if nullif(p_binding->>'repository_full_name','') is null
       or nullif(p_binding->>'path','') is null
       or nullif(p_binding->>'provider_head_sha','') is null
       or nullif(p_binding->>'provider_blob_sha','') is null then
      return jsonb_build_object('valid',false,'code','GITHUB_BINDING_REQUIRED_FIELD_MISSING');
    end if;
    if (p_trust->>'carrier_type') is distinct from p_carrier_type
       or (p_trust->>'repository_full_name') is distinct from (p_binding->>'repository_full_name')
       or (p_trust->>'path') is distinct from (p_binding->>'path')
       or (p_trust->>'provider_head_sha') is distinct from (p_binding->>'provider_head_sha')
       or (p_trust->>'provider_blob_sha') is distinct from (p_binding->>'provider_blob_sha')
       or (p_trust->>'provider_write_guard') is distinct from 'EXPECTED_HEAD_AND_BLOB_SHA' then
      return jsonb_build_object('valid',false,'code','GITHUB_TRUST_BINDING_MISMATCH');
    end if;
    return jsonb_build_object(
      'valid',true,
      'code','GITHUB_GUARD_EXACT',
      'write_route','GITHUB_CONTENTS_OR_GIT_DATA_API',
      'provider_guard_kind','EXPECTED_HEAD_AND_BLOB_SHA',
      'provider_precondition',jsonb_build_object(
        'expected_head_sha',p_binding->>'provider_head_sha',
        'expected_blob_sha',p_binding->>'provider_blob_sha'
      ),
      'bounded_target',jsonb_build_object(
        'repository_full_name',p_binding->>'repository_full_name',
        'path',p_binding->>'path',
        'ref',p_binding->>'ref'
      )
    );
  end if;

  return jsonb_build_object('valid',false,'code','CARRIER_TYPE_UNSUPPORTED_I5','carrier_type',p_carrier_type);
end;
$function$;

create or replace function public.lf_prepare_card_carrier_write_intent_v1(
  p_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_card public.lf_activos%rowtype;
  v_binding jsonb;
  v_trust jsonb;
  v_step80 public.lf_operation_execution_steps%rowtype;
  v_clean_result text;
  v_guard jsonb;
  v_intent jsonb;
  v_hash text;
begin
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found
     or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
     or v_execution.target_type is distinct from 'CARD'
     or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','I5_EXECUTION_IDENTITY_OR_STATUS_INVALID');
  end if;

  select * into v_step80 from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id='pre_write_execution_binding_gate' and step_order=80;
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','I5_PREWRITE_STEP80_MISSING');
  end if;
  select clean_result_value into v_clean_result from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_CARD_LF' and step_id='pre_write_execution_binding_gate' and step_order=80 and status='CANDIDATO_READ_ONLY';
  if v_clean_result is null or v_step80.status is distinct from v_clean_result then
    return jsonb_build_object('outcome','BLOCKED','code','I5_PREWRITE_STEP80_NOT_CLEAN','status',v_step80.status);
  end if;
  if (v_step80.evidence_payload->'trust_validation'->>'valid') is distinct from 'true'
     or (v_step80.evidence_payload->'trust_validation'->>'code') is distinct from 'CARD_TRUST_EXACT' then
    return jsonb_build_object('outcome','BLOCKED','code','I5_PREWRITE_TRUST_NOT_EXACT');
  end if;

  select * into v_card from public.lf_activos
  where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','I5_CARD_TARGET_NOT_FOUND');
  end if;
  if v_card.runtime_estado is distinct from 'PRODUCCION_CONTROLADA_READ_ONLY'
     or v_card.impacto_automatico is distinct from 'BLOQUEADO'
     or coalesce((v_card.metadata->'storage_refs'->'google_drive'->>'operational_read_allowed')::boolean,true) is true then
    return jsonb_build_object('outcome','BLOCKED','code','I5_CARD_SAFETY_CEILING_CHANGED');
  end if;

  v_binding:=v_card.metadata->'carrier_binding_v1';
  v_trust:=v_execution.manifest->'connector_trust_context';
  if v_binding is null or jsonb_typeof(v_binding) is distinct from 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','I5_DURABLE_BINDING_MISSING');
  end if;
  if (v_binding->>'binding_status') is distinct from 'CURRENT_AT_OBSERVATION'
     or coalesce((v_binding->>'carrier_authority')::boolean,true) is true
     or coalesce((v_binding->>'carrier_write_allowed')::boolean,true) is true then
    return jsonb_build_object('outcome','BLOCKED','code','I5_DURABLE_BINDING_STATE_INVALID');
  end if;

  v_guard:=public.lf_validate_carrier_write_guard_shape_v1(v_binding->>'carrier_type',v_binding,v_trust);
  if (v_guard->>'valid') is distinct from 'true' then
    return jsonb_build_object('outcome','BLOCKED','code',coalesce(v_guard->>'code','I5_CARRIER_GUARD_INVALID'),'guard',v_guard);
  end if;

  v_intent:=jsonb_build_object(
    'intent_schema','LF_CARD_CARRIER_WRITE_INTENT_V1',
    'execution_id',p_execution_id,
    'operation_code','ACTUALIZACION_CARD_LF',
    'card_code',v_execution.target_code,
    'supabase_authority_ref',v_binding->>'operational_authority_ref',
    'carrier_type',v_binding->>'carrier_type',
    'carrier_ref',v_binding->>'carrier_ref',
    'write_route',v_guard->>'write_route',
    'provider_guard_kind',v_guard->>'provider_guard_kind',
    'provider_precondition',v_guard->'provider_precondition',
    'bounded_target',v_guard->'bounded_target',
    'change_scope_ref',(select evidence_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='change_scope'),
    'regression_plan_ref',(select evidence_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='regression_plan'),
    'source_policy_sha',v_binding->>'source_policy_sha',
    'provider_call_authorized',false,
    'candidate_only',true,
    'carrier_authority',false,
    'generated_from','SUPABASE_EXECUTION_PLUS_DURABLE_BINDING_PLUS_FRESH_TRUST_CONTEXT'
  );
  v_hash:=encode(extensions.digest(v_intent::text,'sha256'),'hex');
  return v_intent||jsonb_build_object('intent_sha256',v_hash,'outcome','INTENT_PREPARED_NO_WRITE');
end;
$function$;

create or replace function public.lf_validate_card_carrier_write_intent_v1(
  p_execution_id text,
  p_intent jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_expected jsonb;
begin
  if p_intent is null or jsonb_typeof(p_intent) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','I5_INTENT_INVALID_SHAPE');
  end if;
  v_expected:=public.lf_prepare_card_carrier_write_intent_v1(p_execution_id);
  if (v_expected->>'outcome') is distinct from 'INTENT_PREPARED_NO_WRITE' then
    return jsonb_build_object('valid',false,'code','I5_SERVER_INTENT_NOT_AVAILABLE','server_result',v_expected);
  end if;
  if p_intent is distinct from v_expected then
    return jsonb_build_object('valid',false,'code','I5_INTENT_TAMPERED_OR_STALE','expected_intent_sha256',v_expected->>'intent_sha256','observed_intent_sha256',p_intent->>'intent_sha256');
  end if;
  if (p_intent->'provider_call_authorized') is distinct from 'false'::jsonb then
    return jsonb_build_object('valid',false,'code','I5_PROVIDER_CALL_MUST_REMAIN_DISABLED');
  end if;
  return jsonb_build_object('valid',true,'code','I5_INTENT_EXACT_NO_WRITE','intent_sha256',p_intent->>'intent_sha256','provider_call_authorized',false);
end;
$function$;

revoke execute on function public.lf_validate_carrier_write_guard_shape_v1(text,jsonb,jsonb) from public,anon,authenticated;
revoke execute on function public.lf_prepare_card_carrier_write_intent_v1(text) from public,anon,authenticated;
revoke execute on function public.lf_validate_card_carrier_write_intent_v1(text,jsonb) from public,anon,authenticated;
grant execute on function public.lf_validate_carrier_write_guard_shape_v1(text,jsonb,jsonb) to service_role;
grant execute on function public.lf_prepare_card_carrier_write_intent_v1(text) to service_role;
grant execute on function public.lf_validate_card_carrier_write_intent_v1(text,jsonb) to service_role;
