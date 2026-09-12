do $$
declare v_def text;
begin
  if to_regprocedure('programacion.fn_input_subject_depth_expected_v510(integer,text)') is null then
    select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_input_subject_depth_expected' and pg_get_function_identity_arguments(p.oid)='p_pantalla_id integer, p_family_code text';
    v_def:=replace(v_def,'FUNCTION programacion.fn_input_subject_depth_expected(p_pantalla_id integer, p_family_code text)','FUNCTION programacion.fn_input_subject_depth_expected_v510(p_pantalla_id integer, p_family_code text)');
    execute v_def;
  end if;
  if to_regprocedure('programacion.fn_input_security_threat_expected_v510(integer)') is null then
    select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_input_security_threat_expected' and pg_get_function_identity_arguments(p.oid)='p_pantalla_id integer';
    v_def:=replace(v_def,'FUNCTION programacion.fn_input_security_threat_expected(p_pantalla_id integer)','FUNCTION programacion.fn_input_security_threat_expected_v510(p_pantalla_id integer)');
    execute v_def;
  end if;
end$$;

create or replace function programacion.fn_input_security_capability_profile(p_pantalla_id integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,programacion,lf_ops as $$
declare v_profile text; v_rule text;
begin
  if exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-036') then v_profile:='LOGIN'; v_rule:='B2B-RULE-AUTH-036';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-037') then v_profile:='RECOVERY_OTP_VERIFY'; v_rule:='B2B-RULE-AUTH-037';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-028') then v_profile:='ACCOUNT_RECOVERY_REQUEST'; v_rule:='B2B-RULE-AUTH-028';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-030') then v_profile:='PASSWORD_UPDATE'; v_rule:='B2B-RULE-AUTH-030';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034') then v_profile:='OTP_VERIFY'; v_rule:='B2B-RULE-AUTH-034';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035') then v_profile:='LEGACY_TOTP_ENROLLMENT'; v_rule:='B2B-RULE-AUTH-035';
  else v_profile:='UNRESOLVED'; v_rule:=null;
  end if;
  return jsonb_build_object('profile',v_profile,'authority_rule',v_rule,'pantalla_id',p_pantalla_id,'classification_mode','POSITIVE_LINKED_RULE');
end$$;

create or replace function programacion.fn_input_subject_depth_expected(p_pantalla_id integer,p_family_code text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,programacion,lf_ops as $$
declare v_base jsonb; v_profile text; v_result jsonb;
begin
  if not (p_pantalla_id=56 and p_family_code='SECURITY') then return programacion.fn_input_subject_depth_expected_v510(p_pantalla_id,p_family_code); end if;
  v_profile:=programacion.fn_input_security_capability_profile(p_pantalla_id)->>'profile';
  if v_profile<>'RECOVERY_OTP_VERIFY' then return programacion.fn_input_subject_depth_expected_v510(p_pantalla_id,p_family_code); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'subject_type','FIELD','subject_id',c.id,'subject_code',c.codigo,'subject_role','OTP_INPUT','capability_profile',v_profile,
    'status',case when c.es_sensible is not null and c.pii_classification is not null and c.masking_rule is not null and c.logs_allowed=false and c.analytics_allowed=false and c.retention_class is not null
      and exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-037' and r.valor_config->>'server_side_verification'='REQUIRED' and r.valor_config->>'otp_value_logs'='DENY' and r.valor_config->>'otp_value_analytics'='DENY' and (r.valor_config->>'otp_policy_id')::integer=2)
      then 'COMPLETE' else 'PARTIAL' end,
    'checks',jsonb_build_array(
      jsonb_build_object('check_code','SENSITIVITY_CLASSIFICATION','status',case when c.es_sensible is not null and c.pii_classification is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.es_sensible+pii_classification'),
      jsonb_build_object('check_code','MASKING','status',case when c.masking_rule is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.masking_rule'),
      jsonb_build_object('check_code','NO_LOGS','status',case when c.logs_allowed=false then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.logs_allowed'),
      jsonb_build_object('check_code','NO_ANALYTICS','status',case when c.analytics_allowed=false then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.analytics_allowed'),
      jsonb_build_object('check_code','RETENTION_CLASS','status',case when c.retention_class is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.retention_class'),
      jsonb_build_object('check_code','SERVER_SIDE_OTP_VERIFICATION','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-037' and r.valor_config->>'server_side_verification'='REQUIRED') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-037'),
      jsonb_build_object('check_code','OTP_VALUE_LOGS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-037' and r.valor_config->>'otp_value_logs'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-037'),
      jsonb_build_object('check_code','OTP_VALUE_ANALYTICS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-037' and r.valor_config->>'otp_value_analytics'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-037'),
      jsonb_build_object('check_code','OTP_POLICY_BOUND','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id join lf_ops.otp_politicas op on op.id=(r.valor_config->>'otp_policy_id')::integer where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-037' and op.id=2) then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-037 -> lf_ops.otp_politicas')
    )
  ) order by cp.orden_visual,c.id),'[]'::jsonb) into v_result
  from lf_ops.campos_pantallas cp join lf_ops.campos c on c.id=cp.campo_id where cp.pantalla_id=p_pantalla_id;
  return v_result;
end$$;

create or replace function programacion.fn_input_security_threat_expected(p_pantalla_id integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,programacion,lf_ops as $$
declare v_profile text; v_base jsonb; v_out jsonb; v_auth jsonb; v_policy record;
begin
  v_profile:=programacion.fn_input_security_capability_profile(p_pantalla_id)->>'profile';
  if v_profile<>'RECOVERY_OTP_VERIFY' then return programacion.fn_input_security_threat_expected_v510(p_pantalla_id); end if;
  v_base:=programacion.fn_input_security_threat_expected_v510(p_pantalla_id);
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
end$$;

update programacion.contratos
set especificacion=especificacion || jsonb_build_object(
  'contract_revision','5.11',
  'remediation_revision','AUDIT_20260819_R9_RECOVERY_OTP_PROFILE',
  'semantic_depth_contract',(especificacion->'semantic_depth_contract') || jsonb_build_object(
    'mode','FAMILY_PLUS_CONTEXTUAL_SUBJECT_AND_THREAT_DEPTH',
    'capability_profiles',coalesce(especificacion->'semantic_depth_contract'->'capability_profiles','{}'::jsonb) || jsonb_build_object('RECOVERY_OTP_VERIFY','B2B-RULE-AUTH-037'),
    'recovery_otp_is_mfa','DENY',
    'recovery_otp_operational_session_creation','DENY'
  ),
  'negative_tests',coalesce(especificacion->'negative_tests','[]'::jsonb)||jsonb_build_array('RECOVERY_OTP_CLASSIFIED_AS_MFA','RECOVERY_OTP_CREATES_OPERATIONAL_SESSION','RECOVERY_OTP_CREDENTIAL_STUFFING_APPLICABLE','RECOVERY_OTP_REPLAY_OMITTED'),
  'audit_remediation',coalesce(especificacion->'audit_remediation','[]'::jsonb)||jsonb_build_array('AUD-IGA-029_RECOVERY_OTP_CAPABILITY_PROFILE')
)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';