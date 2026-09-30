create or replace function programacion.fn_input_screen_canonical_graph(p_pantalla_id integer, p_version_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops','lf_design'
as $$
declare
  v_screen_code text;
  v_module_code text;
  v_shell_code text;
  v_contract jsonb;
  v_permissions jsonb := '[]'::jsonb;
  v_profile_permissions jsonb := '[]'::jsonb;
  v_messages jsonb := '[]'::jsonb;
  v_analytics jsonb := '[]'::jsonb;
begin
  select p.codigo,m.module_code,s.app_shell_code
    into v_screen_code,v_module_code,v_shell_code
  from lf_ops.pantallas p
  join lf_ops.modulos m on m.module_id=p.module_id
  join lf_ops.app_shells s on s.app_shell_id=m.app_shell_id
  where p.id=p_pantalla_id;
  if v_screen_code is null then raise exception 'SCREEN_CANONICAL_GRAPH_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  select f.contract into v_contract
  from lf_ops.fn_b2b_backoffice_login_contract(v_shell_code,v_module_code,v_screen_code) f
  limit 1;
  if v_contract is null then raise exception 'SCREEN_CANONICAL_CONTRACT_UNRESOLVED:%',p_pantalla_id; end if;

  -- The underlying LF adapter is parameterized but retains Login-specific metadata/analytics.
  -- Remove that metadata and replace analytics with the explicit screen relation.
  v_contract := v_contract - 'metadata';

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'analytics_screen',to_jsonb(ap),
      'event',to_jsonb(ae),
      'parameters',coalesce((
        select jsonb_agg(to_jsonb(prm) order by prm.analytics_parameter_id)
        from lf_ops.analytics_eventos_parametros prm
        where prm.analytics_event_id=ae.analytics_event_id
      ),'[]'::jsonb)
    ) order by ap.analytics_screen_id
  ),'[]'::jsonb)
  into v_analytics
  from lf_ops.analytics_pantallas ap
  join lf_ops.analytics_eventos_definicion ae on ae.analytics_event_id=ap.analytics_event_id
  where ap.pantalla_id=p_pantalla_id;

  v_contract := jsonb_set(v_contract,'{analytics}',v_analytics,true);

  select coalesce(jsonb_agg(jsonb_build_object('link',to_jsonb(pp),'permission',to_jsonb(pm)) order by pp.permission_id),'[]'::jsonb)
    into v_permissions
  from lf_ops.pantallas_permisos pp
  join lf_ops.permisos pm on pm.permission_id=pp.permission_id
  where pp.pantalla_id=p_pantalla_id;

  -- Only permissions actually attached to this screen or explicitly referenced by its rules.
  with direct_permissions as (
    select pp.permission_id
    from lf_ops.pantallas_permisos pp
    where pp.pantalla_id=p_pantalla_id and pp.permission_id is not null
  ), rule_permissions as (
    select distinct e.value::bigint as permission_id
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
    where rp.pantalla_id=p_pantalla_id
      and (e.key='permission_id' or e.key like '%_permission_id')
      and e.value ~ '^[0-9]+$'
  ), relevant_permissions as (
    select permission_id from direct_permissions
    union
    select permission_id from rule_permissions
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'screen_profile',to_jsonb(sp),
      'profile_permission',to_jsonb(pp),
      'permission',to_jsonb(pm),
      'authority','SCREEN_OR_RULE_SCOPED'
    ) order by sp.profile_id,pp.permission_id
  ),'[]'::jsonb)
  into v_profile_permissions
  from lf_ops.pantallas_perfiles sp
  join lf_ops.perfiles_permisos pp on pp.profile_id=sp.profile_id
  join lf_ops.permisos pm on pm.permission_id=pp.permission_id
  where sp.pantalla_id=p_pantalla_id
    and pp.permission_id in (select permission_id from relevant_permissions);

  with field_ids as (
    select cp.campo_id,cp.message_id from lf_ops.campos_pantallas cp where cp.pantalla_id=p_pantalla_id
  ), timeout_policy_ids as (
    select distinct e.value::bigint timeout_policy_id
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
    where rp.pantalla_id=p_pantalla_id and (e.key='timeout_policy_id' or e.key like '%_timeout_policy_id') and e.value ~ '^[0-9]+$'
  ), message_ids as (
    select message_id from field_ids where message_id is not null
    union
    select cv.message_id from lf_ops.campos_validaciones cv join field_ids f on f.campo_id=cv.campo_id where cv.message_id is not null
    union
    select tp.message_id from lf_ops.politicas_timeout tp where tp.timeout_policy_id in (select timeout_policy_id from timeout_policy_ids) and tp.message_id is not null
  )
  select coalesce(jsonb_agg(to_jsonb(mu) order by mu.message_id),'[]'::jsonb)
    into v_messages
  from lf_ops.mensajes_ui mu
  where mu.message_id in (select message_id from message_ids);

  return jsonb_build_object(
    'graph_contract','SCREEN_CANONICAL_GRAPH_V4',
    'screen_code',v_screen_code,
    'module_code',v_module_code,
    'app_shell_code',v_shell_code,
    'canonical_contract',v_contract,
    'screen_permissions',v_permissions,
    'profile_permissions',v_profile_permissions,
    'messages',v_messages,
    'agent_contract_version_id',p_version_id
  );
end;
$$;

revoke all on function programacion.fn_input_screen_canonical_graph(integer,bigint) from public;
grant execute on function programacion.fn_input_screen_canonical_graph(integer,bigint) to postgres;

update programacion.contratos
set especificacion = jsonb_set(
  jsonb_set(
    jsonb_set(especificacion,'{contract_revision}','"4.0"'::jsonb,true),
    '{screen_graph_contract}','"SCREEN_CANONICAL_GRAPH_V4"'::jsonb,true
  ),
  '{screen_graph_scoping}',
  '{"analytics":"lf_ops.analytics_pantallas","permissions":"DIRECT_SCREEN_OR_RULE_REFERENCED","metadata":"GENERIC_NO_LOGIN_METADATA"}'::jsonb,
  true
)
where version_id=12 and contrato_codigo='INPUT_READINESS_CONTRACT';