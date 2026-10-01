-- SADM-PP-L6-025: canonical minimal producer for LF_PLAN_DELTA_AUTHORITY_READBACK_V1.
-- Reuses LF_GOVERNANCE + public.lf_eventos append-only evidence.
-- No new store, no new plan engine, no capability current pointer, no runtime/deploy/production.

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
  if v_payload->>'decision' <> 'AUTHORIZED_PLAN_DELTA' then
    return jsonb_build_object('schema_version','LF_PLAN_DELTA_AUTHORITY_READBACK_V1','authority','PLAN_AUTHORITY','decision','PLAN_DELTA_NOT_AUTHORIZED','ready',false,'reason','AUTHORIZATION_DECISION_MISMATCH','event_id',p_authorization_event_id);
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

  -- Exact canonical JSON used by PLAN_AUTHORITY_DRIFT_GUARD_V1:
  -- json.dumps(sort_keys=True,separators=(',',':'),ensure_ascii=False)
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
  'Read-only canonical producer of LF_PLAN_DELTA_AUTHORITY_READBACK_V1 from an existing LF_GOVERNANCE append-only authorization event. Does not create or authorize deltas.';

do $$
declare
  v_execution_id constant text := 'EXEC-SADM-PP-L6-025-PLAN-DELTA-AUTHORITY-PRODUCER-20261001';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d6d-025000000001'::uuid;
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then
    raise exception 'BLOCK_PLAN_DELTA_AUTHORITY_LF_GOVERNANCE_MISSING';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='PLAN_AUTHORITY_DRIFT_GUARD' and archived_at is null) then
    raise exception 'BLOCK_PLAN_DELTA_AUTHORITY_DRIFT_GUARD_MISSING';
  end if;
  if to_regprocedure('public.fn_lf_plan_delta_authority_readback_v1(bigint,text,text,text)') is null then
    raise exception 'BLOCK_PLAN_DELTA_AUTHORITY_FUNCTION_MISSING';
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,
    estado_original,estado_documental,estado_operativo,impacto_automatico,version,
    ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,
    source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values (
    'PLAN_DELTA_AUTHORITY_READBACK_PRODUCER',
    'LF_PLAN_DELTA_AUTHORITY_READBACK_V1 Producer',
    'FUNCTION','TRANSVERSAL_AUTHORITY_READBACK_PRODUCER','SUPABASE_FUNCTION',
    'CANDIDATE_READ_ONLY','VIGENTE','ACTIVO','BLOQUEADO','1.0.0',
    'sandbox/lf_contract_gate_test/plan_delta_authority/README.md','LF_GOVERNANCE',
    'NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','PLAN_DELTA_AUTHORITY_20261001',1,
    jsonb_build_object(
      'solution_code','PLAN_DELTA_AUTHORITY_READBACK_PRODUCER_V1',
      'work_code','SADM-PP-L6-025',
      'producer_function','public.fn_lf_plan_delta_authority_readback_v1',
      'output_schema','LF_PLAN_DELTA_AUTHORITY_READBACK_V1',
      'new_store',false,'new_plan_engine',false,'self_authorization_allowed',false,
      'runtime_authorized',false,'production_authorized',false
    ),
    jsonb_build_object(
      'schema_version','PLAN_DELTA_AUTHORITY_READBACK_PRODUCER_ASSET_METADATA_V1',
      'authority','LF_GOVERNANCE',
      'evidence_surface','public.lf_eventos',
      'consumer','PLAN_AUTHORITY_DRIFT_GUARD',
      'contract_ref','sandbox/lf_contract_gate_test/plan_delta_authority/plan_delta_authority_contract_v1.json',
      'artifact_transport_policy','PASE_POST_PASE_ARTIFACT_TRANSPORT_NO_ZIP_V1',
      'capability_registry_entry_created',false,
      'current_pointer_created',false
    ),
    v_batch,v_execution_id,v_execution_id
  ) on conflict(codigo_activo) do update set
    estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.0.0',owner_name='LF_GOVERNANCE',
    ruta_esperada=excluded.ruta_esperada,raw_payload=excluded.raw_payload,metadata=excluded.metadata,
    updated_at=now(),updated_by_execution_id=v_execution_id;

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values
    ('PLAN_DELTA_AUTHORITY_READBACK_PRODUCER','LF_GOVERNANCE','DEPENDE_DE',
     'authorization must preexist as LF_GOVERNANCE append-only decision',
     'sandbox/lf_contract_gate_test/plan_delta_authority/plan_delta_authority_contract_v1.json',v_batch,v_execution_id,v_execution_id),
    ('PLAN_AUTHORITY_DRIFT_GUARD','PLAN_DELTA_AUTHORITY_READBACK_PRODUCER','DEPENDE_DE',
     'consumes LF_PLAN_DELTA_AUTHORITY_READBACK_V1; no local shape is authority',
     'sandbox/lf_contract_gate_test/plan_delta_authority/plan_delta_authority_contract_v1.json',v_batch,v_execution_id,v_execution_id)
  on conflict do nothing;
end $$;
