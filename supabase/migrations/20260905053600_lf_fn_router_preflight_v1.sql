create or replace function public.fn_lf_router_preflight_v1(p_execution_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_router jsonb;
  v_ekb jsonb;
  v_evento_id bigint;
begin
  if coalesce(btrim(p_execution_id),'') = '' then
    raise exception 'p_execution_id requerido';
  end if;

  select to_jsonb(r) into v_router
  from (
    select codigo_activo, nombre_canonico, estado_documental, estado_operativo,
           nivel_control, runtime_estado, impacto_automatico,
           version_normalizada, updated_at
    from public.v_lf_fuente_operativa
    where codigo_activo = 'ACT-0001'
  ) r;

  if v_router is null then
    raise exception 'Router ACT-0001 no encontrado en v_lf_fuente_operativa';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', codigo, 'titulo', titulo,
           'severidad', severidad, 'prevencion', prevencion)
         order by ultima_vez desc nulls last), '[]'::jsonb)
  into v_ekb
  from public.lf_error_knowledge
  where upper(coalesce(estado,'')) in ('ACTIVO','ACTIVE','ABIERTO','OPEN')
    and upper(coalesce(severidad,'')) in ('ALTA','HIGH','CRITICA','CRITICAL','P0');

  insert into public.lf_eventos (
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) values (
    'SESION_INICIO','ACTIVO','ACT-0001',
    'Preflight de router y EKB ejecutado por funcion de base de datos, sin pasar por execute_sql.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'execution_id', p_execution_id,
      'producer','fn_lf_router_preflight_v1',
      'purpose','Materializar router ACT-0001 y controles EKB activos al inicio de la corrida',
      'acceptance_declared', false,
      'occurred_at', to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'router', v_router,
      'ekb_activos_count', jsonb_array_length(v_ekb)
    ),
    'DB_FUNCTION', p_execution_id
  ) returning id into v_evento_id;

  return jsonb_build_object(
    'execution_id', p_execution_id,
    'evento_id', v_evento_id,
    'router', v_router,
    'ekb_controles', v_ekb,
    'ekb_controles_count', jsonb_array_length(v_ekb)
  );
end;
$$;

revoke all on function public.fn_lf_router_preflight_v1(text) from public, anon;
grant execute on function public.fn_lf_router_preflight_v1(text) to service_role;