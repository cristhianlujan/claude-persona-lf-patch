-- SADM-PP-L6-025 corrective migration: operational decision events cannot declare acceptance/validation decisions.
-- The existing LF_GOVERNANCE DECISION_ESTRATEGICA direction uses an explicit authorizes token;
-- this read-only producer maps that governed token to the typed AUTHORIZED_PLAN_DELTA receipt.

create or replace function public.fn_lf_plan_delta_authority_readback_v1(
  p_authorization_event_id bigint,
  p_plan_id text,
  p_previous_plan_digest text,
  p_next_plan_digest text
) returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public
as $$
declare
  v_event public.lf_eventos%rowtype;
  v_payload jsonb;
  v_canonical text;
  v_digest text;
begin
  if p_authorization_event_id is null or p_authorization_event_id <= 0 then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_EVENT_ID_INVALID','event_id',p_authorization_event_id);
  end if;
  if coalesce(p_plan_id,'') = '' then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','PLAN_ID_REQUIRED','event_id',p_authorization_event_id);
  end if;
  if p_previous_plan_digest !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','PREVIOUS_PLAN_DIGEST_INVALID','event_id',p_authorization_event_id);
  end if;
  if p_next_plan_digest !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','NEXT_PLAN_DIGEST_INVALID','event_id',p_authorization_event_id);
  end if;

  select * into v_event
  from public.lf_eventos
  where id = p_authorization_event_id;

  if not found then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_EVENT_NOT_FOUND','event_id',p_authorization_event_id);
  end if;

  v_payload := v_event.payload;
  if v_event.evento_tipo <> 'DECISION_ESTRATEGICA' then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_EVENT_TYPE_MISMATCH','event_id',p_authorization_event_id);
  end if;
  if v_event.entidad_tipo <> 'PROGRAM_PLAN' then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_ENTITY_TYPE_MISMATCH','event_id',p_authorization_event_id);
  end if;
  if v_event.entidad_codigo <> p_plan_id then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_PLAN_ENTITY_MISMATCH','event_id',p_authorization_event_id);
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_PAYLOAD_REQUIRED','event_id',p_authorization_event_id);
  end if;
  if v_payload->>'authority' <> 'LF_GOVERNANCE' then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_AUTHORITY_MISMATCH','event_id',p_authorization_event_id);
  end if;
  if jsonb_typeof(v_payload->'authorizes') is distinct from 'array' or not ((v_payload->'authorizes') ? 'PLAN_DELTA_AUTHORITY') then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_TOKEN_MISSING','event_id',p_authorization_event_id);
  end if;
  if v_payload->>'authorization_scope' <> 'PLAN_DELTA_AUTHORITY' then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_SCOPE_MISMATCH','event_id',p_authorization_event_id);
  end if;
  if v_payload->>'plan_id' <> p_plan_id then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_PLAN_ID_MISMATCH','event_id',p_authorization_event_id);
  end if;
  if v_payload->>'previous_plan_digest' <> p_previous_plan_digest then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_PREVIOUS_DIGEST_MISMATCH','event_id',p_authorization_event_id);
  end if;
  if v_payload->>'next_plan_digest' <> p_next_plan_digest then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_NEXT_DIGEST_MISMATCH','event_id',p_authorization_event_id);
  end if;
  if coalesce((v_payload->>'self_authorization')::boolean, true) is not false then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','SELF_AUTHORIZATION_NOT_EXPLICITLY_FORBIDDEN','event_id',p_authorization_event_id);
  end if;

  v_canonical := '{'
    || '"authority":' || to_jsonb('PLAN_AUTHORITY'::text)::text || ','
    || '"decision":' || to_jsonb('AUTHORIZED_PLAN_DELTA'::text)::text || ','
    || '"event_id":' || p_authorization_event_id::text || ','
    || '"next_plan_digest":' || to_jsonb(p_next_plan_digest)::text || ','
    || '"plan_id":' || to_jsonb(p_plan_id)::text || ','
    || '"previous_plan_digest":' || to_jsonb(p_previous_plan_digest)::text || ','
    || '"schema_version":' || to_jsonb('LF_PLAN_DELTA_AUTHORITY_READBACK_V1'::text)::text
    || '}';
  v_digest := encode(extensions.digest(convert_to(v_canonical,'UTF8'),'sha256'),'hex');

  return jsonb_build_object(
    'schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1',
    'authority','PLAN_AUTHORITY',
    'decision','AUTHORIZED_PLAN_DELTA',
    'event_id',p_authorization_event_id,
    'plan_id',p_plan_id,
    'previous_plan_digest',p_previous_plan_digest,
    'next_plan_digest',p_next_plan_digest,
    'receipt_digest',v_digest
  );
end;
$$;

comment on function public.fn_lf_plan_delta_authority_readback_v1(bigint,text,text,text) is
  'Read-only producer of LF_PLAN_DELTA_AUTHORITY_READBACK_V1 from an existing LF_GOVERNANCE DECISION_ESTRATEGICA with exact PLAN_DELTA_AUTHORITY authorizes token. Does not create or authorize events.';

update public.lf_activos
set version='1.0.1',
    raw_payload = coalesce(raw_payload,'{}'::jsonb) || jsonb_build_object(
      'event_authorization_binding','AUTHORIZE_TOKEN_TO_TYPED_RECEIPT',
      'event_contract_compatible',true,
      'self_authorization_allowed',false,
      'runtime_authorized',false,
      'production_authorized',false
    ),
    metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'event_contract','operational-event/v2',
      'event_authorizes_token','PLAN_DELTA_AUTHORITY',
      'receipt_decision','AUTHORIZED_PLAN_DELTA'
    ),
    updated_at=now(),
    updated_by_execution_id='EXEC-SADM-PP-L6-025-PLAN-DELTA-AUTHORITY-PRODUCER-V2-20261001'
where codigo_activo='PLAN_DELTA_AUTHORITY_READBACK_PRODUCER' and archived_at is null;

update public.lf_activo_relaciones
set valor_original='consumes LF_PLAN_DELTA_AUTHORITY_READBACK_V1 produced from LF_GOVERNANCE PLAN_DELTA_AUTHORITY authorizes token; no local shape is authority',
    updated_at=now(),
    updated_by_execution_id='EXEC-SADM-PP-L6-025-PLAN-DELTA-AUTHORITY-PRODUCER-V2-20261001'
where codigo_activo='PLAN_AUTHORITY_DRIFT_GUARD'
  and relacionado_codigo='PLAN_DELTA_AUTHORITY_READBACK_PRODUCER'
  and relacion_tipo='DEPENDE_DE';
