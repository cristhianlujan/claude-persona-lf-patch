create or replace function programacion.fn_input_security_capability_profile(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_profile text;
  v_rule text;
begin
  if exists(
    select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-036'
  ) then
    v_profile:='LOGIN'; v_rule:='B2B-RULE-AUTH-036';
  elsif exists(
    select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-037'
  ) then
    v_profile:='RECOVERY_OTP_VERIFY'; v_rule:='B2B-RULE-AUTH-037';
  elsif exists(
    select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-028'
  ) then
    v_profile:='ACCOUNT_RECOVERY_REQUEST'; v_rule:='B2B-RULE-AUTH-028';
  elsif exists(
    select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-030'
  ) then
    v_profile:='PASSWORD_UPDATE'; v_rule:='B2B-RULE-AUTH-030';
  elsif exists(
    select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034'
  ) then
    v_profile:='OTP_VERIFY'; v_rule:='B2B-RULE-AUTH-034';
  elsif exists(
    select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035'
  ) then
    v_profile:='LEGACY_TOTP_ENROLLMENT'; v_rule:='B2B-RULE-AUTH-035';
  elsif exists(
    select 1
    from lf_ops.reglas r
    join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
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