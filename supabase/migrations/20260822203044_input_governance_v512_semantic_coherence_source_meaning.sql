-- Refine semantic coherence: source presence is not equivalent to family sufficiency.
update programacion.contratos
set especificacion = jsonb_set(
  jsonb_set(
    especificacion,
    '{semantic_coherence_contract}',
    coalesce(especificacion->'semantic_coherence_contract','{}'::jsonb) || '{"source_presence_alone_implies_complete":false,"family_semantics_required":true,"pending_source_rule_may_authorize_missing_coverage":true}'::jsonb,
    true
  ),
  '{negative_tests}',
  case when (especificacion->'negative_tests') ? 'SOURCE_PRESENCE_DOES_NOT_EQUAL_SUFFICIENCY'
       then especificacion->'negative_tests'
       else (especificacion->'negative_tests') || '["SOURCE_PRESENCE_DOES_NOT_EQUAL_SUFFICIENCY"]'::jsonb end,
  true
)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

create or replace function programacion.fn_guard_input_validator_semantic_coherence_v512()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare
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
begin
  if old.validator_outcome<>'PENDING' or new.validator_outcome='PENDING' then return new; end if;
  select contract_revision,version_id,pantalla_id into v_revision,v_version_id,v_pantalla_id
  from programacion.input_readiness_runs where id=old.run_id;
  if v_revision is distinct from '5.12' then return new; end if;

  if jsonb_typeof(new.validator_evidence->'assertions')='array' then
    for v_assertion in select value from jsonb_array_elements(new.validator_evidence->'assertions')
    loop
      if coalesce(v_assertion->>'operator','')='CONTAINS'
         and jsonb_typeof(v_assertion->'expected')='array'
         and jsonb_array_length(v_assertion->'expected')>0
         and coalesce(v_assertion->'source_ref'->>'kind','') in ('SCREEN_CANONICAL_GRAPH','SCREEN_RULE_SET','RULE','SECURITY_POLICY_SET','SCREEN_STATE_SET') then
        v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
        if coalesce((v_eval->>'passed')::boolean,false) is true then v_positive_requirement:=true; end if;
      end if;
    end loop;
  end if;

  if new.validator_outcome='PASS' and old.applicability='NOT_APPLICABLE' then
    v_na_authority:=programacion.fn_input_na_positive_authority_v512(old.family_code,v_pantalla_id,v_version_id);
    if coalesce((v_na_authority->>'qualified')::boolean,false) is not true then
      raise exception 'V512_VALIDATOR_NA_WITHOUT_POSITIVE_EXCLUSION:%:%',v_pantalla_id,old.family_code;
    end if;
  end if;

  if new.validator_outcome='PASS' and v_positive_requirement then
    if old.family_code in ('REDUCED_MOTION','FORCED_COLORS_CONTRAST') then
      if old.applicability<>'APPLICABLE' or old.coverage_status<>'COMPLETE' or old.well_defined_status<>'COMPLETE' then
        raise exception 'V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH:%:% expected=APPLICABLE/COMPLETE/COMPLETE actual=%/%/%',v_pantalla_id,old.family_code,old.applicability,old.coverage_status,old.well_defined_status;
      end if;
    elsif old.family_code='THEME_LIGHT_DARK_SYSTEM' then
      if old.applicability<>'APPLICABLE' or old.coverage_status not in ('PARTIAL','COMPLETE') or old.well_defined_status not in ('PARTIAL','COMPLETE') then
        raise exception 'V512_VALIDATOR_THEME_SEMANTICS_MISMATCH:% actual=%/%/%',v_pantalla_id,old.applicability,old.coverage_status,old.well_defined_status;
      end if;
    end if;

    for v_blocker in select value from jsonb_array_elements(coalesce(old.blockers,'[]'::jsonb))
    loop
      if (old.family_code='REDUCED_MOTION' and v_blocker->>'code'='REDUCED_MOTION_REQUIREMENT_MISSING')
         or (old.family_code='FORCED_COLORS_CONTRAST' and v_blocker->>'code'='FORCED_COLORS_REQUIREMENT_MISSING')
         or (old.family_code='THEME_LIGHT_DARK_SYSTEM' and v_blocker->>'code'='THEME_REQUIREMENTS_NOT_LINKED') then
        v_false_missing:=true;
      end if;
    end loop;
    if v_false_missing then raise exception 'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE:%:%',v_pantalla_id,old.family_code; end if;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  if new.validator_outcome='PASS' and old.family_code='ACCESSIBILITY' then
    select count(distinct r->>'rule_code')=4 into v_a11y_core_complete
    from jsonb_array_elements(v_rules) r
    where r->>'rule_code' in ('B2B-RULE-A11Y-001','B2B-RULE-A11Y-002','B2B-RULE-A11Y-003','B2B-RULE-A11Y-004');
    if v_a11y_core_complete and (old.coverage_status<>'COMPLETE' or old.well_defined_status<>'COMPLETE') then
      raise exception 'V512_VALIDATOR_ACCESSIBILITY_CORE_PRESENT_BUT_CANDIDATE_INCOMPLETE:%',v_pantalla_id;
    end if;
  end if;

  if new.validator_outcome='PASS' and old.family_code='MFA_OTP_SSO' then
    select exists(
      select 1 from jsonb_array_elements(v_rules) r
      where (r->'config' ? 'otp_operation_id') or (r->'config' ? 'otp_policy_id') or (r->'config' ? 'email_otp_policy_code')
    ) into v_otp_present;
    if v_otp_present and old.applicability='NOT_APPLICABLE' then
      raise exception 'V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE:%',v_pantalla_id;
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function programacion.fn_guard_input_validator_semantic_coherence_v512() from public;
grant execute on function programacion.fn_guard_input_validator_semantic_coherence_v512() to postgres;

update public.lf_error_knowledge
set frecuencia=coalesce(frecuencia,0)+1,
    ultima_vez=now(),
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'2026-08-22 V5.12 gate refinement recurrence: first screen56 successor retry correctly stopped on BROWSER_PLATFORM because the new coherence guard treated a positive canonical rule assertion as automatic family sufficiency. The canonical rule itself says current_status=PENDING_SOURCE_IDENTIFICATION and allows Story/Implementation while blocking QA/Production, so MISSING coverage is semantically correct. Transaction rolled back; zero successor residue.'),
    prevencion=concat_ws(E'\n',nullif(prevencion,''),'V5.12 refinement: never infer readiness/coverage from source presence alone. Coherence must interpret the source semantics and stage flags. Positive assertions for a rule with PENDING_SOURCE_IDENTIFICATION may coexist with MISSING coverage; positive fully-defining A11Y rules require COMPLETE input coverage; theme rules allow PARTIAL while dark-token/QA gaps remain.'),
    validacion=concat_ws(E'\n',nullif(validacion,''),'Regression: BROWSER_PLATFORM rule present + current_status=PENDING_SOURCE_IDENTIFICATION + coverage=MISSING must PASS semantic coherence; REDUCED_MOTION/A11Y-003 present + coverage=MISSING must FAIL; THEME rules present + PARTIAL may PASS, MISSING must FAIL.'),
    source_context='INPUT_GOVERNANCE_V512_SOURCE_MEANING_COHERENCE_20260822',
    source_ref='programacion.fn_guard_input_validator_semantic_coherence_v512'
where codigo='AUD-019';

update public.lf_prevention_rules
set regla=concat_ws(E'\n',nullif(regla,''),'V5.12 semantic refinement: presencia de fuente no equivale a suficiencia. El validator debe interpretar estados/flags canónicos por familia y etapa antes de comparar con coverage/readiness.'),
    justificacion=concat_ws(E'\n',nullif(justificacion,''),'Recurrencia 2026-08-22: BROWSER_PLATFORM tiene regla positiva que declara explícitamente fuente pendiente; usar presencia=>COMPLETE habría sobrecerrado la familia.')
where regla_codigo='PRV-AUD-019';