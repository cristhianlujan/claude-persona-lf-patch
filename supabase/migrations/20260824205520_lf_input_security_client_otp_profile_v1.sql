-- LF Input Governance: positive security capability profile for Client OTP verification.
-- Fixes GOV-012 recurrence without weakening semantic-depth guards.

create or replace function programacion.fn_input_security_capability_profile(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $$
declare v_profile text; v_rule text;
begin
  if exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-036') then v_profile:='LOGIN'; v_rule:='B2B-RULE-AUTH-036';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-037') then v_profile:='RECOVERY_OTP_VERIFY'; v_rule:='B2B-RULE-AUTH-037';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-028') then v_profile:='ACCOUNT_RECOVERY_REQUEST'; v_rule:='B2B-RULE-AUTH-028';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-030') then v_profile:='PASSWORD_UPDATE'; v_rule:='B2B-RULE-AUTH-030';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034') then v_profile:='OTP_VERIFY'; v_rule:='B2B-RULE-AUTH-034';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035') then v_profile:='LEGACY_TOTP_ENROLLMENT'; v_rule:='B2B-RULE-AUTH-035';
  elsif exists(
    select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id
    where rp.pantalla_id=p_pantalla_id
      and r.codigo='REG_AUTH_PHONE_OWNERSHIP_001'
      and r.estado='VIGENTE'
      and r.valor_config->>'otp_proves'='PHONE_CONTROL'
      and r.valor_config->>'otp_does_not_prove'='PERSON_IDENTITY'
  ) then v_profile:='OTP_VERIFY'; v_rule:='REG_AUTH_PHONE_OWNERSHIP_001';
  else v_profile:='UNRESOLVED'; v_rule:=null;
  end if;
  return jsonb_build_object('profile',v_profile,'authority_rule',v_rule,'pantalla_id',p_pantalla_id,'classification_mode','POSITIVE_LINKED_RULE');
end;
$$;

revoke all on function programacion.fn_input_security_capability_profile(integer) from public,anon,authenticated;

do $$
declare v_profile jsonb; v_threats jsonb;
begin
  v_profile:=programacion.fn_input_security_capability_profile(2);
  if v_profile->>'profile'<>'OTP_VERIFY' or v_profile->>'authority_rule'<>'REG_AUTH_PHONE_OWNERSHIP_001' then
    raise exception 'CLIENT_OTP_PROFILE_SELFTEST_FAILED:%',v_profile;
  end if;
  v_threats:=programacion.fn_input_security_threat_expected(2);
  if exists(select 1 from jsonb_array_elements(v_threats) t where t->>'applicability'='NOT_APPLICABLE' and (nullif(t->'applicability_authority'->>'authority_rule','') is null or nullif(t->>'rationale','') is null)) then
    raise exception 'CLIENT_OTP_PROFILE_NA_AUTHORITY_SELFTEST_FAILED';
  end if;
  if not exists(select 1 from jsonb_array_elements(v_threats) t where t->>'threat_code'='OTP_GUESSING' and t->>'applicability'='APPLICABLE') then
    raise exception 'CLIENT_OTP_PROFILE_OTP_GUESSING_NOT_APPLICABLE';
  end if;
end;
$$;
