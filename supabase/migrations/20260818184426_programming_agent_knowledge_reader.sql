create or replace function public.programming_agent_knowledge_v1(p_source text)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception 'authenticated user required';
  end if;

  case p_source
    when 'rules' then
      return query
      select jsonb_build_object(
        'id', c.id,
        'control_codigo', c.control_codigo,
        'familia', c.familia,
        'nombre', c.nombre,
        'descripcion', c.descripcion,
        'modo_evaluacion', c.modo_evaluacion,
        'severidad', c.severidad,
        'tipo_resultado', c.tipo_resultado,
        'fuente_umbral', c.fuente_umbral,
        'politica_sin_fuente', c.politica_sin_fuente,
        'accion_fallo', c.accion_fallo,
        'estado', c.estado,
        'created_at', c.created_at
      )
      from programacion.controles_calidad c
      where lower(coalesce(c.estado, '')) = 'defined'
      order by c.control_codigo;

    when 'decisions' then
      return query
      select jsonb_build_object(
        'id', d.id,
        'adr', d.adr,
        'titulo', d.titulo,
        'decision', d.decision,
        'razon', d.razon,
        'impacto', d.impacto,
        'estado', d.estado,
        'created_at', d.created_at
      )
      from transversal.decision_log d
      where lower(coalesce(d.estado, '')) in (
        'vigente', 'accepted', 'approved_plan', 'vigente_con_endurecimiento_pendiente'
      )
      order by d.adr;

    when 'ekb' then
      return query
      select jsonb_build_object(
        'id', e.id,
        'codigo', e.codigo,
        'categoria', e.categoria,
        'titulo', e.titulo,
        'descripcion', e.descripcion,
        'causa_raiz', e.causa_raiz,
        'patron', e.patron,
        'prevencion', e.prevencion,
        'validacion', e.validacion,
        'severidad', e.severidad,
        'estado', e.estado,
        'created_at', e.created_at,
        'updated_at', e.updated_at,
        'lifecycle_phase', e.lifecycle_phase,
        'consumer_role', e.consumer_role,
        'source_ref', e.source_ref
      )
      from transversal.error_knowledge e
      where lower(coalesce(e.estado, '')) in ('active', 'activo', 'open')
      order by e.codigo;

    when 'preventions' then
      return query
      select jsonb_build_object(
        'id', p.id,
        'regla_codigo', p.regla_codigo,
        'error_codigo', p.error_codigo,
        'regla', p.regla,
        'justificacion', p.justificacion,
        'prioridad', p.prioridad,
        'activa', p.activa,
        'created_at', p.created_at,
        'categoria', p.categoria,
        'lifecycle_phase', p.lifecycle_phase,
        'consumer_role', p.consumer_role
      )
      from transversal.prevention_rules p
      where p.activa is true
      order by p.regla_codigo;

    when 'best_practices' then
      return query
      select jsonb_build_object(
        'id', b.id,
        'categoria', b.categoria,
        'titulo', b.titulo,
        'practica', b.practica,
        'evidencia', b.evidencia,
        'created_at', b.created_at
      )
      from transversal.best_practices b
      order by b.created_at, b.id;

    else
      raise exception 'unsupported knowledge source';
  end case;
end;
$$;

revoke all on function public.programming_agent_knowledge_v1(text) from public;
revoke all on function public.programming_agent_knowledge_v1(text) from anon;
grant execute on function public.programming_agent_knowledge_v1(text) to authenticated;

comment on function public.programming_agent_knowledge_v1(text) is
  'Read-only, authenticated Programming Agent knowledge gateway. Exposes only explicit canonical fields; no DML authority.';