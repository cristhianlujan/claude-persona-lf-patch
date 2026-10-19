-- Guard source and scope before changing anything.
DO $pre$
BEGIN
  IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p
      JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='programacion'
      AND p.proname='fn_guard_input_validator_semantic_coherence_v512')
      IS DISTINCT FROM '85f3177d6d01b43a0208233db3e48181' THEN
    RAISE EXCEPTION 'IG_M107_C_SEMANTIC_GUARD_DRIFT'; END IF;
  IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
      ('IG-M107-C-ONE-EVALUATION-034','IG-M107-B-ACTIVE-GUARD-ONEPASS-033'))<>2
    THEN RAISE EXCEPTION 'IG_M107_C_EKB_DEPENDENCIES_MISSING'; END IF;
  IF EXISTS (SELECT 1 FROM public.lf_error_knowledge
      WHERE codigo='IG-M107-C-SEMANTIC-GRAPH-CONDITIONAL-035')
    THEN RAISE EXCEPTION 'IG_M107_C_ALREADY_INSTALLED'; END IF;
  IF (SELECT count(*) FROM pg_trigger t JOIN pg_proc p ON t.tgfoid=p.oid
      WHERE p.proname='fn_guard_input_validator_semantic_coherence_v512'
        AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))<>1
    THEN RAISE EXCEPTION 'IG_M107_C_SEMANTIC_TRIGGER_BINDING_CHANGED'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION programacion.fn_guard_input_validator_semantic_coherence_v512()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_logical_validator_evidence jsonb;
  v_revision text;
  v_version_id bigint;
  v_pantalla_id integer;
  v_assertion jsonb;
  v_eval jsonb;
  v_positive_requirement boolean := false;
  v_na_authority jsonb;
  v_blocker jsonb;
  v_false_missing boolean := false;
  v_graph jsonb;
  v_rules jsonb;
  v_otp_present boolean := false;
  v_a11y_core_complete boolean := false;
  v_capability_profile text;
  v_recovery_session_policy text;
  v_session_applicability text;
  v_session_na_authority jsonb;
begin
  if old.validator_outcome<>'PENDING' or new.validator_outcome='PENDING' then return new; end if;

  v_logical_validator_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);

  select contract_revision,version_id,pantalla_id
    into v_revision,v_version_id,v_pantalla_id
  from programacion.input_readiness_runs
  where id=old.run_id;

  if (v_revision is null or v_revision not in ('5.12','5.13','5.13.1')) then
    return new;
  end if;

  -- M4.6 true cross-family rule.
  -- Recovery OTP verification may use the MFA/OTP policy family, but it must not
  -- create an operational SESSION. The SESSION family must remain positively N/A.
  if new.validator_outcome='PASS'
     and v_revision='5.13.1'
     and old.family_code in ('MFA_OTP_SSO','SESSION') then

    v_capability_profile:=programacion.fn_input_security_capability_profile(v_pantalla_id)->>'profile';

    if v_capability_profile='RECOVERY_OTP_VERIFY' then
      select c.especificacion#>>'{semantic_depth_contract,recovery_otp_operational_session_creation}'
        into v_recovery_session_policy
      from programacion.contratos c
      where c.version_id=v_version_id
        and c.contrato_codigo='INPUT_READINESS_CONTRACT';

      if v_recovery_session_policy is distinct from 'DENY' then
        raise exception
          'V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_POLICY_UNRESOLVED:%:policy=%',
          v_pantalla_id,coalesce(v_recovery_session_policy,'<NULL>');
      end if;

      v_session_na_authority:=
        programacion.fn_input_na_positive_authority_v512(
          'SESSION',v_pantalla_id,v_version_id
        );

      if coalesce((v_session_na_authority->>'qualified')::boolean,false) is not true then
        raise exception
          'V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_EXCLUSION_AUTHORITY_MISSING:%',
          v_pantalla_id;
      end if;

      select a.applicability
        into v_session_applicability
      from programacion.input_family_assessments a
      where a.run_id=old.run_id
        and a.family_code='SESSION';

      if v_session_applicability is null then
        raise exception
          'V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_ASSESSMENT_MISSING:%:run=%',
          v_pantalla_id,old.run_id;
      end if;

      if v_session_applicability<>'NOT_APPLICABLE' then
        raise exception
          'V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION:%:left=MFA_OTP_SSO:right=SESSION:session_applicability=%',
          v_pantalla_id,v_session_applicability;
      end if;
    end if;
  end if;

  if jsonb_typeof(v_logical_validator_evidence->'assertions')='array' then
    for v_assertion in
      select value from jsonb_array_elements(v_logical_validator_evidence->'assertions')
    loop
      if coalesce(v_assertion->>'operator','')='CONTAINS'
         and jsonb_typeof(v_assertion->'expected')='array'
         and jsonb_array_length(v_assertion->'expected')>0
         and coalesce(v_assertion->'source_ref'->>'kind','')
             in ('SCREEN_CANONICAL_GRAPH','SCREEN_RULE_SET','RULE','SECURITY_POLICY_SET','SCREEN_STATE_SET') then
        v_eval:=programacion.fn_input_evaluate_assertion(
          old.run_id,old.family_code,v_assertion
        );
        if coalesce((v_eval->>'passed')::boolean,false) is true then
          v_positive_requirement:=true;
        end if;
      end if;
    end loop;
  end if;

  if new.validator_outcome='PASS' and old.applicability='NOT_APPLICABLE' then
    v_na_authority:=programacion.fn_input_na_positive_authority_v512(
      old.family_code,v_pantalla_id,v_version_id
    );
    if coalesce((v_na_authority->>'qualified')::boolean,false) is not true then
      raise exception 'V512_VALIDATOR_NA_WITHOUT_POSITIVE_EXCLUSION:%:%',
        v_pantalla_id,old.family_code;
    end if;
  end if;

  if new.validator_outcome='PASS' and v_positive_requirement then
    if old.family_code in ('REDUCED_MOTION','FORCED_COLORS_CONTRAST') then
      if old.applicability<>'APPLICABLE'
         or old.coverage_status<>'COMPLETE'
         or old.well_defined_status<>'COMPLETE' then
        raise exception
          'V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH:%:% expected=APPLICABLE/COMPLETE/COMPLETE actual=%/%/%',
          v_pantalla_id,old.family_code,old.applicability,
          old.coverage_status,old.well_defined_status;
      end if;
    elsif old.family_code='THEME_LIGHT_DARK_SYSTEM' then
      if old.applicability<>'APPLICABLE'
         or old.coverage_status not in ('PARTIAL','COMPLETE')
         or old.well_defined_status not in ('PARTIAL','COMPLETE') then
        raise exception
          'V512_VALIDATOR_THEME_SEMANTICS_MISMATCH:% actual=%/%/%',
          v_pantalla_id,old.applicability,old.coverage_status,
          old.well_defined_status;
      end if;
    end if;

    for v_blocker in
      select value from jsonb_array_elements(coalesce(old.blockers,'[]'::jsonb))
    loop
      if (old.family_code='REDUCED_MOTION'
          and v_blocker->>'code'='REDUCED_MOTION_REQUIREMENT_MISSING')
         or (old.family_code='FORCED_COLORS_CONTRAST'
             and v_blocker->>'code'='FORCED_COLORS_REQUIREMENT_MISSING')
         or (old.family_code='THEME_LIGHT_DARK_SYSTEM'
             and v_blocker->>'code'='THEME_REQUIREMENTS_NOT_LINKED') then
        v_false_missing:=true;
      end if;
    end loop;

    if v_false_missing then
      raise exception
        'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE:%:%',
        v_pantalla_id,old.family_code;
    end if;
  end if;

  -- M10.7 C: retain an authority graph read wherever special rules
  -- consume its contents; all other families still pass the final
  -- full-manifest + SHA/currentness and independent assertion guards.
  if old.family_code in ('ACCESSIBILITY','MFA_OTP_SSO') then
    v_graph:=programacion.fn_input_screen_canonical_graph(
      v_pantalla_id,v_version_id
    );
    v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
  end if;

  if new.validator_outcome='PASS' and old.family_code='ACCESSIBILITY' then
    select count(distinct r->>'rule_code')=4
      into v_a11y_core_complete
    from jsonb_array_elements(v_rules) r
    where r->>'rule_code' in (
      'B2B-RULE-A11Y-001','B2B-RULE-A11Y-002',
      'B2B-RULE-A11Y-003','B2B-RULE-A11Y-004'
    );

    if v_a11y_core_complete
       and (old.coverage_status<>'COMPLETE'
            or old.well_defined_status<>'COMPLETE') then
      raise exception
        'V512_VALIDATOR_ACCESSIBILITY_CORE_PRESENT_BUT_CANDIDATE_INCOMPLETE:%',
        v_pantalla_id;
    end if;
  end if;

  if new.validator_outcome='PASS' and old.family_code='MFA_OTP_SSO' then
    select exists(
      select 1
      from jsonb_array_elements(v_rules) r
      where (r->'config' ? 'otp_operation_id')
         or (r->'config' ? 'otp_policy_id')
         or (r->'config' ? 'email_otp_policy_code')
    ) into v_otp_present;

    if v_otp_present and old.applicability='NOT_APPLICABLE' then
      raise exception
        'V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE:%',
        v_pantalla_id;
    end if;
  end if;

  return new;
end;
$function$;

DO $post$
DECLARE f text;
BEGIN
 SELECT pg_get_functiondef('programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure) INTO f;
 IF position('if old.family_code in (''ACCESSIBILITY'',''MFA_OTP_SSO'') then' in f)=0
 OR position('V512_VALIDATOR_ACCESSIBILITY_CORE_PRESENT_BUT_CANDIDATE_INCOMPLETE' in f)=0
 OR position('V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE' in f)=0
 OR position('V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION' in f)=0
 OR position('fn_input_validator_evidence_rehydrate_v1(' in f)=0
 OR (SELECT count(*) FROM pg_trigger t WHERE t.tgrelid='programacion.input_family_assessments'::regclass
       AND NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND (t.tgtype&16)=16)<>6
 THEN RAISE EXCEPTION 'IG_M107_C_SEMANTIC_GUARDS_NOT_PRESERVED'; END IF;
END $post$;
