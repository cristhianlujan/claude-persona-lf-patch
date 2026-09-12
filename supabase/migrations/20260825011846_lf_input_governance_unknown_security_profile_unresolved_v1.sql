create or replace function programacion.fn_input_security_threat_expected(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_profile text;
  v_base jsonb;
  v_out jsonb;
  v_auth jsonb;
  v_policy record;
begin
  v_profile:=programacion.fn_input_security_capability_profile(p_pantalla_id)->>'profile';
  v_base:=programacion.fn_input_security_threat_expected_v510(p_pantalla_id);

  if v_profile='UNRESOLVED' then
    v_auth:=programacion.fn_input_security_capability_profile(p_pantalla_id);
    select jsonb_agg(
      case
        when t->>'applicability'='NOT_APPLICABLE' then
          jsonb_build_object(
            'threat_code',t->>'threat_code',
            'applicability','UNRESOLVED',
            'status','UNRESOLVED',
            'evidence_refs','[]'::jsonb,
            'applicability_authority',v_auth,
            'rationale','Capability profile is unresolved; NOT_APPLICABLE is forbidden without positive linked functional-rule authority.'
          )
        else t
      end
      order by ord
    ) into v_out
    from jsonb_array_elements(v_base) with ordinality x(t,ord);
    return v_out;
  end if;

  if v_profile<>'RECOVERY_OTP_VERIFY' then
    return v_base;
  end if;

  v_auth:=programacion.fn_input_security_capability_profile(p_pantalla_id);
  select * into v_policy from lf_ops.otp_politicas where id=2;
  select jsonb_agg(
    case t->>'threat_code'
      when 'OPEN_REDIRECT' then jsonb_build_object('threat_code','OPEN_REDIRECT','applicability','APPLICABLE','status','COMPLETE','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-029'),'applicability_authority',v_auth,'rationale','Recovery verification uses fixed canonical route/screen identifiers and denies client context promotion; no arbitrary redirect target is accepted.')
      when 'SECRET_CREDENTIAL_EXPOSURE' then jsonb_build_object('threat_code','SECRET_CREDENTIAL_EXPOSURE','applicability','APPLICABLE','status','PARTIAL','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-037'),'applicability_authority',v_auth,'rationale','OTP values are denied from logs/analytics and generated/verified server-side; explicit transport and URL/query exposure controls are not yet independently materialized for this capability.')
      when 'AUTOMATION_BOT_ABUSE' then jsonb_build_object('threat_code','AUTOMATION_BOT_ABUSE','applicability','APPLICABLE','status','PARTIAL','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-037','B2B-RULE-AUTH-038','OTP_POL_B2B_AUTH_EMAIL_BREVO'),'applicability_authority',v_auth,'rationale','Attempt/resend policy and server-side verification exist, but a complete bot/automation control for verification is not independently evidenced.')
      when 'USER_ENUMERATION' then jsonb_build_object('threat_code','USER_ENUMERATION','applicability','APPLICABLE','status','COMPLETE','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-029','B2B-RULE-AUTH-037'),'applicability_authority',v_auth,'rationale','Account existence exposure is denied and recovery verification preserves anti-enumeration.')
      when 'RECOVERY_CONTEXT_REPLAY' then jsonb_build_object('threat_code','RECOVERY_CONTEXT_REPLAY','applicability','APPLICABLE','status','COMPLETE','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-029'),'applicability_authority',v_auth,'rationale','The grant is opaque, one-time and server-verified; reused/invalid recovery context is normalized and cannot be promoted by the client.')
      when 'OTP_GUESSING' then jsonb_build_object('threat_code','OTP_GUESSING','applicability','APPLICABLE','status',case when v_policy.id is not null and v_policy.max_intentos is not null and v_policy.expiracion_minutos is not null then 'PARTIAL' else 'MISSING' end,'evidence_refs',jsonb_build_array('B2B-RULE-AUTH-037','OTP_POL_B2B_AUTH_EMAIL_BREVO'),'applicability_authority',v_auth,'rationale','Server-side verification plus expiry/attempt limits exist; explicit entropy/CSPRNG and per-challenge guessing hardening is not fully evidenced in the materialized LF contract.')
      when 'OTP_REPLAY_SINGLE_USE' then jsonb_build_object('threat_code','OTP_REPLAY_SINGLE_USE','applicability','APPLICABLE','status','MISSING','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-029','B2B-RULE-AUTH-037'),'applicability_authority',v_auth,'rationale','The recovery context is one-time, but current LF evidence does not explicitly state that the OTP code itself is invalidated immediately after successful verification.')
      when 'OTP_RESEND_ABUSE' then jsonb_build_object('threat_code','OTP_RESEND_ABUSE','applicability','APPLICABLE','status',case when v_policy.max_reenvios is not null and v_policy.bloqueo_reenvio_min is not null then 'COMPLETE' else 'MISSING' end,'evidence_refs',jsonb_build_array('B2B-RULE-AUTH-038','OTP_POL_B2B_AUTH_EMAIL_BREVO'),'applicability_authority',v_auth,'rationale','Resend availability and countdown are policy-derived and the central policy defines resend limits/cooldown.')
      when 'MFA_BYPASS' then jsonb_build_object('threat_code','MFA_BYPASS','applicability','APPLICABLE','status','COMPLETE','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-029','B2B-RULE-AUTH-037'),'applicability_authority',v_auth,'rationale','Recovery OTP explicitly does not satisfy MFA and cannot create operational authorization/session.')
      else t
    end order by ord
  ) into v_out
  from jsonb_array_elements(v_base) with ordinality x(t,ord);
  return v_out;
end;
$function$;