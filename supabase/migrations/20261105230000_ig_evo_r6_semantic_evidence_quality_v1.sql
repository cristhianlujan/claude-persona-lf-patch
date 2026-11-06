-- IG-EVO L1 R6: source-bound semantic-evidence quality correction.
-- Scope: existing security threat projector, only LOGIN generic-claim quality
-- and RECOVERY_OTP_VERIFY one-time OTP evidence. Does not alter Router,
-- T_REMED, business rules, permissions, profiles or production by PR alone.
-- EKB preflight: GOV-010, GOV-032, IG-M46-*, IG-M107-A3-*, SEC-011.
-- Do not backfill historical RUNs; new RUN must use governed Curator/Validator.
begin;

do $source_pinning$
declare v_source text;
begin
  select pg_get_functiondef('programacion.fn_input_security_threat_expected(integer)'::regprocedure)
    into v_source;
  if md5(v_source)<>'4b38cbb21aaa30870bdb17f759f40b91' then
    raise exception 'IG_EVO_R6_SOURCE_DRIFT:expected=4b38cbb21aaa30870bdb17f759f40b91:actual=%',md5(v_source);
  end if;
end;
$source_pinning$;

CREATE OR REPLACE FUNCTION programacion.fn_input_security_threat_expected(p_pantalla_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
declare
  v_profile text;
  v_base jsonb;
  v_out jsonb;
  v_auth jsonb;
  v_policy record;
  v_otp_one_time_rule text;
  v_otp_one_time_state text;
begin
  v_profile:=programacion.fn_input_security_capability_profile(p_pantalla_id)->>'profile';
  v_base:=programacion.fn_input_security_threat_expected_v510(p_pantalla_id);

  -- R6 quality gate: eliminate unsupported generic COMPLETE for the LOGIN
  -- capability only. Reuse effective governed links instead of assuming
  -- SCREEN_RULE_SET is sufficient semantic proof.
  if v_profile='LOGIN' then
    with control_spec(threat_code, config_key, expected_value) as (
      values
      ('DOS_DDOS_RESOURCE_EXHAUSTION','resource_exhaustion','DENY_UNBOUNDED_REQUEST_PROCESSING'),
      ('SERVER_INPUT_INJECTION','server_input_injection','DENY'),
      ('XSS_SCRIPT_INJECTION','xss','DENY_UNTRUSTED_SCRIPT_EXECUTION'),
      ('CSRF_REQUEST','csrf','CSRF_TOKEN_REQUIRED'),
      ('SSRF_BACKEND_FETCH','ssrf','DENY_USER_CONTROLLED_BACKEND_FETCH_TARGETS'),
      ('CLICKJACKING','clickjacking','DENY'),
      ('CORS_ORIGIN_CONTROL','cors','EXPLICIT_ORIGIN_POLICY_REQUIRED'),
      ('DEPENDENCY_SUPPLY_CHAIN','supply_chain','SBOM_AND_DEPENDENCY_VULNERABILITY_CONTROL_REQUIRED'),
      ('REQUEST_PAYLOAD_RESOURCE_LIMIT','request_body_limit','REQUIRED')
    ), effective_rules as materialized (
      select r.codigo,r.estado,r.valor_config
      from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') link
      join lf_ops.reglas r on r.id=link.regla_id
      where r.estado in ('VIGENTE','CANDIDATO')
        and not coalesce(r.pendiente_decision,false)
    ), inspected as (
      select t,ord,
        (select e.codigo
         from effective_rules e
         where e.valor_config->>spec.config_key=spec.expected_value
         order by case when e.estado='VIGENTE' then 0 else 1 end,e.codigo
         limit 1) as source_code,
        (select e.estado
         from effective_rules e
         where e.valor_config->>spec.config_key=spec.expected_value
         order by case when e.estado='VIGENTE' then 0 else 1 end,e.codigo
         limit 1) as source_state
      from jsonb_array_elements(v_base) with ordinality x(t,ord)
      left join control_spec spec on spec.threat_code=t->>'threat_code'
    )
    select coalesce(jsonb_agg(
      case when t->>'status'='COMPLETE'
                 and t->'evidence_refs'='["SCREEN_RULE_SET"]'::jsonb then
        case when source_code is not null then
          (t - 'rationale' - 'evidence_refs')
          || jsonb_build_object(
             'evidence_refs',jsonb_build_array(source_code),
             'rationale',format('Exact linked rule (%s). Declarative control only; implementation and QA not evidenced.',source_state))
        else
          (t - 'rationale' - 'evidence_refs')
          || jsonb_build_object(
             'status','PARTIAL',
             'evidence_refs','[]'::jsonb,
             'rationale','Generic SCREEN_RULE_SET does not identify an applicable exact mitigation; source evidence pending.')
        end
      else t end order by ord
    ),'[]'::jsonb) into v_base
    from inspected;
  end if;

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
  -- Evidence of one-time OTP definition is not evidence of live enforcement.
  select r.codigo,r.estado into v_otp_one_time_rule,v_otp_one_time_state
  from lf_ops.reglas r
  join programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') link
       on link.regla_id=r.id
  where r.estado in ('VIGENTE','CANDIDATO')
    and not coalesce(r.pendiente_decision,false)
    and r.valor_config->>'one_time_use'='REQUIRED'
    and r.valor_config->>'replay_after_success'='DENY'
    and r.valor_config->>'otp_policy_id'=v_policy.id::text
  order by case when r.estado='VIGENTE' then 0 else 1 end,r.codigo
  limit 1;
  select jsonb_agg(
    case t->>'threat_code'
      when 'OPEN_REDIRECT' then jsonb_build_object('threat_code','OPEN_REDIRECT','applicability','APPLICABLE','status','COMPLETE','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-029'),'applicability_authority',v_auth,'rationale','Recovery verification uses fixed canonical route/screen identifiers and denies client context promotion; no arbitrary redirect target is accepted.')
      when 'SECRET_CREDENTIAL_EXPOSURE' then jsonb_build_object('threat_code','SECRET_CREDENTIAL_EXPOSURE','applicability','APPLICABLE','status','PARTIAL','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-037'),'applicability_authority',v_auth,'rationale','OTP values are denied from logs/analytics and generated/verified server-side; explicit transport and URL/query exposure controls are not yet independently materialized for this capability.')
      when 'AUTOMATION_BOT_ABUSE' then jsonb_build_object('threat_code','AUTOMATION_BOT_ABUSE','applicability','APPLICABLE','status','PARTIAL','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-037','B2B-RULE-AUTH-038','OTP_POL_B2B_AUTH_EMAIL_BREVO'),'applicability_authority',v_auth,'rationale','Attempt/resend policy and server-side verification exist, but a complete bot/automation control for verification is not independently evidenced.')
      when 'USER_ENUMERATION' then jsonb_build_object('threat_code','USER_ENUMERATION','applicability','APPLICABLE','status','COMPLETE','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-029','B2B-RULE-AUTH-037'),'applicability_authority',v_auth,'rationale','Account existence exposure is denied and recovery verification preserves anti-enumeration.')
      when 'RECOVERY_CONTEXT_REPLAY' then jsonb_build_object('threat_code','RECOVERY_CONTEXT_REPLAY','applicability','APPLICABLE','status','COMPLETE','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-029'),'applicability_authority',v_auth,'rationale','The grant is opaque, one-time and server-verified; reused/invalid recovery context is normalized and cannot be promoted by the client.')
      when 'OTP_GUESSING' then jsonb_build_object('threat_code','OTP_GUESSING','applicability','APPLICABLE','status',case when v_policy.id is not null and v_policy.max_intentos is not null and v_policy.expiracion_minutos is not null then 'PARTIAL' else 'MISSING' end,'evidence_refs',jsonb_build_array('B2B-RULE-AUTH-037','OTP_POL_B2B_AUTH_EMAIL_BREVO'),'applicability_authority',v_auth,'rationale','Server-side verification plus expiry/attempt limits exist; explicit entropy/CSPRNG and per-challenge guessing hardening is not fully evidenced in the materialized LF contract.')
      when 'OTP_REPLAY_SINGLE_USE' then jsonb_build_object('threat_code','OTP_REPLAY_SINGLE_USE','applicability','APPLICABLE','status',case when v_otp_one_time_rule is null then 'MISSING' else 'PARTIAL' end,'evidence_refs',case when v_otp_one_time_rule is null then jsonb_build_array('B2B-RULE-AUTH-029','B2B-RULE-AUTH-037') else jsonb_build_array(v_otp_one_time_rule,v_policy.codigo) end,'applicability_authority',v_auth,'rationale',case when v_otp_one_time_rule is null then 'No applicable, linked one-time OTP rule was found.' else format('One-time OTP and replay-deny defined by linked %s (%s); runtime verification and single-use atomicity not evidenced.',v_otp_one_time_rule,v_otp_one_time_state) end)
      when 'OTP_RESEND_ABUSE' then jsonb_build_object('threat_code','OTP_RESEND_ABUSE','applicability','APPLICABLE','status',case when v_policy.max_reenvios is not null and v_policy.bloqueo_reenvio_min is not null then 'COMPLETE' else 'MISSING' end,'evidence_refs',jsonb_build_array('B2B-RULE-AUTH-038','OTP_POL_B2B_AUTH_EMAIL_BREVO'),'applicability_authority',v_auth,'rationale','Resend availability and countdown are policy-derived and the central policy defines resend limits/cooldown.')
      when 'MFA_BYPASS' then jsonb_build_object('threat_code','MFA_BYPASS','applicability','APPLICABLE','status','COMPLETE','evidence_refs',jsonb_build_array('B2B-RULE-AUTH-029','B2B-RULE-AUTH-037'),'applicability_authority',v_auth,'rationale','Recovery OTP explicitly does not satisfy MFA and cannot create operational authorization/session.')
      else t
    end order by ord
  ) into v_out
  from jsonb_array_elements(v_base) with ordinality x(t,ord);
  return v_out;
end;
$function$;

-- Preserve preexisting function privileges. CREATE OR REPLACE does not issue
-- a fresh grant to PUBLIC; confirm grant matrix at apply/readback.
do $semantic_postcheck$
declare
  v_login jsonb;
  v_recovery jsonb;
  v_bad_generic int;
  v_explicit_count int;
  v_csrf_status text;
  v_replay_status text;
  v_replay_evidence jsonb;
begin
  v_login:=programacion.fn_input_security_threat_expected(51);
  select count(*) into v_bad_generic
  from jsonb_array_elements(v_login) x
  where x->>'status'='COMPLETE' and x->'evidence_refs'='["SCREEN_RULE_SET"]'::jsonb;
  if v_bad_generic<>0 then
    raise exception 'IG_EVO_R6_GENERIC_COMPLETE_STILL_PRESENT:%',v_bad_generic;
  end if;

  select count(*) into v_explicit_count
  from jsonb_array_elements(v_login) x
  where x->>'status'='COMPLETE'
    and x->'evidence_refs'='["B2B-RULE-SECURITY-BASELINE-001"]'::jsonb
    and x->>'rationale' like '%Declarative control only%';
  if v_explicit_count<>8 then
    raise exception 'IG_EVO_R6_EXPECTED_8_TYPED_CONTROLS:%',v_explicit_count;
  end if;

  select x->>'status' into v_csrf_status
  from jsonb_array_elements(v_login) x where x->>'threat_code'='CSRF_REQUEST';
  if v_csrf_status<>'PARTIAL' then
    raise exception 'IG_EVO_R6_CSRF_UNGROUNDED_COMPLETE:%',v_csrf_status;
  end if;

  v_recovery:=programacion.fn_input_security_threat_expected(56);
  select x->>'status',x->'evidence_refs'
   into v_replay_status,v_replay_evidence
  from jsonb_array_elements(v_recovery) x where x->>'threat_code'='OTP_REPLAY_SINGLE_USE';
  if v_replay_status<>'PARTIAL'
     or not(v_replay_evidence @> '["B2B-RULE-AUTH-041"]'::jsonb) then
    raise exception 'IG_EVO_R6_OTP_REPLAY_QUALITY_NOT_CORRECTED:%:%',v_replay_status,v_replay_evidence;
  end if;

  if exists (select 1 from jsonb_array_elements(v_login) x where x->>'threat_code'='OTP_REPLAY_SINGLE_USE' and x->>'status'<>'NOT_APPLICABLE') then
    raise exception 'IG_EVO_R6_NON_OTP_CAPABILITY_FALSE_POSITIVE';
  end if;
end;
$semantic_postcheck$;
commit;
