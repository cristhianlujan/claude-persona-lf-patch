-- IG M9.3: root performance fix. Security profile repeated seven full selector/effective-rule
-- resolutions on every semantic probe. Reuse one resolution in the current invocation.
-- Existing precedence, positive requirements, rule statuses and links are unchanged.
-- Tested in LF_SUPABASE_SANDBOX with exact SQL + ROLLBACK:
-- B2B-AUTH-001 LOGIN/036; HOME_001 UNRESOLVED; ONB_002 OTP_VERIFY phone ownership.
DO $guard$ BEGIN
 IF md5(pg_get_functiondef('programacion.fn_input_security_capability_profile(integer)'::regprocedure)) <> 'c2398236d74c1756c851bb55ee662100' THEN
   RAISE EXCEPTION 'SECURITY_CAPABILITY_PROFILE_SOURCE_DRIFT';
 END IF;
END $guard$;
CREATE OR REPLACE FUNCTION programacion.fn_input_security_capability_profile(p_pantalla_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
declare
  v_profile text;
  v_rule text;
  v_rule_links jsonb;
begin
  -- Reuse the same effective-rule resolution across all security profile checks.
  select coalesce(jsonb_agg(to_jsonb(z)),'[]'::jsonb) into v_rule_links
  from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') z;
  if exists(
    select 1 from lf_ops.reglas r join jsonb_to_recordset(v_rule_links) rp(pantalla_id integer,regla_id integer) on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-036'
  ) then
    v_profile:='LOGIN'; v_rule:='B2B-RULE-AUTH-036';
  elsif exists(
    select 1 from lf_ops.reglas r join jsonb_to_recordset(v_rule_links) rp(pantalla_id integer,regla_id integer) on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-037'
  ) then
    v_profile:='RECOVERY_OTP_VERIFY'; v_rule:='B2B-RULE-AUTH-037';
  elsif exists(
    select 1 from lf_ops.reglas r join jsonb_to_recordset(v_rule_links) rp(pantalla_id integer,regla_id integer) on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-028'
  ) then
    v_profile:='ACCOUNT_RECOVERY_REQUEST'; v_rule:='B2B-RULE-AUTH-028';
  elsif exists(
    select 1 from lf_ops.reglas r join jsonb_to_recordset(v_rule_links) rp(pantalla_id integer,regla_id integer) on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-030'
  ) then
    v_profile:='PASSWORD_UPDATE'; v_rule:='B2B-RULE-AUTH-030';
  elsif exists(
    select 1 from lf_ops.reglas r join jsonb_to_recordset(v_rule_links) rp(pantalla_id integer,regla_id integer) on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034'
  ) then
    v_profile:='OTP_VERIFY'; v_rule:='B2B-RULE-AUTH-034';
  elsif exists(
    select 1 from lf_ops.reglas r join jsonb_to_recordset(v_rule_links) rp(pantalla_id integer,regla_id integer) on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035'
  ) then
    v_profile:='LEGACY_TOTP_ENROLLMENT'; v_rule:='B2B-RULE-AUTH-035';
  elsif exists(
    select 1
    from lf_ops.reglas r
    join jsonb_to_recordset(v_rule_links) rp(pantalla_id integer,regla_id integer) on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id
      and r.codigo='REG_AUTH_PHONE_OWNERSHIP_001'
      and r.estado='VIGENTE'
      and r.valor_config->>'otp_proves'='PHONE_CONTROL'
      and r.valor_config->>'otp_does_not_prove'='PERSON_IDENTITY'
      and nullif(r.valor_config->>'otp_field_code','') is not null
      and exists(
        select 1
        from lf_ops.campos_pantallas cp
        join lf_ops.campos c on c.id=cp.campo_id
        where cp.pantalla_id=p_pantalla_id
          and c.codigo=r.valor_config->>'otp_field_code'
          and c.estado='ACTIVO'
      )
  ) then
    v_profile:='OTP_VERIFY'; v_rule:='REG_AUTH_PHONE_OWNERSHIP_001';
  else
    v_profile:='UNRESOLVED'; v_rule:=null;
  end if;

  return jsonb_build_object(
    'profile',v_profile,
    'authority_rule',v_rule,
    'pantalla_id',p_pantalla_id,
    'classification_mode','POSITIVE_LINKED_RULE'
  );
end;
$function$;
COMMENT ON FUNCTION programacion.fn_input_security_capability_profile(integer) IS
'Classify linked B2B/phone ownership authority; effective rule selector evaluated once per profile call (same outcomes/precedence).';
