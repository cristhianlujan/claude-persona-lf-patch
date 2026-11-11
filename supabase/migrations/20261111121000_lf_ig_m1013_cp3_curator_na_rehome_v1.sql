-- LF M10.13 CP3 | First production disconnection of ACTIVE Curator from frozen M10.4.
-- Governed exclusively by ACTUALIZACION_DB_LF / DB_WRITE_TRANSPORT / LF Migration Merge Train.
-- Source: Supabase pg_proc exact hashes; PR #3788. No Router/Edge/frozen source changes.
-- Rehome: existing ACTIVE fn_input_na_positive_authority_v512 overload with cached graph.
-- 47-family paired regression before caller mutation; any mismatch aborts entire transaction.
-- Never declare ZERO_LEGACY_CALLERS, AUD045 or other checkpoints PASS from this lot.
BEGIN;
SET LOCAL lock_timeout = '2000ms';
SET LOCAL statement_timeout = '120000ms';
DO $preflight$
DECLARE v_exec_id text;
BEGIN
  SELECT e.execution_id INTO v_exec_id FROM public.lf_operation_execution e
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code ~ ('^[0-9]{14}_lf_ig_m1013_cp3_curator_na_rehome_v1$')
    AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
    AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
    AND e.manifest->>'producer'='lf-migration-merge-train'
    AND e.manifest->>'pr'='3788'
    AND e.status='IN_PROGRESS' ORDER BY e.created_at DESC LIMIT 1;
  IF v_exec_id IS NULL THEN RAISE EXCEPTION 'IG_CP3_GOVERNED_OPERATION_REQUIRED'; END IF;
  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') IS DISTINCT FROM 'PENDING'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=474 AND checkpoint_code='AUD045_EVIDENCE') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'IG_CP3_STATE_NOT_CURRENT'; END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
     'programacion.fn_input_governance_bootstrap_classify_v1_ctx(integer,text,bigint,jsonb)'::regprocedure)
     IS DISTINCT FROM '42e02cece283329a2a6f16063599a595'
     OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
     'programacion.fn_input_na_positive_authority_v512_cached_v1(text,integer,bigint,jsonb)'::regprocedure)
     IS DISTINCT FROM 'dbb181d6df12c9bca188b0072c23fe10'
     OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
     'programacion.fn_input_na_positive_authority_v512(text,integer,bigint)'::regprocedure)
     IS DISTINCT FROM '023828d5eb05d1a836145ebc9cd8a3e2'
  THEN RAISE EXCEPTION 'IG_CP3_FROZEN_OR_ACTIVE_SOURCE_DRIFT'; END IF;
  IF to_regprocedure('programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb)') IS NOT NULL
  THEN RAISE EXCEPTION 'IG_CP3_TARGET_OVERLOAD_ALREADY_EXISTS'; END IF;
  IF (SELECT count(*) FROM programacion.input_family_assessments WHERE run_id=951)<>47
     OR programacion.fn_input_run_is_source_current(951) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'IG_CP3_RUN951_NOT_CURRENT_47'; END IF;
END;
$preflight$;

-- This creates a graph-aware overload of the CURRENT function; the original
-- 3-argument function remains unchanged. Body exactly equals frozen helper body.
CREATE OR REPLACE FUNCTION programacion.fn_input_na_positive_authority_v512(p_family_code text, p_pantalla_id integer, p_version_id bigint, p_graph jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
declare
  v_graph jsonb;
  v_rules jsonb;
  v_screen_permissions jsonb;
  v_profile_permissions jsonb;
  v_rule jsonb;
  v_exclusion jsonb;
  v_codes jsonb := '[]'::jsonb;
  v_qualified boolean := false;
  v_has_otp_field boolean := false;
  v_route_public boolean := false;
  v_profile_link_count integer := 0;
  v_permission_link_count integer := 0;
  v_client_recovery_no_access boolean := false;
begin
  v_graph := p_graph;
  v_rules := coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
  v_screen_permissions := coalesce(v_graph->'screen_permissions','[]'::jsonb);
  v_profile_permissions := coalesce(v_graph->'profile_permissions','[]'::jsonb);

  select exists(
    select 1
    from lf_ops.rutas rt
    where rt.pantalla_id=p_pantalla_id
      and rt.status='VIGENTE'
      and rt.authentication_required is false
  ) into v_route_public;

  select count(*) into v_profile_link_count
  from lf_ops.pantallas_perfiles pp
  where pp.pantalla_id=p_pantalla_id
    and pp.status<>'ARCHIVADO';

  select count(*) into v_permission_link_count
  from lf_ops.pantallas_permisos pp
  where pp.pantalla_id=p_pantalla_id
    and pp.status<>'ARCHIVADO';

  select exists(
    select 1
    from jsonb_array_elements(v_rules) x(rule)
    where x.rule->>'status'='VIGENTE'
      and coalesce((x.rule->>'transversal')::boolean,false) is false
      and x.rule->>'rule_code' in (
        'REG_CLIENT_RECOVERY_IDV_STEPUP_001',
        'REG_CLIENT_RECOVERY_REBIND_ATOMIC_001',
        'REG_CLIENT_RECOVERY_ACCESS_AFTER_REBIND_001'
      )
      and (
        x.rule->'config'->>'operational_access_before_verified'='DENY'
        or x.rule->'config'->>'operational_access_before_commit'='DENY'
        or x.rule->'config'->>'partial_recovery_session_promotion'='DENY'
      )
  ) into v_client_recovery_no_access;

  if p_family_code='SESSION' then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if coalesce(v_rule->'config'->>'operational_session_creation','')='DENY' then
        v_qualified:=true;
        v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code');
      end if;
    end loop;

  elsif p_family_code='PERMISSIONS'
        and jsonb_array_length(v_screen_permissions)=0
        and jsonb_array_length(v_profile_permissions)=0 then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if coalesce(v_rule->>'transversal','true')::boolean is false
         and (
           coalesce(v_rule->'config'->>'operational_access_grant','')='DENY'
           or coalesce(v_rule->'config'->>'operational_authorization_before_completion','')='DENY'
           or coalesce(v_rule->'config'->>'mfa_route_full_operational_session_required','')='false'
         ) then
        v_qualified:=true;
        v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code');
      end if;
    end loop;

    if not v_qualified
       and v_route_public
       and v_profile_link_count=0
       and v_permission_link_count=0
       and v_client_recovery_no_access then
      v_qualified:=true;
      select coalesce(jsonb_agg(x.rule->>'rule_code' order by x.rule->>'rule_code'),'[]'::jsonb)
      into v_codes
      from jsonb_array_elements(v_rules) x(rule)
      where x.rule->>'status'='VIGENTE'
        and x.rule->>'rule_code' in (
          'REG_CLIENT_RECOVERY_IDV_STEPUP_001',
          'REG_CLIENT_RECOVERY_REBIND_ATOMIC_001',
          'REG_CLIENT_RECOVERY_ACCESS_AFTER_REBIND_001'
        );
    end if;

  elsif p_family_code='PROFILES'
        and v_route_public
        and v_profile_link_count=0
        and v_permission_link_count=0
        and v_client_recovery_no_access then
    v_qualified:=true;
    select coalesce(jsonb_agg(x.rule->>'rule_code' order by x.rule->>'rule_code'),'[]'::jsonb)
    into v_codes
    from jsonb_array_elements(v_rules) x(rule)
    where x.rule->>'status'='VIGENTE'
      and x.rule->>'rule_code' in (
        'REG_CLIENT_RECOVERY_IDV_STEPUP_001',
        'REG_CLIENT_RECOVERY_REBIND_ATOMIC_001',
        'REG_CLIENT_RECOVERY_ACCESS_AFTER_REBIND_001'
      );

  elsif p_family_code in ('FEATURE_FLAGS','I18N_FORMATS') then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if v_rule->>'rule_code'='B2B-RULE-INPUT-APPLICABILITY-001'
         and coalesce((v_rule->>'pending_decision')::boolean,false) is false
         and coalesce(v_rule->'config'->>'decision_id','')='DEC-INPUT-GOV-512-HUMAN-001' then
        v_exclusion:=v_rule->'config'->'input_family_exclusions'->p_family_code;
        if (p_family_code='FEATURE_FLAGS' and coalesce(v_exclusion->>'status','')='EXCLUDED_CURRENT_SCOPE')
           or (p_family_code='I18N_FORMATS' and coalesce(v_exclusion->>'status','')='EXCLUDED_CURRENT_SINGLE_LOCALE_SCOPE') then
          v_qualified:=true;
          v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code');
        end if;
      end if;
    end loop;

  elsif p_family_code='MFA_OTP_SSO' then
    select exists(
      select 1
      from lf_ops.campos_pantallas cp
      join lf_ops.campos c on c.id=cp.campo_id
      where cp.pantalla_id=p_pantalla_id
        and c.codigo='CAMPO_OTP_CODE'
        and c.estado='ACTIVO'
    ) into v_has_otp_field;

    if not v_has_otp_field then
      for v_rule in select value from jsonb_array_elements(v_rules) loop
        if coalesce(v_rule->>'status','')='VIGENTE'
           and coalesce(v_rule->>'transversal','true')::boolean is false
           and coalesce(v_rule->'config'->>'repeat_current_phone_otp_after_creation','')='false'
           and coalesce(v_rule->'config'->>'current_phone_proof_source','')='ONB_002_SAME_SERVER_SESSION'
           and coalesce(v_rule->'config'->>'session_creation_authority','')='SERVER_ONLY' then
          v_qualified:=true;
          v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code');
        end if;
      end loop;
    end if;
  end if;

  return jsonb_build_object(
    'qualified',v_qualified,
    'family_code',p_family_code,
    'pantalla_id',p_pantalla_id,
    'authority_kind',case when v_qualified then 'EXPLICIT_CANONICAL_EXCLUSION' else 'NO_POSITIVE_EXCLUSION' end,
    'rule_codes',v_codes,
    'screen_permission_count',jsonb_array_length(v_screen_permissions),
    'profile_permission_count',jsonb_array_length(v_profile_permissions),
    'screen_profile_link_count',v_profile_link_count,
    'screen_permission_link_count',v_permission_link_count,
    'public_unauthenticated_route',v_route_public,
    'client_recovery_operational_access_denied',v_client_recovery_no_access
  );
end;
$function$;

REVOKE ALL ON FUNCTION programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb) TO service_role;

DO $pair$
DECLARE
  v_run record; v_a record; v_graph jsonb; v_old jsonb; v_new jsonb;
  v_legacy_ms numeric:=0; v_active_ms numeric:=0; v_started timestamptz;
  v_pairs integer:=0; v_match integer:=0;
  v_bad jsonb:='[]'::jsonb;
BEGIN
  SELECT id,pantalla_id,version_id INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=951;
  v_graph:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
  IF md5((SELECT p.prosrc FROM pg_proc p WHERE p.oid=
     'programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb)'::regprocedure))
     IS DISTINCT FROM 'dbb181d6df12c9bca188b0072c23fe10'
  THEN RAISE EXCEPTION 'IG_CP3_COPIED_BODY_MISMATCH'; END IF;
  FOR v_a IN SELECT family_code FROM programacion.input_family_assessments WHERE run_id=951 ORDER BY family_code LOOP
    v_started:=clock_timestamp();
    v_old:=programacion.fn_input_na_positive_authority_v512_cached_v1(v_a.family_code,v_run.pantalla_id,v_run.version_id,v_graph);
    v_legacy_ms:=v_legacy_ms+extract(epoch from(clock_timestamp()-v_started))*1000;
    v_started:=clock_timestamp();
    v_new:=programacion.fn_input_na_positive_authority_v512(v_a.family_code,v_run.pantalla_id,v_run.version_id,v_graph);
    v_active_ms:=v_active_ms+extract(epoch from(clock_timestamp()-v_started))*1000;
    v_pairs:=v_pairs+1;
    IF v_old IS NOT DISTINCT FROM v_new THEN v_match:=v_match+1;
    ELSE v_bad:=v_bad||jsonb_build_array(jsonb_build_object('family',v_a.family_code,'old',v_old,'new',v_new)); END IF;
  END LOOP;
  IF v_pairs<>47 OR v_match<>47 OR jsonb_array_length(v_bad)<>0
  THEN RAISE EXCEPTION 'IG_CP3_NA_47_PARITY_FAILED:pairs=%,match=%,diff=%',v_pairs,v_match,v_bad; END IF;
  -- Pair equality is a prerequisite, not a terminal pass for the checkpoint.
  PERFORM set_config('lf.ig_cp3_na_pairs',v_pairs::text,true);
  PERFORM set_config('lf.ig_cp3_na_legacy_ms',round(v_legacy_ms,3)::text,true);
  PERFORM set_config('lf.ig_cp3_na_active_ms',round(v_active_ms,3)::text,true);
END;
$pair$;

-- One ACTIVE, nonfrozen call site only. No edit to M10.4 bodies.
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v1_ctx(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops', 'transversal'
AS $function$
declare
  v_graph jsonb;
  v_rules jsonb;
  v_fields jsonb;
  v_errors jsonb;
  v_messages jsonb;
  v_analytics jsonb;
  v_evidence jsonb;
  v_variants jsonb;
  v_components jsonb;
  v_screen jsonb;
  v_design jsonb;
  v_design_summary jsonb;
  v_api jsonb;
  v_states_receipt jsonb;
  v_states jsonb;
  v_probe jsonb:='{}'::jsonb;
  v_na jsonb;
  v_source_refs jsonb;
  v_stage_cfg jsonb;
  v_stage text;
  v_level text:='MISSING';
  v_severity text:='P0';
  v_cov text:='MISSING';
  v_wd text:='MISSING';
  v_story text:='BLOCKED';
  v_impl text:='BLOCKED';
  v_qa text:='BLOCKED';
  v_prod text:='BLOCKED';
  v_blockers jsonb:='[]'::jsonb;
  v_blocker_code text;
  v_count integer:=0;
  v_aux integer:=0;
  v_missing_required_validations integer:=0;
  v_theme_count integer:=0;
  v_rule_count integer:=0;
  v_candidate_count integer:=0;
  v_pending_count integer:=0;
  v_pending_marker integer:=0;
  v_payload jsonb;
begin
  if not exists(
    select 1
    from lf_ops.reglas q
    cross join lateral jsonb_array_elements_text(q.valor_config->'families') f(value)
    where q.codigo='B2B-RULE-STORY-READINESS-001' and f.value=p_family_code
  ) then raise exception 'BOOTSTRAP_FAMILY_NOT_IN_CANONICAL_UNIVERSE:%',p_family_code; end if;

  v_graph:=p_graph;
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
  v_fields:=coalesce(v_graph->'canonical_contract'->'fields','[]'::jsonb);
  v_errors:=coalesce(v_graph->'canonical_contract'->'errors','[]'::jsonb);
  v_messages:=coalesce(v_graph->'messages','[]'::jsonb);
  v_analytics:=coalesce(v_graph->'canonical_contract'->'analytics','[]'::jsonb);
  v_evidence:=coalesce(v_graph->'canonical_contract'->'evidence','[]'::jsonb);
  v_variants:=coalesce(v_graph->'canonical_contract'->'visual'->'variants','[]'::jsonb);
  v_components:=coalesce(v_graph->'canonical_contract'->'visual'->'components','[]'::jsonb);
  v_screen:=coalesce(v_graph->'canonical_contract'->'context'->'screen','{}'::jsonb);
  v_design:=coalesce(v_graph->'canonical_contract'->'visual'->'design_system','{}'::jsonb);
  v_design_summary:=coalesce(v_graph->'canonical_contract'->'visual'->'design_bindings'->'summary','{}'::jsonb);
  v_api:=coalesce(v_graph->'canonical_contract'->'api_contract_resolution','{}'::jsonb);
  select coalesce(c.especificacion->'family_stage_requirements'->p_family_code,'{}'::jsonb)
    into v_stage_cfg from programacion.contratos c
    where c.version_id=p_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  v_stage:=upper(coalesce(v_stage_cfg->>'coverage_required_by','UNRESOLVED'));
  v_source_refs:=jsonb_build_array(jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id));
  v_na:=programacion.fn_input_na_positive_authority_v512(p_family_code,p_pantalla_id,p_version_id,p_graph);

  if coalesce((v_na->>'qualified')::boolean,false) then
    v_payload:=jsonb_build_object(
      'family_code',p_family_code,'severity','P4','applicability','NOT_APPLICABLE',
      'coverage_status','NOT_APPLICABLE','well_defined_status','NOT_APPLICABLE',
      'story_ready_status','NOT_APPLICABLE','implementation_ready_status','NOT_APPLICABLE',
      'qa_ready_status','NOT_APPLICABLE','production_ready_status','NOT_APPLICABLE',
      'source_refs',v_source_refs,'blockers','[]'::jsonb,
      'negative_requirements',jsonb_build_array('NO_INVENTION','POSITIVE_NA_AUTHORITY_REQUIRED'),
      'test_obligations','[]'::jsonb,'probe',v_na,'bootstrap_level','NOT_APPLICABLE',
      'rationale','Governed bootstrap: explicit positive canonical exclusion authorizes NOT_APPLICABLE.'
    );
    return v_payload||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  case p_family_code
    when 'SCREEN_IDENTITY' then
      if nullif(v_graph->>'screen_code','') is not null and nullif(v_graph->>'module_code','') is not null and nullif(v_graph->>'app_shell_code','') is not null then v_level:='COMPLETE'; end if;
      v_probe:=jsonb_build_object('screen_code',v_graph->>'screen_code','module_code',v_graph->>'module_code','app_shell_code',v_graph->>'app_shell_code');
    when 'OBJECTIVE_OUTCOMES' then
      if nullif(btrim(coalesce(v_screen->>'objective','')),'') is not null then v_level:='COMPLETE'; end if;
      v_probe:=jsonb_build_object('objective',v_screen->'objective');
    when 'FIELDS' then
      v_count:=jsonb_array_length(v_fields); if v_count>0 then v_level:='COMPLETE'; end if; v_probe:=jsonb_build_object('field_count',v_count);
    when 'VALIDATIONS' then
      v_count:=jsonb_array_length(v_fields);
      select count(*) into v_missing_required_validations from jsonb_array_elements(v_fields) f
      where coalesce((f->>'required')::boolean,false) and jsonb_array_length(coalesce(f->'validations','[]'::jsonb))=0;
      if v_count>0 and v_missing_required_validations=0 then v_level:='COMPLETE'; elsif v_count>0 then v_level:='PARTIAL'; end if;
      v_probe:=jsonb_build_object('field_count',v_count,'required_fields_without_validations',v_missing_required_validations);
    when 'STATES' then
      v_states_receipt:=programacion.fn_input_resolve_source_ref(jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',p_pantalla_id),p_pantalla_id,p_version_id);
      v_states:=coalesce(v_states_receipt->'observed','[]'::jsonb); v_count:=jsonb_array_length(v_states); if v_count>0 then v_level:='COMPLETE'; end if;
      v_source_refs:=jsonb_build_array(jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',p_pantalla_id)); v_probe:=jsonb_build_object('canonical_state_count',v_count);
    when 'TRANSITIONS' then
      v_states_receipt:=programacion.fn_input_resolve_source_ref(jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',p_pantalla_id),p_pantalla_id,p_version_id);
      v_states:=coalesce(v_states_receipt->'observed','[]'::jsonb); v_count:=jsonb_array_length(v_states);
      v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['flujo'],'(transition|transicion|after_screen|post_)');
      if v_count>0 and coalesce((v_probe->>'count')::integer,0)>0 then v_level:='PARTIAL'; end if;
      v_source_refs:=jsonb_build_array(jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',p_pantalla_id)); v_probe:=v_probe||jsonb_build_object('canonical_state_count',v_count);
    when 'PROFILES' then v_count:=jsonb_array_length(coalesce(v_graph->'canonical_contract'->'profiles','[]'::jsonb)); if v_count>0 then v_level:='COMPLETE'; end if; v_probe:=jsonb_build_object('profile_count',v_count);
    when 'PERMISSIONS' then v_count:=jsonb_array_length(coalesce(v_graph->'screen_permissions','[]'::jsonb)); v_aux:=jsonb_array_length(coalesce(v_graph->'profile_permissions','[]'::jsonb)); if v_count+v_aux>0 then v_level:='COMPLETE'; end if; v_probe:=jsonb_build_object('screen_permission_count',v_count,'profile_permission_count',v_aux);
    when 'ERRORS' then v_count:=jsonb_array_length(v_errors); if v_count>0 then v_level:='COMPLETE'; end if; v_probe:=jsonb_build_object('error_count',v_count);
    when 'UI_MESSAGES' then v_count:=jsonb_array_length(v_messages); v_aux:=jsonb_array_length(v_errors); if v_count>0 then v_level:='COMPLETE'; elsif v_aux>0 then v_level:='PARTIAL'; end if; v_probe:=jsonb_build_object('message_registry_count',v_count,'error_message_count',v_aux);
    when 'ANALYTICS' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['analytics','tageo'],null); if jsonb_array_length(v_analytics)>0 and coalesce((v_probe->>'count')::integer,0)>0 then v_level:='PARTIAL'; end if; v_probe:=v_probe||jsonb_build_object('analytics_event_count',jsonb_array_length(v_analytics));
    when 'RESPONSIVE' then v_count:=jsonb_array_length(v_variants); v_aux:=coalesce((v_design_summary->>'variant_layout_missing_count')::integer,0); if v_count>=3 and v_aux=0 then v_level:='COMPLETE'; elsif v_count>0 then v_level:='PARTIAL'; end if; v_probe:=jsonb_build_object('variant_count',v_count,'variant_layout_missing_count',v_aux);
    when 'DESIGN_SYSTEM' then
      if nullif(v_design->>'design_system_code','') is not null then
        if coalesce((v_design_summary->>'referential_integrity_failure_count')::integer,0)=0 and coalesce((v_design_summary->>'field_component_missing_count')::integer,0)=0 and coalesce((v_design_summary->>'variant_layout_missing_count')::integer,0)=0 and coalesce((v_design_summary->>'element_required_missing_component_count')::integer,0)=0 and v_design->>'status'='VIGENTE' then v_level:='COMPLETE'; else v_level:='PARTIAL'; end if;
      end if;
      v_probe:=jsonb_build_object('design_system',v_design,'summary',v_design_summary);
    when 'ASSETS_ICONS' then v_count:=jsonb_array_length(v_components); if v_count>0 then v_level:='PARTIAL'; end if; v_probe:=jsonb_build_object('component_count',v_count,'required_missing_component_count',coalesce((v_design_summary->>'element_required_missing_component_count')::integer,0));
    when 'API_DATA_CONTRACT' then if coalesce((v_api->>'has_resolvable_operation_schema_authority')::boolean,false) and v_api->>'implementation_gate'='READY' then v_level:='COMPLETE'; elsif coalesce((v_api->>'has_behavioral_contract')::boolean,false) then v_level:='PARTIAL'; end if; v_probe:=v_api;
    when 'DEPENDENCIES' then if jsonb_typeof(v_screen->'dependencies')='array' then v_level:='COMPLETE'; end if; v_probe:=jsonb_build_object('dependencies',v_screen->'dependencies');
    when 'VISUAL_EVIDENCE' then v_count:=jsonb_array_length(v_evidence); if v_count>0 then v_level:='PARTIAL'; end if; v_probe:=jsonb_build_object('artifact_count',v_count,'current_count',(select count(*) from jsonb_array_elements(v_evidence) e where coalesce((e->>'is_current')::boolean,false)));
    when 'EKB' then v_level:='COMPLETE'; v_source_refs:=jsonb_build_array(jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-GOV-010'))); v_probe:=jsonb_build_object('authority','PRV-GOV-010');
    when 'SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS' then v_level:='COMPLETE'; v_source_refs:=jsonb_build_array(jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033')),jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-AUD-019'))); v_probe:=jsonb_build_object('decision_authority','ADR-EKB-033','prevention_authority','PRV-AUD-019');
    when 'CONTEXT_BUDGET_RETRIEVAL_POLICY' then v_level:='COMPLETE'; v_source_refs:=jsonb_build_array(jsonb_build_object('kind','CONTRACT','codigo','INPUT_READINESS_CONTRACT')); v_probe:=jsonb_build_object('contract','INPUT_READINESS_CONTRACT','revision',programacion.fn_input_contract_clause_v1(p_version_id,'INPUT_READINESS_CONTRACT',array['family_stage_requirements','CONTEXT_BUDGET_RETRIEVAL_POLICY'])->>'contract_revision');
    when 'ROLLOUT_PRODUCTION_GATES' then v_level:='COMPLETE'; v_probe:=jsonb_build_object('production_authorized',false);
    when 'ACTIONS' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['flujo','ux','ui','copy'],null);
    when 'ROUTING_NAVIGATION' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(NAVIGATION|NAVEGACION|ROUTE|RUTA|DESTINO|after_screen|post_)');
    when 'SESSION' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['sesion'],null);
    when 'RATE_LIMIT' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['rate_limiting'],'(RATE|RL_)');
    when 'TIMEOUT_RETRY' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(TIMEOUT|RETRY|BACKOFF|COOLDOWN|REG_RATE_005|REG_RL_|REG_ATQ_011)');
    when 'SECURITY' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['seguridad','ataques'],null);
    when 'MFA_OTP_SSO' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(OTP|MFA|SSO)');
    when 'PRIVACY_PII' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(PII|MASK|PRIVACY|PRIVACIDAD|RETEN|DATO)');
    when 'AUDIT' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['auditoria'],null);
    when 'OBSERVABILITY' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['observabilidad','alertas'],null);
    when 'PERFORMANCE' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(LCP|PERFORMANCE|CORE WEB|OBS_004|ALR_005)');
    when 'THEME_LIGHT_DARK_SYSTEM' then select count(distinct x.value->>'theme_binding_code') into v_theme_count from jsonb_array_elements(v_variants) x(value) where nullif(x.value->>'theme_binding_code','') is not null; if jsonb_array_length(v_variants)>0 and v_theme_count>1 then v_level:='COMPLETE'; elsif jsonb_array_length(v_variants)>0 then v_level:='PARTIAL'; end if; v_probe:=jsonb_build_object('variant_count',jsonb_array_length(v_variants),'distinct_theme_bindings',v_theme_count);
    when 'FORCED_COLORS_CONTRAST' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['accesibilidad'],'(FORCED|CONTRAST|CONTRASTE)');
    when 'REDUCED_MOTION' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['accesibilidad'],'(REDUCED|MOTION|MOVIMIENTO)');
    when 'ACCESSIBILITY' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['accesibilidad'],null);
    when 'LOADING_EMPTY_ERROR_STATES' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['error_states','estados_ui'],null); if jsonb_array_length(v_errors)>0 and coalesce((v_probe->>'count')::integer,0)>0 then v_level:='PARTIAL'; end if; v_probe:=v_probe||jsonb_build_object('error_count',jsonb_array_length(v_errors));
    when 'IDEMPOTENCY_CONCURRENCY' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(IDEMP|CONCURRENC|SINGLE.?FLIGHT|X-IDEMPOTENCY)');
    when 'FEATURE_FLAGS' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(FEATURE|FLAG|EXPERIMENT|ABT)');
    when 'TESTING_OBLIGATIONS' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(TEST|PRUEBA|QA)');
    when 'BROWSER_PLATFORM' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(BROWSER|NAVEGADOR|COMPAT|PLATFORM)');
    when 'I18N_FORMATS' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(I18N|LOCALE|IDIOMA|INTERNACIONAL|FORMAT)');
    when 'RUNTIME_CONFIG' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['tecnico'],null);
    else raise exception 'BOOTSTRAP_CLASSIFIER_UNHANDLED_FAMILY:%',p_family_code;
  end case;

  if v_level='MISSING' and v_probe ? 'count' then
    v_rule_count:=coalesce((v_probe->>'count')::integer,0);
    v_candidate_count:=coalesce((v_probe->>'candidate_count')::integer,0);
    v_pending_count:=coalesce((v_probe->>'pending_decision_count')::integer,0);
    v_pending_marker:=coalesce((v_probe->>'pending_marker_count')::integer,0);
    if v_rule_count>0 then v_level:='PARTIAL'; end if;
  end if;

  if v_level='COMPLETE' then
    v_cov:='COMPLETE'; v_wd:='COMPLETE'; v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='READY'; v_severity:='P4';
  else
    v_cov:=case when v_level='PARTIAL' then 'PARTIAL' else 'MISSING' end;
    v_wd:=v_cov;
    if v_stage='PRODUCTION' then v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='BLOCKED'; v_severity:='P3';
    elsif v_stage='QA' then v_story:='READY'; v_impl:='READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_severity:='P2';
    elsif v_stage='IMPLEMENTATION' then v_story:='READY'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_severity:='P1';
    else v_story:='BLOCKED'; v_impl:='BLOCKED'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_severity:='P0'; end if;
  end if;

  if p_family_code='ROLLOUT_PRODUCTION_GATES' then
    v_cov:='COMPLETE'; v_wd:='COMPLETE'; v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='NOT_READY'; v_severity:='P3';
    v_blockers:=jsonb_build_array(jsonb_build_object('code','PRODUCTION_NOT_AUTHORIZED','source_ref','INPUT_GOVERNANCE_EXECUTION_CONTRACT'));
  elsif v_level<>'COMPLETE' then
    v_blocker_code:=case p_family_code
      when 'OBJECTIVE_OUTCOMES' then 'OBJECTIVE_CANONICAL_MISSING'
      when 'STATES' then 'SCREEN_STATE_SET_EMPTY'
      when 'TRANSITIONS' then 'CANONICAL_TRANSITIONS_INSUFFICIENT'
      when 'ROUTING_NAVIGATION' then 'CANONICAL_ROUTES_PENDING'
      when 'PROFILES' then 'PROFILE_SCOPE_UNRESOLVED'
      when 'PERMISSIONS' then 'PERMISSION_SCOPE_UNRESOLVED'
      when 'API_DATA_CONTRACT' then 'API_OPERATION_SCHEMA_SOURCE_INCOMPLETE'
      when 'DESIGN_SYSTEM' then 'DESIGN_BINDING_INCOMPLETE'
      when 'TIMEOUT_RETRY' then 'TIMING_RECONCILIATION_REQUIRED'
      when 'FEATURE_FLAGS' then 'FEATURE_FLAG_CANONICAL_SOURCE_INCOMPLETE'
      when 'I18N_FORMATS' then 'I18N_APPLICABILITY_AUTHORITY_MISSING'
      when 'VISUAL_EVIDENCE' then 'CURRENT_VISUAL_EVIDENCE_PARTIAL'
      when 'SECURITY' then 'SECURITY_SEMANTIC_DEPTH_REVIEW_REQUIRED'
      else 'BOOTSTRAP_CANONICAL_EVIDENCE_'||v_level end;
    v_blockers:=jsonb_build_array(jsonb_build_object('code',v_blocker_code,'family_code',p_family_code,'bootstrap_level',v_level));
    if p_family_code='DESIGN_SYSTEM' then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','ELEMENT_REQUIRED_COMPONENT_BINDING_MISSING','count',coalesce((v_design_summary->>'element_required_missing_component_count')::integer,0))); end if;
  end if;

  v_payload:=jsonb_build_object(
    'family_code',p_family_code,'severity',v_severity,'applicability','APPLICABLE','coverage_status',v_cov,'well_defined_status',v_wd,
    'story_ready_status',v_story,'implementation_ready_status',v_impl,'qa_ready_status',v_qa,'production_ready_status',v_prod,
    'source_refs',v_source_refs,'blockers',v_blockers,'negative_requirements',jsonb_build_array('NO_INVENTION','NO_SILENT_OMISSION','SOURCE_AUTHORITY','ABSENCE_IS_NOT_NA'),
    'test_obligations','[]'::jsonb,'probe',v_probe,'bootstrap_level',v_level,'required_by_stage',v_stage,
    'rationale',format('Governed canonical bootstrap DEC-INPUT-GOV-BOOTSTRAP-001: %s=%s from direct source readback; absence never implies N/A.',p_family_code,v_level)
  );
  return v_payload||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

DO $postflight$
DECLARE v_exec_id text; v_payload jsonb; v_event bigint;
BEGIN
  SELECT e.execution_id INTO STRICT v_exec_id
    FROM public.lf_operation_execution e
   WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_code ~ ('^[0-9]{14}_lf_ig_m1013_cp3_curator_na_rehome_v1$')
    AND e.manifest->>'pr'='3788' AND e.status='IN_PROGRESS'
   ORDER BY e.created_at DESC LIMIT 1;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
     'programacion.fn_input_na_positive_authority_v512_cached_v1(text,integer,bigint,jsonb)'::regprocedure)
     IS DISTINCT FROM 'dbb181d6df12c9bca188b0072c23fe10'
    OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
     'programacion.fn_input_na_positive_authority_v512(text,integer,bigint)'::regprocedure)
     IS DISTINCT FROM '023828d5eb05d1a836145ebc9cd8a3e2'
  THEN RAISE EXCEPTION 'IG_CP3_FROZEN_SOURCE_CHANGED'; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=
    'programacion.fn_input_governance_bootstrap_classify_v1_ctx(integer,text,bigint,jsonb)'::regprocedure
    AND p.prosrc LIKE '%fn_input_na_positive_authority_v512_cached_v1(%')
  THEN RAISE EXCEPTION 'IG_CP3_LEGACY_CALL_STILL_PRESENT'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=
    'programacion.fn_input_governance_bootstrap_classify_v1_ctx(integer,text,bigint,jsonb)'::regprocedure
    AND p.prosrc LIKE '%fn_input_na_positive_authority_v512(%')
  THEN RAISE EXCEPTION 'IG_CP3_ACTIVE_CALL_NOT_PRESENT'; END IF;
  IF has_function_privilege('anon','programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb)','EXECUTE')
    OR NOT has_function_privilege('service_role','programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb)','EXECUTE')
  THEN RAISE EXCEPTION 'IG_CP3_OVERLOAD_ACL_INCORRECT'; END IF;
  v_payload:=jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id',v_exec_id,
    'producer','LF_MIGRATION_TRAIN_IG_M1013_CP3_NA_REHOME',
    'purpose','Rehome one live Curator dependency from frozen cached NA to active graph-aware overload without behavior drift',
    'acceptance_declared',false,'occurred_at',clock_timestamp(),
    'run_id',951,'paired_families',current_setting('lf.ig_cp3_na_pairs',true)::integer,
    'exact_equal_family_pairs',current_setting('lf.ig_cp3_na_pairs',true)::integer,
    'legacy_na_total_ms',current_setting('lf.ig_cp3_na_legacy_ms',true),
    'current_overload_na_total_ms',current_setting('lf.ig_cp3_na_active_ms',true),
    'frozen_function_md5','dbb181d6df12c9bca188b0072c23fe10',
    'source_disconnection','programacion.fn_input_governance_bootstrap_classify_v1_ctx',
    'target_function','programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb)',
    'checkpoint_code','ZERO_LEGACY_CALLERS','checkpoint_pass',false,
    'semantic_independence_credited',false,'production_activation',false,
    'next_gate','REMAINING_FROZEN_REACHABLE_PATHS'
  );
  IF private.fn_lf_event_acceptance_signal_v2(
    'ARTIFACT_RECONCILED','IG_M1013_CP3_NA_REHOME_V1','Active Curator NA dependency rehomed; CP3 remains PENDING',v_payload) IS NOT NULL
  THEN RAISE EXCEPTION 'IG_CP3_FALSE_ACCEPTANCE_SIGNAL'; END IF;
  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
    created_by_execution_id,payload)
  VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN','IG_M1013_CP3_NA_REHOME_V1',
    'Active Curator NA dependency rehomed; CP3 remains PENDING',
    'INFO','DERIVE_FROM_EXECUTION_ID',v_exec_id,v_payload)
  RETURNING id INTO v_event;
  IF NOT EXISTS(SELECT 1 FROM public.lf_eventos WHERE id=v_event
    AND payload->>'checkpoint_pass'='false'
    AND payload->>'exact_equal_family_pairs'='47'
    AND payload->>'acceptance_declared'='false')
  THEN RAISE EXCEPTION 'IG_CP3_GOVERNED_RECEIPT_READBACK_FAILED'; END IF;
  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'IG_CP3_PREMATURE_CLOSURE'; END IF;
END;
$postflight$;
COMMIT;
