-- Strategy 28 / Input Governance IG-C / sixth independent oracle pattern
-- Rollback-only. No human decision is created, no canonical rule is mutated, no runtime switch.
-- Purpose: prove I18N_FORMATS can be evaluated independently without treating absence as N/A.

begin;

create or replace function programacion.fn_input_governance_shadow_i18n_oracle_candidate_v1(
  p_pantalla_id integer,
  p_override jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v jsonb;
  v_screen_code text;
  v_module_code text;
  v_exclusion_count integer:=0;
  v_i18n_rule_count integer:=0;
  v_classification text:='MISSING';
  v_reason text:='NO_POSITIVE_I18N_APPLICABILITY_AUTHORITY';
begin
  if p_override is null then
    with screen_row as (
      select p.id,p.codigo,p.module_code
      from lf_ops.pantallas p
      where p.id=p_pantalla_id
    ), explicit_exclusion as (
      select r.codigo rule_code,r.estado rule_status,r.pendiente_decision,r.valor_config,
             d.id_decision,d.decision_number,d.estado_normalizado decision_status
      from screen_row s
      join lf_ops.reglas_pantallas rp on rp.pantalla_id=s.id
      join lf_ops.reglas r on r.id=rp.regla_id
      left join public.lf_decisiones_gov d
        on d.decision_number=case when coalesce(r.valor_config->>'decision_number','')~'^[0-9]+$' then (r.valor_config->>'decision_number')::bigint else null end
      where r.codigo='B2B-RULE-INPUT-APPLICABILITY-001'
        and coalesce(r.pendiente_decision,false)=false
        and r.valor_config->>'module_code'=s.module_code
        and coalesce(r.valor_config->'screen_codes','[]'::jsonb) ? s.codigo
        and r.valor_config->'input_family_exclusions'->'I18N_FORMATS'->>'status'='EXCLUDED_CURRENT_SINGLE_LOCALE_SCOPE'
        and r.valor_config->'input_family_exclusions'->'I18N_FORMATS'->>'authority'='OWNER_DECISION'
        and d.id_decision=r.valor_config->>'decision_id'
        and d.decision_number=(r.valor_config->>'decision_number')::bigint
        and d.estado_normalizado in ('VIGENTE','CANDIDATO_CONTROLADO')
    ), direct_i18n_rules as (
      select r.codigo,r.estado,r.origen,r.valor_config
      from screen_row s
      join lf_ops.reglas_pantallas rp on rp.pantalla_id=s.id
      join lf_ops.reglas r on r.id=rp.regla_id
      where lower(coalesce(r.codigo,'')) ~ '(i18n|locale|idioma|internacional|timezone|currency|moneda|format)'
         or lower(coalesce(r.titulo,'')) ~ '(i18n|locale|idioma|internacional|zona horaria|timezone|moneda|currency|formato de fecha|formato num)'
         or lower(coalesce(r.descripcion,'')) ~ '(i18n|locale|idioma|internacional|zona horaria|timezone|moneda|currency|formato de fecha|formato num)'
         or lower(coalesce(r.valor_config::text,'')) ~ '(i18n|locale|idioma|internacional|timezone|currency|moneda|date_format|number_format)'
    )
    select jsonb_build_object(
      'pantalla_id',s.id,'screen_code',s.codigo,'module_code',s.module_code,
      'explicit_positive_exclusion_count',(select count(*) from explicit_exclusion),
      'explicit_exclusions',coalesce((select jsonb_agg(to_jsonb(x) order by x.rule_code) from explicit_exclusion x),'[]'::jsonb),
      'direct_i18n_rule_count',(select count(*) from direct_i18n_rules),
      'direct_i18n_rules',coalesce((select jsonb_agg(to_jsonb(x) order by x.codigo) from direct_i18n_rules x),'[]'::jsonb)
    ) into v
    from screen_row s;
  else
    v:=p_override;
  end if;

  v_screen_code:=v->>'screen_code';
  v_module_code:=v->>'module_code';
  v_exclusion_count:=coalesce((v->>'explicit_positive_exclusion_count')::integer,0);
  v_i18n_rule_count:=coalesce((v->>'direct_i18n_rule_count')::integer,0);

  if v_exclusion_count>0 then
    v_classification:='NOT_APPLICABLE';
    v_reason:='EXPLICIT_OWNER_SINGLE_LOCALE_EXCLUSION_RESOLVED';
  elsif v_i18n_rule_count>0 then
    -- Presence proves applicability evidence but not complete format sufficiency.
    v_classification:='PARTIAL';
    v_reason:='DIRECT_I18N_SOURCE_PRESENT_SUFFICIENCY_NOT_PROVEN';
  else
    v_classification:='MISSING';
    v_reason:='NO_POSITIVE_I18N_APPLICABILITY_AUTHORITY';
  end if;

  return jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_I18N_POSITIVE_AUTHORITY_ORACLE_CANDIDATE_V1',
    'family_code','I18N_FORMATS','pantalla_id',p_pantalla_id,
    'screen_code',v_screen_code,'module_code',v_module_code,
    'implemented',true,'decisional',false,'comparison_only',true,'mutates_readiness',false,
    'classification',v_classification,'reason',v_reason,
    'absence_authorizes_not_applicable',false,
    'complete_claim_supported',false,
    'observed_authority',v,
    'source_refs',jsonb_build_array(
      jsonb_build_object('kind','SCREEN_RULE_BINDINGS','pantalla_id',p_pantalla_id),
      jsonb_build_object('kind','OWNER_DECISION_RESOLUTION','pantalla_id',p_pantalla_id)
    )
  );
end
$function$;

do $tests$
declare
  v jsonb;
  v_base jsonb;
  v_mut jsonb;
  v_live text;
begin
  -- Positive authority control: B2B-AUTH-001 has an explicit owner exclusion for I18N while single-locale.
  v:=programacion.fn_input_governance_shadow_i18n_oracle_candidate_v1(51,null);
  if v->>'classification'<>'NOT_APPLICABLE' then
    raise exception 'S28_I18N_B2B_POSITIVE_EXCLUSION_FAIL:%',v;
  end if;
  v_live:=programacion.fn_input_governance_bootstrap_classify_v2(51,'I18N_FORMATS',19)->>'coverage_status';
  if v_live<>'NOT_APPLICABLE' then
    raise exception 'S28_I18N_B2B_CANONICAL_CONTROL_DIVERGED:%',v_live;
  end if;

  -- Frozen holdout negatives: no positive I18N applicability authority on CLIENT_ONBOARDING.
  v:=programacion.fn_input_governance_shadow_i18n_oracle_candidate_v1(3,null);
  if v->>'classification'<>'MISSING' then raise exception 'S28_I18N_ONB003_EXPECTED_MISSING:%',v; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=213 and family_code='I18N_FORMATS')<>v->>'classification' then
    raise exception 'S28_I18N_ONB003_HOLDOUT_DIVERGENCE';
  end if;

  v:=programacion.fn_input_governance_shadow_i18n_oracle_candidate_v1(57,null);
  if v->>'classification'<>'MISSING' then raise exception 'S28_I18N_ONB004_EXPECTED_MISSING:%',v; end if;
  if (select coverage_status from programacion.input_family_assessments where run_id=214 and family_code='I18N_FORMATS')<>v->>'classification' then
    raise exception 'S28_I18N_ONB004_HOLDOUT_DIVERGENCE';
  end if;

  -- Absence must never mutate into N/A.
  v_base:=v->'observed_authority';
  v_mut:=jsonb_set(v_base,'{explicit_positive_exclusion_count}','0'::jsonb,true);
  v_mut:=jsonb_set(v_mut,'{direct_i18n_rule_count}','0'::jsonb,true);
  if programacion.fn_input_governance_shadow_i18n_oracle_candidate_v1(57,v_mut)->>'classification'<>'MISSING' then
    raise exception 'S28_I18N_ABSENCE_SELF_NA';
  end if;

  -- Direct I18N evidence without a sufficient locale/format contract may prove only PARTIAL.
  v_mut:=jsonb_set(v_base,'{direct_i18n_rule_count}','1'::jsonb,true);
  if programacion.fn_input_governance_shadow_i18n_oracle_candidate_v1(57,v_mut)->>'classification'<>'PARTIAL' then
    raise exception 'S28_I18N_SOURCE_PRESENCE_FALSE_COMPLETE';
  end if;

  -- Explicit owner exclusion is the only current path to N/A in this candidate.
  v_mut:=jsonb_set(v_base,'{explicit_positive_exclusion_count}','1'::jsonb,true);
  v_mut:=jsonb_set(v_mut,'{direct_i18n_rule_count}','0'::jsonb,true);
  if programacion.fn_input_governance_shadow_i18n_oracle_candidate_v1(57,v_mut)->>'classification'<>'NOT_APPLICABLE' then
    raise exception 'S28_I18N_POSITIVE_EXCLUSION_METAMORPHIC_FAIL';
  end if;
end
$tests$;

select jsonb_build_object(
  'status','PASS_ROLLBACK_ONLY',
  'independent_oracle_patterns_demonstrated',6,
  'holdout_pairs_total',6,
  'i18n_oracle_implemented',true,
  'i18n_client_authority_resolved',false,
  'i18n_client_holdout_result','MISSING_MATCHES_RUNS_213_214',
  'positive_control','B2B_AUTH_001_EXPLICIT_OWNER_SINGLE_LOCALE_EXCLUSION_NOT_APPLICABLE',
  'absence_to_na_forbidden',true,
  'source_presence_to_complete_forbidden',true,
  'human_decision_still_required_for_client_scope_change',true,
  'claim_ceiling','PREVALIDATION_6_OF_6_ORACLE_PATTERNS_IMPLEMENTED_I18N_FUNCTIONAL_AUTHORITY_STILL_OPEN_NO_LIVE_ORACLE_NO_MERGE_NO_PRODUCTION'
) as receipt;

rollback;

select jsonb_build_object(
  'status','PASS_POST_ROLLBACK_READBACK',
  'candidate_function_residue',(
    select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion' and p.proname='fn_input_governance_shadow_i18n_oracle_candidate_v1'
  )
) as post_rollback;