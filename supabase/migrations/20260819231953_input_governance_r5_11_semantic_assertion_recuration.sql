create or replace function programacion.fn_input_v58_assertion_template(
  p_pantalla_id integer,
  p_family_code text,
  p_assertion jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion'
as $function$
declare
  v jsonb := p_assertion;
  v_kind text := coalesce(p_assertion->'source_ref'->>'kind','');
begin
  if p_pantalla_id=52 and p_family_code='OBJECTIVE_OUTCOMES' then
    v:=v || jsonb_build_object(
      'operator','EQ',
      'expected','Permitir que un usuario inicie recuperación de acceso de forma segura y anti-enumeración, enviando únicamente el correo antes de cualquier nueva contraseña.'
    );

  elsif p_family_code='BROWSER_PLATFORM' and p_pantalla_id in (51,52,53,54,56) then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id),
      'path',jsonb_build_array('observed','canonical_contract','rules'),
      'operator','CONTAINS',
      'expected','[{"rule_code":"B2B-RULE-COMPAT-001","config":{"blocks_story":false,"blocks_implementation":false,"blocks_qa":true,"blocks_production":true,"current_status":"PENDING_SOURCE_IDENTIFICATION","frontend_source_required":true,"compatibility_matrix_required":true,"browser_versions_in_screen_rules":"DENY"}}]'::jsonb
    );

  elsif p_family_code='FORCED_COLORS_CONTRAST' and p_pantalla_id in (51,52,53,54,56) then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id),
      'path',jsonb_build_array('observed','canonical_contract','rules'),
      'operator','CONTAINS',
      'expected','[{"rule_code":"B2B-RULE-A11Y-004","config":{"forced_colors_support":"REQUIRED","focus_visibility":"REQUIRED","state_color_only":"DENY","global_forced_color_adjust_none":"DENY","custom_palette_in_screen_rule":"DENY","implementation_status":"PENDING_IMPLEMENTATION_QA"}}]'::jsonb
    );

  elsif p_family_code='REDUCED_MOTION' and p_pantalla_id in (51,52,53,54,56) then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id),
      'path',jsonb_build_array('observed','canonical_contract','rules'),
      'operator','CONTAINS',
      'expected','[{"rule_code":"B2B-RULE-A11Y-003","config":{"preference":"prefers-reduced-motion","functional_dependency_on_motion":"DENY","non_essential_motion_when_reduce":"REDUCE_OR_REMOVE","status_requires_non_motion_cue":true,"implementation_status":"PENDING_IMPLEMENTATION_QA"}}]'::jsonb
    );

  elsif p_family_code='THEME_LIGHT_DARK_SYSTEM' and p_pantalla_id in (51,52,53,54,56) then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id),
      'path',jsonb_build_array('observed','canonical_contract','rules'),
      'operator','CONTAINS',
      'expected','[{"rule_code":"B2B-RULE-THEME-001","config":{"persist_preference":true,"respect_system_preference":true}},{"rule_code":"B2B-RULE-THEME-002","config":{"blocked_until_tokens_vigente":true}},{"rule_code":"B2B-RULE-THEME-003","config":{"theme_flash":"DENY","implementation_status":"PENDING_IMPLEMENTATION_QA","system_preference_used_when_user_preference_absent":true}}]'::jsonb
    );

  elsif p_family_code='RATE_LIMIT' and p_pantalla_id in (52,56) then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id),
      'path',jsonb_build_array('observed','canonical_contract','policies','rate_limit'),
      'operator','CONTAINS',
      'expected','[{"rate_limit_policy_id":7,"policy_code":"RATE-B2B-PASSWORD-RECOVERY-OTP","resource_code":"AUTH_PASSWORD_RECOVERY_OTP_SEND","scope_key":"USER","max_requests":6,"burst_limit":6,"window_seconds":900,"status":"CANDIDATO"}]'::jsonb
    );

  elsif p_family_code='RATE_LIMIT' and p_pantalla_id=54 then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id),
      'path',jsonb_build_array('observed','canonical_contract','policies','rate_limit'),
      'operator','CONTAINS',
      'expected','[{"rate_limit_policy_id":8,"policy_code":"RATE-B2B-NEW-DEVICE-OTP","resource_code":"AUTH_NEW_DEVICE_OTP_SEND","scope_key":"USER","max_requests":6,"burst_limit":6,"window_seconds":900,"status":"CANDIDATO"}]'::jsonb
    );

  elsif p_family_code='SOURCE_AUTHORITY_PROVENANCE'
        and v_kind='EKB_PREVENTION_SET'
        and coalesce(v->'source_ref'->'codes','[]'::jsonb) @> '["PRV-AUD-019"]'::jsonb then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-AUD-019')),
      'path',jsonb_build_array('observed'),
      'operator','CONTAINS',
      'expected','[{"regla_codigo":"PRV-AUD-019","activa":true}]'::jsonb
    );

  elsif p_pantalla_id in (52,53,56) and p_family_code='VISUAL_EVIDENCE' then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',p_pantalla_id),
      'path',jsonb_build_array('observed'),
      'operator','CONTAINS',
      'expected',jsonb_build_array(
        jsonb_build_object('artifact',jsonb_build_object('pantalla_id',p_pantalla_id,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('viewport','DESKTOP'))),
        jsonb_build_object('artifact',jsonb_build_object('pantalla_id',p_pantalla_id,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('viewport','TABLET'))),
        jsonb_build_object('artifact',jsonb_build_object('pantalla_id',p_pantalla_id,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('viewport','MOBILE')))
      )
    );

  elsif p_pantalla_id=56 and p_family_code='PROFILES' then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_RULE_SET','pantalla_id',56),
      'path',jsonb_build_array('observed','rules'),
      'operator','CONTAINS',
      'expected','[{"rule":{"codigo":"B2B-RULE-AUTH-029","valor_config":{"operational_authorization_before_completion":"DENY","recovery_context_scope":"PASSWORD_UPDATE_ONLY","client_context_promotion":"DENY"}}}]'::jsonb
    );

  elsif p_pantalla_id=56 and p_family_code='UI_MESSAGES' and v_kind='SCREEN_CANONICAL_GRAPH' then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),
      'path',jsonb_build_array('observed','canonical_contract','fields'),
      'operator','CONTAINS',
      'expected','[{"field_id":306,"validations":[{"validation_code":"B2B_VAL_RECOVERY_EMAIL_OTP_REQUIRED","message":"Ingresa el código de verificación."},{"validation_code":"B2B_VAL_RECOVERY_EMAIL_OTP_POLICY","message":"El código ingresado no es válido o ya venció. Solicita un nuevo código para continuar."}]}]'::jsonb
    );

  elsif p_pantalla_id=53 and p_family_code='PRIVACY_PII' and (v->'path')::text ilike '%rules%' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-030","config":{"password_logs":"DENY","password_analytics":"DENY","password_persistence_lf_ops":"DENY"}}]'::jsonb);

  elsif p_pantalla_id=53 and p_family_code='ROUTING_NAVIGATION' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-029","config":{"recovery_verify_route_id":11,"password_update_screen_id":53,"client_context_promotion":"DENY"}},{"rule_code":"B2B-RULE-AUTH-031","config":{"login_route_id":10,"client_redirect_authoritative":"DENY","fresh_login_required":true}}]'::jsonb);

  elsif p_pantalla_id=53 and p_family_code='RUNTIME_CONFIG' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-029","config":{"provider_architecture_security_policy_id":23}},{"rule_code":"B2B-RULE-AUTH-030","config":{"provider_binding":"SUPABASE_AUTH","password_security_policy_id":24,"provider_architecture_security_policy_id":23}}]'::jsonb);

  elsif p_pantalla_id=54 and p_family_code='FIELDS' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"field_id":302,"field_code":"B2B_FLD_MFA_EMAIL_OTP_CODE","required":true,"sensitive":true,"logs_allowed":false,"analytics_allowed":false,"ui":{"context_key":"MFA_EMAIL_OTP_CODE","component_token_id":40,"component_token_code":"otp_pin"}}]'::jsonb);

  elsif p_pantalla_id=51 and p_family_code='PERMISSIONS' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"permission":{"permission_code":"B2B_USER_UPDATE"}},{"permission":{"permission_code":"B2B_AUTH_FACTOR_RESET"}}]'::jsonb);
  end if;

  return v - 'actual' - 'result' - 'source_observed_sha256';
end;
$function$;