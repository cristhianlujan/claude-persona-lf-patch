-- Laboratory-only reconstruction of exact deployed provenance validator and guard.
-- Original L37 policy19 fixture is loaded first, unchanged. Add ONLY missing live constraints/triggers.
CREATE SCHEMA IF NOT EXISTS programacion;
CREATE OR REPLACE FUNCTION programacion.fn_input_parameter_provenance_valid_v1(p_provenance jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
declare
  r record;
  v_origin text;
  v_status text;
  v_decision text;
  v_ref text;
  v_clause text;
  v_version text;
begin
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    return false;
  end if;

  for r in select key,value from jsonb_each(p_provenance)
  loop
    if nullif(btrim(r.key),'') is null or jsonb_typeof(r.value)<>'object' then return false; end if;
    v_origin:=r.value->>'origin_type';
    v_status:=r.value->>'value_status';
    v_decision:=nullif(btrim(coalesce(r.value->>'decision_ref','')),'');
    v_ref:=nullif(btrim(coalesce(r.value->>'origin_reference','')),'');
    v_clause:=nullif(btrim(coalesce(r.value->>'origin_clause','')),'');
    v_version:=nullif(btrim(coalesce(r.value->>'origin_version','')),'');

    if v_origin not in ('LF_CANONICAL','INTERNATIONAL_STANDARD','INDUSTRY_GUIDANCE','LF_PROVISIONAL_DEFAULT','UNCLASSIFIED_LEGACY') then return false; end if;
    if v_status not in ('LF_CANONICAL','EXTERNAL_REFERENCE','LF_PROVISIONAL','LEGACY_UNCLASSIFIED') then return false; end if;

    if v_origin='LF_CANONICAL' and (v_status<>'LF_CANONICAL' or v_decision is null) then return false; end if;
    if v_origin='INTERNATIONAL_STANDARD' and (v_ref is null or (v_clause is null and v_version is null)) then return false; end if;
    if v_origin='INDUSTRY_GUIDANCE' and v_ref is null then return false; end if;
    if v_origin='LF_PROVISIONAL_DEFAULT' and (
      v_status<>'LF_PROVISIONAL'
      or r.value->>'replacement_policy'<>'MUST_BE_RATIFIED_OR_OVERRIDDEN'
    ) then return false; end if;
    if v_origin='UNCLASSIFIED_LEGACY' and v_status<>'LEGACY_UNCLASSIFIED' then return false; end if;

    -- External provenance may become LF canonical only through an explicit LF ratification decision.
    if v_status='LF_CANONICAL' and v_origin<>'LF_CANONICAL' and (
      coalesce((r.value->>'ratified_by_lf')::boolean,false) is not true
      or v_decision is null
    ) then return false; end if;
  end loop;
  return true;
exception when others then
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_guard_input_parameter_provenance_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_new jsonb:=to_jsonb(new);
  v_old jsonb:=case when tg_op='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_prov jsonb:=coalesce(v_new->'parameter_provenance','{}'::jsonb);
  v_old_prov jsonb:=coalesce(v_old->'parameter_provenance','{}'::jsonb);
  v_keys text[];
  v_key text;
  v_changed boolean;
  v_old_cfg jsonb;
  v_new_cfg jsonb;
begin
  if not programacion.fn_input_parameter_provenance_valid_v1(v_prov) then
    raise exception 'PARAMETER_PROVENANCE_INVALID:%',tg_table_name;
  end if;

  if tg_table_name='politicas_rate_limit' then
    v_keys:=array['window_seconds','max_requests','burst_limit','scope_key'];
  elsif tg_table_name='politicas_timeout' then
    v_keys:=array['timeout_seconds','retry_limit','backoff_strategy'];
  elsif tg_table_name='politicas_sesion' then
    v_keys:=array['idle_timeout_seconds','warning_before_timeout_seconds','absolute_timeout_seconds','access_token_ttl_seconds','refresh_rotation_enabled','max_concurrent_sessions','extend_on_user_activity'];
  elsif tg_table_name='otp_politicas' then
    v_keys:=array['longitud','digitos_permitidos','expiracion_minutos','max_intentos','max_reenvios','bloqueo_reenvio_min','canal_primario','canal_fallback','fallback_segundos'];
  elsif tg_table_name='politicas_seguridad' then
    v_old_cfg:=coalesce(v_old->'policy_config','{}'::jsonb);
    v_new_cfg:=coalesce(v_new->'policy_config','{}'::jsonb);
    for v_key in
      select key from (
        select jsonb_object_keys(v_old_cfg) key
        union
        select jsonb_object_keys(v_new_cfg) key
      ) q order by key
    loop
      v_changed:=tg_op='INSERT' or (v_new_cfg->v_key is distinct from v_old_cfg->v_key);
      if v_changed then
        if not (v_prov ? v_key) then
          raise exception 'PARAMETER_PROVENANCE_REQUIRED:%:%',tg_table_name,v_key;
        end if;
        if tg_op='UPDATE' and v_prov->v_key is not distinct from v_old_prov->v_key then
          raise exception 'PARAMETER_PROVENANCE_REFRESH_REQUIRED:%:%',tg_table_name,v_key;
        end if;
      end if;
    end loop;
    return new;
  else
    raise exception 'PARAMETER_PROVENANCE_TABLE_UNSUPPORTED:%',tg_table_name;
  end if;

  foreach v_key in array v_keys
  loop
    v_changed:=tg_op='INSERT' or (v_new->v_key is distinct from v_old->v_key);
    if v_changed and jsonb_typeof(v_new->v_key)<>'null' then
      if not (v_prov ? v_key) then
        raise exception 'PARAMETER_PROVENANCE_REQUIRED:%:%',tg_table_name,v_key;
      end if;
      if tg_op='UPDATE' and v_prov->v_key is not distinct from v_old_prov->v_key then
        raise exception 'PARAMETER_PROVENANCE_REFRESH_REQUIRED:%:%',tg_table_name,v_key;
      end if;
    end if;
  end loop;
  return new;
end;
$function$;

ALTER TABLE lf_ops.politicas_seguridad ADD CONSTRAINT politicas_seguridad_parameter_provenance_ck
 CHECK (programacion.fn_input_parameter_provenance_valid_v1(parameter_provenance));
CREATE TRIGGER trg_politicas_seguridad_parameter_provenance
 BEFORE INSERT OR UPDATE ON lf_ops.politicas_seguridad FOR EACH ROW
 EXECUTE FUNCTION programacion.fn_guard_input_parameter_provenance_v1();
