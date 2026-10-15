-- IG M10.7 A3 candidate-only; source and selector unchanged, no cross-call cache.
DO $pre$
BEGIN
 IF md5(pg_get_functiondef('programacion.fn_input_subject_depth_expected_v510(integer,text)'::regprocedure))
   <> '83c6b61cd23cc0c57abbd8ee4831f8b5' THEN
   RAISE EXCEPTION 'IG_M107_A3_CANONICAL_SOURCE_DRIFT';
 END IF;
 IF to_regprocedure('programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(integer,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'IG_M107_A3_CANDIDATE_EXISTS'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M107-A3-EFFECTIVE-LINKS-MATERIALIZED-CANDIDATE-015')
 THEN RAISE EXCEPTION 'IG_M107_A3_EKB_EXISTS'; END IF;
END $pre$;

CREATE FUNCTION programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(p_pantalla_id integer, p_family_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops', 'lf_design'
AS $function$
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
    with effective_links as materialized (
      select * from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE')
    ), subjects as (
      select c.id subject_id,c.codigo subject_code,c.tipo_dato,cp.context_key,cp.orden_visual,
             case when cp.context_key='MFA_ENROLL_QR' then 'QR_DISPLAY' when cp.context_key='MFA_ENROLL_SECRET' then 'GENERATED_SECRET' when cp.component_token_code='otp_pin' or cp.context_key='MFA_EMAIL_OTP_CODE' then 'OTP_INPUT' when c.tipo_dato='password' then 'PASSWORD_INPUT' when cp.context_key='MFA_ENROLL_CODE' then 'TOTP_CODE_INPUT' else 'INPUT' end subject_role,
             c.es_sensible,c.pii_classification,c.masking_rule,c.logs_allowed,c.analytics_allowed,c.retention_class
      from lf_ops.campos_pantallas cp join lf_ops.campos c on c.id=cp.campo_id where cp.pantalla_id=p_pantalla_id
    ), checks as (
      select s.*,
        jsonb_build_array(
          jsonb_build_object('check_code','SENSITIVITY_CLASSIFICATION','status',case when s.es_sensible is not null and s.pii_classification is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.es_sensible+pii_classification'),
          jsonb_build_object('check_code','MASKING','status',case when s.es_sensible is false and coalesce(s.pii_classification,'NONE')='NONE' then 'NOT_APPLICABLE' when s.masking_rule is not null then 'COMPLETE' else 'MISSING' end,'source_ref',case when s.es_sensible is false and coalesce(s.pii_classification,'NONE')='NONE' then 'lf_ops.campos.es_sensible+pii_classification' else 'lf_ops.campos.masking_rule' end,'rationale',case when s.es_sensible is false and coalesce(s.pii_classification,'NONE')='NONE' then 'Canonical field is non-sensitive and contains no PII; masking is not applicable.' else null end),
          jsonb_build_object('check_code','NO_LOGS','status',case when s.logs_allowed is false then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.logs_allowed'),
          jsonb_build_object('check_code','NO_ANALYTICS','status',case when s.analytics_allowed is false then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.analytics_allowed'),
          jsonb_build_object('check_code','RETENTION_CLASS','status',case when s.retention_class is not null then 'COMPLETE' else 'MISSING' end,'source_ref','lf_ops.campos.retention_class')
        ) || case
          when s.subject_role='PASSWORD_INPUT' then jsonb_build_array(
            jsonb_build_object('check_code','PASSWORD_PERSISTENCE_DENY','status',case when (v_profile='LOGIN' and exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-005' and r.valor_config->>'persistence'='DENY')) or (v_profile='PASSWORD_UPDATE' and exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-030' and r.valor_config->>'password_persistence_lf_ops'='DENY')) then 'COMPLETE' else 'MISSING' end,'source_ref',case when v_profile='LOGIN' then 'B2B-RULE-AUTH-005' else 'B2B-RULE-AUTH-030' end),
            jsonb_build_object('check_code','HTTPS_TRANSPORT','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.valor_config->>'transport'='HTTPS_REQUIRED') then 'COMPLETE' else 'MISSING' end,'source_ref','SCREEN_RULE_SET:transport=HTTPS_REQUIRED'),
            jsonb_build_object('check_code','NO_URL_QUERY_EXPOSURE','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.valor_config->>'credentials_in_url'='DENY' and r.valor_config->>'credentials_in_query_string'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','SCREEN_RULE_SET:credentials_in_url/query=DENY')
          )
          when s.subject_role='OTP_INPUT' then jsonb_build_array(
            jsonb_build_object('check_code','SERVER_SIDE_OTP_VERIFICATION','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034' and r.valor_config->>'server_side_verification'='REQUIRED') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-034'),
            jsonb_build_object('check_code','OTP_VALUE_LOGS_DENY','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034' and r.valor_config->>'otp_value_logs'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-034'),
            jsonb_build_object('check_code','OTP_VALUE_ANALYTICS_DENY','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034' and r.valor_config->>'otp_value_analytics'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-034'),
            jsonb_build_object('check_code','OTP_POLICY_BOUND','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id join lf_ops.otp_politicas op on op.codigo=r.valor_config->>'otp_policy_code' where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-034') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-034 -> lf_ops.otp_politicas')
          )
          when s.subject_role='QR_DISPLAY' then jsonb_build_array(
            jsonb_build_object('check_code','QR_LOGS_DENY','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'qr_logs'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','QR_ANALYTICS_DENY','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'qr_analytics'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','QR_TRANSIENT','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'qr_retention'='TRANSIENT') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035')
          )
          when s.subject_role='GENERATED_SECRET' then jsonb_build_array(
            jsonb_build_object('check_code','SECRET_LOGS_DENY','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'secret_logs'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','SECRET_ANALYTICS_DENY','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'secret_analytics'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','SECRET_TRANSIENT','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'secret_retention'='TRANSIENT') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035')
          )
          when s.subject_role='TOTP_CODE_INPUT' then jsonb_build_array(
            jsonb_build_object('check_code','TOTP_CODE_LOGS_DENY','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'verification_code_logs'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','TOTP_CODE_ANALYTICS_DENY','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'verification_code_analytics'='DENY') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035'),
            jsonb_build_object('check_code','SERVER_RECHECK_AFTER_VERIFY','status',case when exists(select 1 from lf_ops.reglas r join effective_links rp on rp.regla_id=r.id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-035' and r.valor_config->>'server_recheck_aal_after_verify'='REQUIRED') then 'COMPLETE' else 'MISSING' end,'source_ref','B2B-RULE-AUTH-035')
          ) else '[]'::jsonb end as check_list
      from subjects s
    )
    select coalesce(jsonb_agg(jsonb_build_object('subject_type','FIELD','subject_id',subject_id,'subject_code',subject_code,'subject_role',subject_role,'capability_profile',v_profile,'status',case when exists(select 1 from jsonb_array_elements(check_list) x where x->>'status' not in ('COMPLETE','NOT_APPLICABLE')) then 'PARTIAL' else 'COMPLETE' end,'checks',check_list) order by orden_visual,subject_id),'[]'::jsonb)
    into v_result from checks;
    return v_result;
  end if;
  return '[]'::jsonb;
end;
$function$
;


REVOKE ALL ON FUNCTION programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(integer,text) FROM PUBLIC;
COMMENT ON FUNCTION programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(integer,text) IS
 'IG M10.7 A3 internal candidate: SECURITY branch reuses governed effective-rule links once per statement via MATERIALIZED CTE. No runtime consumers.';

DO $test$
DECLARE
 v_code constant text:='IG-M107-A3-EFFECTIVE-LINKS-MATERIALIZED-CANDIDATE-015';
 v_screen integer;
 v_family text;
 v_trial integer;
 v_original jsonb;
 v_candidate jsonb;
 v_start timestamptz;
 v_original_ms numeric;
 v_candidate_ms numeric;
 v_samples jsonb:='[]'::jsonb;
 v_negative_o text;
 v_negative_c text;
 v_security_checks int;
 v_old_sha text;
 v_evidence jsonb;
BEGIN
 FOREACH v_screen IN ARRAY ARRAY[1,43,53,55,58] LOOP
  FOR v_trial IN 1..2 LOOP
   IF v_trial=1 THEN
    v_start:=clock_timestamp();
    v_original:=programacion.fn_input_subject_depth_expected_v510(v_screen,'SECURITY');
    v_original_ms:=round((extract(epoch from(clock_timestamp()-v_start))*1000)::numeric,3);
    v_start:=clock_timestamp();
    v_candidate:=programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(v_screen,'SECURITY');
    v_candidate_ms:=round((extract(epoch from(clock_timestamp()-v_start))*1000)::numeric,3);
   ELSE
    v_start:=clock_timestamp();
    v_candidate:=programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(v_screen,'SECURITY');
    v_candidate_ms:=round((extract(epoch from(clock_timestamp()-v_start))*1000)::numeric,3);
    v_start:=clock_timestamp();
    v_original:=programacion.fn_input_subject_depth_expected_v510(v_screen,'SECURITY');
    v_original_ms:=round((extract(epoch from(clock_timestamp()-v_start))*1000)::numeric,3);
   END IF;
   IF v_original IS DISTINCT FROM v_candidate
     OR programacion.fn_v09_sha256_jsonb(v_original)
        IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_candidate)
   THEN RAISE EXCEPTION 'IG_M107_A3_PARITY_FAILED_SCREEN_%_TRIAL_%',v_screen,v_trial; END IF;
   IF v_screen IN (53,55) THEN
    SELECT count(*) INTO v_security_checks
    FROM jsonb_array_elements(v_candidate) subject_record
    CROSS JOIN LATERAL jsonb_array_elements(subject_record->'checks') chk
    WHERE chk->>'check_code' NOT IN ('SENSITIVITY_CLASSIFICATION','PII_CLASSIFICATION');
    IF v_security_checks=0 THEN
      RAISE EXCEPTION 'IG_M107_A3_MISSING_SECURITY_CHECKS_SCREEN_%',v_screen;
    END IF;
   END IF;
   v_samples:=v_samples||jsonb_build_array(jsonb_build_object(
     'screen_id',v_screen,'family_code','SECURITY','trial',v_trial,
     'original_ms',v_original_ms,'candidate_ms',v_candidate_ms,
     'json_exact_equal',true,'sha_equal',true));
  END LOOP;
 END LOOP;
 -- DESIGN_SYSTEM is a negative-scope control: no rule CTE change in this branch.
 FOREACH v_screen IN ARRAY ARRAY[53,55] LOOP
  v_original:=programacion.fn_input_subject_depth_expected_v510(v_screen,'DESIGN_SYSTEM');
  v_candidate:=programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(v_screen,'DESIGN_SYSTEM');
  IF v_original IS DISTINCT FROM v_candidate OR
     programacion.fn_v09_sha256_jsonb(v_original)
       IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_candidate)
  THEN RAISE EXCEPTION 'IG_M107_A3_DESIGN_SYSTEM_OUT_OF_SCOPE_REGRESSION:%',v_screen; END IF;
 END LOOP;
 -- Missing-screen result must retain its existing fail/empty behavior.
 v_negative_o:=null;v_negative_c:=null;
 BEGIN
  v_original:=programacion.fn_input_subject_depth_expected_v510(2147483647,'SECURITY');
 EXCEPTION WHEN OTHERS THEN v_negative_o:=SQLSTATE||':'||SQLERRM; END;
 BEGIN
  v_candidate:=programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(2147483647,'SECURITY');
 EXCEPTION WHEN OTHERS THEN v_negative_c:=SQLSTATE||':'||SQLERRM; END;
 IF v_negative_o IS DISTINCT FROM v_negative_c OR
    (v_negative_o IS NULL AND v_original IS DISTINCT FROM v_candidate) THEN
    RAISE EXCEPTION 'IG_M107_A3_NEGATIVE_SCREEN_BEHAVIOR_CHANGED'; END IF;

 IF EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  WHERE n.nspname='programacion'
    AND p.proname='fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1'
    AND a.grantee=0 AND a.privilege_type='EXECUTE'
 ) THEN RAISE EXCEPTION 'IG_M107_A3_PUBLIC_EXECUTE'; END IF;
 SELECT md5(pg_get_functiondef('programacion.fn_input_subject_depth_expected_v510(integer,text)'::regprocedure)) INTO v_old_sha;
 IF v_old_sha <> '83c6b61cd23cc0c57abbd8ee4831f8b5'
 THEN RAISE EXCEPTION 'IG_M107_A3_CANONICAL_DEFINITION_CHANGED'; END IF;
 v_evidence:=jsonb_build_object(
  'schema_version','IG_M107_A3_RULE_LINKS_INCALL_V1',
  'canonical_md5',v_old_sha,
  'effective_links_static_call_sites_before',17,
  'effective_links_calls_in_candidate_security_branch',1,
  'repeated_security_samples',v_samples,
  'design_system_unchanged',true,'screen_missing_behavior_preserved',true,
  'candidate_only',true,'public_execute',false,
  'no_cross_call_cache',true,'source_mutation_tested',false,
  'original_selector_unchanged',true,
  'validator_p90_proven',false,'cp3_closed',false);
 INSERT INTO public.lf_error_knowledge(
   id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
   validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
   estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
   detectability,source_context,source_ref
 ) VALUES(
   gen_random_uuid(),v_code,'GOVERNANCE',
   'A3 reutilización única de vínculos de reglas en SECURITY, candidato',
   '17 sitios de llamada a fn_input_effective_rule_links_v1 en la rama SECURITY de subject_depth_expected_v510 quedan cubiertos por CTE MATERIALIZED en una sentencia. Función candidata aditiva, ninguna decisión, regla ni juez omitido; paridad JSON/SHA contra canónico en cinco pantallas y control DESIGN_SYSTEM sin cambios.',
   'Redundancia de evaluaciones del mismo resolvedor estable durante la construcción de checks de seguridad dentro de una sola sentencia.',
   'EFFECTIVE_RULE_LINKS_SINGLE_STATEMENT_REUSE',
   'No reutilizar entre llamadas sin G2B. Preservar selectores canónicos, ramas de seguridad y fallos cerrados. En funciones generadas desde pg_get_functiondef agregar y verificar terminador SQL antes del Train.',
   'Pruebas positivas, control fuera de alcance y comportamiento con pantalla inexistente. Los tiempos son microbenchmark de función, no prueba de ahorro del Validator ni p90.',
   'HIGH',1,clock_timestamp(),clock_timestamp(),
   'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
   v_evidence::text,clock_timestamp(),clock_timestamp(),
   'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
   'A3 candidate links single-statement reuse, semantic equality, legitimate LF project operation',
   'programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(integer,text)'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
 THEN RAISE EXCEPTION 'IG_M107_A3_EKB_MISSING_AFTER_WRITE'; END IF;
END $test$;
