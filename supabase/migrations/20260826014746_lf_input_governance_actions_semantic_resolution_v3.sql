-- INPUT_GOVERNANCE_AGENT 5.12
-- Semantic resolution v3 for ACTIONS.
-- No product action is invented and pending provider/copy/evidence decisions are not treated as resolved.
-- ACTIONS is COMPLETE only when direct VIGENTE rules provide all four structural dimensions:
-- branch choice, normalized outcomes, atomic commit boundary, and post-success/invalid-session behavior.

create or replace function programacion.fn_input_governance_semantic_probe_v3(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_base jsonb;
  v_graph jsonb;
  v_rules jsonb;
  v_branch_count integer:=0;
  v_outcome_count integer:=0;
  v_commit_count integer:=0;
  v_post_success_count integer:=0;
  v_outcome_integrity_failures integer:=0;
  v_action_rule_codes jsonb:='[]'::jsonb;
begin
  v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id);
  if p_family_code<>'ACTIONS' then
    return v_base;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_branch_count
  from direct_vigente_rules d
  where coalesce((d.rule->'config'->>'ask_old_phone_access')::boolean,false)=true
    and nullif(d.rule->'config'->>'old_phone_accessible','') is not null
    and nullif(d.rule->'config'->>'old_phone_unavailable','') is not null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_outcome_count
  from direct_vigente_rules d
  where jsonb_typeof(d.rule->'config'->'allowed_outcomes')='array'
    and jsonb_array_length(d.rule->'config'->'allowed_outcomes')>0
    and jsonb_typeof(d.rule->'config'->'outcomes')='object';

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
      and jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      and jsonb_array_length(r.value->'config'->'allowed_outcomes')>0
      and jsonb_typeof(r.value->'config'->'outcomes')='object'
  ), allowed as (
    select d.rule, a.value as outcome_code
    from direct_vigente_rules d
    cross join lateral jsonb_array_elements_text(d.rule->'config'->'allowed_outcomes') a(value)
  )
  select count(*) into v_outcome_integrity_failures
  from allowed a
  where not (a.rule->'config'->'outcomes' ? a.outcome_code)
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'rebind','') is null
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'operational_access','') is null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_commit_count
  from direct_vigente_rules d
  where d.rule->'config'->>'atomic_commit'='REQUIRED'
    and d.rule->'config'->>'operational_access_before_commit'='DENY'
    and jsonb_typeof(d.rule->'config'->'accepted_recovery_proofs')='array'
    and jsonb_array_length(d.rule->'config'->'accepted_recovery_proofs')>0;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_post_success_count
  from direct_vigente_rules d
  where nullif(d.rule->'config'->>'success_outcome','') is not null
    and nullif(d.rule->'config'->>'post_auth_route','') is not null
    and nullif(d.rule->'config'->>'invalid_session_action','') is not null
    and nullif(d.rule->'config'->>'required_rebind_outcome','') is not null;

  select coalesce(jsonb_agg(distinct r.value->>'rule_code' order by r.value->>'rule_code'),'[]'::jsonb)
    into v_action_rule_codes
  from jsonb_array_elements(v_rules) r(value)
  where r.value->>'status'='VIGENTE'
    and (
      coalesce((r.value->'config'->>'ask_old_phone_access')::boolean,false)=true
      or jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      or r.value->'config'->>'atomic_commit'='REQUIRED'
      or nullif(r.value->'config'->>'success_outcome','') is not null
    );

  if v_branch_count>0
     and v_outcome_count>0
     and v_outcome_integrity_failures=0
     and v_commit_count>0
     and v_post_success_count>0 then
    return jsonb_build_object(
      'handled',true,
      'family_code',p_family_code,
      'level','COMPLETE',
      'blocker_code',null,
      'probe',jsonb_build_object(
        'resolution_contract','STRUCTURED_ACTION_TOPOLOGY_RESOLUTION_V3',
        'branch_contract_count',v_branch_count,
        'outcome_contract_count',v_outcome_count,
        'outcome_integrity_failures',v_outcome_integrity_failures,
        'atomic_commit_contract_count',v_commit_count,
        'post_success_contract_count',v_post_success_count,
        'action_rule_codes',v_action_rule_codes,
        'pending_provider_copy_visual_does_not_authorize_missing_action_dimensions',true
      )
    );
  end if;

  return v_base;
end;
$function$;

do $patch_classifier$
declare
  vdef text;
  vbefore text;
begin
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure)
    into vdef;
  vbefore:=vdef;

  if position('programacion.fn_input_governance_semantic_probe_v3(' in vdef)=0 then
    vdef:=replace(
      vdef,
      'programacion.fn_input_governance_semantic_probe_v2(',
      'programacion.fn_input_governance_semantic_probe_v3('
    );
    if vdef=vbefore or position('programacion.fn_input_governance_semantic_probe_v3(' in vdef)=0 then
      raise exception 'SELFTEST_SEMANTIC_V3_CLASSIFIER_PATCH_NOT_APPLIED';
    end if;
    execute vdef;
  end if;
end;
$patch_classifier$;

do $selftest$
declare
  vj jsonb;
begin
  vj:=programacion.fn_input_governance_semantic_probe_v3(58,'ACTIONS',19);
  if coalesce((vj->>'handled')::boolean,false) is not true
     or vj->>'level'<>'COMPLETE'
     or coalesce((vj->'probe'->>'branch_contract_count')::integer,0)<1
     or coalesce((vj->'probe'->>'outcome_contract_count')::integer,0)<1
     or coalesce((vj->'probe'->>'outcome_integrity_failures')::integer,-1)<>0
     or coalesce((vj->'probe'->>'atomic_commit_contract_count')::integer,0)<1
     or coalesce((vj->'probe'->>'post_success_contract_count')::integer,0)<1 then
    raise exception 'SELFTEST_REC001_ACTIONS_SEMANTIC_RESOLUTION_INVALID:%',vj;
  end if;

  vj:=programacion.fn_input_governance_bootstrap_classify_v2(58,'ACTIONS',19);
  if vj->>'story_ready_status'<>'READY'
     or vj->>'bootstrap_level'<>'COMPLETE'
     or vj->>'severity'<>'P4'
     or vj->>'coverage_status'<>'COMPLETE'
     or vj->>'well_defined_status'<>'COMPLETE' then
    raise exception 'SELFTEST_REC001_ACTIONS_CLASSIFICATION_INVALID:%',vj;
  end if;

  vj:=programacion.fn_input_governance_semantic_probe_v3(1,'ACTIONS',19);
  if coalesce((vj->>'handled')::boolean,false) and vj->>'level'='COMPLETE' then
    raise exception 'SELFTEST_ONB001_ACTIONS_MUST_NOT_GAIN_RECOVERY_TOPOLOGY:%',vj;
  end if;

  if programacion.fn_input_readiness_run_is_current(208) is not false then
    raise exception 'SELFTEST_ARC015_RUN208_MUST_BE_STALE_AFTER_ACTION_CLASSIFIER_CHANGE';
  end if;
end;
$selftest$;

comment on function programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)
is 'INPUT_GOVERNANCE semantic resolver v3. Adds fail-closed structured ACTIONS topology resolution while delegating all other families to v2.';
