-- LF_CARD_UPDATE_I7_SOURCE_AWARE_TRUST_INTENT_V1
-- Closes IR-F04 without enabling provider writes.
-- Google Docs and GitHub carriers are transport/currentness only; Supabase remains operational authority.

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
  v_carrier_type text;
  v_expected_source text;
  v_currentness_token text;
  v_expected_anchor_or_path text;
  v_expected_guard text;
  v_server_assertions jsonb := jsonb_build_array(
    'source policy v1.4 exact',
    'Supabase authority exact',
    'carrier binding exact',
    'fresh provider revision/blob exact',
    'change_scope present',
    'regression_plan present',
    'trusted context exact',
    'provider write guard planned'
  );
begin
  if p_step_id is distinct from 'pre_write_execution_binding_gate' then
    return jsonb_build_object('valid',true,'code','TRUST_GATE_NOT_APPLICABLE','server_assertions',v_server_assertions,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('step_id',p_step_id));
  end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_EVIDENCE_PAYLOAD_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb);
  end if;

  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
     or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_EXECUTION_IDENTITY_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb);
  end if;

  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('valid',false,'code','CARD_TRUST_TARGET_NOT_FOUND','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('target_code',v_execution.target_code)); end if;

  v_binding:=v_card.metadata->'carrier_binding_v1';
  if v_binding is null or jsonb_typeof(v_binding) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_DURABLE_BINDING_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb);
  end if;
  if (v_binding->>'binding_status') is distinct from 'CURRENT_AT_OBSERVATION'
     or coalesce((v_binding->>'carrier_authority')::boolean,true) is true
     or coalesce((v_binding->>'carrier_write_allowed')::boolean,true) is true then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_DURABLE_BINDING_STATE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb);
  end if;

  v_carrier_type:=v_binding->>'carrier_type';
  if v_carrier_type='GOOGLE_DOC_EMBEDDED_BLOCK' then
    v_expected_source:='GOOGLE_DOCS_API_CONNECTOR_FRESH_READ';
    v_currentness_token:=v_binding->>'provider_revision_id';
    v_expected_anchor_or_path:=v_binding->>'block_anchor';
    v_expected_guard:='requiredRevisionId';
  elsif v_carrier_type='GITHUB_FILE' then
    v_expected_source:='GITHUB_API_CONNECTOR_FRESH_READ';
    v_currentness_token:=v_binding->>'provider_blob_sha';
    v_expected_anchor_or_path:=v_binding->>'path';
    v_expected_guard:='EXPECTED_HEAD_AND_BLOB_SHA';
  else
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CARRIER_NOT_SUPPORTED','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('carrier_type',v_carrier_type));
  end if;

  select count(*) into v_policy_count from public.v_lf_operation_policy_snapshot
  where operation_code='ACTUALIZACION_CARD_LF' and policy_code='POL-LF-SOURCE-RESOLUTION';
  if v_policy_count<>1 then return jsonb_build_object('valid',false,'code','CARD_TRUST_SOURCE_POLICY_NOT_EXACT','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('count',v_policy_count)); end if;
  select policy_version,policy_sha into v_policy_version,v_policy_sha from public.v_lf_operation_policy_snapshot
  where operation_code='ACTUALIZACION_CARD_LF' and policy_code='POL-LF-SOURCE-RESOLUTION';
  if v_policy_version is distinct from 'v1.4-transversal-supabase-authority-visual-support'
     or v_policy_sha is distinct from '5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_SOURCE_POLICY_STALE','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('version',v_policy_version,'sha',v_policy_sha));
  end if;
  if (v_binding->>'source_policy_version') is distinct from v_policy_version or (v_binding->>'source_policy_sha') is distinct from v_policy_sha then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_BINDING_POLICY_STALE','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb);
  end if;

  v_trust:=v_execution.manifest->'connector_trust_context';
  if v_trust is null or jsonb_typeof(v_trust) is distinct from 'object' then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if (v_trust->>'source') is distinct from v_expected_source or (v_trust->>'carrier_type') is distinct from v_carrier_type
     or (v_trust->>'carrier_ref') is distinct from (v_binding->>'carrier_ref') then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_SOURCE_OR_ROUTE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('source',v_trust->>'source','carrier_type',v_trust->>'carrier_type'));
  end if;
  if nullif(v_trust->>'observed_at','') is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_OBSERVED_AT_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  begin v_trust_observed_at:=(v_trust->>'observed_at')::timestamptz; exception when others then return jsonb_build_object('valid',false,'code','CARD_TRUST_OBSERVED_AT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end;
  if v_trust_observed_at<v_execution.started_at or v_trust_observed_at>clock_timestamp()+interval '60 seconds' or clock_timestamp()-v_trust_observed_at>interval '5 minutes' then
    return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_OUTSIDE_FRESHNESS_WINDOW','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('observed_at',v_trust_observed_at,'started_at',v_execution.started_at,'max_age_seconds',300));
  end if;

  if v_carrier_type='GOOGLE_DOC_EMBEDDED_BLOCK' then
    if (v_trust->>'document_id') is distinct from (v_binding->>'document_id')
       or (v_trust->>'provider_revision_id') is distinct from v_currentness_token
       or (v_trust->>'block_anchor_or_path') is distinct from v_expected_anchor_or_path then
      return jsonb_build_object('valid',false,'code','CARD_TRUST_GOOGLE_CURRENTNESS_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb);
    end if;
  else
    if (v_trust->>'repository_full_name') is distinct from (v_binding->>'repository_full_name')
       or (v_trust->>'path') is distinct from (v_binding->>'path')
       or (v_trust->>'provider_head_sha') is distinct from (v_binding->>'provider_head_sha')
       or (v_trust->>'provider_blob_sha') is distinct from v_currentness_token
       or (v_trust->>'block_anchor_or_path') is distinct from v_expected_anchor_or_path then
      return jsonb_build_object('valid',false,'code','CARD_TRUST_GITHUB_CURRENTNESS_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb);
    end if;
  end if;
  if (v_trust->>'content_sha256') is distinct from (v_binding->>'content_sha256') then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTENT_HASH_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;

  select count(*),min(relacionado_codigo) into v_parent_count,v_parent_code from public.lf_activo_relaciones where codigo_activo=v_execution.target_code and relacion_tipo='HIJO_DE';
  if v_parent_count<>1 or v_parent_code is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_PARENT_RELATION_NOT_EXACT','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('count',v_parent_count)); end if;
  v_parent_ref:='supabase://public/lf_activos/'||v_parent_code;
  select evidence_ref into v_change_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='change_scope';
  select evidence_ref into v_regression_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='regression_plan';
  if v_change_ref is null or v_regression_ref is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_PLANNING_REFS_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if coalesce((select evidence_payload->>'parent_source_ref' from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='parent_source_read'),'') is distinct from v_parent_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_PARENT_SOURCE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('expected',v_parent_ref)); end if;

  v_expected_binding_ref:='supabase://public/lf_activos/'||v_execution.target_code||'#metadata.carrier_binding_v1';
  v_expected_trust_ref:=p_execution_id||'/manifest/connector_trust_context';
  if (p_evidence_payload->>'execution_id') is distinct from p_execution_id or (p_evidence_payload->>'card_code') is distinct from v_execution.target_code then return jsonb_build_object('valid',false,'code','CARD_TRUST_PAYLOAD_IDENTITY_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if (p_evidence_payload->>'current_source_policy_code') is distinct from 'POL-LF-SOURCE-RESOLUTION' or (p_evidence_payload->>'current_source_policy_version') is distinct from v_policy_version or (p_evidence_payload->>'current_source_policy_sha') is distinct from v_policy_sha then return jsonb_build_object('valid',false,'code','CARD_TRUST_PAYLOAD_POLICY_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if (p_evidence_payload->>'supabase_authority_ref') is distinct from (v_binding->>'operational_authority_ref') or (p_evidence_payload->>'carrier_binding_ref') is distinct from v_expected_binding_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_AUTHORITY_OR_BINDING_REF_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if (p_evidence_payload->>'carrier_type') is distinct from v_carrier_type or (p_evidence_payload->>'carrier_ref') is distinct from (v_binding->>'carrier_ref') then return jsonb_build_object('valid',false,'code','CARD_TRUST_CARRIER_ROUTE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if (p_evidence_payload->>'fresh_provider_revision_or_blob_sha') is distinct from v_currentness_token then return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_CURRENTNESS_BINDING_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if (p_evidence_payload->>'content_sha256') is distinct from (v_binding->>'content_sha256') or (p_evidence_payload->>'content_sha256') is distinct from (v_trust->>'content_sha256') then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTENT_HASH_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if (p_evidence_payload->>'block_anchor_or_path') is distinct from v_expected_anchor_or_path or (p_evidence_payload->>'block_anchor_or_path') is distinct from (v_trust->>'block_anchor_or_path') then return jsonb_build_object('valid',false,'code','CARD_TRUST_ANCHOR_OR_PATH_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if (p_evidence_payload->>'trusted_context_ref') is distinct from v_expected_trust_ref or (v_trust->>'trusted_context_ref') is distinct from v_expected_trust_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_REF_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if (p_evidence_payload->>'change_scope_ref') is distinct from v_change_ref or (p_evidence_payload->>'regression_plan_ref') is distinct from v_regression_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_PLANNING_REF_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('change_scope_expected',v_change_ref,'regression_plan_expected',v_regression_ref)); end if;
  if (p_evidence_payload->>'provider_write_guard') is distinct from v_expected_guard or (v_binding->>'provider_write_guard') is distinct from v_expected_guard or (v_trust->>'provider_write_guard') is distinct from v_expected_guard then return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_GUARD_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if p_evidence_payload->'pre_write_gate_passed' is distinct from 'true'::jsonb then return jsonb_build_object('valid',false,'code','CARD_TRUST_PREWRITE_PASS_FLAG_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;
  if v_card.runtime_estado is distinct from 'PRODUCCION_CONTROLADA_READ_ONLY' or v_card.impacto_automatico is distinct from 'BLOQUEADO' then return jsonb_build_object('valid',false,'code','CARD_TRUST_SAFETY_CEILING_CHANGED','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('runtime_estado',v_card.runtime_estado,'impacto_automatico',v_card.impacto_automatico)); end if;
  if v_carrier_type='GOOGLE_DOC_EMBEDDED_BLOCK' and coalesce((v_card.metadata->'storage_refs'->'google_drive'->>'operational_read_allowed')::boolean,true) is true then return jsonb_build_object('valid',false,'code','CARD_TRUST_GOOGLE_OPERATIONAL_READ_NOT_BLOCKED','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'details','{}'::jsonb); end if;

  return jsonb_build_object('valid',true,'code','CARD_TRUST_EXACT','server_assertions',v_server_assertions,'server_hard_fails','[]'::jsonb,'details',jsonb_build_object('card_code',v_execution.target_code,'parent_source_ref',v_parent_ref,'carrier_type',v_carrier_type,'currentness_token',v_currentness_token,'content_sha256',v_binding->>'content_sha256','source_policy_sha',v_policy_sha));
end;
$function$;

create or replace function public.lf_prepare_card_carrier_write_intent_v1(p_execution_id text)
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
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','I5_EXECUTION_IDENTITY_OR_STATUS_INVALID'); end if;
  select * into v_step80 from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='pre_write_execution_binding_gate' and step_order=80;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','I5_PREWRITE_STEP80_MISSING'); end if;
  select clean_result_value into v_clean_result from public.lf_operation_step_judge_bindings where operation_code='ACTUALIZACION_CARD_LF' and step_id='pre_write_execution_binding_gate' and step_order=80 and status='CANDIDATO_READ_ONLY';
  if v_clean_result is null or v_step80.status is distinct from v_clean_result then return jsonb_build_object('outcome','BLOCKED','code','I5_PREWRITE_STEP80_NOT_CLEAN','status',v_step80.status); end if;
  if (v_step80.evidence_payload->'trust_validation'->>'valid') is distinct from 'true' or (v_step80.evidence_payload->'trust_validation'->>'code') is distinct from 'CARD_TRUST_EXACT' then return jsonb_build_object('outcome','BLOCKED','code','I5_PREWRITE_TRUST_NOT_EXACT'); end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','I5_CARD_TARGET_NOT_FOUND'); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  v_trust:=v_execution.manifest->'connector_trust_context';
  if v_binding is null or jsonb_typeof(v_binding) is distinct from 'object' then return jsonb_build_object('outcome','BLOCKED','code','I5_DURABLE_BINDING_MISSING'); end if;
  if v_card.runtime_estado is distinct from 'PRODUCCION_CONTROLADA_READ_ONLY' or v_card.impacto_automatico is distinct from 'BLOQUEADO' then return jsonb_build_object('outcome','BLOCKED','code','I5_CARD_SAFETY_CEILING_CHANGED'); end if;
  if (v_binding->>'carrier_type')='GOOGLE_DOC_EMBEDDED_BLOCK' and coalesce((v_card.metadata->'storage_refs'->'google_drive'->>'operational_read_allowed')::boolean,true) is true then return jsonb_build_object('outcome','BLOCKED','code','I5_GOOGLE_OPERATIONAL_READ_NOT_BLOCKED'); end if;
  if (v_binding->>'binding_status') is distinct from 'CURRENT_AT_OBSERVATION' or coalesce((v_binding->>'carrier_authority')::boolean,true) is true or coalesce((v_binding->>'carrier_write_allowed')::boolean,true) is true then return jsonb_build_object('outcome','BLOCKED','code','I5_DURABLE_BINDING_STATE_INVALID'); end if;
  v_guard:=public.lf_validate_carrier_write_guard_shape_v1(v_binding->>'carrier_type',v_binding,v_trust);
  if (v_guard->>'valid') is distinct from 'true' then return jsonb_build_object('outcome','BLOCKED','code',coalesce(v_guard->>'code','I5_CARRIER_GUARD_INVALID'),'guard',v_guard); end if;
  v_intent:=jsonb_build_object('intent_schema','LF_CARD_CARRIER_WRITE_INTENT_V1','execution_id',p_execution_id,'operation_code','ACTUALIZACION_CARD_LF','card_code',v_execution.target_code,'supabase_authority_ref',v_binding->>'operational_authority_ref','carrier_type',v_binding->>'carrier_type','carrier_ref',v_binding->>'carrier_ref','write_route',v_guard->>'write_route','provider_guard_kind',v_guard->>'provider_guard_kind','provider_precondition',v_guard->'provider_precondition','bounded_target',v_guard->'bounded_target','change_scope_ref',(select evidence_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='change_scope'),'regression_plan_ref',(select evidence_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='regression_plan'),'source_policy_sha',v_binding->>'source_policy_sha','provider_call_authorized',false,'candidate_only',true,'carrier_authority',false,'generated_from','SUPABASE_EXECUTION_PLUS_DURABLE_BINDING_PLUS_FRESH_TRUST_CONTEXT');
  v_hash:=encode(extensions.digest(v_intent::text,'sha256'),'hex');
  return v_intent||jsonb_build_object('intent_sha256',v_hash,'outcome','INTENT_PREPARED_NO_WRITE');
end;
$function$;

revoke execute on function public.lf_validate_card_update_trust_v1(text,text,jsonb) from public,anon,authenticated;
revoke execute on function public.lf_prepare_card_carrier_write_intent_v1(text) from public,anon,authenticated;
grant execute on function public.lf_validate_card_update_trust_v1(text,text,jsonb) to service_role;
grant execute on function public.lf_prepare_card_carrier_write_intent_v1(text) to service_role;
