-- IG M9.3 / shared canonical graph performance repair. NON-PRODUCTION sandbox only.
-- Root: the same effective rule links were queried independently for permissions,
-- timeout policies and UI messages. One rule-config snapshot is reused across all
-- three projections. JSON null is normalized to SQL-style coalesce semantics.
-- Canonical authority outputs must remain byte-for-byte equivalent.
-- Transaction+ROLLBACK regression (v19): HOME_001 id4, ONB_002 id2,
-- B2B-AUTH-001 id51 have unchanged SHA-256; no persistent test residue.
DO $preflight$
BEGIN
 IF md5(pg_get_functiondef('programacion.fn_input_screen_canonical_graph(integer,bigint)'::regprocedure)) <> 'df0eacee1c14ec9d5d8810f98d615913' THEN
  RAISE EXCEPTION 'IG_M93_CANONICAL_GRAPH_SOURCE_DRIFT';
 END IF;
END $preflight$;
CREATE OR REPLACE FUNCTION programacion.fn_input_screen_canonical_graph(p_pantalla_id integer, p_version_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops', 'lf_design'
AS $function$
declare
  v_request_context jsonb;
  v_cached_graph jsonb;
  v_cached_graph_sha text;
  v_request_graph_build_count integer;
  v_screen_code text; v_module_code text; v_shell_code text; v_contract jsonb;
  v_permissions jsonb:='[]'::jsonb; v_profile_permissions jsonb:='[]'::jsonb; v_messages jsonb:='[]'::jsonb; v_analytics jsonb:='[]'::jsonb;
  v_rule_configs jsonb:='[]'::jsonb;
  v_readiness_spec jsonb;
  v_design_binding_contract text;
  v_api_resolution_contract text;
  v_graph_contract text;
begin
  begin
    v_request_context:=nullif(current_setting('lf.input_request_context_v1',true),'')::jsonb;
  exception when others then
    raise exception 'INPUT_REQUEST_CONTEXT_INVALID';
  end;
  if v_request_context is not null then
    if coalesce((v_request_context->>'pantalla_id')::integer,-1)<>p_pantalla_id
       or coalesce((v_request_context->>'version_id')::bigint,-1)<>p_version_id then
      raise exception 'INPUT_REQUEST_CONTEXT_IDENTITY_MISMATCH:%:%',p_pantalla_id,p_version_id;
    end if;
    v_cached_graph:=v_request_context->'graph';
    v_cached_graph_sha:=nullif(v_request_context->>'graph_sha256','');
    if v_cached_graph is null
       or v_cached_graph_sha is null
       or v_cached_graph_sha is distinct from programacion.fn_v09_sha256_jsonb(v_cached_graph) then
      raise exception 'INPUT_REQUEST_CONTEXT_GRAPH_SHA_MISMATCH:%:%',p_pantalla_id,p_version_id;
    end if;
    return v_cached_graph;
  end if;
  v_request_graph_build_count:=coalesce(nullif(current_setting('lf.input_request_graph_build_count_v1',true),'')::integer,0);
  perform set_config('lf.input_request_graph_build_count_v1',(v_request_graph_build_count+1)::text,true);
  select p.codigo,m.module_code,s.app_shell_code into v_screen_code,v_module_code,v_shell_code
  from lf_ops.pantallas p join lf_ops.modulos m on m.module_id=p.module_id join lf_ops.app_shells s on s.app_shell_id=m.app_shell_id where p.id=p_pantalla_id;
  if v_screen_code is null then raise exception 'SCREEN_CANONICAL_GRAPH_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not exists(select 1 from programacion.versiones_agente where id=p_version_id) then raise exception 'SCREEN_CANONICAL_GRAPH_AGENT_VERSION_NOT_FOUND:%',p_version_id; end if;
  select c.especificacion into v_readiness_spec
  from programacion.contratos c
  where c.version_id=p_version_id
    and c.contrato_codigo='INPUT_READINESS_CONTRACT'
    and c.estado='defined'
    and c.fail_closed
  order by c.id desc
  limit 1;
  if v_readiness_spec is null then raise exception 'SCREEN_CANONICAL_GRAPH_READINESS_CONTRACT_NOT_FOUND:%',p_version_id; end if;
  v_graph_contract:=nullif(v_readiness_spec->>'screen_graph_contract','');
  if v_graph_contract is null then raise exception 'SCREEN_CANONICAL_GRAPH_CONTRACT_NOT_PINNED:%',p_version_id; end if;
  v_design_binding_contract:=nullif(v_readiness_spec#>>'{design_system_readiness,binding_graph}','');
  v_api_resolution_contract:=nullif(v_readiness_spec#>>'{api_data_contract_readiness,resolution_contract}','');
  select f.contract into v_contract from lf_ops.fn_b2b_backoffice_login_contract(v_shell_code,v_module_code,v_screen_code) f limit 1;
  if v_contract is null then raise exception 'SCREEN_CANONICAL_CONTRACT_UNRESOLVED:%',p_pantalla_id; end if;
  v_contract:=v_contract-'metadata';
  -- Read effective-rule configuration once and share the exact per-rule JSON payload.
  select coalesce(jsonb_agg(jsonb_build_object('config',r.valor_config)),'[]'::jsonb)
  into v_rule_configs
  from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
  join lf_ops.reglas r on r.id=rp.regla_id where rp.pantalla_id=p_pantalla_id;

  select coalesce(jsonb_agg(jsonb_build_object('analytics_screen',to_jsonb(ap),'event',to_jsonb(ae),'parameters',coalesce((select jsonb_agg(to_jsonb(prm) order by prm.analytics_parameter_id) from lf_ops.analytics_eventos_parametros prm where prm.analytics_event_id=ae.analytics_event_id),'[]'::jsonb)) order by ap.analytics_screen_id),'[]'::jsonb)
  into v_analytics from lf_ops.analytics_pantallas ap join lf_ops.analytics_eventos_definicion ae on ae.analytics_event_id=ap.analytics_event_id where ap.pantalla_id=p_pantalla_id;
  v_contract:=jsonb_set(v_contract,'{analytics}',v_analytics,true);

  select coalesce(jsonb_agg(jsonb_build_object('link',to_jsonb(pp),'permission',to_jsonb(pm)) order by pp.permission_id),'[]'::jsonb) into v_permissions
  from lf_ops.pantallas_permisos pp join lf_ops.permisos pm on pm.permission_id=pp.permission_id where pp.pantalla_id=p_pantalla_id;

  with direct_permissions as (select pp.permission_id from lf_ops.pantallas_permisos pp where pp.pantalla_id=p_pantalla_id and pp.permission_id is not null),
  rule_permissions as (select distinct e.value::bigint permission_id from jsonb_array_elements(v_rule_configs) rr(value) cross join lateral jsonb_each_text(coalesce(nullif(rr.value->'config','null'::jsonb),'{}'::jsonb)) e where (e.key='permission_id' or e.key like '%_permission_id') and e.value~'^[0-9]+$'),
  relevant_permissions as (select permission_id from direct_permissions union select permission_id from rule_permissions)
  select coalesce(jsonb_agg(jsonb_build_object('screen_profile',to_jsonb(sp),'profile_permission',to_jsonb(pp),'permission',to_jsonb(pm),'authority','SCREEN_OR_RULE_SCOPED') order by sp.profile_id,pp.permission_id),'[]'::jsonb)
  into v_profile_permissions from lf_ops.pantallas_perfiles sp join lf_ops.perfiles_permisos pp on pp.profile_id=sp.profile_id join lf_ops.permisos pm on pm.permission_id=pp.permission_id
  where sp.pantalla_id=p_pantalla_id and pp.permission_id in (select permission_id from relevant_permissions);

  with field_ids as (select cp.campo_id,cp.message_id from lf_ops.campos_pantallas cp where cp.pantalla_id=p_pantalla_id),
  timeout_policy_ids as (select distinct e.value::bigint timeout_policy_id from jsonb_array_elements(v_rule_configs) rr(value) cross join lateral jsonb_each_text(coalesce(nullif(rr.value->'config','null'::jsonb),'{}'::jsonb)) e where (e.key='timeout_policy_id' or e.key like '%_timeout_policy_id') and e.value~'^[0-9]+$'),
  rule_message_ids as (select distinct e.value::bigint message_id from jsonb_array_elements(v_rule_configs) rr(value) cross join lateral jsonb_each_text(coalesce(nullif(rr.value->'config','null'::jsonb),'{}'::jsonb)) e where (e.key='message_id' or e.key like '%_message_id') and e.value~'^[0-9]+$'),
  message_ids as (select message_id from field_ids where message_id is not null union select cv.message_id from lf_ops.campos_validaciones cv join field_ids f on f.campo_id=cv.campo_id where cv.message_id is not null union select tp.message_id from lf_ops.politicas_timeout tp where tp.timeout_policy_id in (select timeout_policy_id from timeout_policy_ids) and tp.message_id is not null union select message_id from rule_message_ids)
  select coalesce(jsonb_agg(to_jsonb(mu) order by mu.message_id),'[]'::jsonb) into v_messages from lf_ops.mensajes_ui mu where mu.message_id in (select message_id from message_ids);

  if v_design_binding_contract is not null then
    case v_design_binding_contract
      when 'DESIGN_BINDING_GRAPH_V1' then
        v_contract:=jsonb_set(v_contract,'{visual,design_bindings}',programacion.fn_input_design_binding_graph(p_pantalla_id),true);
      when 'DESIGN_BINDING_GRAPH_V2' then
        v_contract:=jsonb_set(v_contract,'{visual,design_bindings}',programacion.fn_input_design_binding_graph_v2(p_pantalla_id),true);
      else
        raise exception 'SCREEN_CANONICAL_GRAPH_UNSUPPORTED_DESIGN_BINDING_CONTRACT:%:%',p_version_id,v_design_binding_contract;
    end case;
  end if;

  if v_api_resolution_contract is not null then
    if v_api_resolution_contract<>'API_CONTRACT_RESOLUTION_V1' then
      raise exception 'SCREEN_CANONICAL_GRAPH_UNSUPPORTED_API_RESOLUTION_CONTRACT:%:%',p_version_id,v_api_resolution_contract;
    end if;
    v_contract:=jsonb_set(v_contract,'{api_contract_resolution}',programacion.fn_input_api_contract_resolution(p_pantalla_id),true);
  end if;

  return jsonb_build_object('graph_contract',v_graph_contract,'screen_code',v_screen_code,'module_code',v_module_code,'app_shell_code',v_shell_code,'canonical_contract',v_contract,'screen_permissions',v_permissions,'profile_permissions',v_profile_permissions,'messages',v_messages,'agent_contract_version_id',p_version_id);
end;
$function$;
COMMENT ON FUNCTION programacion.fn_input_screen_canonical_graph(integer,bigint) IS
 'Canonical graph: effective rule-config links are read once and reused by permission, timeout and UI-message projections. Contract and authority identities unchanged (IG M9.3).';
