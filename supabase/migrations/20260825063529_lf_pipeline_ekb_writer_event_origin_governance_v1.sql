-- LF pipeline EKB writer + lf_eventos origin provenance governance v1.
-- Scope: ACT-0052..ACT-0058 operational governance only. No pipeline content semantics changed.

alter table public.lf_eventos
  alter column origen set default 'DERIVE_FROM_EXECUTION_ID'::text;

comment on column public.lf_eventos.origen is
  'Provenance label. If omitted, DB derives EXECUTION:<created_by_execution_id>. created_by_execution_id remains the authoritative execution identity. CHATGPT_SUPABASE_CONNECTOR is forbidden for new rows.';

create or replace function private.fn_lf_event_origin_provenance_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
begin
  if new.origen = 'CHATGPT_SUPABASE_CONNECTOR' then
    raise exception using errcode='23514', message='lf_eventos.origen CHATGPT_SUPABASE_CONNECTOR is forbidden for new rows; provide real provenance or omit origen for execution-derived provenance';
  end if;

  if new.origen = 'DERIVE_FROM_EXECUTION_ID' then
    if nullif(btrim(coalesce(new.created_by_execution_id,'')),'') is null then
      raise exception using errcode='23514', message='lf_eventos origin derivation requires created_by_execution_id';
    end if;
    new.origen := 'EXECUTION:' || new.created_by_execution_id;
  end if;

  if nullif(btrim(coalesce(new.origen,'')),'') is null then
    raise exception using errcode='23514', message='lf_eventos.origen cannot be empty';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_00_lf_eventos_origin_provenance_v1 on public.lf_eventos;
create trigger trg_00_lf_eventos_origin_provenance_v1
before insert on public.lf_eventos
for each row execute function private.fn_lf_event_origin_provenance_v1();

alter table public.lf_eventos
  drop constraint if exists lf_eventos_origen_no_false_connector_v1;
alter table public.lf_eventos
  add constraint lf_eventos_origen_no_false_connector_v1
  check (origen <> 'CHATGPT_SUPABASE_CONNECTOR' and btrim(origen) <> '') not valid;

create or replace function public.lf_registrar_evento(
  p_evento_tipo text,
  p_entidad_tipo text,
  p_entidad_codigo text,
  p_descripcion text,
  p_severidad text default 'INFO'::text,
  p_payload jsonb default '{}'::jsonb,
  p_migration_batch_id uuid default null::uuid
)
returns public.lf_eventos
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row public.lf_eventos;
begin
  insert into public.lf_eventos(
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, migration_batch_id
  ) values (
    p_evento_tipo, p_entidad_tipo, p_entidad_codigo, p_descripcion,
    coalesce(p_severidad,'INFO'), coalesce(p_payload,'{}'::jsonb),
    'LF_REGISTRAR_EVENTO', p_migration_batch_id
  ) returning * into v_row;
  return v_row;
end;
$function$;

create or replace function public.lf_write_pipeline_ekb_v1(
  p_operation_code text,
  p_error jsonb,
  p_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','transversal'
as $function$
declare
  v_code text;
  v_existing transversal.error_knowledge%rowtype;
  v_row transversal.error_knowledge%rowtype;
  v_roles text[];
  v_classification text;
  v_event_id bigint;
  v_now timestamptz := clock_timestamp();
  v_payload jsonb;
  v_required text[] := array[
    'codigo','categoria','titulo','descripcion','causa_raiz','prevencion','validacion',
    'severidad','lifecycle_phase','consumer_role','root_cause_family','detectability',
    'source_context','source_ref','evidencia'
  ];
begin
  if nullif(btrim(coalesce(p_operation_code,'')),'') is null
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or jsonb_typeof(p_error) is distinct from 'object' then
    raise exception using errcode='23514', message='pipeline EKB writer requires operation_code, execution_id and object error payload';
  end if;

  if not exists (
    select 1
    from public.lf_operation_contracts c
    where c.operation_code=p_operation_code
      and c.contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
      and c.status='ACTIVE_ENFORCEMENT'
      and coalesce((c.required_before_write->>'pre_ekb_gate_required')::boolean,false)
  ) then
    raise exception using errcode='42501', message=format('pipeline EKB writer operation is not governed by active PRE_EKB_GATE: %s',p_operation_code);
  end if;

  if not exists (
    select 1 from private.lf_event_type_contracts_v2 c
    where c.event_type='REMEDIACION_GOBERNANZA'
      and c.active
      and c.contract_mode='OPERATIONAL'
      and 'operational-event/v2'=any(c.allowed_evidence_schemas)
  ) then
    raise exception using errcode='23514', message='pipeline EKB writer requires active REMEDIACION_GOBERNANZA operational-event/v2 contract';
  end if;

  v_code := upper(btrim(coalesce(p_error->>'codigo','')));
  if v_code='' or v_code !~ '^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$' then
    raise exception using errcode='23514', message='pipeline EKB writer requires canonical error codigo';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('lf-pipeline-ekb:'||v_code,0));
  select * into v_existing
  from transversal.error_knowledge
  where codigo=v_code
  for update;

  if found then
    v_classification := 'RECURRENCE';
    update transversal.error_knowledge
       set frecuencia=frecuencia+1,
           ultima_vez=v_now,
           evidencia=concat_ws(E'\n\n',evidencia,nullif(btrim(coalesce(p_error->>'evidencia','')),'')),
           source_context=coalesce(nullif(btrim(coalesce(p_error->>'source_context','')),''),source_context),
           source_ref=coalesce(nullif(btrim(coalesce(p_error->>'source_ref','')),''),source_ref),
           lote_origen=coalesce(nullif(btrim(coalesce(p_error->>'lote_origen','')),''),lote_origen),
           pr=coalesce(nullif(btrim(coalesce(p_error->>'pr','')),''),pr),
           updated_at=v_now
     where id=v_existing.id
     returning * into v_row;
  else
    v_classification := 'NEW_ERROR';

    if not (p_error ?& v_required) then
      raise exception using errcode='23514', message='NEW_ERROR requires complete governed EKB shape';
    end if;
    if jsonb_typeof(p_error->'consumer_role') is distinct from 'array'
       or jsonb_array_length(p_error->'consumer_role')=0 then
      raise exception using errcode='23514', message='NEW_ERROR consumer_role must be a non-empty array';
    end if;
    select array_agg(value order by ord)
      into v_roles
    from jsonb_array_elements_text(p_error->'consumer_role') with ordinality x(value,ord);

    if exists(select 1 from unnest(v_roles) x where nullif(btrim(x),'') is null) then
      raise exception using errcode='23514', message='NEW_ERROR consumer_role cannot contain empty values';
    end if;
    if initcap(lower(btrim(p_error->>'severidad'))) not in ('Low','Medium','High','Critical') then
      raise exception using errcode='23514', message='NEW_ERROR severidad must be Low, Medium, High or Critical';
    end if;
    if p_error->>'root_cause_family' not in ('R1_NO_SABE','R2_NO_VE','R3_NO_PRIORIZA','R4_NO_CUESTIONA','R5_EROSION_PROCESO','UNCLASSIFIED_WITH_REASON') then
      raise exception using errcode='23514', message='NEW_ERROR root_cause_family is outside governed catalog';
    end if;
    if p_error->>'detectability' not in ('LOUD_EARLY','LOUD_LATE','SILENT','PROCESS_DEPENDENT') then
      raise exception using errcode='23514', message='NEW_ERROR detectability is outside governed catalog';
    end if;
    if exists (
      select 1 from unnest(array[
        p_error->>'categoria',p_error->>'titulo',p_error->>'descripcion',p_error->>'causa_raiz',
        p_error->>'prevencion',p_error->>'validacion',p_error->>'lifecycle_phase',
        p_error->>'source_context',p_error->>'source_ref',p_error->>'evidencia'
      ]) x where nullif(btrim(coalesce(x,'')),'') is null
    ) then
      raise exception using errcode='23514', message='NEW_ERROR governed text fields cannot be empty';
    end if;

    insert into transversal.error_knowledge(
      codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
      severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
      lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref
    ) values (
      v_code,btrim(p_error->>'categoria'),btrim(p_error->>'titulo'),btrim(p_error->>'descripcion'),
      btrim(p_error->>'causa_raiz'),nullif(btrim(coalesce(p_error->>'patron','')),''),
      btrim(p_error->>'prevencion'),btrim(p_error->>'validacion'),
      initcap(lower(btrim(p_error->>'severidad'))),1,v_now,v_now,
      nullif(btrim(coalesce(p_error->>'lote_origen','')),''),nullif(btrim(coalesce(p_error->>'pr','')),''),
      'activo',btrim(p_error->>'evidencia'),btrim(p_error->>'lifecycle_phase'),v_roles,
      p_error->>'root_cause_family',p_error->>'detectability',btrim(p_error->>'source_context'),btrim(p_error->>'source_ref')
    ) returning * into v_row;
  end if;

  v_payload := jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id',p_execution_id,
    'producer','LF_PIPELINE_EKB_WRITER_V1',
    'purpose','Persist governed pipeline EKB error or verified recurrence with readback receipt',
    'occurred_at',v_now,
    'acceptance_declared',false,
    'operation_code',p_operation_code,
    'classification',v_classification,
    'error_code',v_row.codigo,
    'ekb_id',v_row.id,
    'frequency_after',v_row.frecuencia,
    'source_ref',v_row.source_ref
  );

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
  ) values (
    'REMEDIACION_GOBERNANZA','LF_PIPELINE_EKB',v_row.codigo,
    case when v_classification='NEW_ERROR'
      then 'Nuevo error del pipeline LF registrado mediante writer gobernado'
      else 'Recurrencia verificada del pipeline LF registrada mediante writer gobernado' end,
    case when lower(coalesce(v_row.severidad,''))='critical' then 'CRITICAL'
         when lower(coalesce(v_row.severidad,''))='high' then 'WARN'
         else 'INFO' end,
    v_payload,'LF_PIPELINE_EKB_WRITER_V1',p_execution_id
  ) returning id into v_event_id;

  return jsonb_build_object(
    'schema_version',1,
    'writer','public.lf_write_pipeline_ekb_v1',
    'operation_code',p_operation_code,
    'classification',v_classification,
    'error_code',v_row.codigo,
    'ekb_id',v_row.id,
    'frequency_after',v_row.frecuencia,
    'event_id',v_event_id,
    'readback',jsonb_build_object(
      'codigo',v_row.codigo,'estado',v_row.estado,'severidad',v_row.severidad,
      'frecuencia',v_row.frecuencia,'ultima_vez',v_row.ultima_vez,'source_ref',v_row.source_ref
    )
  );
end;
$function$;

revoke all on function public.lf_write_pipeline_ekb_v1(text,jsonb,text) from public,anon,authenticated;
grant execute on function public.lf_write_pipeline_ekb_v1(text,jsonb,text) to service_role;
comment on function public.lf_write_pipeline_ekb_v1(text,jsonb,text) is
  'Governed EKB writer for LF pipeline operations protected by CONTRACT-PRE-EKB-GATE-LF-v0.1. Derives NEW_ERROR vs RECURRENCE, validates complete new-error shape, emits REMEDIACION_GOBERNANZA receipt, and does not accept pantalla_id.';

update public.lf_operation_contracts
set allowed = coalesce(allowed,'{}'::jsonb) || jsonb_build_object(
      'ekb_writer','public.lf_write_pipeline_ekb_v1(text,jsonb,text)',
      'ekb_write_policy','NEW_ERROR_OR_RECURRENCE_ONLY',
      'pantalla_id_required',false
    ),
    blocked = coalesce(blocked,'{}'::jsonb) || jsonb_build_object(
      'ekb_direct_write_for_pipeline','DENY_BY_CONTRACT',
      'ekb_duplicate_codigo','DENY',
      'ekb_malformed_new_error','DENY'
    ),
    required_after_write = coalesce(required_after_write,'{}'::jsonb) || jsonb_build_object(
      'ekb_writer_receipt_required',true,
      'ekb_writer_event_type','REMEDIACION_GOBERNANZA'
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT_LF_EKB_ORIGIN_GOV_20260825'
where contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
  and status='ACTIVE_ENFORCEMENT'
  and operation_code in (
    'ORQUESTACION_PIPELINE_LF','EXTRACCION_FUENTES_DIGITALES_LF','HOMOLOGACION_FUENTES_DIGITALES_LF',
    'EXTRACCION_NOTICIAS_FINANCIERAS_LF','EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
    'ANALISIS_RIESGO_CONTENIDO_LF','ESCRITURA_BASE_CONOCIMIENTO_LF'
  );

-- Fail-closed self-test: the false historical connector label must be rejected for new events.
do $selftest$
declare
  v_rejected boolean := false;
begin
  begin
    insert into public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
    ) values (
      'REMEDIACION_GOBERNANZA','LF_TEST','ORIGIN_FALSE_CONNECTOR_SELFTEST',
      'Negative self-test for false connector origin','INFO',
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id','CHATGPT_LF_EKB_ORIGIN_GOV_20260825_SELFTEST',
        'producer','migration-selftest',
        'purpose','Verify false historical connector origin is rejected for new events',
        'occurred_at',clock_timestamp(),
        'acceptance_declared',false
      ),
      'CHATGPT_SUPABASE_CONNECTOR','CHATGPT_LF_EKB_ORIGIN_GOV_20260825_SELFTEST'
    );
  exception when check_violation then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'LF_EVENT_ORIGIN_FALSE_CONNECTOR_SELFTEST_FAILED';
  end if;
end;
$selftest$;