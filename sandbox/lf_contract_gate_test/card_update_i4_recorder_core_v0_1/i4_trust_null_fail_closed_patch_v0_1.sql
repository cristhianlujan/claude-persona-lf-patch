-- LF_CARD_UPDATE_I4_TRUST_NULL_FAIL_CLOSED_V1
-- Negative canary found SQL NULL comparisons could fail open when connector_trust_context or required keys were absent.
-- Harden every Card pre-write trust comparison with explicit NULL-safe semantics.

create or replace function public.lf_validate_card_update_trust_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
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
  v_policy_version text;
  v_policy_sha text;
  v_policy_count integer := 0;
  v_parent_count integer := 0;
  v_parent_code text;
  v_parent_ref text;
  v_change_ref text;
  v_regression_ref text;
  v_expected_binding_ref text;
  v_expected_trust_ref text;
  v_trust_observed_at timestamptz;
begin
  if p_step_id is distinct from 'pre_write_execution_binding_gate' then
    return jsonb_build_object('valid',true,'code','TRUST_GATE_NOT_APPLICABLE','details',jsonb_build_object('step_id',p_step_id));
  end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_EVIDENCE_PAYLOAD_INVALID','details','{}'::jsonb);
  end if;

  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found
     or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
     or v_execution.target_type is distinct from 'CARD'
     or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_EXECUTION_IDENTITY_INVALID','details','{}'::jsonb);
  end if;

  select * into v_card from public.lf_activos
  where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_TARGET_NOT_FOUND','details',jsonb_build_object('target_code',v_execution.target_code));
  end if;

  v_binding:=v_card.metadata->'carrier_binding_v1';
  if v_binding is null or jsonb_typeof(v_binding) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_DURABLE_BINDING_MISSING','details','{}'::jsonb);
  end if;
  if (v_binding->>'binding_status') is distinct from 'CURRENT_AT_OBSERVATION'
     or coalesce((v_binding->>'carrier_authority')::boolean,true) is true
     or coalesce((v_binding->>'carrier_write_allowed')::boolean,true) is true then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_DURABLE_BINDING_STATE_INVALID','details','{}'::jsonb);
  end if;
  if (v_binding->>'carrier_type') is distinct from 'GOOGLE_DOC_EMBEDDED_BLOCK' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CARRIER_NOT_SUPPORTED_I4','details',jsonb_build_object('carrier_type',v_binding->>'carrier_type'));
  end if;

  select count(*) into v_policy_count
  from public.v_lf_operation_policy_snapshot
  where operation_code='ACTUALIZACION_CARD_LF' and policy_code='POL-LF-SOURCE-RESOLUTION';
  if v_policy_count<>1 then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_SOURCE_POLICY_NOT_EXACT','details',jsonb_build_object('count',v_policy_count));
  end if;
  select policy_version,policy_sha into v_policy_version,v_policy_sha
  from public.v_lf_operation_policy_snapshot
  where operation_code='ACTUALIZACION_CARD_LF' and policy_code='POL-LF-SOURCE-RESOLUTION';
  if v_policy_version is distinct from 'v1.4-transversal-supabase-authority-visual-support'
     or v_policy_sha is distinct from '5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_SOURCE_POLICY_STALE','details',jsonb_build_object('version',v_policy_version,'sha',v_policy_sha));
  end if;
  if (v_binding->>'source_policy_version') is distinct from v_policy_version
     or (v_binding->>'source_policy_sha') is distinct from v_policy_sha then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_BINDING_POLICY_STALE','details','{}'::jsonb);
  end if;

  v_trust:=v_execution.manifest->'connector_trust_context';
  if v_trust is null or jsonb_typeof(v_trust) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_MISSING','details','{}'::jsonb);
  end if;
  if (v_trust->>'source') is distinct from 'GOOGLE_DOCS_API_CONNECTOR_FRESH_READ' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_SOURCE_INVALID','details',jsonb_build_object('source',v_trust->>'source'));
  end if;
  if (v_trust->>'observed_at') is null or btrim(v_trust->>'observed_at')='' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_OBSERVED_AT_MISSING','details','{}'::jsonb);
  end if;
  begin
    v_trust_observed_at:=(v_trust->>'observed_at')::timestamptz;
  exception when others then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_OBSERVED_AT_INVALID','details','{}'::jsonb);
  end;
  if v_trust_observed_at is null or v_trust_observed_at<v_execution.started_at then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_PREDATES_EXECUTION','details',jsonb_build_object('observed_at',v_trust_observed_at,'started_at',v_execution.started_at));
  end if;

  select count(*),min(relacionado_codigo) into v_parent_count,v_parent_code
  from public.lf_activo_relaciones where codigo_activo=v_execution.target_code and relacion_tipo='HIJO_DE';
  if v_parent_count<>1 or v_parent_code is null then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PARENT_RELATION_NOT_EXACT','details',jsonb_build_object('count',v_parent_count));
  end if;
  v_parent_ref:='supabase://public/lf_activos/'||v_parent_code;
  select evidence_ref into v_change_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='change_scope';
  select evidence_ref into v_regression_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='regression_plan';
  if v_change_ref is null or v_regression_ref is null then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PLANNING_REFS_MISSING','details','{}'::jsonb);
  end if;
  if coalesce((select evidence_payload->>'parent_source_ref' from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='parent_source_read'),'') is distinct from v_parent_ref then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PARENT_SOURCE_MISMATCH','details',jsonb_build_object('expected',v_parent_ref));
  end if;

  v_expected_binding_ref:='supabase://public/lf_activos/'||v_execution.target_code||'#metadata.carrier_binding_v1';
  v_expected_trust_ref:=p_execution_id||'/manifest/connector_trust_context';

  if (p_evidence_payload->>'execution_id') is distinct from p_execution_id
     or (p_evidence_payload->>'card_code') is distinct from v_execution.target_code then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PAYLOAD_IDENTITY_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->>'current_source_policy_code') is distinct from 'POL-LF-SOURCE-RESOLUTION'
     or (p_evidence_payload->>'current_source_policy_version') is distinct from v_policy_version
     or (p_evidence_payload->>'current_source_policy_sha') is distinct from v_policy_sha then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PAYLOAD_POLICY_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->>'supabase_authority_ref') is distinct from (v_binding->>'operational_authority_ref')
     or (p_evidence_payload->>'carrier_binding_ref') is distinct from v_expected_binding_ref then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_AUTHORITY_OR_BINDING_REF_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->>'carrier_type') is distinct from (v_binding->>'carrier_type')
     or (p_evidence_payload->>'carrier_ref') is distinct from (v_binding->>'carrier_ref') then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CARRIER_ROUTE_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->>'fresh_provider_revision_or_blob_sha') is distinct from (v_binding->>'provider_revision_id') then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_REVISION_BINDING_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->>'fresh_provider_revision_or_blob_sha') is distinct from (v_trust->>'provider_revision_id') then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_REVISION_PAYLOAD_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->>'content_sha256') is distinct from (v_binding->>'content_sha256')
     or (p_evidence_payload->>'content_sha256') is distinct from (v_trust->>'content_sha256') then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTENT_HASH_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->>'block_anchor_or_path') is distinct from (v_binding->>'block_anchor')
     or (p_evidence_payload->>'block_anchor_or_path') is distinct from (v_trust->>'block_anchor_or_path') then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_ANCHOR_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->>'trusted_context_ref') is distinct from v_expected_trust_ref
     or (v_trust->>'trusted_context_ref') is distinct from v_expected_trust_ref then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_REF_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->>'change_scope_ref') is distinct from v_change_ref
     or (p_evidence_payload->>'regression_plan_ref') is distinct from v_regression_ref then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PLANNING_REF_MISMATCH','details',jsonb_build_object('change_scope_expected',v_change_ref,'regression_plan_expected',v_regression_ref));
  end if;
  if (p_evidence_payload->>'provider_write_guard') is distinct from 'requiredRevisionId'
     or (v_binding->>'provider_write_guard') is distinct from 'requiredRevisionId'
     or (v_trust->>'provider_write_guard') is distinct from 'requiredRevisionId' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_GUARD_MISMATCH','details','{}'::jsonb);
  end if;
  if (p_evidence_payload->'pre_write_gate_passed') is distinct from 'true'::jsonb then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_PREWRITE_PASS_FLAG_MISSING','details','{}'::jsonb);
  end if;
  if v_card.runtime_estado is distinct from 'PRODUCCION_CONTROLADA_READ_ONLY'
     or v_card.impacto_automatico is distinct from 'BLOQUEADO'
     or coalesce((v_card.metadata->'storage_refs'->'google_drive'->>'operational_read_allowed')::boolean,true) is true then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_SAFETY_CEILING_CHANGED','details',jsonb_build_object('runtime_estado',v_card.runtime_estado,'impacto_automatico',v_card.impacto_automatico));
  end if;

  return jsonb_build_object('valid',true,'code','CARD_TRUST_EXACT','details',jsonb_build_object(
    'card_code',v_execution.target_code,
    'parent_source_ref',v_parent_ref,
    'carrier_type',v_binding->>'carrier_type',
    'provider_revision_id',v_binding->>'provider_revision_id',
    'content_sha256',v_binding->>'content_sha256',
    'source_policy_sha',v_policy_sha
  ));
end;
$function$;

revoke execute on function public.lf_validate_card_update_trust_v1(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.lf_validate_card_update_trust_v1(text,text,jsonb) to service_role;
