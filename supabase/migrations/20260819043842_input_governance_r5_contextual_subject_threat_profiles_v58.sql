create or replace function programacion.fn_input_security_capability_profile(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare v_profile text; v_rule text;
begin
  if exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-036') then v_profile:='LOGIN'; v_rule:='B2B-RULE-AUTH-036';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-028') then v_profile:='ACCOUNT_RECOVERY_REQUEST'; v_rule:='B2B-RULE-AUTH-028';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-030') then v_profile:='PASSWORD_UPDATE'; v_rule:='B2B-RULE-AUTH-030';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034') then v_profile:='OTP_VERIFY'; v_rule:='B2B-RULE-AUTH-034';
  elsif exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035') then v_profile:='LEGACY_TOTP_ENROLLMENT'; v_rule:='B2B-RULE-AUTH-035';
  else v_profile:='UNRESOLVED'; v_rule:=null;
  end if;
  return jsonb_build_object('profile',v_profile,'authority_rule',v_rule,'pantalla_id',p_pantalla_id,'classification_mode','POSITIVE_LINKED_RULE');
end;
$$;

create or replace function programacion.fn_input_subject_depth_expected(p_pantalla_id integer, p_family_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops, lf_design
as $$
declare
  v_label_typography boolean := false;
  v_profile text;
  v_result jsonb := '[]'::jsonb;
begin
  select programacion.fn_input_security_capability_profile(p_pantalla_id)->>'profile' into v_profile;
  select exists(
    select 1 from lf_ops.pantalla_variantes pv
    join lf_design.component_tokens lct on lct.component_token_id=pv.layout_component_token_id
    where pv.pantalla_id=p_pantalla_id and coalesce(lct.token_bindings,'{}'::jsonb) ? 'label_typography'
  ) into v_label_typography;

  if p_family_code='DESIGN_SYSTEM' then
    with subjects as (
      select c.id subject_id,c.codigo subject_code,c.tipo_dato,cp.context_key,cp.placeholder,cp.orden_visual,cp.component_token_id,cp.component_token_code,
             case
               when cp.context_key='MFA_ENROLL_QR' then 'QR_DISPLAY'
               when cp.context_key='MFA_ENROLL_SECRET' then 'GENERATED_SECRET'
               when cp.component_token_code='otp_pin' or cp.context_key='MFA_EMAIL_OTP_CODE' then 'OTP_INPUT'
               when c.tipo_dato='password' then 'PASSWORD_INPUT'
               else 'INPUT'
             end subject_role,
             coalesce(ct.token_bindings,'{}'::jsonb) bindings
      from lf_ops.campos_pantallas cp join lf_ops.campos c on c.id=cp.campo_id
      left join lf_design.component_tokens ct on ct.component_token_id=cp.component_token_id
      where cp.pantalla_id=p_pantalla_id
    ), checks as (
      select s.*,
        case s.subject_role
          when 'OTP_INPUT' then jsonb_build_array(
            jsonb_build_object('check_code','COMPONENT_TOKEN','status',case when s.component_token_id is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos_pantallas.component_token_id'),
            jsonb_build_object('check_code','TEXT_COLOR','status',case when s.bindings ? 'text' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.text'),
            jsonb_build_object('check_code','BACKGROUND_COLOR','status',case when s.bindings ? 'background' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.background'),
            jsonb_build_object('check_code','RADIUS','status',case when s.bindings ? 'radius' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.radius'),
            jsonb_build_object('check_code','BORDER_DEFAULT','status',case when s.bindings ? 'border_default' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.border_default'),
            jsonb_build_object('check_code','BORDER_FOCUS','status',case when s.bindings ? 'border_focus' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.border_focus'),
            jsonb_build_object('check_code','INPUT_TYPOGRAPHY','status',case when s.bindings ? 'typography' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.typography'),
            jsonb_build_object('check_code','LABEL_TYPOGRAPHY','status',case when v_label_typography then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.pantalla_variantes.layout_component_token_id -> lf_design.component_tokens.token_bindings.label_typography'),
            jsonb_build_object('check_code','ERROR_STATE_TOKEN','status',case when s.bindings ? 'error_text' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.error_text'),
            jsonb_build_object('check_code','SUCCESS_STATE_TOKEN','status',case when s.bindings ? 'success_text' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.success_text'),
            jsonb_build_object('check_code','INPUT_MODE','status',case when s.bindings ? 'input_mode' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.input_mode'),
            jsonb_build_object('check_code','AUTOCOMPLETE','status',case when s.bindings ? 'autocomplete' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.autocomplete'),
            jsonb_build_object('check_code','POLICY_DRIVEN_LENGTH','status',case when s.bindings ? 'length_source' and s.bindings ? 'visual_slots' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.length_source+visual_slots'),
            jsonb_build_object('check_code','PLACEHOLDER_STYLE','status','NOT_APPLICABLE','source_ref','SUBJECT_ROLE:OTP_INPUT','rationale','OTP pin uses policy-driven slots rather than a placeholder.')
          )
          when 'QR_DISPLAY' then jsonb_build_array(
            jsonb_build_object('check_code','COMPONENT_TOKEN','status',case when s.component_token_id is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos_pantallas.component_token_id'),
            jsonb_build_object('check_code','QR_RENDER_COMPONENT','status',case when s.component_token_id is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens'),
            jsonb_build_object('check_code','LABEL_TYPOGRAPHY','status',case when v_label_typography then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.pantalla_variantes.layout_component_token_id -> lf_design.component_tokens.token_bindings.label_typography'),
            jsonb_build_object('check_code','INPUT_TYPOGRAPHY','status','NOT_APPLICABLE','source_ref','SUBJECT_ROLE:QR_DISPLAY','rationale','Server-generated QR is not a text input.'),
            jsonb_build_object('check_code','PLACEHOLDER_STYLE','status','NOT_APPLICABLE','source_ref','SUBJECT_ROLE:QR_DISPLAY','rationale','Server-generated QR has no placeholder.')
          )
          when 'GENERATED_SECRET' then jsonb_build_array(
            jsonb_build_object('check_code','COMPONENT_TOKEN','status',case when s.component_token_id is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos_pantallas.component_token_id'),
            jsonb_build_object('check_code','TEXT_COLOR','status',case when s.bindings ? 'text' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.text'),
            jsonb_build_object('check_code','BACKGROUND_COLOR','status',case when s.bindings ? 'background' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.background'),
            jsonb_build_object('check_code','DISPLAY_TYPOGRAPHY','status',case when s.bindings ? 'typography' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.typography'),
            jsonb_build_object('check_code','LABEL_TYPOGRAPHY','status',case when v_label_typography then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.pantalla_variantes.layout_component_token_id -> lf_design.component_tokens.token_bindings.label_typography'),
            jsonb_build_object('check_code','PLACEHOLDER_STYLE','status','NOT_APPLICABLE','source_ref','SUBJECT_ROLE:GENERATED_SECRET','rationale','Server-generated secret is displayed, not entered.')
          )
          else jsonb_build_array(
            jsonb_build_object('check_code','COMPONENT_TOKEN','status',case when s.component_token_id is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos_pantallas.component_token_id'),
            jsonb_build_object('check_code','TEXT_COLOR','status',case when s.bindings ? 'text' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.text'),
            jsonb_build_object('check_code','BORDER_COLOR','status',case when s.bindings ? 'border' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.border'),
            jsonb_build_object('check_code','BACKGROUND_COLOR','status',case when s.bindings ? 'background' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.background'),
            jsonb_build_object('check_code','RADIUS','status',case when s.bindings ? 'radius' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.radius'),
            jsonb_build_object('check_code','INPUT_TYPOGRAPHY','status',case when s.bindings ? 'typography' then 'COMPLETE' else 'MISSING' end,'source_ref','lf_design.component_tokens.token_bindings.typography'),
            jsonb_build_object('check_code','LABEL_TYPOGRAPHY','status',case when v_label_typography then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.pantalla_variantes.layout_component_token_id -> lf_design.component_tokens.token_bindings.label_typography'),
            jsonb_build_object('check_code','PLACEHOLDER_STYLE','status',case when s.placeholder is null then 'NOT_APPLICABLE' when s.bindings ? 'placeholder_typography' or s.bindings ? 'placeholder_color' or s.bindings ? 'placeholder_style' then 'COMPLETE' else 'MISSING' end,'source_ref',case when s.placeholder is null then 'lf_ops.campos_pantallas.placeholder' else 'lf_design.component_tokens.token_bindings.placeholder_*' end,'rationale',case when s.placeholder is null then 'Canonical field has no placeholder.' else null end)
          )
        end as check_list
      from subjects s
    )
    select coalesce(jsonb_agg(jsonb_build_object('subject_type','FIELD','subject_id',subject_id,'subject_code',subject_code,'subject_role',subject_role,'status',case when exists(select 1 from jsonb_array_elements(check_list) x where x->>'status' not in ('COMPLETE','NOT_APPLICABLE')) then 'PARTIAL' else 'COMPLETE' end,'checks',check_list) order by orden_visual,subject_id),'[]'::jsonb)
    into v_result from checks;
    return v_result;
  end if;

  if p_family_code='SECURITY' then
    with subjects as (
      select c.id subject_id,c.codigo subject_code,c.tipo_dato,cp.context_key,cp.orden_visual,
             case when cp.context_key='MFA_ENROLL_QR' then 'QR_DISPLAY' when cp.context_key='MFA_ENROLL_SECRET' then 'GENERATED_SECRET' when cp.component_token_code='otp_pin' or cp.context_key='MFA_EMAIL_OTP_CODE' then 'OTP_INPUT' when c.tipo_dato='password' then 'PASSWORD_INPUT' when cp.context_key='MFA_ENROLL_CODE' then 'TOTP_CODE_INPUT' else 'INPUT' end subject_role,
             c.es_sensible,c.pii_classification,c.masking_rule,c.logs_allowed,c.analytics_allowed,c.retention_class
      from lf_ops.campos_pantallas cp join lf_ops.campos c on c.id=cp.campo_id where cp.pantalla_id=p_pantalla_id
    ), checks as (
      select s.*,
        jsonb_build_array(
          jsonb_build_object('check_code','SENSITIVITY_CLASSIFICATION','status',case when s.es_sensible is not null and s.pii_classification is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.es_sensible+pii_classification'),
          jsonb_build_object('check_code','MASKING','status',case when s.masking_rule is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.masking_rule'),
          jsonb_build_object('check_code','NO_LOGS','status',case when s.logs_allowed is false then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.logs_allowed'),
          jsonb_build_object('check_code','NO_ANALYTICS','status',case when s.analytics_allowed is false then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.analytics_allowed'),
          jsonb_build_object('check_code','RETENTION_CLASS','status',case when s.retention_class is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.retention_class')
        ) || case
          when s.subject_role='PASSWORD_INPUT' then jsonb_build_array(
            jsonb_build_object('check_code','PASSWORD_PERSISTENCE_DENY','status',case when (v_profile='LOGIN' and exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-005' and r.valor_config->>'persistence'='DENY')) or (v_profile='PASSWORD_UPDATE' and exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-030' and r.valor_config->>'password_persistence_lf_ops'='DENY')) then 'COMPLETE' else 'MISSING' end,'source_ref',case when v_profile='LOGIN' then 'B2B-RULE-AUTH-005' else 'B2B-RULE-AUTH-030' end),
            jsonb_build_object('check_code','HTTPS_TRANSPORT','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.valor_config->>'transport'='HTTPS_REQUIRED') then 'COMPLETE' else 'MISSING' end,'source_ref','SCREEN_RULE_SET:transport=HTTPS_REQUIRED'),
            jsonb_build_object('check_code','NO_URL_QUERY_EXPOSURE','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.valor_config->>'credentials_in_url'='DENY' and r.valor_config->>'credentials_in_query_string'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','SCREEN_RULE_SET:credentials_in_url/query=DENY')
          )
          when s.subject_role='OTP_INPUT' then jsonb_build_array(
            jsonb_build_object('check_code','SERVER_SIDE_OTP_VERIFICATION','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034' and r.valor_config->>'server_side_verification'='REQUIRED') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-034'),
            jsonb_build_object('check_code','OTP_VALUE_LOGS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034' and r.valor_config->>'otp_value_logs'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-034'),
            jsonb_build_object('check_code','OTP_VALUE_ANALYTICS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034' and r.valor_config->>'otp_value_analytics'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-034'),
            jsonb_build_object('check_code','OTP_POLICY_BOUND','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id join lf_ops.otp_politicas op on op.codigo=r.valor_config->>'otp_policy_code' where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-034 -> lf_ops.otp_politicas')
          )
          when s.subject_role='QR_DISPLAY' then jsonb_build_array(
            jsonb_build_object('check_code','QR_LOGS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'qr_logs'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','QR_ANALYTICS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'qr_analytics'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','QR_TRANSIENT','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'qr_retention'='TRANSIENT') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035')
          )
          when s.subject_role='GENERATED_SECRET' then jsonb_build_array(
            jsonb_build_object('check_code','SECRET_LOGS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'secret_logs'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','SECRET_ANALYTICS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'secret_analytics'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','SECRET_TRANSIENT','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'secret_retention'='TRANSIENT') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035')
          )
          when s.subject_role='TOTP_CODE_INPUT' then jsonb_build_array(
            jsonb_build_object('check_code','TOTP_CODE_LOGS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'verification_code_logs'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','TOTP_CODE_ANALYTICS_DENY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'verification_code_analytics'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','SERVER_RECHECK_AFTER_VERIFY','status',case when exists(select 1 from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'server_recheck_aal_after_verify'='REQUIRED') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035')
          ) else '[]'::jsonb end as check_list
      from subjects s
    )
    select coalesce(jsonb_agg(jsonb_build_object('subject_type','FIELD','subject_id',subject_id,'subject_code',subject_code,'subject_role',subject_role,'capability_profile',v_profile,'status',case when exists(select 1 from jsonb_array_elements(check_list) x where x->>'status' not in ('COMPLETE','NOT_APPLICABLE')) then 'PARTIAL' else 'COMPLETE' end,'checks',check_list) order by orden_visual,subject_id),'[]'::jsonb)
    into v_result from checks;
    return v_result;
  end if;
  return '[]'::jsonb;
end;
$$;

create or replace function programacion.fn_input_security_threat_expected(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_cap jsonb; v_profile text; v_auth_rule text;
  v_rule_text text;
  v_auth021 boolean; v_auth008 boolean; v_auth004 boolean; v_auth023 boolean; v_auth027 boolean; v_auth028 boolean; v_auth029 boolean; v_auth030 boolean; v_auth031 boolean; v_auth034 boolean; v_auth035 boolean; v_auth022 boolean; v_sessionfix boolean;
  v_tls boolean; v_ddos boolean; v_injection boolean; v_xss boolean; v_csrf boolean; v_ssrf boolean; v_clickjacking boolean; v_cors boolean; v_headers boolean; v_replay boolean; v_supply boolean; v_payload boolean; v_rate boolean;
  v_otp record; v_pwpol record;
  v_authority jsonb;
  v_common jsonb; v_specific jsonb;
begin
  v_cap:=programacion.fn_input_security_capability_profile(p_pantalla_id); v_profile:=v_cap->>'profile'; v_auth_rule:=v_cap->>'authority_rule';
  v_authority:=jsonb_build_object('profile',v_profile,'authority_rule',v_auth_rule,'pantalla_id',p_pantalla_id);
  select string_agg(lower(coalesce(r.descripcion,'')||' '||coalesce(r.valor_config::text,'')),' '),
    bool_or(r.codigo='B2B-RULE-AUTH-021'),bool_or(r.codigo='B2B-RULE-AUTH-008'),bool_or(r.codigo='B2B-RULE-AUTH-004'),bool_or(r.codigo='B2B-RULE-AUTH-023'),bool_or(r.codigo='B2B-RULE-AUTH-027'),bool_or(r.codigo='B2B-RULE-AUTH-028'),bool_or(r.codigo='B2B-RULE-AUTH-029'),bool_or(r.codigo='B2B-RULE-AUTH-030'),bool_or(r.codigo='B2B-RULE-AUTH-031'),bool_or(r.codigo='B2B-RULE-AUTH-034'),bool_or(r.codigo='B2B-RULE-AUTH-035'),bool_or(r.codigo='B2B-RULE-AUTH-022'),bool_or(r.codigo='B2B-RULE-SESSION-002'),bool_or(r.codigo='B2B-RULE-RATE-001'),
    bool_or(r.valor_config->>'transport'='HTTPS_REQUIRED'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%ddos%' or lower(coalesce(r.valor_config::text,'')) like '%ddos%' or lower(coalesce(r.valor_config::text,'')) like '%resource_exhaustion%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%injection%' or lower(coalesce(r.valor_config::text,'')) like '%parameterized quer%' or lower(coalesce(r.valor_config::text,'')) like '%prepared statement%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%cross-site scripting%' or lower(coalesce(r.valor_config::text,'')) like '%"xss"%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%csrf%' or lower(coalesce(r.valor_config::text,'')) like '%csrf%' or lower(coalesce(r.valor_config::text,'')) like '%same_site%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%ssrf%' or lower(coalesce(r.valor_config::text,'')) like '%ssrf%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%clickjacking%' or lower(coalesce(r.valor_config::text,'')) like '%frame-ancestors%' or lower(coalesce(r.valor_config::text,'')) like '%x-frame-options%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%cors%' or lower(coalesce(r.valor_config::text,'')) like '%allowed_origin%'),
    bool_or(lower(coalesce(r.valor_config::text,'')) like '%strict-transport-security%' or lower(coalesce(r.valor_config::text,'')) like '%content-security-policy%' or lower(coalesce(r.valor_config::text,'')) like '%x-content-type-options%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%replay attack%' or lower(coalesce(r.valor_config::text,'')) like '%replay_protection%' or lower(coalesce(r.valor_config::text,'')) like '%anti_replay%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%supply chain%' or lower(coalesce(r.valor_config::text,'')) like '%sbom%' or lower(coalesce(r.valor_config::text,'')) like '%dependency vulnerability%'),
    bool_or(lower(coalesce(r.descripcion,'')) like '%payload size%' or lower(coalesce(r.valor_config::text,'')) like '%max_payload%' or lower(coalesce(r.valor_config::text,'')) like '%request_body_limit%')
  into v_rule_text,v_auth021,v_auth008,v_auth004,v_auth023,v_auth027,v_auth028,v_auth029,v_auth030,v_auth031,v_auth034,v_auth035,v_auth022,v_sessionfix,v_rate,v_tls,v_ddos,v_injection,v_xss,v_csrf,v_ssrf,v_clickjacking,v_cors,v_headers,v_replay,v_supply,v_payload
  from lf_ops.reglas r join lf_ops.reglas_pantallas rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id;
  select * into v_otp from lf_ops.otp_politicas where id=2;
  select * into v_pwpol from lf_ops.politicas_seguridad where security_policy_id=24;

  v_common:=jsonb_build_array(
    jsonb_build_object('threat_code','DOS_DDOS_RESOURCE_EXHAUSTION','applicability','APPLICABLE','status',case when coalesce(v_ddos,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_ddos,false) then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','SERVER_INPUT_INJECTION','applicability','APPLICABLE','status',case when coalesce(v_injection,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_injection,false) then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','XSS_SCRIPT_INJECTION','applicability','APPLICABLE','status',case when coalesce(v_xss,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_xss,false) then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','CSRF_REQUEST','applicability',case when coalesce(v_csrf,false) then 'APPLICABLE' else 'UNRESOLVED' end,'status',case when coalesce(v_csrf,false) then 'COMPLETE' else 'UNRESOLVED' end,'evidence_refs',case when coalesce(v_csrf,false) then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'rationale',case when coalesce(v_csrf,false) then null else 'Applicability depends on the materialized browser session/cookie/request contract; N/A is not inferred.' end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','SSRF_BACKEND_FETCH','applicability',case when coalesce(v_ssrf,false) then 'APPLICABLE' else 'UNRESOLVED' end,'status',case when coalesce(v_ssrf,false) then 'COMPLETE' else 'UNRESOLVED' end,'evidence_refs',case when coalesce(v_ssrf,false) then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'rationale',case when coalesce(v_ssrf,false) then null else 'No N/A without a materialized operation/schema proving absence of a user-controlled fetch target.' end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','CLICKJACKING','applicability','APPLICABLE','status',case when coalesce(v_clickjacking,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_clickjacking,false) then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','CORS_ORIGIN_CONTROL','applicability',case when coalesce(v_cors,false) then 'APPLICABLE' else 'UNRESOLVED' end,'status',case when coalesce(v_cors,false) then 'COMPLETE' else 'UNRESOLVED' end,'evidence_refs',case when coalesce(v_cors,false) then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'rationale',case when coalesce(v_cors,false) then null else 'Cross-origin requirement is unresolved until the operation/network contract is materialized.' end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','SECURITY_HEADERS_TLS','applicability','APPLICABLE','status',case when coalesce(v_tls,false) and coalesce(v_headers,false) then 'COMPLETE' when coalesce(v_tls,false) then 'PARTIAL' else 'MISSING' end,'evidence_refs',case when coalesce(v_tls,false) then jsonb_build_array('SCREEN_RULE_SET:HTTPS_REQUIRED') else '[]'::jsonb end,'rationale',case when coalesce(v_tls,false) and not coalesce(v_headers,false) then 'HTTPS is explicit but security headers are not fully evidenced.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','DEPENDENCY_SUPPLY_CHAIN','applicability','APPLICABLE','status',case when coalesce(v_supply,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_supply,false) then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','REQUEST_PAYLOAD_RESOURCE_LIMIT','applicability','APPLICABLE','status',case when coalesce(v_payload,false) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when coalesce(v_payload,false) then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','OPEN_REDIRECT','applicability','APPLICABLE','status',case when (v_profile in ('LOGIN','OTP_VERIFY','LEGACY_TOTP_ENROLLMENT') and coalesce(v_auth023,false)) or (v_profile='ACCOUNT_RECOVERY_REQUEST' and coalesce(v_auth028,false)) or (v_profile='PASSWORD_UPDATE' and coalesce(v_auth031,false)) then 'COMPLETE' else 'MISSING' end,'evidence_refs',case when v_profile in ('LOGIN','OTP_VERIFY','LEGACY_TOTP_ENROLLMENT') and coalesce(v_auth023,false) then jsonb_build_array('B2B-RULE-AUTH-023') when v_profile='ACCOUNT_RECOVERY_REQUEST' and coalesce(v_auth028,false) then jsonb_build_array('B2B-RULE-AUTH-028') when v_profile='PASSWORD_UPDATE' and coalesce(v_auth031,false) then jsonb_build_array('B2B-RULE-AUTH-031') else '[]'::jsonb end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','SESSION_FIXATION_REPLAY','applicability',case when v_profile in ('LOGIN','OTP_VERIFY','LEGACY_TOTP_ENROLLMENT') then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile in ('LOGIN','OTP_VERIFY','LEGACY_TOTP_ENROLLMENT') then case when coalesce(v_sessionfix,false) and coalesce(v_replay,false) then 'COMPLETE' when coalesce(v_sessionfix,false) then 'PARTIAL' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when coalesce(v_sessionfix,false) then jsonb_build_array('B2B-RULE-SESSION-002') else '[]'::jsonb end,'rationale',case when v_profile not in ('LOGIN','OTP_VERIFY','LEGACY_TOTP_ENROLLMENT') then 'This capability does not create/promote an operational session; recovery-context replay is assessed separately.' when coalesce(v_sessionfix,false) and not coalesce(v_replay,false) then 'Session fixation is governed; generic replay protection is not independently evidenced.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','SECRET_CREDENTIAL_EXPOSURE','applicability',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then 'NOT_APPLICABLE' else 'APPLICABLE' end,'status',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then 'NOT_APPLICABLE' when v_profile='LOGIN' then case when v_rule_text like '%persistence%deny%' and v_tls then 'COMPLETE' else 'PARTIAL' end when v_profile='PASSWORD_UPDATE' then case when coalesce(v_auth030,false) then 'PARTIAL' else 'MISSING' end when v_profile='OTP_VERIFY' then case when coalesce(v_auth034,false) then 'COMPLETE' else 'MISSING' end when v_profile='LEGACY_TOTP_ENROLLMENT' then case when coalesce(v_auth035,false) then 'COMPLETE' else 'MISSING' end else 'UNRESOLVED' end,'evidence_refs',case when v_profile='LOGIN' then jsonb_build_array('B2B-RULE-AUTH-005','B2B-RULE-AUTH-015') when v_profile='PASSWORD_UPDATE' then jsonb_build_array('B2B-RULE-AUTH-030','B2B-RULE-AUTH-032') when v_profile='OTP_VERIFY' then jsonb_build_array('B2B-RULE-AUTH-034') when v_profile='LEGACY_TOTP_ENROLLMENT' then jsonb_build_array('B2B-RULE-AUTH-035') else '[]'::jsonb end,'rationale',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then 'This screen accepts an email identifier only and does not receive an authentication secret.' when v_profile='PASSWORD_UPDATE' then 'Persistence/logging/analytics controls exist, but transport/query-string exposure is not yet explicit on this capability.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','AUTOMATION_BOT_ABUSE','applicability',case when v_profile in ('LOGIN','ACCOUNT_RECOVERY_REQUEST','OTP_VERIFY') then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='LOGIN' then case when coalesce(v_auth008,false) and coalesce(v_auth021,false) then 'COMPLETE' else 'PARTIAL' end when v_profile='ACCOUNT_RECOVERY_REQUEST' then case when coalesce(v_rate,false) and v_otp.id is not null then 'PARTIAL' else 'MISSING' end when v_profile='OTP_VERIFY' then case when v_otp.id is not null then 'PARTIAL' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='LOGIN' then jsonb_build_array('B2B-RULE-AUTH-008','B2B-RULE-AUTH-021') when v_profile in ('ACCOUNT_RECOVERY_REQUEST','OTP_VERIFY') then jsonb_build_array('B2B-RULE-RATE-001','OTP_POL_B2B_AUTH_EMAIL_BREVO') else '[]'::jsonb end,'rationale',case when v_profile in ('PASSWORD_UPDATE','LEGACY_TOTP_ENROLLMENT') then 'Automation abuse is not a primary entry threat for this positively classified capability; its prerequisite context/factor controls are assessed separately.' when v_profile in ('ACCOUNT_RECOVERY_REQUEST','OTP_VERIFY') then 'Central limits exist, but a complete anti-automation control is not independently evidenced.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','USER_ENUMERATION','applicability',case when v_profile in ('LOGIN','ACCOUNT_RECOVERY_REQUEST') then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='LOGIN' then case when coalesce(v_auth004,false) then 'COMPLETE' else 'MISSING' end when v_profile='ACCOUNT_RECOVERY_REQUEST' then case when coalesce(v_auth027,false) then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='LOGIN' then jsonb_build_array('B2B-RULE-AUTH-004') when v_profile='ACCOUNT_RECOVERY_REQUEST' then jsonb_build_array('B2B-RULE-AUTH-027') else '[]'::jsonb end,'rationale',case when v_profile not in ('LOGIN','ACCOUNT_RECOVERY_REQUEST') then 'This capability does not accept an account identifier to determine account existence.' else null end,'applicability_authority',v_authority)
  );

  v_specific:=jsonb_build_array(
    jsonb_build_object('threat_code','AUTH_BRUTE_FORCE','applicability',case when v_profile='LOGIN' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='LOGIN' then case when coalesce(v_auth021,false) then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='LOGIN' then jsonb_build_array('B2B-RULE-AUTH-021') else '[]'::jsonb end,'rationale',case when v_profile<>'LOGIN' then 'Positive capability profile does not accept a password for primary authentication.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','CREDENTIAL_STUFFING','applicability',case when v_profile='LOGIN' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='LOGIN' then case when coalesce(v_auth021,false) then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='LOGIN' then jsonb_build_array('B2B-RULE-AUTH-021') else '[]'::jsonb end,'rationale',case when v_profile<>'LOGIN' then 'Credential stuffing requires a primary username/password authentication capability.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','PASSWORD_SPRAYING','applicability',case when v_profile='LOGIN' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='LOGIN' then case when coalesce(v_auth021,false) then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='LOGIN' then jsonb_build_array('B2B-RULE-AUTH-021') else '[]'::jsonb end,'rationale',case when v_profile<>'LOGIN' then 'Password spraying requires a primary password authentication capability.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','RECOVERY_REQUEST_FLOODING','applicability',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then case when coalesce(v_rate,false) and v_otp.max_reenvios is not null then 'PARTIAL' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then jsonb_build_array('B2B-RULE-RATE-001','OTP_POL_B2B_AUTH_EMAIL_BREVO') else '[]'::jsonb end,'rationale',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then 'OTP resend limits exist, but the initial recovery-request flood control is not explicitly bound to a concrete rate-limit policy.' else 'This capability does not initiate account recovery messages.' end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','RECOVERY_LOCKOUT_DOS','applicability',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then case when v_rule_text like '%account_lockout%deny%' or v_rule_text like '%lockout%deny%' then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then jsonb_build_array('SCREEN_RULE_SET') else '[]'::jsonb end,'rationale',case when v_profile='ACCOUNT_RECOVERY_REQUEST' then 'No explicit evidence yet that recovery attempts cannot lock the account and be abused for denial of access.' else 'Only the recovery-request capability can create this specific lockout abuse.' end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','RECOVERY_CONTEXT_REPLAY','applicability',case when v_profile='PASSWORD_UPDATE' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='PASSWORD_UPDATE' then case when coalesce(v_auth029,false) and v_rule_text like '%opaque_one_time_server_verified%' then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='PASSWORD_UPDATE' then jsonb_build_array('B2B-RULE-AUTH-029') else '[]'::jsonb end,'rationale',case when v_profile<>'PASSWORD_UPDATE' then 'This capability does not consume the restricted password-update recovery context.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','PASSWORD_POLICY_BYPASS','applicability',case when v_profile='PASSWORD_UPDATE' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='PASSWORD_UPDATE' then case when coalesce(v_auth030,false) and v_pwpol.security_policy_id=24 and v_pwpol.policy_config->>'server_side_validation'='REQUIRED' then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='PASSWORD_UPDATE' then jsonb_build_array('B2B-RULE-AUTH-030','SEC-B2B-PASSWORD-CREDENTIAL') else '[]'::jsonb end,'rationale',case when v_profile<>'PASSWORD_UPDATE' then 'This capability does not set a new password.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','PASSWORD_VALUE_EXPOSURE','applicability',case when v_profile='PASSWORD_UPDATE' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='PASSWORD_UPDATE' then 'PARTIAL' else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='PASSWORD_UPDATE' then jsonb_build_array('B2B-RULE-AUTH-030','B2B-RULE-AUTH-032') else '[]'::jsonb end,'rationale',case when v_profile='PASSWORD_UPDATE' then 'No LF persistence/logs/analytics are defined, but transport and URL/query exposure are not yet explicit on this capability.' else 'This capability does not accept a new password value.' end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','OTP_GUESSING','applicability',case when v_profile in ('OTP_VERIFY','LEGACY_TOTP_ENROLLMENT') then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='OTP_VERIFY' then case when v_otp.id is not null and v_otp.max_intentos is not null and v_otp.expiracion_minutos is not null and coalesce(v_auth034,false) then 'PARTIAL' else 'MISSING' end when v_profile='LEGACY_TOTP_ENROLLMENT' then 'MISSING' else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='OTP_VERIFY' then jsonb_build_array('B2B-RULE-AUTH-034','OTP_POL_B2B_AUTH_EMAIL_BREVO') when v_profile='LEGACY_TOTP_ENROLLMENT' then jsonb_build_array('B2B-RULE-AUTH-035') else '[]'::jsonb end,'rationale',case when v_profile='OTP_VERIFY' then 'TTL and attempt limits exist; cryptographically secure generation/verification hardening is not explicitly evidenced in the LF contract.' when v_profile='LEGACY_TOTP_ENROLLMENT' then 'Provider verify exists but no explicit attempt-throttling policy is bound to the legacy TOTP verification code.' else 'This capability does not verify an OTP/TOTP value.' end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','OTP_REPLAY_SINGLE_USE','applicability',case when v_profile in ('OTP_VERIFY','LEGACY_TOTP_ENROLLMENT') then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='OTP_VERIFY' then case when v_rule_text like '%single_use%' or v_rule_text like '%invalidate_on_success%' then 'COMPLETE' else 'MISSING' end when v_profile='LEGACY_TOTP_ENROLLMENT' then 'UNRESOLVED' else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='OTP_VERIFY' then jsonb_build_array('B2B-RULE-AUTH-034') when v_profile='LEGACY_TOTP_ENROLLMENT' then jsonb_build_array('B2B-RULE-AUTH-035') else '[]'::jsonb end,'rationale',case when v_profile='OTP_VERIFY' then 'Single-use/invalidate-on-success behavior is not explicit in current LF evidence.' when v_profile='LEGACY_TOTP_ENROLLMENT' then 'Provider TOTP replay semantics are not materialized in LF evidence.' else 'This capability does not verify an OTP/TOTP value.' end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','OTP_RESEND_ABUSE','applicability',case when v_profile='OTP_VERIFY' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='OTP_VERIFY' then case when v_otp.max_reenvios is not null and v_otp.bloqueo_reenvio_min is not null then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='OTP_VERIFY' then jsonb_build_array('OTP_POL_B2B_AUTH_EMAIL_BREVO') else '[]'::jsonb end,'rationale',case when v_profile<>'OTP_VERIFY' then 'Email OTP resend behavior is not part of this capability.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','MFA_BYPASS','applicability',case when v_profile in ('PASSWORD_UPDATE','OTP_VERIFY','LEGACY_TOTP_ENROLLMENT') then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='PASSWORD_UPDATE' then case when coalesce(v_auth029,false) and coalesce(v_auth031,false) then 'COMPLETE' else 'MISSING' end when v_profile='OTP_VERIFY' then case when coalesce(v_auth022,false) and coalesce(v_auth034,false) then 'COMPLETE' else 'MISSING' end when v_profile='LEGACY_TOTP_ENROLLMENT' then case when coalesce(v_auth022,false) and coalesce(v_auth035,false) then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='PASSWORD_UPDATE' then jsonb_build_array('B2B-RULE-AUTH-029','B2B-RULE-AUTH-031') when v_profile='OTP_VERIFY' then jsonb_build_array('B2B-RULE-AUTH-022','B2B-RULE-AUTH-034') when v_profile='LEGACY_TOTP_ENROLLMENT' then jsonb_build_array('B2B-RULE-AUTH-022','B2B-RULE-AUTH-035') else '[]'::jsonb end,'rationale',case when v_profile not in ('PASSWORD_UPDATE','OTP_VERIFY','LEGACY_TOTP_ENROLLMENT') then 'This capability does not satisfy or enroll the second control.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','TOTP_SECRET_QR_EXPOSURE','applicability',case when v_profile='LEGACY_TOTP_ENROLLMENT' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='LEGACY_TOTP_ENROLLMENT' then case when coalesce(v_auth035,false) and v_rule_text like '%qr_retention%transient%' and v_rule_text like '%secret_retention%transient%' then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='LEGACY_TOTP_ENROLLMENT' then jsonb_build_array('B2B-RULE-AUTH-035') else '[]'::jsonb end,'rationale',case when v_profile<>'LEGACY_TOTP_ENROLLMENT' then 'This capability does not display a TOTP QR or enrollment secret.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','UNAUTHORIZED_FACTOR_ENROLLMENT','applicability',case when v_profile='LEGACY_TOTP_ENROLLMENT' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='LEGACY_TOTP_ENROLLMENT' then case when coalesce(v_auth035,false) and v_rule_text like '%activation_authority%human_decision_required%' and v_rule_text like '%normal_flow%deny%' then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='LEGACY_TOTP_ENROLLMENT' then jsonb_build_array('B2B-RULE-AUTH-035') else '[]'::jsonb end,'rationale',case when v_profile<>'LEGACY_TOTP_ENROLLMENT' then 'This capability does not enroll a factor.' else null end,'applicability_authority',v_authority),
    jsonb_build_object('threat_code','LEGACY_FACTOR_REACTIVATION','applicability',case when v_profile='LEGACY_TOTP_ENROLLMENT' then 'APPLICABLE' else 'NOT_APPLICABLE' end,'status',case when v_profile='LEGACY_TOTP_ENROLLMENT' then case when coalesce(v_auth035,false) and v_rule_text like '%implementation_as_active_path%deny%' and v_rule_text like '%activation_authority%human_decision_required%' then 'COMPLETE' else 'MISSING' end else 'NOT_APPLICABLE' end,'evidence_refs',case when v_profile='LEGACY_TOTP_ENROLLMENT' then jsonb_build_array('B2B-RULE-AUTH-035') else '[]'::jsonb end,'rationale',case when v_profile<>'LEGACY_TOTP_ENROLLMENT' then 'This capability is not the legacy TOTP enrollment path.' else null end,'applicability_authority',v_authority)
  );
  return v_common || v_specific;
end;
$$;

create or replace function programacion.fn_guard_input_family_semantic_depth()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, programacion
as $$
declare
  v_revision text; v_pantalla_id integer; v_expected_subject jsonb:='[]'::jsonb; v_expected_threat jsonb:='[]'::jsonb; v_bad integer:=0; v_expected_count integer:=0;
begin
  select r.contract_revision,r.pantalla_id into v_revision,v_pantalla_id from programacion.input_readiness_runs r where r.id=coalesce(new.run_id,old.run_id);
  if v_revision not in ('5.7','5.8') then return new; end if;
  if tg_op='INSERT' then
    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then new.subject_coverage:=programacion.fn_input_subject_depth_expected(v_pantalla_id,new.family_code); else new.subject_coverage:='[]'::jsonb; end if;
    if new.family_code='SECURITY' then new.threat_coverage:=programacion.fn_input_security_threat_expected(v_pantalla_id); else new.threat_coverage:='[]'::jsonb; end if;
    new.semantic_depth_sha256:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',new.family_code,'subject_coverage',new.subject_coverage,'threat_coverage',new.threat_coverage));
    new.curator_evidence:=jsonb_set(coalesce(new.curator_evidence,'{}'::jsonb),'{semantic_depth_sha256}',to_jsonb(new.semantic_depth_sha256),true);
    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then select count(*) into v_bad from jsonb_array_elements(new.subject_coverage) s where s->>'status' not in ('COMPLETE','NOT_APPLICABLE'); if v_bad>0 and new.coverage_status='COMPLETE' then raise exception 'FAMILY_COMPLETE_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if; if v_bad>0 and new.well_defined_status='COMPLETE' then raise exception 'FAMILY_WELL_DEFINED_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if; end if;
    if new.family_code='SECURITY' then
      select count(*) into v_bad from jsonb_array_elements(new.threat_coverage) t where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');
      if v_bad>0 and new.coverage_status='COMPLETE' then raise exception 'SECURITY_COMPLETE_WITH_UNRESOLVED_THREAT:%',v_bad; end if;
      if v_bad>0 and new.well_defined_status='COMPLETE' then raise exception 'SECURITY_WELL_DEFINED_WITH_UNRESOLVED_THREAT:%',v_bad; end if;
      if exists(select 1 from jsonb_array_elements(new.threat_coverage) t where t->>'applicability'='NOT_APPLICABLE' and (t->'applicability_authority'->>'authority_rule' is null or nullif(t->>'rationale','') is null)) then raise exception 'SECURITY_THREAT_NA_REQUIRES_POSITIVE_PROFILE_AUTHORITY'; end if;
      select jsonb_array_length(c.especificacion->'semantic_depth_contract'->'security_threat_catalog') into v_expected_count from programacion.contratos c join programacion.input_readiness_runs r on r.version_id=c.version_id where r.id=new.run_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
      if jsonb_array_length(new.threat_coverage)<>v_expected_count then raise exception 'SECURITY_THREAT_CATALOG_CARDINALITY_MISMATCH expected=% actual=%',v_expected_count,jsonb_array_length(new.threat_coverage); end if;
    end if;
    return new;
  end if;
  if new.subject_coverage is distinct from old.subject_coverage or new.threat_coverage is distinct from old.threat_coverage or new.semantic_depth_sha256 is distinct from old.semantic_depth_sha256 then raise exception 'SEMANTIC_DEPTH_IMMUTABLE:%',old.family_code; end if;
  if old.validator_outcome='PENDING' and new.validator_outcome<>'PENDING' then
    if new.validator_evidence->>'semantic_depth_sha256' is distinct from old.semantic_depth_sha256 then raise exception 'VALIDATOR_SEMANTIC_DEPTH_HASH_MISMATCH:%',old.family_code; end if;
    if old.family_code in ('DESIGN_SYSTEM','SECURITY') then v_expected_subject:=programacion.fn_input_subject_depth_expected(v_pantalla_id,old.family_code); if old.subject_coverage is distinct from v_expected_subject then raise exception 'SEMANTIC_SUBJECT_DEPTH_STALE_DURING_VALIDATION:%',old.family_code; end if; end if;
    if old.family_code='SECURITY' then v_expected_threat:=programacion.fn_input_security_threat_expected(v_pantalla_id); if old.threat_coverage is distinct from v_expected_threat then raise exception 'SEMANTIC_THREAT_DEPTH_STALE_DURING_VALIDATION'; end if; end if;
  end if;
  return new;
end;
$$;

create or replace function programacion.fn_guard_input_family_assessment_update()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare
  v_payload jsonb; v_run_status text; v_run_sha text; v_curator_identity text; v_validator_identity text; v_validator_component_id bigint;
  v_version_id bigint; v_pantalla_id integer; v_run_contract_revision text; v_run_contract_sha text;
  v_contract_revision text; v_contract_payload jsonb; v_contract_sha text;
  v_current_manifest jsonb; v_current_sha text; v_bad_assertions integer; v_assertion jsonb; v_eval jsonb; v_governance_family boolean;
begin
  if new.run_id is distinct from old.run_id or new.family_code is distinct from old.family_code or new.severity is distinct from old.severity or new.applicability is distinct from old.applicability or new.coverage_status is distinct from old.coverage_status or new.well_defined_status is distinct from old.well_defined_status or new.story_ready_status is distinct from old.story_ready_status or new.implementation_ready_status is distinct from old.implementation_ready_status or new.qa_ready_status is distinct from old.qa_ready_status or new.production_ready_status is distinct from old.production_ready_status or new.source_refs is distinct from old.source_refs or new.rationale is distinct from old.rationale or new.blockers is distinct from old.blockers or new.negative_requirements is distinct from old.negative_requirements or new.test_obligations is distinct from old.test_obligations or new.freshness is distinct from old.freshness or new.curator_evidence is distinct from old.curator_evidence or new.curator_sha256 is distinct from old.curator_sha256 or new.subject_coverage is distinct from old.subject_coverage or new.threat_coverage is distinct from old.threat_coverage or new.semantic_depth_sha256 is distinct from old.semantic_depth_sha256 or new.created_at is distinct from old.created_at then raise exception 'CURATOR_FIELDS_IMMUTABLE:%',old.family_code; end if;
  if old.validator_outcome<>'PENDING' then raise exception 'VALIDATOR_RECEIPT_IMMUTABLE:%',old.family_code; end if;
  if new.validator_outcome='PENDING' then raise exception 'VALIDATOR_UPDATE_MUST_BE_TERMINAL:%',old.family_code; end if;
  select r.status,r.source_snapshot_sha256,r.curator_identity,r.validator_identity,r.validator_component_id,r.version_id,r.pantalla_id,r.contract_revision,r.contract_snapshot_sha256 into v_run_status,v_run_sha,v_curator_identity,v_validator_identity,v_validator_component_id,v_version_id,v_pantalla_id,v_run_contract_revision,v_run_contract_sha from programacion.input_readiness_runs r where r.id=old.run_id;
  if v_run_status<>'VALIDATING' then raise exception 'VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.family_code; end if;
  if v_validator_component_id is null then raise exception 'RUN_VALIDATOR_COMPONENT_REQUIRED'; end if;
  if v_validator_identity is null or v_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  if new.validator_identity is distinct from v_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH:%',old.family_code; end if;
  select c.especificacion->>'contract_revision',jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion) into v_contract_revision,v_contract_payload from programacion.contratos c where c.version_id=v_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_run_contract_revision is distinct from v_contract_revision or v_run_contract_sha is distinct from v_contract_sha then raise exception 'INPUT_READINESS_CONTRACT_PIN_STALE_DURING_VALIDATION:%',old.family_code; end if;
  if new.validator_assessed_at is null then new.validator_assessed_at:=now(); end if;
  if jsonb_typeof(new.validator_evidence)<>'object' or new.validator_evidence='{}'::jsonb then raise exception 'VALIDATOR_EVIDENCE_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'source_snapshot_sha256' is distinct from v_run_sha then raise exception 'VALIDATOR_EVIDENCE_SOURCE_SNAPSHOT_MISMATCH:%',old.family_code; end if;
  if new.validator_evidence->>'curator_sha256' is distinct from old.curator_sha256 then raise exception 'VALIDATOR_EVIDENCE_CURATOR_HASH_MISMATCH:%',old.family_code; end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'VALIDATOR_DIRECT_SOURCE_READBACK_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'execution_mode'<>'INDEPENDENT_VALIDATOR' then raise exception 'VALIDATOR_EXECUTION_MODE_REQUIRED:%',old.family_code; end if;
  if coalesce(new.validator_evidence->>'contract_revision','')<>v_contract_revision then raise exception 'VALIDATOR_EVIDENCE_CONTRACT_REVISION_MISMATCH:%',old.family_code; end if;
  if v_contract_revision in ('5.7','5.8') and new.validator_evidence->>'semantic_depth_sha256' is distinct from old.semantic_depth_sha256 then raise exception 'VALIDATOR_EVIDENCE_SEMANTIC_DEPTH_MISMATCH:%',old.family_code; end if;
  if jsonb_typeof(new.validator_evidence->'assertions')<>'array' or jsonb_array_length(new.validator_evidence->'assertions')=0 then raise exception 'VALIDATOR_ASSERTIONS_REQUIRED:%',old.family_code; end if;
  select count(*) into v_bad_assertions from jsonb_array_elements(new.validator_evidence->'assertions') a where jsonb_typeof(a)<>'object' or not (a?'actual') or not (a?'expected') or not (a?'operator') or not (a?'source_ref') or not (a?'path');
  if v_bad_assertions>0 then raise exception 'VALIDATOR_ASSERTION_SCHEMA_INVALID:%',old.family_code; end if;
  v_governance_family:=old.family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS');
  for v_assertion in select value from jsonb_array_elements(new.validator_evidence->'assertions') loop
    if v_assertion->'source_ref'->>'kind' in ('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','CURRENT_VISUAL_ARTIFACT','CAPABILITY_ABSENCE','SCREEN_CANONICAL_GRAPH') then if not (v_assertion->'source_ref'?'pantalla_id') or (v_assertion->'source_ref'->>'pantalla_id')::integer<>v_pantalla_id then raise exception 'VALIDATOR_SCREEN_SOURCE_REF_REQUIRES_EXPLICIT_PANTALLA_ID:%',old.family_code; end if; end if;
    if v_governance_family then if not programacion.fn_input_governance_assertion_relevant(old.family_code,v_assertion->'source_ref',v_assertion->'path') then raise exception 'GOVERNANCE_VALIDATOR_ASSERTION_REQUIRES_INDEPENDENT_AUTHORITY:%',old.family_code; end if; else if not programacion.fn_input_assertion_is_relevant(old.family_code,v_assertion->'source_ref',v_assertion->'path') then raise exception 'VALIDATOR_ASSERTION_NOT_RELEVANT:%',old.family_code; end if; end if;
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion); if new.validator_outcome='PASS' and coalesce((v_eval->>'passed')::boolean,false) is not true then raise exception 'VALIDATOR_ASSERTION_FAILED:%',old.family_code; end if;
  end loop;
  v_current_manifest:=programacion.fn_input_build_source_manifest(old.run_id); v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest); if v_current_sha<>v_run_sha then raise exception 'SOURCE_SNAPSHOT_STALE_DURING_VALIDATION:%',old.family_code; end if;
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'semantic_depth_sha256',old.semantic_depth_sha256,'source_snapshot_sha256',v_run_sha,'validator_outcome',new.validator_outcome,'validator_findings',new.validator_findings,'validator_evidence',new.validator_evidence,'validator_identity',new.validator_identity,'validator_assessed_at',new.validator_assessed_at); new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload); return new;
end;
$$;

update programacion.contratos
set especificacion = especificacion || jsonb_build_object(
  'schema_version',5,
  'contract_revision','5.8',
  'remediation_revision','AUDIT_20260818_R5_CONTEXTUAL_SUBJECT_THREAT_PROFILES',
  'semantic_depth_contract',jsonb_build_object(
    'mode','FAMILY_PLUS_CONTEXTUAL_SUBJECT_AND_THREAT_DEPTH',
    'new_family_created',false,'new_agent_created',false,
    'capability_profile_source','POSITIVE_LINKED_FUNCTIONAL_RULE',
    'capability_profiles',jsonb_build_object('LOGIN','B2B-RULE-AUTH-036','ACCOUNT_RECOVERY_REQUEST','B2B-RULE-AUTH-028','PASSWORD_UPDATE','B2B-RULE-AUTH-030','OTP_VERIFY','B2B-RULE-AUTH-034','LEGACY_TOTP_ENROLLMENT','B2B-RULE-AUTH-035'),
    'subject_roles',jsonb_build_array('INPUT','PASSWORD_INPUT','OTP_INPUT','QR_DISPLAY','GENERATED_SECRET','TOTP_CODE_INPUT'),
    'subject_depth_required_families',jsonb_build_array('DESIGN_SYSTEM','SECURITY'),
    'complete_requires_all_subjects_complete',true,
    'security_threat_matrix_required',true,
    'threat_not_applicable_requires_positive_evidence',true,
    'unknown_capability_profile_policy','FAIL_CLOSED_UNRESOLVED',
    'security_threat_catalog',jsonb_build_array('DOS_DDOS_RESOURCE_EXHAUSTION','SERVER_INPUT_INJECTION','XSS_SCRIPT_INJECTION','CSRF_REQUEST','SSRF_BACKEND_FETCH','CLICKJACKING','CORS_ORIGIN_CONTROL','SECURITY_HEADERS_TLS','DEPENDENCY_SUPPLY_CHAIN','REQUEST_PAYLOAD_RESOURCE_LIMIT','OPEN_REDIRECT','SESSION_FIXATION_REPLAY','SECRET_CREDENTIAL_EXPOSURE','AUTOMATION_BOT_ABUSE','USER_ENUMERATION','AUTH_BRUTE_FORCE','CREDENTIAL_STUFFING','PASSWORD_SPRAYING','RECOVERY_REQUEST_FLOODING','RECOVERY_LOCKOUT_DOS','RECOVERY_CONTEXT_REPLAY','PASSWORD_POLICY_BYPASS','PASSWORD_VALUE_EXPOSURE','OTP_GUESSING','OTP_REPLAY_SINGLE_USE','OTP_RESEND_ABUSE','MFA_BYPASS','TOTP_SECRET_QR_EXPOSURE','UNAUTHORIZED_FACTOR_ENROLLMENT','LEGACY_FACTOR_REACTIVATION'),
    'semantic_depth_hash_binding','REQUIRED_CURATOR_AND_VALIDATOR'
  ),
  'negative_tests',coalesce(especificacion->'negative_tests','[]'::jsonb) || jsonb_build_array('THREAT_PROFILE_FROM_ABSENCE','THREAT_NA_WITHOUT_PROFILE_AUTHORITY','LOGIN_THREATS_APPLIED_TO_PASSWORD_UPDATE','PLACEHOLDER_REQUIRED_FOR_QR_DISPLAY','OTP_PIN_TREATED_AS_GENERIC_TEXT_INPUT','UNKNOWN_SECURITY_CAPABILITY_SELF_NA'),
  'audit_remediation',coalesce(especificacion->'audit_remediation','[]'::jsonb) || jsonb_build_array('AUD-IGA-025_CONTEXTUAL_THREAT_APPLICABILITY','AUD-IGA-026_CONTEXTUAL_DESIGN_SUBJECT_ROLE')
)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';