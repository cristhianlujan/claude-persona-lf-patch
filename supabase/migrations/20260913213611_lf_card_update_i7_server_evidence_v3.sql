-- LF_CARD_UPDATE_I7_SERVER_EVIDENCE_VALIDATOR_V0_3
-- Source-first overlay for I7 independent-review remediation.
-- Preserves candidate/no-write ceiling. Does not register CARD_UPDATE in Router.

create or replace function public.lf_validate_card_update_step_evidence_v3(
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
  v_parent_count integer := 0;
  v_parent_code text;
  v_parent_ref text;
  v_expected_binding_ref text;
  v_assertions jsonb := jsonb_build_array(
    'required evidence present',
    'prior required steps clean',
    'Supabase operational authority preserved',
    'external carrier not used as authority'
  );
  v_hash text;
  v_state text;
  v_router_count integer := 0;
  v_trust_observed_at timestamptz;
  v_expected_trust_source text;
  v_expected_currentness_token text;
  v_expected_anchor_or_path text;
  v_expected_content_hash text;
begin
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARD_STEP_EVIDENCE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;

  select * into v_execution
  from public.lf_operation_execution
  where execution_id=p_execution_id;
  if not found
     or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
     or v_execution.target_type is distinct from 'CARD'
     or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','CARD_STEP_EXECUTION_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;

  select * into v_card
  from public.lf_activos
  where codigo_activo=v_execution.target_code
    and tipo_activo='CARD'
    and archived_at is null;
  if not found then
    return jsonb_build_object('valid',false,'code','CARD_STEP_TARGET_NOT_FOUND','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;

  v_binding:=v_card.metadata->'carrier_binding_v1';
  v_trust:=v_execution.manifest->'connector_trust_context';
  if v_binding is null or jsonb_typeof(v_binding) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','CARD_STEP_BINDING_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;
  if (v_binding->>'binding_status') is distinct from 'CURRENT_AT_OBSERVATION'
     or (v_binding->>'carrier_authority')::boolean is distinct from false
     or (v_binding->>'carrier_write_allowed')::boolean is distinct from false
     or v_card.runtime_estado is distinct from 'PRODUCCION_CONTROLADA_READ_ONLY'
     or v_card.estado_operativo is distinct from 'READ_ONLY'
     or v_card.impacto_automatico is distinct from 'BLOQUEADO' then
    return jsonb_build_object(
      'valid',false,'code','CARD_STEP_AUTHORITY_CEILING_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested')
    );
  end if;

  select count(*),min(relacionado_codigo)
  into v_parent_count,v_parent_code
  from public.lf_activo_relaciones
  where codigo_activo=v_execution.target_code
    and relacion_tipo='HIJO_DE';
  if v_parent_count<>1 or v_parent_code is null then
    return jsonb_build_object(
      'valid',false,'code','CARD_STEP_PARENT_NOT_EXACT',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('identity or parent source changed')
    );
  end if;
  v_parent_ref:='supabase://public/lf_activos/'||v_parent_code;
  v_expected_binding_ref:='supabase://public/lf_activos/'||v_execution.target_code||'#metadata.carrier_binding_v1';

  if (v_binding->>'carrier_type')='GOOGLE_DOC_EMBEDDED_BLOCK' then
    v_expected_trust_source:='GOOGLE_DOCS_API_CONNECTOR_FRESH_READ';
    v_expected_currentness_token:=v_binding->>'provider_revision_id';
    v_expected_anchor_or_path:=v_binding->>'block_anchor';
    v_expected_content_hash:=v_binding->>'content_sha256';
  elsif (v_binding->>'carrier_type')='GITHUB_FILE' then
    v_expected_trust_source:='GITHUB_API_CONNECTOR_FRESH_READ';
    v_expected_currentness_token:=v_binding->>'provider_blob_sha';
    v_expected_anchor_or_path:=v_binding->>'path';
    v_expected_content_hash:=v_binding->>'content_sha256';
  else
    return jsonb_build_object('valid',false,'code','CARD_STEP_CARRIER_UNSUPPORTED','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;

  -- Steps that claim carrier currentness must consume the fresh execution-bound trust context.
  if p_step_id in ('parent_source_read','baseline_read') then
    if v_trust is null or jsonb_typeof(v_trust) is distinct from 'object' then
      return jsonb_build_object('valid',false,'code','CARD_STEP_FRESH_TRUST_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
    if (v_trust->>'source') is distinct from v_expected_trust_source
       or (v_trust->>'carrier_type') is distinct from (v_binding->>'carrier_type')
       or (v_trust->>'carrier_ref') is distinct from (v_binding->>'carrier_ref')
       or (v_trust->>'content_sha256') is distinct from v_expected_content_hash
       or (v_trust->>'block_anchor_or_path') is distinct from v_expected_anchor_or_path then
      return jsonb_build_object('valid',false,'code','CARD_STEP_FRESH_TRUST_BINDING_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
    if (v_binding->>'carrier_type')='GOOGLE_DOC_EMBEDDED_BLOCK' then
      if (v_trust->>'document_id') is distinct from (v_binding->>'document_id')
         or (v_trust->>'provider_revision_id') is distinct from v_expected_currentness_token then
        return jsonb_build_object('valid',false,'code','CARD_STEP_GOOGLE_CURRENTNESS_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
      end if;
    else
      if (v_trust->>'repository_full_name') is distinct from (v_binding->>'repository_full_name')
         or (v_trust->>'path') is distinct from (v_binding->>'path')
         or (v_trust->>'provider_head_sha') is distinct from (v_binding->>'provider_head_sha')
         or (v_trust->>'provider_blob_sha') is distinct from v_expected_currentness_token then
        return jsonb_build_object('valid',false,'code','CARD_STEP_GITHUB_CURRENTNESS_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
      end if;
    end if;
    if nullif(v_trust->>'observed_at','') is null then
      return jsonb_build_object('valid',false,'code','CARD_STEP_TRUST_OBSERVED_AT_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
    begin
      v_trust_observed_at:=(v_trust->>'observed_at')::timestamptz;
    exception when others then
      return jsonb_build_object('valid',false,'code','CARD_STEP_TRUST_OBSERVED_AT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end;
    if v_trust_observed_at<v_execution.started_at
       or v_trust_observed_at>clock_timestamp()+interval '60 seconds'
       or clock_timestamp()-v_trust_observed_at>interval '5 minutes' then
      return jsonb_build_object(
        'valid',false,'code','CARD_STEP_TRUST_OUTSIDE_FRESHNESS_WINDOW',
        'server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,
        'details',jsonb_build_object('observed_at',v_trust_observed_at,'started_at',v_execution.started_at,'max_age_seconds',300)
      );
    end if;
  end if;

  if p_step_id='router' then
    select count(*) into v_router_count
    from public.lf_router_action_registry
    where asset_type='CARD'
      and action_code='CARD_UPDATE'
      and status in ('ACTIVE','CANDIDATO_READ_ONLY');
    if v_router_count<>0 then
      return jsonb_build_object(
        'valid',false,'code','CARD_STEP_UNEXPECTED_ROUTER_BINDING_PRESENT',
        'server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,
        'details',jsonb_build_object('router_binding_count',v_router_count)
      );
    end if;
    if (p_evidence_payload->>'action') is distinct from 'CARD_UPDATE'
       or (p_evidence_payload->>'router_state') is distinct from 'CANDIDATO_READ_ONLY_NO_ROUTER' then
      return jsonb_build_object('valid',false,'code','CARD_STEP_ROUTER_ABSENCE_EVIDENCE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='card_resolve' then
    if (p_evidence_payload->>'card_code') is distinct from v_execution.target_code
       or nullif(p_evidence_payload->>'card_id','') is null
       or (p_evidence_payload->>'card_id')::bigint is distinct from v_card.id
       or p_evidence_payload->'exact_card_resolved' is distinct from 'true'::jsonb
       or p_evidence_payload->'active_before' is distinct from 'true'::jsonb then
      return jsonb_build_object('valid',false,'code','CARD_STEP_CARD_RESOLVE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='carrier_resolve' then
    if (p_evidence_payload->>'carrier_type') is distinct from (v_binding->>'carrier_type')
       or (p_evidence_payload->>'carrier_ref') is distinct from (v_binding->>'carrier_ref')
       or (p_evidence_payload->>'parent_asset_code') is distinct from v_parent_code
       or (p_evidence_payload->>'parent_source_ref') is distinct from v_parent_ref
       or (p_evidence_payload->>'supabase_authority_ref') is distinct from (v_binding->>'operational_authority_ref')
       or (p_evidence_payload->>'carrier_binding_ref') is distinct from v_expected_binding_ref
       or (p_evidence_payload->>'block_anchor') is distinct from v_expected_anchor_or_path then
      return jsonb_build_object(
        'valid',false,'code','CARD_STEP_CARRIER_RESOLVE_MISMATCH',
        'server_assertions','[]'::jsonb,
        'server_hard_fails',jsonb_build_array('authority inferred from carrier')
      );
    end if;
  elsif p_step_id='parent_source_read' then
    if (p_evidence_payload->>'parent_source_ref') is distinct from v_parent_ref
       or p_evidence_payload->'block_anchor_found' is distinct from 'true'::jsonb
       or p_evidence_payload->'transport_integrity_only' is distinct from 'true'::jsonb
       or (p_evidence_payload->>'source_currentness') is distinct from 'FRESH_CONNECTOR_CURRENT'
       or (p_evidence_payload->>'carrier_revision') is distinct from v_expected_currentness_token then
      return jsonb_build_object('valid',false,'code','CARD_STEP_PARENT_SOURCE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='baseline_read' then
    if nullif(p_evidence_payload->>'baseline_canonical_content','') is null
       or nullif(p_evidence_payload->>'baseline_content_sha256','') is null
       or nullif(p_evidence_payload->>'baseline_block_excerpt_hash','') is null then
      return jsonb_build_object('valid',false,'code','CARD_STEP_BASELINE_REVERSIBLE_CONTENT_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
    v_hash:=encode(extensions.digest(p_evidence_payload->>'baseline_canonical_content','sha256'),'hex');
    v_state:=v_card.estado_documental||'/'||v_card.estado_operativo||'/'||v_card.runtime_estado||'/'||v_card.impacto_automatico;
    if (p_evidence_payload->>'baseline_identity') is distinct from v_execution.target_code
       or (p_evidence_payload->>'baseline_card_state') is distinct from v_state
       or (p_evidence_payload->>'baseline_carrier_type') is distinct from (v_binding->>'carrier_type')
       or (p_evidence_payload->>'baseline_carrier_ref') is distinct from (v_binding->>'carrier_ref')
       or (p_evidence_payload->>'baseline_block_anchor_or_path') is distinct from v_expected_anchor_or_path
       or (p_evidence_payload->>'baseline_carrier_revision') is distinct from v_expected_currentness_token
       or (p_evidence_payload->>'baseline_block_excerpt_hash') is distinct from v_expected_content_hash
       or (p_evidence_payload->>'baseline_content_sha256') is distinct from v_hash
       or (p_evidence_payload->>'baseline_content_sha256') is distinct from v_expected_content_hash
       or (p_evidence_payload->>'baseline_content_chars')::integer is distinct from length(p_evidence_payload->>'baseline_canonical_content') then
      return jsonb_build_object(
        'valid',false,'code','CARD_STEP_BASELINE_CONTENT_OR_IDENTITY_MISMATCH',
        'server_assertions','[]'::jsonb,
        'server_hard_fails',jsonb_build_array('identity or parent source changed')
      );
    end if;
  elsif p_step_id='change_scope' then
    if nullif(p_evidence_payload->>'defect','') is null
       or nullif(p_evidence_payload->>'root_cause','') is null
       or jsonb_typeof(p_evidence_payload->'minimal_patch_scope') is distinct from 'array'
       or jsonb_array_length(p_evidence_payload->'minimal_patch_scope')=0
       or jsonb_typeof(p_evidence_payload->'preserved_constraints') is distinct from 'array'
       or jsonb_array_length(p_evidence_payload->'preserved_constraints')=0
       or p_evidence_payload->'authority_boundaries_preserved' is distinct from 'true'::jsonb
       or p_evidence_payload->'carrier_route_preserved' is distinct from 'true'::jsonb then
      return jsonb_build_object('valid',false,'code','CARD_STEP_CHANGE_SCOPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='regression_plan' then
    if jsonb_typeof(p_evidence_payload->'positive_cases') is distinct from 'array'
       or jsonb_typeof(p_evidence_payload->'negative_cases') is distinct from 'array'
       or jsonb_typeof(p_evidence_payload->'adversarial_cases') is distinct from 'array'
       or jsonb_typeof(p_evidence_payload->'stale_revision_cases') is distinct from 'array'
       or jsonb_typeof(p_evidence_payload->'wrong_carrier_cases') is distinct from 'array'
       or jsonb_typeof(p_evidence_payload->'holdout') is distinct from 'array'
       or jsonb_array_length(p_evidence_payload->'positive_cases')=0
       or jsonb_array_length(p_evidence_payload->'negative_cases')=0
       or jsonb_array_length(p_evidence_payload->'adversarial_cases')=0
       or jsonb_array_length(p_evidence_payload->'stale_revision_cases')=0
       or jsonb_array_length(p_evidence_payload->'wrong_carrier_cases')=0
       or jsonb_array_length(p_evidence_payload->'holdout')=0 then
      return jsonb_build_object('valid',false,'code','CARD_STEP_REGRESSION_PLAN_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
  elsif p_step_id='pre_write_execution_binding_gate' then
    return public.lf_validate_card_update_trust_v1(p_execution_id,p_step_id,p_evidence_payload);
  else
    return jsonb_build_object(
      'valid',false,'code','CARD_STEP_VALIDATOR_STEP_NOT_SUPPORTED',
      'details',jsonb_build_object('step_id',p_step_id),
      'server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb
    );
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CARD_STEP_SERVER_VALIDATED',
    'server_assertions',v_assertions,
    'server_hard_fails','[]'::jsonb,
    'details',jsonb_build_object(
      'step_id',p_step_id,
      'card_code',v_execution.target_code,
      'carrier_type',v_binding->>'carrier_type',
      'authority','SUPABASE',
      'validation_scope','SERVER_DETERMINISTIC_STRUCTURAL',
      'router_binding_count',case when p_step_id='router' then v_router_count else null end,
      'trust_freshness_checked',p_step_id in ('parent_source_read','baseline_read')
    )
  );
exception when invalid_text_representation or numeric_value_out_of_range then
  return jsonb_build_object('valid',false,'code','CARD_STEP_EVIDENCE_TYPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
end;
$function$;

create or replace function public.lf_record_card_operation_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_step_order integer;
  v_server_validation jsonb;
begin
  select step_order into v_step_order
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_CARD_LF'
    and step_id=p_step_id
    and active is true;
  if v_step_order is null then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false);
  end if;
  if v_step_order>80 then
    v_server_validation:=jsonb_build_object(
      'valid',false,
      'code','CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I7',
      'details',jsonb_build_object('step_order',v_step_order,'ceiling_step_order',80),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested')
    );
  else
    v_server_validation:=public.lf_validate_card_update_step_evidence_v3(p_execution_id,p_step_id,p_evidence_payload);
  end if;
  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'ACTUALIZACION_CARD_LF','CARD','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY',
    v_server_validation,true,'lf_record_card_operation_step_v1'
  );
end;
$function$;

revoke execute on function public.lf_validate_card_update_step_evidence_v3(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.lf_validate_card_update_step_evidence_v3(text,text,jsonb) to service_role;
